"""Rutas para gestión del dataset educativo."""

from __future__ import annotations

import uuid
from pathlib import Path
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import obtener_usuario_actual, requerir_rol
from app.database import get_db
from app.models.usuario import RolUsuario, Usuario
from app.schemas.dataset import DatasetLeer, DatasetValidacion
from app.services.dataset_service import DatasetService


router = APIRouter()


@router.get("/", response_model=list[DatasetLeer], summary="Listar dataset educativo")
async def listar(
    sesion: Annotated[AsyncSession, Depends(get_db)],
    _usuario: Annotated[Usuario, Depends(obtener_usuario_actual)],
    solo_validados: bool = False,
    limite: int = 100,
) -> list:
    servicio = DatasetService(sesion)
    return await servicio.listar(solo_validados=solo_validados, limite=limite)


@router.get("/estadisticas", summary="Estadísticas globales del dataset")
async def estadisticas(
    sesion: Annotated[AsyncSession, Depends(get_db)],
    _usuario: Annotated[Usuario, Depends(obtener_usuario_actual)],
) -> dict[str, int]:
    servicio = DatasetService(sesion)
    return await servicio.estadisticas()


@router.post(
    "/{dataset_id}/validar",
    response_model=DatasetLeer,
    summary="Validar (o rechazar) un registro del dataset",
)
async def validar(
    dataset_id: uuid.UUID,
    datos: DatasetValidacion,
    sesion: Annotated[AsyncSession, Depends(get_db)],
    _usuario: Annotated[
        Usuario,
        Depends(requerir_rol(RolUsuario.INVESTIGADOR, RolUsuario.ADMINISTRADOR)),
    ],
):
    servicio = DatasetService(sesion)
    try:
        registro = await servicio.marcar_validacion(
            dataset_id=dataset_id,
            validado=datos.validado,
            validado_por=datos.validado_por,
            observaciones=datos.observaciones_validacion,
        )
    except LookupError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc))
    await sesion.commit()
    await sesion.refresh(registro)
    return registro


@router.post(
    "/exportar-jsonl",
    summary="Exportar dataset validado a JSONL (Alpaca-like)",
)
async def exportar_jsonl(
    sesion: Annotated[AsyncSession, Depends(get_db)],
    _usuario: Annotated[
        Usuario,
        Depends(requerir_rol(RolUsuario.INVESTIGADOR, RolUsuario.ADMINISTRADOR)),
    ],
    solo_validados: bool = True,
    nombre_archivo: str = "finetune.jsonl",
) -> dict[str, str | int]:
    seguro = "".join(c for c in nombre_archivo if c.isalnum() or c in ("_", "-", "."))
    if not seguro.endswith(".jsonl"):
        seguro += ".jsonl"
    ruta = Path("datasets/processed") / seguro
    servicio = DatasetService(sesion)
    cantidad, destino = await servicio.exportar_jsonl(ruta, solo_validados=solo_validados)
    await sesion.commit()
    return {"cantidad": cantidad, "ruta": str(destino)}
