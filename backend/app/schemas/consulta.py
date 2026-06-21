"""Schemas para consultas al orquestador IA."""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

from app.schemas.ai_response import RespuestaIAEducativa


ProveedorLiteral = Literal["gemini", "deepseek", "auto"]


class SolicitudGeneracion(BaseModel):
    """Lo que envía el estudiante al endpoint /ai/generar."""

    prompt: str = Field(min_length=4, max_length=4000)
    nivel_solicitado: Literal["basico", "intermedio", "avanzado"] | None = None
    tema_solicitado: str | None = Field(default=None, max_length=60)
    proveedor: ProveedorLiteral = "auto"
    temperatura: float = Field(default=0.4, ge=0.0, le=1.5)


class ConsultaCrear(BaseModel):
    usuario_id: uuid.UUID
    prompt_original: str
    nivel_solicitado: str | None = None
    tema_solicitado: str | None = None
    modelo_usado: str
    temperatura: float


class ConsultaResumen(BaseModel):
    """Vista compacta de una consulta para listados."""

    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    prompt_original: str
    modelo_usado: str
    estado: str
    tokens_totales: int
    latencia_segundos: float
    fecha_creacion: datetime


class ConsultaLeer(ConsultaResumen):
    """Vista detallada incluyendo la respuesta educativa estructurada."""

    respuesta: RespuestaIAEducativa | None = None
    error_mensaje: str | None = None
    intentos_reparacion_json: int = 0
    origen_respuesta: str = "api"
    score_recuperacion: float = 0.0
    puntaje_calidad: float = 0.0
