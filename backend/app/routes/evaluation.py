"""Rutas para evaluación del aprendizaje."""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import obtener_usuario_actual
from app.database import get_db
from app.models.usuario import Usuario
from app.schemas.evaluacion import EvaluacionCrear, EvaluacionLeer
from app.services.evaluation_service import EvaluationService


router = APIRouter()


@router.post(
    "/responder",
    response_model=EvaluacionLeer,
    status_code=status.HTTP_201_CREATED,
    summary="Enviar respuesta a una actividad evaluativa",
)
async def responder(
    datos: EvaluacionCrear,
    usuario: Annotated[Usuario, Depends(obtener_usuario_actual)],
    sesion: Annotated[AsyncSession, Depends(get_db)],
):
    servicio = EvaluationService(sesion)
    try:
        evaluacion = await servicio.registrar_respuesta(
            usuario_id=usuario.id,
            dataset_id=datos.dataset_id,
            tipo_actividad=datos.tipo_actividad,
            respuesta_estudiante=datos.respuesta_estudiante,
        )
    except LookupError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc))
    await sesion.commit()
    await sesion.refresh(evaluacion)
    return evaluacion
