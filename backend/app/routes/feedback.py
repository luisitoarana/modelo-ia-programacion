"""Endpoints para que el usuario vote 👍/👎 las respuestas del asistente.

Esta es la base del sistema RLHF: cada voto se guarda en la tabla
`feedbacks` junto con el prompt y la respuesta originales. El proceso
batch `rlhf/exportar_dataset.py` luego convierte estos votos en pares
(chosen, rejected) listos para DPO.

Ver: docs/RLHF_PLAN.md
"""

from __future__ import annotations

import uuid
from collections import Counter
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import desc, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import obtener_usuario_actual
from app.database import get_db
from app.models.conversacion import Mensaje, RolMensaje
from app.models.feedback import Feedback
from app.models.usuario import Usuario
from app.schemas.feedback import (
    CrearFeedback,
    EstadisticasFeedback,
    FeedbackCreado,
    FeedbackResumen,
)


router = APIRouter()


@router.post(
    "",
    response_model=FeedbackCreado,
    status_code=status.HTTP_201_CREATED,
    summary="Registrar 👍 o 👎 sobre una respuesta del asistente",
)
async def crear_feedback(
    datos: CrearFeedback,
    usuario: Annotated[Usuario, Depends(obtener_usuario_actual)],
    sesion: Annotated[AsyncSession, Depends(get_db)],
) -> Feedback:
    """Guarda un voto del usuario.

    Validaciones:
    - El mensaje debe existir
    - El mensaje debe pertenecer a una conversación del usuario
    - El mensaje debe ser de rol 'asistente' (no se vota lo propio)
    - Un usuario solo puede votar una vez por mensaje (lo último gana)
    """
    # Recuperar el mensaje y el mensaje del usuario anterior (= el prompt).
    mensaje = await sesion.get(Mensaje, datos.mensaje_id)
    if mensaje is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Mensaje no encontrado",
        )

    if mensaje.rol != RolMensaje.ASISTENTE:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Solo se pueden votar respuestas del asistente",
        )

    # Verificar autoría: el mensaje debe pertenecer a una conversación
    # del usuario actual.
    if mensaje.conversacion and mensaje.conversacion.usuario_id != usuario.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="No puedes votar mensajes de otros usuarios",
        )

    # Buscar el mensaje del usuario inmediatamente anterior — ése es el
    # "prompt" que generó esta respuesta.
    stmt_prev = (
        select(Mensaje)
        .where(
            Mensaje.conversacion_id == mensaje.conversacion_id,
            Mensaje.fecha_creacion < mensaje.fecha_creacion,
            Mensaje.rol == RolMensaje.USUARIO,
        )
        .order_by(desc(Mensaje.fecha_creacion))
        .limit(1)
    )
    prev = (await sesion.execute(stmt_prev)).scalar_one_or_none()
    prompt_texto = prev.contenido if prev else "(sin prompt previo)"

    # Si ya hay un feedback de este usuario para este mensaje, lo
    # actualizamos en lugar de duplicar.
    stmt_exist = select(Feedback).where(
        Feedback.usuario_id == usuario.id,
        Feedback.mensaje_id == datos.mensaje_id,
    )
    existente = (await sesion.execute(stmt_exist)).scalar_one_or_none()

    if existente is not None:
        existente.voto = datos.voto
        existente.razon = datos.razon
        existente.comentario = datos.comentario
        # Se vuelve "pendiente de procesar" porque cambió.
        existente.procesado = False
        await sesion.commit()
        await sesion.refresh(existente)
        return existente

    # Caso normal: crear nuevo
    feedback = Feedback(
        usuario_id=usuario.id,
        mensaje_id=datos.mensaje_id,
        conversacion_id=mensaje.conversacion_id,
        voto=datos.voto,
        razon=datos.razon,
        comentario=datos.comentario,
        prompt=prompt_texto,
        respuesta=mensaje.contenido,
        modelo=getattr(mensaje, "modelo_origen", None) or getattr(mensaje, "origen_respuesta", None),
        nivel=getattr(mensaje, "nivel", None),
    )
    sesion.add(feedback)
    await sesion.commit()
    await sesion.refresh(feedback)
    return feedback


@router.delete(
    "/{feedback_id}",
    summary="Eliminar un voto propio (deshacer)",
)
async def eliminar_feedback(
    feedback_id: uuid.UUID,
    usuario: Annotated[Usuario, Depends(obtener_usuario_actual)],
    sesion: Annotated[AsyncSession, Depends(get_db)],
) -> dict:
    """Devuelve 200 con `{ok: true}` en lugar de 204 — FastAPI no permite
    body con 204 cuando hay anotación de retorno."""
    fb = await sesion.get(Feedback, feedback_id)
    if fb is None:
        raise HTTPException(status_code=404, detail="Feedback no existe")
    if fb.usuario_id != usuario.id:
        raise HTTPException(
            status_code=403, detail="No puedes borrar votos de otros usuarios"
        )
    await sesion.delete(fb)
    await sesion.commit()
    return {"ok": True, "id": str(feedback_id)}


@router.get(
    "/estadisticas",
    response_model=EstadisticasFeedback,
    summary="Estadísticas agregadas (admin)",
)
async def estadisticas(
    usuario: Annotated[Usuario, Depends(obtener_usuario_actual)],
    sesion: Annotated[AsyncSession, Depends(get_db)],
) -> EstadisticasFeedback:
    """Stats globales — útil para el panel admin y para tracking semanal."""
    if usuario.rol != "administrador":
        raise HTTPException(
            status_code=403, detail="Solo administradores"
        )

    # Conteos totales
    total = (await sesion.execute(select(func.count(Feedback.id)))).scalar_one()
    positivos = (
        await sesion.execute(
            select(func.count(Feedback.id)).where(Feedback.voto > 0)
        )
    ).scalar_one()
    negativos = total - positivos
    pendientes = (
        await sesion.execute(
            select(func.count(Feedback.id)).where(Feedback.procesado == False)  # noqa: E712
        )
    ).scalar_one()

    # Distribución por modelo y por razón
    rows_modelo = await sesion.execute(
        select(Feedback.modelo, func.count(Feedback.id)).group_by(Feedback.modelo)
    )
    por_modelo = {(m or "desconocido"): c for m, c in rows_modelo.all()}

    rows_razon = await sesion.execute(
        select(Feedback.razon, func.count(Feedback.id))
        .where(Feedback.razon.is_not(None))
        .group_by(Feedback.razon)
    )
    por_razon = {r: c for r, c in rows_razon.all()}

    return EstadisticasFeedback(
        total=total,
        positivos=positivos,
        negativos=negativos,
        tasa_aprobacion=(positivos / total) if total > 0 else 0.0,
        pendientes_procesar=pendientes,
        por_modelo=por_modelo,
        por_razon=por_razon,
    )


@router.get(
    "/recientes",
    response_model=list[FeedbackResumen],
    summary="Últimos feedbacks (admin) — para revisar la calidad del modelo",
)
async def listar_recientes(
    usuario: Annotated[Usuario, Depends(obtener_usuario_actual)],
    sesion: Annotated[AsyncSession, Depends(get_db)],
    limite: int = 50,
    solo_negativos: bool = False,
) -> list[Feedback]:
    if usuario.rol != "administrador":
        raise HTTPException(status_code=403, detail="Solo administradores")

    stmt = select(Feedback).order_by(desc(Feedback.fecha_creacion)).limit(limite)
    if solo_negativos:
        stmt = stmt.where(Feedback.voto < 0)
    rows = (await sesion.execute(stmt)).scalars().all()
    return list(rows)
