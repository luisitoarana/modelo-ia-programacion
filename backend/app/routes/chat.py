"""Rutas del chat conversacional (estilo asistente IA)."""

from __future__ import annotations

import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import obtener_usuario_actual
from app.database import get_db
from app.models.usuario import Usuario
from app.schemas.chat import (
    ConversacionDetalle,
    ConversacionResumen,
    CrearConversacion,
    EnviarMensaje,
    RenombrarConversacion,
    RespuestaEnvio,
)
from app.services.ai_provider import proveedores_disponibles
from app.services.chat_service import ChatService
from app.services import motor_pedagogico_service


router = APIRouter()


@router.get("/proveedores", summary="Proveedores de IA disponibles para este chat")
async def listar_proveedores(
    usuario: Annotated[Usuario, Depends(obtener_usuario_actual)],
) -> dict:
    """Opciones visibles con procedencia y política de red explícitas."""
    salida = [
        {
            "id": "auto",
            "nombre": "Asistente Python IA",
            "descripcion": "Selección automática: puede usar una API externa si está configurada.",
            "tipo": "auto",
            "disponible": True,
        },
        {
            "id": "propio",
            "nombre": "Motor Pedagógico Propio (Local Offline)",
            "descripcion": "Motor neuronal propio local offline con andamiaje pedagógico y aceleración por hardware.",
            "tipo": "local",
            "disponible": motor_pedagogico_service.esta_disponible(),
        },
    ]
    return {"proveedores": salida}


@router.get("/conversaciones", response_model=list[ConversacionResumen],
            summary="Listar conversaciones (Recientes)")
async def listar(
    usuario: Annotated[Usuario, Depends(obtener_usuario_actual)],
    sesion: Annotated[AsyncSession, Depends(get_db)],
) -> list:
    return await ChatService(sesion).listar_conversaciones(usuario.id)


@router.post("/conversaciones", response_model=ConversacionResumen,
             status_code=status.HTTP_201_CREATED, summary="Crear nueva conversación")
async def crear(
    datos: CrearConversacion,
    usuario: Annotated[Usuario, Depends(obtener_usuario_actual)],
    sesion: Annotated[AsyncSession, Depends(get_db)],
):
    servicio = ChatService(sesion)
    conv = await servicio.crear_conversacion(usuario.id, titulo=datos.titulo)
    await sesion.commit()
    await sesion.refresh(conv)
    return conv


@router.get("/conversaciones/{conv_id}", response_model=ConversacionDetalle,
            summary="Obtener una conversación con sus mensajes")
async def detalle(
    conv_id: uuid.UUID,
    usuario: Annotated[Usuario, Depends(obtener_usuario_actual)],
    sesion: Annotated[AsyncSession, Depends(get_db)],
):
    servicio = ChatService(sesion)
    conv = await servicio.obtener_conversacion(conv_id, usuario.id)
    if conv is None:
        raise HTTPException(status_code=404, detail="Conversación no encontrada.")
    mensajes = await servicio.mensajes(conv_id)
    return ConversacionDetalle(
        id=conv.id,
        titulo=conv.titulo,
        proyecto=conv.proyecto,
        fecha_actualizacion=conv.fecha_actualizacion,
        mensajes=mensajes,
    )


@router.post("/conversaciones/{conv_id}/mensajes", response_model=RespuestaEnvio,
             summary="Enviar un mensaje y recibir la respuesta del asistente")
async def enviar(
    conv_id: uuid.UUID,
    datos: EnviarMensaje,
    usuario: Annotated[Usuario, Depends(obtener_usuario_actual)],
    sesion: Annotated[AsyncSession, Depends(get_db)],
) -> RespuestaEnvio:
    servicio = ChatService(sesion)
    conv = await servicio.obtener_conversacion(conv_id, usuario.id)
    if conv is None:
        raise HTTPException(status_code=404, detail="Conversación no encontrada.")
    msg_u, msg_a = await servicio.enviar_mensaje(
        conv,
        datos.contenido,
        idioma=datos.idioma,
        habilitar_busqueda_web=datos.buscar_web,
        proveedor_forzado=datos.proveedor,
        modo_acompanamiento=datos.modo_acompanamiento,
        nivel_modulo=datos.nivel_modulo,
    )
    await sesion.commit()
    await sesion.refresh(msg_u)
    await sesion.refresh(msg_a)
    return RespuestaEnvio(
        conversacion_id=conv.id,
        titulo=conv.titulo,
        mensaje_usuario=msg_u,
        mensaje_asistente=msg_a,
    )


# Endpoint MULTIPART para mensajes con imágenes adjuntas.
# Mantenemos el endpoint JSON original arriba para clientes existentes;
# este es el camino nuevo para visión multimodal. Ver docs/VISION_PLAN.md.
_MIMES_IMAGEN_PERMITIDOS = {"image/png", "image/jpeg", "image/jpg", "image/webp"}
_MAX_BYTES_IMAGEN = 5 * 1024 * 1024  # 5 MB
_MAX_IMAGENES = 3


