"""Schemas Pydantic para el endpoint /agente."""

from __future__ import annotations

from typing import Any, Literal

from pydantic import BaseModel, Field


class ConsultarAgenteRequest(BaseModel):
    """Pregunta al agente con tool calling."""

    pregunta: str = Field(..., min_length=1, max_length=8000)
    proveedor: Literal["auto", "gemini", "deepseek"] = "auto"
    max_iteraciones: int = Field(
        default=6, ge=1, le=15,
        description="Máximo de turnos LLM↔tools antes de abortar.",
    )
    historial: list[dict] | None = Field(
        default=None,
        description=(
            "Mensajes previos de la conversación para dar contexto. "
            "Formato: [{'rol': 'usuario'|'asistente', 'contenido': '...'}]"
        ),
    )


class PasoAgenteOut(BaseModel):
    """Un paso del ciclo expuesto al cliente."""

    iteracion: int
    razonamiento: str
    tool: str | None = None
    args: dict[str, Any] = Field(default_factory=dict)
    observacion: str | None = None
    es_error: bool = False


class ConsultarAgenteRespuesta(BaseModel):
    """Respuesta completa del agente, con su traza."""

    respuesta_final: str
    pasos: list[PasoAgenteOut]
    tools_usadas: list[str]
    n_iteraciones: int
    tokens_totales: int
    razon_fin: Literal["respuesta_final", "max_iters", "error"]
