"""Endpoints REST para gestionar el servidor MCP desde el frontend.

Endpoints:
    GET  /api/v1/mcp/estado          — info del server + tools + permisos
    GET  /api/v1/mcp/tools           — solo la lista de tools
    GET  /api/v1/mcp/permisos        — solo permisos efectivos
    PUT  /api/v1/mcp/permisos        — actualizar permisos
    POST /api/v1/mcp/invocar         — invocar una tool a mano (admin only)
    POST /api/v1/mcp/ping            — verificar que el server responde

Ver: docs/MCP_PLAN.md
"""

from __future__ import annotations

import sys
from pathlib import Path
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, status

from app.core.security import obtener_usuario_actual
from app.models.usuario import Usuario
from app.schemas.mcp import (
    EstadoMcp,
    InvocarToolRequest,
    InvocarToolRespuesta,
    McpToolDescripcion,
    PermisosMcpDto,
)
from app.services.mcp_client import obtener_cliente_mcp


# Import defensivo de mcp_server — puede no estar disponible en el
# container del backend si no se montó el volumen. En ese caso, los
# endpoints siguen respondiendo pero indican que MCP no está instalado.
_RAIZ = Path(__file__).resolve().parents[3]
if str(_RAIZ) not in sys.path:
    sys.path.insert(0, str(_RAIZ))

try:
    from mcp_server.permisos import (  # type: ignore
        PermisosMcp,
        cargar_permisos,
        guardar_permisos,
    )
    _MCP_DISPONIBLE = True
except ImportError:
    _MCP_DISPONIBLE = False

    # Stubs mínimos para que los type hints no rompan.
    class PermisosMcp:  # type: ignore
        directorios_permitidos: list = []
        tools_habilitadas: list = []
        modo_escribir: str = "bloquear"
        modo_ejecutar: str = "bloquear"
        max_bytes_lectura: int = 0
        timeout_ejecucion_segundos: int = 0

    def cargar_permisos() -> PermisosMcp:  # type: ignore
        return PermisosMcp()

    def guardar_permisos(_: PermisosMcp) -> None:  # type: ignore
        raise RuntimeError(
            "MCP no está instalado en este backend. Añade el volumen "
            "`./mcp_server:/app/mcp_server` a docker-compose."
        )


router = APIRouter()


def _solo_admin(usuario: Usuario) -> None:
    if usuario.rol != "administrador":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Solo administradores pueden configurar MCP.",
        )


def _permisos_a_dto(p: PermisosMcp) -> PermisosMcpDto:
    return PermisosMcpDto(
        directorios_permitidos=list(p.directorios_permitidos),
        tools_habilitadas=list(p.tools_habilitadas),
        modo_escribir=p.modo_escribir,
        modo_ejecutar=p.modo_ejecutar,
        max_bytes_lectura=p.max_bytes_lectura,
        timeout_ejecucion_segundos=p.timeout_ejecucion_segundos,
    )


@router.get("/estado", response_model=EstadoMcp, summary="Estado completo del MCP")
async def estado(
    usuario: Annotated[Usuario, Depends(obtener_usuario_actual)],
) -> EstadoMcp:
    if not _MCP_DISPONIBLE:
        return EstadoMcp(
            activo=False,
            handshake_completado=False,
            tools=[],
            permisos=_permisos_a_dto(cargar_permisos()),
        )
    try:
        cliente = await obtener_cliente_mcp()
        activo = await cliente.ping()
    except Exception:
        activo = False
    tools: list[McpToolDescripcion] = []
    if activo:
        try:
            raw = await cliente.listar_tools()
            tools = [
                McpToolDescripcion(
                    name=t.name,
                    description=t.description,
                    inputSchema=t.input_schema,
                )
                for t in raw
            ]
        except Exception:
            tools = []
    return EstadoMcp(
        activo=activo,
        handshake_completado=activo,
        tools=tools,
        permisos=_permisos_a_dto(cargar_permisos()),
    )


@router.get("/tools", response_model=list[McpToolDescripcion])
async def listar_tools(
    usuario: Annotated[Usuario, Depends(obtener_usuario_actual)],
) -> list[McpToolDescripcion]:
    cliente = await obtener_cliente_mcp()
    raw = await cliente.listar_tools()
    return [
        McpToolDescripcion(
            name=t.name, description=t.description, inputSchema=t.input_schema
        )
        for t in raw
    ]


@router.get("/permisos", response_model=PermisosMcpDto)
async def permisos_actuales(
    usuario: Annotated[Usuario, Depends(obtener_usuario_actual)],
) -> PermisosMcpDto:
    return _permisos_a_dto(cargar_permisos())


@router.put("/permisos", response_model=PermisosMcpDto)
async def actualizar_permisos(
    nuevos: PermisosMcpDto,
    usuario: Annotated[Usuario, Depends(obtener_usuario_actual)],
) -> PermisosMcpDto:
    _solo_admin(usuario)
    p = PermisosMcp(
        directorios_permitidos=list(nuevos.directorios_permitidos),
        tools_habilitadas=list(nuevos.tools_habilitadas),
        modo_escribir=nuevos.modo_escribir,
        modo_ejecutar=nuevos.modo_ejecutar,
        max_bytes_lectura=int(nuevos.max_bytes_lectura),
        timeout_ejecucion_segundos=int(nuevos.timeout_ejecucion_segundos),
    )
    guardar_permisos(p)
    # NOTA: el subproceso MCP cachea permisos al arranque. Para que tome
    # los nuevos, lo reiniciamos.
    from app.services.mcp_client import cerrar_cliente_mcp
    await cerrar_cliente_mcp()
    return _permisos_a_dto(p)


@router.post("/invocar", response_model=InvocarToolRespuesta)
async def invocar_tool(
    datos: InvocarToolRequest,
    usuario: Annotated[Usuario, Depends(obtener_usuario_actual)],
) -> InvocarToolRespuesta:
    """Invoca una tool MCP a mano — útil para probar desde el panel admin."""
    _solo_admin(usuario)
    cliente = await obtener_cliente_mcp()
    resultado = await cliente.invocar_tool(datos.nombre, datos.argumentos)
    return InvocarToolRespuesta(
        contenido=resultado.contenido,
        es_error=resultado.es_error,
    )


@router.post("/ping")
async def ping(
    usuario: Annotated[Usuario, Depends(obtener_usuario_actual)],
) -> dict:
    cliente = await obtener_cliente_mcp()
    ok = await cliente.ping()
    return {"ok": ok}
