"""Schemas para el dataset educativo y exportación a JSONL."""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Any

from pydantic import BaseModel, ConfigDict, Field

from app.schemas.ai_response import RespuestaIAEducativa


class DatasetCrear(BaseModel):
    usuario_id: uuid.UUID
    consulta_id: uuid.UUID
    respuesta: RespuestaIAEducativa


class DatasetLeer(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    usuario_id: uuid.UUID
    consulta_id: uuid.UUID
    nivel: str
    tema: str
    pregunta: str
    codigo: str
    explicacion_general: str
    respuesta_json: dict[str, Any]
    fuente_ia: str
    validado: bool
    exportado_para_finetuning: bool
    fecha_creacion: datetime


class DatasetValidacion(BaseModel):
    """Payload del investigador para validar (o rechazar) un registro."""

    validado: bool
    validado_por: str = Field(min_length=2, max_length=180)
    observaciones_validacion: str | None = Field(default=None, max_length=2000)


class ExportacionJSONLPar(BaseModel):
    """Par instruction/response listo para fine-tuning (formato Alpaca-like)."""

    instruction: str
    input: str = ""
    output: str
    metadata: dict[str, Any] = Field(default_factory=dict)
