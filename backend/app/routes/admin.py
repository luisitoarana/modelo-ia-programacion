"""Rutas exclusivas del administrador.

Gestión segura de API keys (cifradas en BD), prueba de conexión y resumen del
sistema. Solo accesible con rol administrador.
"""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy import func, select
from sqlalchemy.engine.url import make_url
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import requerir_rol
from app.config import settings
from app.database import get_db
from app.models.conocimiento import EstadoConocimiento, UnidadConocimiento
from app.models.consulta import Consulta
from app.models.dataset import DatasetEducativo
from app.models.usuario import RolUsuario, Usuario
from app.models.intento_aprendizaje import AsignacionEstudio
from app.services import runtime_config
from app.services.ai_provider import GeminiProvider, DeepSeekProvider, ProveedorIAError
from app.services.config_service import ConfigService


router = APIRouter()
_SOLO_ADMIN = requerir_rol(RolUsuario.ADMINISTRADOR)


class ActualizarAPIKey(BaseModel):
    proveedor: str = Field(pattern="^(gemini|deepseek|groq|openai|anthropic|openrouter)$")
    api_key: str = Field(min_length=8, max_length=400)


_CLAVE_POR_PROVEEDOR = runtime_config.CLAVES_PROVEEDOR


@router.get("/usuarios", summary="Participantes y condición asignada")
async def listar_usuarios(
    sesion: Annotated[AsyncSession, Depends(get_db)],
    _admin: Annotated[Usuario, Depends(_SOLO_ADMIN)],
) -> list[dict[str, object]]:
    filas = await sesion.execute(
        select(Usuario, AsignacionEstudio)
        .outerjoin(AsignacionEstudio, AsignacionEstudio.usuario_id == Usuario.id)
        .order_by(Usuario.fecha_creacion.desc()).limit(1000)
    )
    return [
        {"id": str(usuario.id), "nombre": usuario.nombre, "email": usuario.email,
         "rol": usuario.rol.value, "activo": usuario.activo,
         "institucion": usuario.institucion, "nivel_academico": usuario.nivel_academico,
         "condicion": asignacion.condicion if asignacion else None,
         "fase": asignacion.fase if asignacion else None}
        for usuario, asignacion in filas.all()
    ]


class EstadoCuenta(BaseModel):
    activo: bool


@router.patch("/usuarios/{usuario_id}/estado", summary="Activar o desactivar estudiante")
async def cambiar_estado_usuario(
    usuario_id: str,
    datos: EstadoCuenta,
    sesion: Annotated[AsyncSession, Depends(get_db)],
    _admin: Annotated[Usuario, Depends(_SOLO_ADMIN)],
) -> dict[str, object]:
    from uuid import UUID
    try:
        identificador = UUID(usuario_id)
    except ValueError as exc:
        raise HTTPException(status_code=422, detail="Identificador inválido.") from exc
    usuario = await sesion.get(Usuario, identificador)
    if usuario is None:
        raise HTTPException(status_code=404, detail="Usuario no encontrado.")
    if usuario.rol != RolUsuario.ESTUDIANTE:
        raise HTTPException(status_code=403, detail="Esta acción solo aplica a estudiantes.")
    usuario.activo = datos.activo
    await sesion.commit()
    return {"id": usuario_id, "activo": usuario.activo}


@router.get("/config/api-keys", summary="Estado de las API keys (enmascaradas)")
async def estado_api_keys(
    sesion: Annotated[AsyncSession, Depends(get_db)],
    _admin: Annotated[Usuario, Depends(_SOLO_ADMIN)],
) -> dict[str, object]:
    cfg = ConfigService(sesion)
    return {"keys": await cfg.estado_api_keys()}


@router.put("/config/api-keys", summary="Guardar/actualizar una API key (cifrada)")
async def guardar_api_key(
    payload: ActualizarAPIKey,
    sesion: Annotated[AsyncSession, Depends(get_db)],
    admin: Annotated[Usuario, Depends(_SOLO_ADMIN)],
) -> dict[str, str]:
    clave = _CLAVE_POR_PROVEEDOR[payload.proveedor]
    cfg = ConfigService(sesion)
    await cfg.set_api_key(clave, payload.api_key.strip(), actualizado_por=admin.email)
    runtime_config.set_valor(clave, payload.api_key.strip())
    await sesion.commit()
    return {"estado": "ok", "proveedor": payload.proveedor}


@router.post("/config/probar/{proveedor}", summary="Probar una API key con una llamada real")
async def probar_api_key(
    proveedor: str,
    _admin: Annotated[Usuario, Depends(_SOLO_ADMIN)],
) -> dict[str, object]:
    if proveedor not in _CLAVE_POR_PROVEEDOR:
        raise HTTPException(status_code=400, detail="Proveedor inválido.")
    from app.services.ai_provider import obtener_proveedor
    cliente = obtener_proveedor(proveedor)
    if not cliente.esta_configurado:
        return {"ok": False, "detalle": "No hay API key configurada para este proveedor."}
    try:
        resultado = await cliente.generar(
            sistema="Responde solo con la palabra OK.",
            usuario="Di OK.",
            temperatura=0.0,
            max_tokens=8,
        )
        return {
            "ok": True,
            "proveedor": proveedor,
            "modelo": resultado.modelo,
            "respuesta": resultado.texto[:60],
            "latencia_segundos": resultado.latencia_segundos,
        }
    except ProveedorIAError as exc:
        return {"ok": False, "detalle": str(exc)}


@router.get("/resumen", summary="Resumen del sistema para el administrador")
async def resumen(
    sesion: Annotated[AsyncSession, Depends(get_db)],
    _admin: Annotated[Usuario, Depends(_SOLO_ADMIN)],
) -> dict[str, object]:
    usuarios = await sesion.scalar(select(func.count(Usuario.id))) or 0
    consultas = await sesion.scalar(select(func.count(Consulta.id))) or 0
    dataset = await sesion.scalar(select(func.count(DatasetEducativo.id))) or 0
    unidades = await sesion.scalar(select(func.count(UnidadConocimiento.id))) or 0
    validadas = await sesion.scalar(
        select(func.count(UnidadConocimiento.id)).where(
            UnidadConocimiento.estado == EstadoConocimiento.VALIDADO
        )
    ) or 0
    return {
        "base_datos": {
            "motor": make_url(settings.database_url).get_backend_name(),
            "host": make_url(settings.database_url).host or "archivo local",
        },
        "proveedores_ia_activos": runtime_config.proveedores_configurados(),
        "usuarios": int(usuarios),
        "consultas": int(consultas),
        "dataset": int(dataset),
        "unidades_conocimiento": int(unidades),
        "unidades_validadas": int(validadas),
    }
