"""Rutas exclusivas del administrador.

Gestión segura de API keys (cifradas en BD), prueba de conexión y resumen del
sistema. Solo accesible con rol administrador.
"""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import requerir_rol
from app.database import get_db
from app.models.conocimiento import EstadoConocimiento, UnidadConocimiento
from app.models.consulta import Consulta
from app.models.dataset import DatasetEducativo
from app.models.usuario import RolUsuario, Usuario
from app.services import runtime_config
from app.services.ai_provider import GeminiProvider, DeepSeekProvider, ProveedorIAError
from app.services.config_service import ConfigService


router = APIRouter()
_SOLO_ADMIN = requerir_rol(RolUsuario.ADMINISTRADOR)


class ActualizarAPIKey(BaseModel):
    proveedor: str = Field(pattern="^(gemini|deepseek)$")
    api_key: str = Field(min_length=8, max_length=400)


_CLAVE_POR_PROVEEDOR = {
    "gemini": runtime_config.GEMINI_API_KEY,
    "deepseek": runtime_config.DEEPSEEK_API_KEY,
}


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
    await sesion.commit()
    return {"estado": "ok", "proveedor": payload.proveedor}


@router.post("/config/probar/{proveedor}", summary="Probar una API key con una llamada real")
async def probar_api_key(
    proveedor: str,
    _admin: Annotated[Usuario, Depends(_SOLO_ADMIN)],
) -> dict[str, object]:
    if proveedor not in _CLAVE_POR_PROVEEDOR:
        raise HTTPException(status_code=400, detail="Proveedor inválido.")
    cliente = GeminiProvider() if proveedor == "gemini" else DeepSeekProvider()
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
        "proveedores_ia_activos": runtime_config.proveedores_configurados(),
        "usuarios": int(usuarios),
        "consultas": int(consultas),
        "dataset": int(dataset),
        "unidades_conocimiento": int(unidades),
        "unidades_validadas": int(validadas),
    }
