"""Implementación de las tools expuestas por el servidor MCP.

Cada tool:
    - Tiene un `name`, `description` y `inputSchema` (JSON-Schema)
      para que el LLM sepa cuándo y cómo usarla
    - Recibe `args: dict` validado y devuelve `dict` serializable
    - Valida permisos antes de ejecutar
    - Lanza `ToolError` con mensaje claro si falla — se devuelve como
      respuesta del tool, NO como error del protocolo
"""

from __future__ import annotations

import re
from pathlib import Path
from typing import Any, Callable

from .permisos import PermisosMcp
from .sandbox import ejecutar_python as _exec_py


class ToolError(Exception):
    """Error legible para devolver al LLM en `content` con isError=True."""


# ── Catálogo de tools ───────────────────────────────────────────────

def catalogo() -> list[dict[str, Any]]:
    """Lista de tools en el formato exacto que MCP espera para `tools/list`."""
    return [
        {
            "name": "leer_archivo",
            "description": (
                "Lee el contenido de un archivo de texto del disco del "
                "usuario. Útil para ver código, configuración o logs. "
                "Devuelve el contenido como string. Solo funciona en rutas "
                "previamente autorizadas por el usuario."
            ),
            "inputSchema": {
                "type": "object",
                "properties": {
                    "ruta": {
                        "type": "string",
                        "description": "Ruta absoluta del archivo a leer",
                    },
                },
                "required": ["ruta"],
            },
        },
        {
            "name": "listar_directorio",
            "description": (
                "Lista los archivos y subdirectorios de una ruta. Devuelve "
                "una lista con nombre, tipo (archivo/directorio) y tamaño."
            ),
            "inputSchema": {
                "type": "object",
                "properties": {
                    "ruta": {"type": "string"},
                    "recursivo": {"type": "boolean", "default": False},
                    "max_entradas": {"type": "integer", "default": 200},
                },
                "required": ["ruta"],
            },
        },
        {
            "name": "escribir_archivo",
            "description": (
                "Escribe contenido a un archivo. Si el modo de escritura "
                "está en 'confirmar', el args debe incluir `confirmado=true`."
            ),
            "inputSchema": {
                "type": "object",
                "properties": {
                    "ruta": {"type": "string"},
                    "contenido": {"type": "string"},
                    "confirmado": {"type": "boolean", "default": False},
                },
                "required": ["ruta", "contenido"],
            },
        },
        {
            "name": "buscar_en_archivos",
            "description": (
                "Busca un patrón regex en archivos de un directorio "
                "recursivamente. Devuelve hasta 50 líneas con coincidencias."
            ),
            "inputSchema": {
                "type": "object",
                "properties": {
                    "patron": {"type": "string"},
                    "ruta": {"type": "string"},
                    "extensiones": {
                        "type": "array",
                        "items": {"type": "string"},
                        "default": [".py", ".md", ".txt", ".json"],
                    },
                    "max_resultados": {"type": "integer", "default": 50},
                },
                "required": ["patron", "ruta"],
            },
        },
        {
            "name": "ejecutar_python",
            "description": (
                "Ejecuta un snippet de código Python en un sandbox aislado. "
                "El sandbox tiene un timeout duro y no comparte env con el "
                "sistema. Devuelve stdout, stderr y exit_code. Si el modo "
                "está en 'confirmar', args debe incluir `confirmado=true`."
            ),
            "inputSchema": {
                "type": "object",
                "properties": {
                    "codigo": {"type": "string"},
                    "confirmado": {"type": "boolean", "default": False},
                },
                "required": ["codigo"],
            },
        },
    ]


# ── Dispatcher ─────────────────────────────────────────────────────

def invocar(
    nombre: str, args: dict[str, Any], permisos: PermisosMcp
) -> dict[str, Any]:
    """Invoca una tool por nombre. Devuelve el resultado en formato MCP."""
    handler = _HANDLERS.get(nombre)
    if handler is None:
        raise ToolError(f"Tool desconocida: {nombre}")

    if not permisos.tool_habilitada(nombre):
        raise ToolError(
            f"La tool '{nombre}' no está habilitada. Actívala en "
            f"Configuración → MCP."
        )

    try:
        return handler(args, permisos)
    except ToolError:
        raise
    except FileNotFoundError as e:
        raise ToolError(f"No encontrado: {e.filename}") from e
    except PermissionError as e:
        raise ToolError(f"Sin permiso del SO: {e}") from e
    except Exception as e:  # noqa: BLE001
        raise ToolError(f"Error inesperado: {e}") from e


# ── Handlers individuales ──────────────────────────────────────────

def _h_leer_archivo(args: dict, p: PermisosMcp) -> dict:
    ruta = args.get("ruta") or ""
    if not ruta:
        raise ToolError("Falta argumento 'ruta'")
    if not p.ruta_permitida(ruta):
        raise ToolError(
            f"Ruta no autorizada: {ruta}. Añádela a 'directorios_permitidos'."
        )
    path = Path(ruta)
    if not path.is_file():
        raise ToolError(f"No es un archivo: {ruta}")
    tamano = path.stat().st_size
    if tamano > p.max_bytes_lectura:
        raise ToolError(
            f"Archivo demasiado grande ({tamano} bytes > "
            f"{p.max_bytes_lectura}). Sube max_bytes_lectura si lo necesitas."
        )
    contenido = path.read_text(encoding="utf-8", errors="replace")
    return {
        "ruta": str(path),
        "tamano_bytes": tamano,
        "contenido": contenido,
    }


