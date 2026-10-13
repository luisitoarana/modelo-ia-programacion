"""Rutas del orquestador IA: generación y explicación de código."""

from __future__ import annotations

import asyncio
import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import obtener_usuario_actual
from app.database import get_db
from app.models.consulta import Consulta, EstadoConsulta, FuenteIA
from app.models.usuario import Usuario
from app.schemas.ai_response import RespuestaIAEducativa
from app.schemas.consulta import ConsultaLeer, ConsultaResumen, SolicitudGeneracion
from app.services.ai_provider import obtener_proveedor, proveedores_disponibles
from app.services.dataset_service import DatasetService
from app.services.educational_engine import EducationalEngine
from app.services.explanation_service import ExplicacionServiceError
from app.services import model_inference_service as modelo
from app.utils.logger import obtener_logger
from pydantic import BaseModel, Field


router = APIRouter()
log = obtener_logger(__name__)


class PreguntaModelo(BaseModel):
    instruccion: str = Field(min_length=3, max_length=2000)
    entrada: str = Field(default="", max_length=4000)
    max_tokens: int | None = Field(default=None, ge=16, le=512)
    temperatura: float | None = Field(default=None, ge=0.0, le=1.5)


class RespuestaModeloOut(BaseModel):
    texto: str
    tokens_generados: int
    latencia_segundos: float
    device: str
    num_parametros: int
    origen: str = "modelo_propio"


def _resolver_fuente(proveedor: str) -> FuenteIA:
    return {
        "gemini": FuenteIA.GEMINI,
        "deepseek": FuenteIA.DEEPSEEK,
    }.get(proveedor, FuenteIA.GEMINI)


@router.get("/modelo-estado", summary="Estado del LLM propio entrenado")
async def modelo_estado() -> dict[str, object]:
    return modelo.estado_modelo()


@router.post(
    "/preguntar-modelo",
    response_model=RespuestaModeloOut,
    summary="Responder con el MODELO PROPIO (Usuario → Modelo propio → Respuesta)",
)
async def preguntar_modelo(
    payload: PreguntaModelo,
    _usuario: Annotated[Usuario, Depends(obtener_usuario_actual)],
) -> RespuestaModeloOut:
    """Flujo objetivo de la investigación: responde con el LLM entrenado desde
    cero, SIN llamar a ninguna API externa."""
    if not modelo.modelo_disponible():
        estado = modelo.estado_modelo()
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=f"Modelo propio no disponible: {estado.get('motivo')}",
        )
    try:
        r = await asyncio.to_thread(
            modelo.responder_con_modelo,
            payload.instruccion,
            entrada=payload.entrada,
            max_tokens=payload.max_tokens,
            temperatura=payload.temperatura,
        )
    except RuntimeError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail=str(exc)
        ) from exc

    return RespuestaModeloOut(
        texto=(r.texto or "").strip(),
        tokens_generados=r.tokens_generados,
        latencia_segundos=r.latencia_segundos,
        device=r.device,
        num_parametros=r.num_parametros,
    )


@router.get("/proveedores", summary="Listar proveedores IA disponibles")
async def listar_proveedores() -> dict[str, list[str] | str]:
    return {
        "disponibles": proveedores_disponibles(),
        "por_defecto": obtener_proveedor("auto").nombre,
    }


