"""Schemas Pydantic para el endpoint de feedback."""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field


class CrearFeedback(BaseModel):
    """Payload que envía el frontend al hacer click en 👍 o 👎."""

    mensaje_id: uuid.UUID = Field(
        ..., description="ID del mensaje del asistente que recibe el voto"
    )
    voto: Literal[-1, 1] = Field(
        ..., description="+1 para 👍, -1 para 👎"
    )
    razon: str | None = Field(
        None,
        max_length=40,
        description=(
            "Una de: preciso, claro, incorrecto, alucina, incompleto, "
            "muy_largo, muy_corto, fuera_de_tema"
        ),
    )
    comentario: str | None = Field(
        None, max_length=500, description="Comentario libre del usuario"
    )


class FeedbackCreado(BaseModel):
    """Respuesta del endpoint al guardar un feedback."""

    id: uuid.UUID
    voto: int
    fecha_creacion: datetime
    ok: bool = True

    class Config:
        from_attributes = True


class FeedbackResumen(BaseModel):
    """Vista de un feedback para administradores."""

    id: uuid.UUID
    voto: int
    razon: str | None
    comentario: str | None
    modelo: str | None
    nivel: str | None
    prompt: str
    respuesta: str
    procesado: bool
    fecha_creacion: datetime

    class Config:
        from_attributes = True


class EstadisticasFeedback(BaseModel):
    """KPI agregado para el panel admin."""

    total: int
    positivos: int
    negativos: int
    tasa_aprobacion: float = Field(
        description="positivos / total — entre 0.0 y 1.0"
    )
    pendientes_procesar: int
    por_modelo: dict[str, int]
    por_razon: dict[str, int]
