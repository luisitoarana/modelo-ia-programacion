"""Rutas de herramientas del agente (capacidades).

Por ahora: búsqueda web + ejecutar Python en sandbox. Estas herramientas
son la base de la capa agéntica; el modelo (propio, cuando esté entrenado)
las invocará en su bucle.
"""

from __future__ import annotations

import ast
import sys
from pathlib import Path
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, Field

from app.core.security import obtener_usuario_actual
from app.models.usuario import Usuario
from app.services.web_search import buscar_web

# Reusar el sandbox del MCP server para ejecutar Python con timeout.
_RAIZ = Path(__file__).resolve().parents[3]
if str(_RAIZ) not in sys.path:
    sys.path.insert(0, str(_RAIZ))
try:
    from mcp_server.sandbox import ejecutar as _exec_sandbox  # type: ignore
    _SANDBOX_OK = True
except ImportError:
    _SANDBOX_OK = False


router = APIRouter()


class ValidarSintaxisReq(BaseModel):
    codigo: str = Field(..., min_length=1, max_length=20_000)


@router.post("/validar-sintaxis", summary="Verificar sintaxis con el parser real de Python")
async def validar_sintaxis(
    req: ValidarSintaxisReq,
    _u: Annotated[Usuario, Depends(obtener_usuario_actual)],
) -> dict[str, object]:
    try:
        ast.parse(req.codigo)
    except SyntaxError as exc:
        return {
            "valido": False,
            "linea": exc.lineno,
            "columna": exc.offset,
            "mensaje": exc.msg,
        }
    return {"valido": True, "linea": None, "columna": None, "mensaje": "Sintaxis válida"}


@router.get("/buscar-web", summary="Buscar en internet (sin API key)")
async def buscar(
    _u: Annotated[Usuario, Depends(obtener_usuario_actual)],
    q: Annotated[str, Query(min_length=2, max_length=300)],
    limite: int = 8,
) -> dict[str, object]:
    try:
        resultados = await buscar_web(q, limite=min(max(limite, 1), 15))
    except RuntimeError as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY, detail=str(exc)
        ) from exc
    return {
        "consulta": q,
        "total": len(resultados),
        "resultados": [r.to_dict() for r in resultados],
    }


# ──────────────────────────── Ejecutar Python ────────────────────────────

class EjecutarPythonReq(BaseModel):
    """Snippet de código a ejecutar en el sandbox.

    Backward-compat: el nombre dice "Python" pero ahora acepta cualquier
    lenguaje soportado por el sandbox (python, javascript, bash).
    """
    codigo: str = Field(..., min_length=1, max_length=20_000)
    timeout: int = Field(default=10, ge=1, le=60)
    lenguaje: str = Field(
        default="python",
        description="python | javascript | bash",
    )
    stdin_texto: str | None = Field(
        default=None,
        description="Texto opcional para suministrar a la entrada estándar (stdin/input).",
    )


class EjecutarPythonResp(BaseModel):
    """Resultado de la ejecución sandbox."""
    exit_code: int
    stdout: str
    stderr: str
    timeout: bool
    duracion_segundos: float


@router.post(
    "/ejecutar-python",
    response_model=EjecutarPythonResp,
    summary="Ejecutar snippet Python en sandbox (timeout duro, env aislado)",
)
async def ejecutar_python(
    req: EjecutarPythonReq,
    _u: Annotated[Usuario, Depends(obtener_usuario_actual)],
) -> EjecutarPythonResp:
    """Ejecuta `req.codigo` en un subproceso aislado y devuelve stdout/stderr.

    Usa el mismo sandbox que el MCP server (`mcp_server.sandbox`). Para
    fines pedagógicos: el estudiante escribe código en la vista Code y
    ve la salida sin salir de la app.
    """
    if not _SANDBOX_OK:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Sandbox no disponible (mcp_server no encontrado en backend).",
        )
    try:
        r = _exec_sandbox(
            req.codigo,
            lenguaje=req.lenguaje,
            timeout_segundos=req.timeout,
            stdin_texto=req.stdin_texto,
        )
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Error inesperado en sandbox: {exc}",
        ) from exc
    return EjecutarPythonResp(
        exit_code=r.exit_code,
        stdout=r.stdout,
        stderr=r.stderr,
        timeout=r.timeout,
        duracion_segundos=r.duracion_segundos,
    )
