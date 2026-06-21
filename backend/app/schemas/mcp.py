"""Schemas Pydantic para los endpoints MCP del backend."""

from __future__ import annotations

from typing import Any, Literal

from pydantic import BaseModel, Field


ModoConfirmacion = Literal["auto", "confirmar", "bloquear"]


class McpToolDescripcion(BaseModel):
    """Una tool expuesta por el servidor MCP, visible para el cliente."""

    name: str
    description: str
    input_schema: dict[str, Any] = Field(alias="inputSchema")

    class Config:
        populate_by_name = True


class EstadoMcp(BaseModel):
    """Estado actual del servidor MCP + permisos efectivos."""

    activo: bool
    handshake_completado: bool
    tools: list[McpToolDescripcion]
    permisos: "PermisosMcpDto"


class PermisosMcpDto(BaseModel):
    """Permisos persistidos en ~/.explicador/mcp.json."""

    directorios_permitidos: list[str] = Field(default_factory=list)
    tools_habilitadas: list[str] = Field(default_factory=list)
    modo_escribir: ModoConfirmacion = "bloquear"
    modo_ejecutar: ModoConfirmacion = "bloquear"
    max_bytes_lectura: int = 256 * 1024
    timeout_ejecucion_segundos: int = 10


class InvocarToolRequest(BaseModel):
    """Invocación manual de una tool desde el panel admin."""

    nombre: str
    argumentos: dict[str, Any] = Field(default_factory=dict)


class InvocarToolRespuesta(BaseModel):
    contenido: str
    es_error: bool


# Necesario para que Pydantic resuelva las forward references.
EstadoMcp.model_rebuild()
