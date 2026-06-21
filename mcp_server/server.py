"""Servidor MCP (Model Context Protocol) — protocolo JSON-RPC 2.0 sobre stdio.

Implementa los métodos del subconjunto de MCP necesarios para que un
cliente (nuestro backend, Claude Desktop, etc.) descubra y use las tools.

Métodos soportados:
    - initialize
    - initialized   (notificación)
    - tools/list
    - tools/call
    - ping

Protocolo en una frase:
    El cliente envía mensajes JSON-RPC separados por '\\n' por stdin.
    El servidor responde por stdout, también separados por '\\n'.
    Los logs van a stderr (nunca a stdout — corrompería el protocolo).

Spec: https://spec.modelcontextprotocol.io/
"""

from __future__ import annotations

import json
import sys
from dataclasses import dataclass
from typing import Any

from . import PROTOCOL_VERSION, __version__
from .permisos import PermisosMcp, cargar_permisos
from .tools import ToolError, catalogo, invocar


# ── Códigos de error JSON-RPC (spec estándar) ───────────────────────
PARSE_ERROR = -32700
INVALID_REQUEST = -32600
METHOD_NOT_FOUND = -32601
INVALID_PARAMS = -32602
INTERNAL_ERROR = -32603


def _log(msg: str) -> None:
    """Logs van a stderr — nunca a stdout (eso es para el protocolo)."""
    print(f"[mcp_server] {msg}", file=sys.stderr, flush=True)


def _respuesta_ok(req_id: Any, resultado: Any) -> dict:
    return {"jsonrpc": "2.0", "id": req_id, "result": resultado}


def _respuesta_error(req_id: Any, codigo: int, mensaje: str) -> dict:
    return {
        "jsonrpc": "2.0",
        "id": req_id,
        "error": {"code": codigo, "message": mensaje},
    }


# ── Handlers de métodos MCP ─────────────────────────────────────────

def _initialize(params: dict) -> dict:
    """Negociación inicial: capabilities, versión del protocolo, server info."""
    cliente_protocolo = (params or {}).get("protocolVersion", "?")
    _log(f"initialize por cliente con protocolo {cliente_protocolo}")
    return {
        "protocolVersion": PROTOCOL_VERSION,
        "capabilities": {
            "tools": {"listChanged": False},
            # No exponemos resources ni prompts en esta v1
        },
        "serverInfo": {
            "name": "explicador-python-ia",
            "version": __version__,
        },
    }


def _tools_list(_params: dict) -> dict:
    return {"tools": catalogo()}


def _tools_call(params: dict, permisos: PermisosMcp) -> dict:
    nombre = params.get("name")
    args = params.get("arguments") or {}
    if not nombre:
        raise ValueError("Falta 'name' en params")
    try:
        resultado = invocar(nombre, args, permisos)
        # Formato MCP: array de content blocks. Para nosotros, devolvemos
        # JSON serializado como texto (el LLM lo lee bien).
        return {
            "content": [
                {"type": "text", "text": json.dumps(resultado, ensure_ascii=False, indent=2)}
            ],
            "isError": False,
        }
    except ToolError as e:
        return {
            "content": [{"type": "text", "text": str(e)}],
            "isError": True,
        }


# ── Loop principal ──────────────────────────────────────────────────

@dataclass
class _Estado:
    permisos: PermisosMcp
    inicializado: bool = False


def _procesar(linea: str, estado: _Estado) -> dict | None:
    """Procesa un mensaje JSON-RPC y devuelve la respuesta (o None si era notif)."""
    try:
        msg = json.loads(linea)
    except json.JSONDecodeError as e:
        return _respuesta_error(None, PARSE_ERROR, f"JSON inválido: {e}")

    if not isinstance(msg, dict):
        return _respuesta_error(None, INVALID_REQUEST, "Mensaje no es objeto")

    metodo = msg.get("method")
    req_id = msg.get("id")  # ausente = notificación, no se responde
    params = msg.get("params") or {}

    # Notificación 'initialized' — no respondemos pero marcamos estado
    if metodo == "notifications/initialized" or metodo == "initialized":
        estado.inicializado = True
        return None

    if metodo == "ping":
        return _respuesta_ok(req_id, {})

    if metodo == "initialize":
        return _respuesta_ok(req_id, _initialize(params))

    if metodo == "tools/list":
        return _respuesta_ok(req_id, _tools_list(params))

    if metodo == "tools/call":
        try:
            return _respuesta_ok(req_id, _tools_call(params, estado.permisos))
        except ValueError as e:
            return _respuesta_error(req_id, INVALID_PARAMS, str(e))
        except Exception as e:  # noqa: BLE001
            _log(f"error inesperado en tools/call: {e}")
            return _respuesta_error(req_id, INTERNAL_ERROR, str(e))

    return _respuesta_error(req_id, METHOD_NOT_FOUND, f"Método no soportado: {metodo}")


def correr_stdio() -> None:
    """Loop principal: lee stdin línea a línea y responde por stdout."""
    estado = _Estado(permisos=cargar_permisos())
    _log(f"servidor iniciado · protocolo {PROTOCOL_VERSION} · v{__version__}")
    _log(f"tools habilitadas: {estado.permisos.tools_habilitadas}")
    _log(f"directorios permitidos: {estado.permisos.directorios_permitidos or '(ninguno)'}")

    while True:
        try:
            linea = sys.stdin.readline()
        except KeyboardInterrupt:
            _log("interrupción de teclado, cerrando")
            return
        if not linea:
            _log("EOF en stdin, cerrando")
            return
        linea = linea.strip()
        if not linea:
            continue

        respuesta = _procesar(linea, estado)
        if respuesta is not None:
            sys.stdout.write(json.dumps(respuesta, ensure_ascii=False) + "\n")
            sys.stdout.flush()