def _h_listar_directorio(args: dict, p: PermisosMcp) -> dict:
    ruta = args.get("ruta") or ""
    recursivo = bool(args.get("recursivo", False))
    max_entradas = int(args.get("max_entradas", 200))
    if not p.ruta_permitida(ruta):
        raise ToolError(f"Ruta no autorizada: {ruta}")
    path = Path(ruta)
    if not path.is_dir():
        raise ToolError(f"No es un directorio: {ruta}")

    entradas: list[dict] = []
    iterador = path.rglob("*") if recursivo else path.iterdir()
    for hijo in iterador:
        try:
            es_dir = hijo.is_dir()
            entradas.append({
                "nombre": hijo.name,
                "ruta": str(hijo),
                "tipo": "directorio" if es_dir else "archivo",
                "tamano_bytes": hijo.stat().st_size if not es_dir else 0,
            })
        except Exception:
            # Skip cosas a las que no podemos hacer stat (links rotos)
            continue
        if len(entradas) >= max_entradas:
            break

    return {
        "ruta": str(path),
        "total": len(entradas),
        "truncado": len(entradas) >= max_entradas,
        "entradas": entradas,
    }


def _h_escribir_archivo(args: dict, p: PermisosMcp) -> dict:
    ruta = args.get("ruta") or ""
    contenido = args.get("contenido", "")
    confirmado = bool(args.get("confirmado", False))

    if p.modo_escribir == "bloquear":
        raise ToolError(
            "Escribir archivos está bloqueado. Cámbialo a 'confirmar' o "
            "'auto' en Configuración → MCP."
        )
    if p.modo_escribir == "confirmar" and not confirmado:
        raise ToolError(
            "Esta escritura requiere confirmación del usuario. Reintenta "
            "incluyendo `confirmado=true` después de que el usuario apruebe."
        )
    if not p.ruta_permitida(ruta):
        raise ToolError(f"Ruta no autorizada: {ruta}")
    path = Path(ruta)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(contenido, encoding="utf-8")
    return {
        "ruta": str(path),
        "bytes_escritos": len(contenido.encode("utf-8")),
        "sobrescrito": True,
    }


def _h_buscar_en_archivos(args: dict, p: PermisosMcp) -> dict:
    patron = args.get("patron") or ""
    ruta = args.get("ruta") or ""
    extensiones = args.get("extensiones") or [".py", ".md", ".txt", ".json"]
    max_res = int(args.get("max_resultados", 50))

    if not patron:
        raise ToolError("Falta argumento 'patron'")
    if not p.ruta_permitida(ruta):
        raise ToolError(f"Ruta no autorizada: {ruta}")
    try:
        regex = re.compile(patron)
    except re.error as e:
        raise ToolError(f"Regex inválida: {e}") from e

    resultados: list[dict] = []
    base = Path(ruta)
    if not base.is_dir():
        raise ToolError(f"No es un directorio: {ruta}")

    for f in base.rglob("*"):
        if len(resultados) >= max_res:
            break
        if not f.is_file():
            continue
        if extensiones and f.suffix not in extensiones:
            continue
        try:
            with f.open("r", encoding="utf-8", errors="replace") as h:
                for i, linea in enumerate(h, start=1):
                    if regex.search(linea):
                        resultados.append({
                            "archivo": str(f),
                            "linea": i,
                            "texto": linea.rstrip("\n")[:300],
                        })
                        if len(resultados) >= max_res:
                            break
        except Exception:
            continue

    return {
        "patron": patron,
        "total": len(resultados),
        "truncado": len(resultados) >= max_res,
        "resultados": resultados,
    }


def _h_ejecutar_python(args: dict, p: PermisosMcp) -> dict:
    codigo = args.get("codigo") or ""
    confirmado = bool(args.get("confirmado", False))

    if p.modo_ejecutar == "bloquear":
        raise ToolError(
            "Ejecutar Python está bloqueado. Cámbialo en Configuración → MCP."
        )
    if p.modo_ejecutar == "confirmar" and not confirmado:
        raise ToolError(
            "Esta ejecución requiere confirmación del usuario. Reintenta "
            "incluyendo `confirmado=true`."
        )
    if not codigo.strip():
        raise ToolError("El código está vacío.")

    resultado = _exec_py(codigo, timeout_segundos=p.timeout_ejecucion_segundos)
    return {
        "exit_code": resultado.exit_code,
        "stdout": resultado.stdout,
        "stderr": resultado.stderr,
        "timeout": resultado.timeout,
        "duracion_segundos": resultado.duracion_segundos,
    }


_HANDLERS: dict[str, Callable[[dict, PermisosMcp], dict]] = {
    "leer_archivo": _h_leer_archivo,
    "listar_directorio": _h_listar_directorio,
    "escribir_archivo": _h_escribir_archivo,
    "buscar_en_archivos": _h_buscar_en_archivos,
    "ejecutar_python": _h_ejecutar_python,
}