@router.post(
    "/generar",
    response_model=ConsultaLeer,
    status_code=status.HTTP_201_CREATED,
    summary="Responder al estudiante (retrieval-first: base de conocimiento → API)",
)
async def generar_explicacion(
    solicitud: SolicitudGeneracion,
    usuario: Annotated[Usuario, Depends(obtener_usuario_actual)],
    sesion: Annotated[AsyncSession, Depends(get_db)],
) -> ConsultaLeer:
    """Punto de entrada del estudiante.

    El motor educativo intenta PRIMERO responder desde la base de conocimiento
    propia. Solo si no hay una unidad validada suficientemente similar, usa la
    API como herramienta auxiliar, valida la calidad y guarda el resultado como
    conocimiento candidato para futuras consultas.
    """
    proveedor = obtener_proveedor(solicitud.proveedor)
    fuente = _resolver_fuente(proveedor.nombre)

    consulta = Consulta(
        usuario_id=usuario.id,
        prompt_original=solicitud.prompt,
        nivel_solicitado=solicitud.nivel_solicitado,
        tema_solicitado=solicitud.tema_solicitado,
        modelo_usado=fuente,
        temperatura=solicitud.temperatura,
        estado=EstadoConsulta.EN_PROCESO,
    )
    sesion.add(consulta)
    await sesion.flush()

    engine = EducationalEngine(sesion)
    respuesta: RespuestaIAEducativa | None = None
    try:
        motor = await engine.responder(
            prompt=solicitud.prompt,
            nivel=solicitud.nivel_solicitado,
            tema=solicitud.tema_solicitado,
            proveedor=solicitud.proveedor,
            temperatura=solicitud.temperatura,
        )
        respuesta = motor.respuesta
        consulta.origen_respuesta = motor.origen
        consulta.score_recuperacion = motor.score_recuperacion
        consulta.tokens_totales = motor.tokens_totales
        consulta.latencia_segundos = motor.latencia_segundos
        consulta.intentos_reparacion_json = motor.intentos_reparacion
        consulta.puntaje_calidad = (
            motor.calidad.puntaje_total if motor.calidad else 0.0
        )
        if motor.unidad_id:
            try:
                consulta.unidad_conocimiento_id = uuid.UUID(motor.unidad_id)
            except (ValueError, TypeError):
                consulta.unidad_conocimiento_id = None
        consulta.estado = EstadoConsulta.COMPLETADA
    except ExplicacionServiceError as exc:
        log.error("Error en motor educativo: %s", exc)
        consulta.estado = EstadoConsulta.FALLIDA
        consulta.error_mensaje = str(exc)[:2000]
        await sesion.commit()
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"No se pudo producir una respuesta válida: {exc}",
        ) from exc

    if respuesta is not None:
        dataset_service = DatasetService(sesion)
        await dataset_service.registrar_desde_respuesta(
            usuario_id=usuario.id,
            consulta_id=consulta.id,
            respuesta=respuesta,
        )

    await sesion.commit()
    await sesion.refresh(consulta)

    return ConsultaLeer(
        id=consulta.id,
        prompt_original=consulta.prompt_original,
        modelo_usado=consulta.modelo_usado.value,
        estado=consulta.estado.value,
        tokens_totales=consulta.tokens_totales,
        latencia_segundos=consulta.latencia_segundos,
        fecha_creacion=consulta.fecha_creacion,
        respuesta=respuesta,
        error_mensaje=consulta.error_mensaje,
        intentos_reparacion_json=consulta.intentos_reparacion_json,
        origen_respuesta=consulta.origen_respuesta,
        score_recuperacion=consulta.score_recuperacion,
        puntaje_calidad=consulta.puntaje_calidad,
    )


@router.get(
    "/historial",
    response_model=list[ConsultaResumen],
    summary="Historial de consultas del usuario actual",
)
async def historial(
    usuario: Annotated[Usuario, Depends(obtener_usuario_actual)],
    sesion: Annotated[AsyncSession, Depends(get_db)],
    limite: int = 50,
) -> list[Consulta]:
    consultas = (
        await sesion.scalars(
            select(Consulta)
            .where(Consulta.usuario_id == usuario.id)
            .order_by(Consulta.fecha_creacion.desc())
            .limit(min(max(limite, 1), 200))
        )
    ).all()
    return list(consultas)


@router.get(
    "/consulta/{consulta_id}",
    response_model=ConsultaLeer,
    summary="Detalle de una consulta",
)
async def detalle_consulta(
    consulta_id: uuid.UUID,
    usuario: Annotated[Usuario, Depends(obtener_usuario_actual)],
    sesion: Annotated[AsyncSession, Depends(get_db)],
) -> ConsultaLeer:
    consulta = await sesion.get(Consulta, consulta_id)
    if consulta is None or consulta.usuario_id != usuario.id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="No encontrada")

    respuesta: RespuestaIAEducativa | None = None
    if consulta.dataset is not None:
        try:
            respuesta = RespuestaIAEducativa.model_validate(
                consulta.dataset.respuesta_json
            )
        except Exception:  # noqa: BLE001 — defensa para datos legacy
            respuesta = None

    return ConsultaLeer(
        id=consulta.id,
        prompt_original=consulta.prompt_original,
        modelo_usado=consulta.modelo_usado.value,
        estado=consulta.estado.value,
        tokens_totales=consulta.tokens_totales,
        latencia_segundos=consulta.latencia_segundos,
        fecha_creacion=consulta.fecha_creacion,
        respuesta=respuesta,
        error_mensaje=consulta.error_mensaje,
        intentos_reparacion_json=consulta.intentos_reparacion_json,
    )