@router.post(
    "/conversaciones/{conv_id}/mensajes-multimodal",
    response_model=RespuestaEnvio,
    summary="Enviar mensaje con imágenes adjuntas (vision via Gemini)",
)
async def enviar_multimodal(
    conv_id: uuid.UUID,
    usuario: Annotated[Usuario, Depends(obtener_usuario_actual)],
    sesion: Annotated[AsyncSession, Depends(get_db)],
    contenido: str = Form(..., description="Texto del mensaje del usuario"),
    idioma: str = Form("es"),
    buscar_web: bool = Form(False),
    imagenes: list[UploadFile] = File(
        default=[], description="Hasta 3 imágenes (PNG/JPEG/WebP, max 5 MB c/u)"
    ),
) -> RespuestaEnvio:
    # Validación de imágenes
    if len(imagenes) > _MAX_IMAGENES:
        raise HTTPException(
            status_code=400,
            detail=f"Máximo {_MAX_IMAGENES} imágenes por mensaje",
        )
    imagenes_bytes: list[tuple[bytes, str]] = []
    for img in imagenes:
        if img.content_type not in _MIMES_IMAGEN_PERMITIDOS:
            raise HTTPException(
                status_code=400,
                detail=f"Formato no soportado: {img.content_type}. "
                       f"Usa PNG, JPEG o WebP.",
            )
        blob = await img.read()
        if len(blob) > _MAX_BYTES_IMAGEN:
            raise HTTPException(
                status_code=400,
                detail=f"Imagen '{img.filename}' supera el máximo de 5 MB",
            )
        imagenes_bytes.append((blob, img.content_type))

    servicio = ChatService(sesion)
    conv = await servicio.obtener_conversacion(conv_id, usuario.id)
    if conv is None:
        raise HTTPException(status_code=404, detail="Conversación no encontrada.")
    msg_u, msg_a = await servicio.enviar_mensaje(
        conv,
        contenido,
        idioma=idioma,
        habilitar_busqueda_web=buscar_web,
        imagenes=imagenes_bytes or None,
    )
    await sesion.commit()
    await sesion.refresh(msg_u)
    await sesion.refresh(msg_a)
    return RespuestaEnvio(
        conversacion_id=conv.id,
        titulo=conv.titulo,
        mensaje_usuario=msg_u,
        mensaje_asistente=msg_a,
    )


@router.post("/mensaje-rapido", response_model=RespuestaEnvio,
             summary="Crear conversación y enviar el primer mensaje en un paso")
async def mensaje_rapido(
    datos: EnviarMensaje,
    usuario: Annotated[Usuario, Depends(obtener_usuario_actual)],
    sesion: Annotated[AsyncSession, Depends(get_db)],
) -> RespuestaEnvio:
    servicio = ChatService(sesion)
    conv = await servicio.crear_conversacion(usuario.id)
    msg_u, msg_a = await servicio.enviar_mensaje(
        conv,
        datos.contenido,
        idioma=datos.idioma,
        habilitar_busqueda_web=datos.buscar_web,
        proveedor_forzado=datos.proveedor,
        modo_acompanamiento=datos.modo_acompanamiento,
        nivel_modulo=datos.nivel_modulo,
    )
    await sesion.commit()
    await sesion.refresh(conv)
    await sesion.refresh(msg_u)
    await sesion.refresh(msg_a)
    return RespuestaEnvio(
        conversacion_id=conv.id,
        titulo=conv.titulo,
        mensaje_usuario=msg_u,
        mensaje_asistente=msg_a,
    )


@router.patch("/conversaciones/{conv_id}", response_model=ConversacionResumen,
              summary="Renombrar una conversación")
async def renombrar(
    conv_id: uuid.UUID,
    datos: RenombrarConversacion,
    usuario: Annotated[Usuario, Depends(obtener_usuario_actual)],
    sesion: Annotated[AsyncSession, Depends(get_db)],
):
    servicio = ChatService(sesion)
    conv = await servicio.obtener_conversacion(conv_id, usuario.id)
    if conv is None:
        raise HTTPException(status_code=404, detail="Conversación no encontrada.")
    await servicio.renombrar(conv, datos.titulo)
    await sesion.commit()
    await sesion.refresh(conv)
    return conv


@router.delete("/conversaciones/{conv_id}", summary="Eliminar una conversación")
async def eliminar(
    conv_id: uuid.UUID,
    usuario: Annotated[Usuario, Depends(obtener_usuario_actual)],
    sesion: Annotated[AsyncSession, Depends(get_db)],
) -> dict[str, str]:
    servicio = ChatService(sesion)
    conv = await servicio.obtener_conversacion(conv_id, usuario.id)
    if conv is None:
        raise HTTPException(status_code=404, detail="Conversación no encontrada.")
    await servicio.eliminar(conv)
    await sesion.commit()
    return {"estado": "eliminada"}
