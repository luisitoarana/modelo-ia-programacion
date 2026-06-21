"""Cliente MCP — lanza el servidor mcp_server como subproceso y le habla.

Diseño:
    - Singleton (`obtener_cliente()`) — un solo subproceso compartido.
    - Lazy start: el subproceso arranca al primer `listar_tools()` o
      `invocar_tool()`.
    - Auto-restart: si el subproceso muere, lo levanta otra vez.
    - Async: usa `asyncio.subprocess`, no bloquea el event loop FastAPI.
    - Timeout por llamada (30s default) — protege contra MCP colgado.

Uso típico desde el chat_service:
    cliente = await obtener_cliente_mcp()
    tools = await cliente.listar_tools()
    resultado = await cliente.invocar_tool("leer_archivo", {"ruta": "..."})

Ver: docs/MCP_PLAN.md
"""

from __future__ import annotations

import asyncio
import json
import logging
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any


log = logging.getLogger(__name__)


# ── DTOs ────────────────────────────────────────────────────────────

@dataclass
class McpTool:
    """Representación ligera de una tool expuesta por el servidor."""
    name: str
    description: str
    input_schema: dict[str, Any]


@dataclass
class ResultadoTool:
    """Resultado de invocar una tool."""
    contenido: str          # text concatenado de los content blocks
    es_error: bool
    raw: dict               # respuesta cruda del MCP


# ── Cliente ─────────────────────────────────────────────────────────

