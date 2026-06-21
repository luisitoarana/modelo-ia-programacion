"""Schemas para el chat conversacional."""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Any

from pydantic import BaseModel, ConfigDict, Field


class MensajeLeer(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    rol: str
    contenido: str
    origen_respuesta: str | None = None
    tokens_totales: int = 0
    latencia_segundos: float = 0.0
    fecha_creacion: datetime
    # Metadatos opcionales: fuentes_rag, fuentes_web, n_imagenes, proveedor…
    # La UI los lee para mostrar chips de citas, banners, etc.
    metadata_json: dict[str, Any] | None = None


class ConversacionResumen(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    titulo: str
    proyecto: str | None = None
    fecha_actualizacion: datetime


class ConversacionDetalle(ConversacionResumen):
    mensajes: list[MensajeLeer] = Field(default_factory=list)


class CrearConversacion(BaseModel):
    titulo: str = Field(default="Nueva conversación", max_length=160)


class EnviarMensaje(BaseModel):
    contenido: str = Field(min_length=1, max_length=8000)
    idioma: str = Field(default="es", max_length=10)
    # Si es True el backend invoca búsqueda web cuando la pregunta lo amerita
    # (heurística sobre el texto). Por defecto desactivado para ahorrar latencia.
    buscar_web: bool = Field(default=False)
    # Switcher multi-IA: el usuario elige qué motor responde este turno.
    # Valores: "auto" (default — modelo propio si está, si no API),
    # "propio" (forzar modelo propio), "gemini", "deepseek".
    proveedor: str = Field(default="auto", max_length=30)


class RespuestaEnvio(BaseModel):
    conversacion_id: uuid.UUID
    titulo: str
    mensaje_usuario: MensajeLeer
    mensaje_asistente: MensajeLeer


class RenombrarConversacion(BaseModel):
    titulo: str = Field(min_length=1, max_length=160)
