"""Schemas para evaluaciones del aprendizaje."""

from __future__ import annotations

import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field


class EvaluacionCrear(BaseModel):
    dataset_id: uuid.UUID
    tipo_actividad: str = Field(min_length=2, max_length=60)
    respuesta_estudiante: str = Field(min_length=1)


class EvaluacionLeer(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    usuario_id: uuid.UUID
    dataset_id: uuid.UUID
    tipo_actividad: str
    respuesta_estudiante: str
    respuesta_correcta: str
    puntaje: float
    retroalimentacion: str | None
    fecha_creacion: datetime