class ClienteMcp:
    """Cliente MCP que mantiene un subproceso del servidor stdio."""

    def __init__(
        self,
        *,
        comando: list[str] | None = None,
        cwd: Path | None = None,
        timeout_segundos: float = 30.0,
    ) -> None:
        # Por default: lanza nuestro propio server `python -m mcp_server`
        # desde la raíz del proyecto.
        raiz = Path(__file__).resolve().parents[3]
        self._comando = comando or [sys.executable, "-m", "mcp_server"]
        self._cwd = cwd or raiz
        self._timeout = timeout_segundos

        self._proc: asyncio.subprocess.Process | None = None
        self._lock = asyncio.Lock()           # serializa requests
        self._proximo_id = 1
        self._inicializado = False

    # ── ciclo de vida ──────────────────────────────────────────────

    async def _asegurar_proceso(self) -> None:
        """Lanza el subproceso si no existe o murió."""
        if self._proc is not None and self._proc.returncode is None:
            return  # vivo
        log.info("Iniciando MCP server: %s (cwd=%s)", self._comando, self._cwd)
        # En Windows hay que forzar UTF-8 en stdin/stdout del subproceso;
        # si no, Python escribe en cp1252 y rompemos el JSON.
        import os
        env = os.environ.copy()
        env["PYTHONIOENCODING"] = "utf-8"
        env["PYTHONUTF8"] = "1"
        self._proc = await asyncio.create_subprocess_exec(
            *self._comando,
            cwd=str(self._cwd),
            stdin=asyncio.subprocess.PIPE,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            env=env,
        )
        self._inicializado = False
        # Lector pasivo de stderr para logs (no bloqueante)
        asyncio.create_task(self._leer_stderr())
        await self._handshake()

    async def _leer_stderr(self) -> None:
        if self._proc is None or self._proc.stderr is None:
            return
        while True:
            linea = await self._proc.stderr.readline()
            if not linea:
                return
            log.info("[mcp_server] %s", linea.decode("utf-8", errors="replace").rstrip())

    async def _handshake(self) -> None:
        """initialize + notifications/initialized."""
        respuesta = await self._llamar_raw(
            "initialize",
            {"protocolVersion": "2024-11-05",
             "capabilities": {},
             "clientInfo": {"name": "explicador-backend", "version": "0.1.0"}},
        )
        if "error" in respuesta:
            raise RuntimeError(f"MCP initialize falló: {respuesta['error']}")
        # Notificación 'initialized' (sin id → sin respuesta)
        await self._enviar({"jsonrpc": "2.0",
                            "method": "notifications/initialized",
                            "params": {}})
        self._inicializado = True
        log.info("MCP handshake completado")

    async def cerrar(self) -> None:
        if self._proc is None:
            return
        if self._proc.returncode is None:
            try:
                if self._proc.stdin is not None:
                    self._proc.stdin.close()
                await asyncio.wait_for(self._proc.wait(), timeout=2.0)
            except asyncio.TimeoutError:
                self._proc.kill()
        self._proc = None
        self._inicializado = False

    # ── transport ──────────────────────────────────────────────────

    async def _enviar(self, msg: dict) -> None:
        if self._proc is None or self._proc.stdin is None:
            raise RuntimeError("MCP process no iniciado")
        linea = json.dumps(msg, ensure_ascii=False) + "\n"
        self._proc.stdin.write(linea.encode("utf-8"))
        await self._proc.stdin.drain()

    async def _leer(self) -> dict:
        if self._proc is None or self._proc.stdout is None:
            raise RuntimeError("MCP process no iniciado")
        linea = await asyncio.wait_for(
            self._proc.stdout.readline(),
            timeout=self._timeout,
        )
        if not linea:
            raise RuntimeError("MCP process cerró stdout (EOF)")
        # `errors='replace'` evita romper la conexión si llega un byte
        # accidental fuera de UTF-8 (raro pero defensa en profundidad).
        return json.loads(linea.decode("utf-8", errors="replace"))

    async def _llamar_raw(self, metodo: str, params: dict) -> dict:
        rid = self._proximo_id
        self._proximo_id += 1
        await self._enviar({
            "jsonrpc": "2.0", "id": rid, "method": metodo, "params": params,
        })
        respuesta = await self._leer()
        if respuesta.get("id") != rid:
            # Protocolo inconsistente — recargamos por seguridad.
            log.warning("MCP respondió con id distinto al pedido: %s", respuesta)
        return respuesta

    # ── API pública ────────────────────────────────────────────────

    async def listar_tools(self) -> list[McpTool]:
        async with self._lock:
            await self._asegurar_proceso()
            resp = await self._llamar_raw("tools/list", {})
            if "error" in resp:
                raise RuntimeError(f"tools/list error: {resp['error']}")
            tools = resp.get("result", {}).get("tools", [])
            return [
                McpTool(
                    name=t["name"],
                    description=t.get("description", ""),
                    input_schema=t.get("inputSchema", {}),
                )
                for t in tools
            ]

    async def invocar_tool(
        self, nombre: str, argumentos: dict[str, Any]
    ) -> ResultadoTool:
        async with self._lock:
            await self._asegurar_proceso()
            resp = await self._llamar_raw(
                "tools/call",
                {"name": nombre, "arguments": argumentos},
            )
            if "error" in resp:
                return ResultadoTool(
                    contenido=str(resp["error"].get("message", "error desconocido")),
                    es_error=True,
                    raw=resp,
                )
            r = resp.get("result", {})
            content = r.get("content", [])
            texto = "\n".join(
                c.get("text", "") for c in content if isinstance(c, dict)
            )
            return ResultadoTool(
                contenido=texto,
                es_error=bool(r.get("isError", False)),
                raw=resp,
            )

    async def ping(self) -> bool:
        try:
            async with self._lock:
                await self._asegurar_proceso()
                resp = await self._llamar_raw("ping", {})
            return "result" in resp
        except Exception:
            return False


# ── Singleton ──────────────────────────────────────────────────────

_singleton: ClienteMcp | None = None


async def obtener_cliente_mcp() -> ClienteMcp:
    """Devuelve la instancia única del cliente MCP."""
    global _singleton
    if _singleton is None:
        _singleton = ClienteMcp()
    return _singleton


async def cerrar_cliente_mcp() -> None:
    """Cierra el subproceso MCP (llamar en shutdown del backend)."""
    global _singleton
    if _singleton is not None:
        await _singleton.cerrar()
        _singleton = None
