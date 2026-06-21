"""Sistema de permisos para el servidor MCP.

Diseño:
    - Whitelist de directorios donde se permite leer/escribir/listar.
    - Toolset habilitado/deshabilitado por nombre.
    - Modo "confirmar antes de ejecutar" para tools destructivas
      (`escribir_archivo`, `ejecutar_python`). En modo `auto` se
      permite sin pedir; en modo `confirmar` el cliente debe enviar
      `{"confirmado": true}` en los args.
    - Config persistida en JSON en la home del usuario (~/.explicador/mcp.json).

Por defecto NADA está permitido — el usuario debe habilitar explícitamente.
Esto evita que la primera vez que se conecte un LLM, este pueda leer
archivos privados sin consentimiento.
"""

from __future__ import annotations

import json
import os
from dataclasses import dataclass, field, asdict
from pathlib import Path
from typing import Literal


ModoConfirmacion = Literal["auto", "confirmar", "bloquear"]


@dataclass
class PermisosMcp:
    """Configuración actual de permisos.

    Atributos:
        directorios_permitidos: lista de prefijos absolutos donde se
            puede leer/escribir/listar. Cualquier ruta fuera de ellos
            se rechaza.
        tools_habilitadas: nombres de tools que se pueden invocar.
        modo_escribir: 'auto' | 'confirmar' | 'bloquear'
        modo_ejecutar: 'auto' | 'confirmar' | 'bloquear'
        max_bytes_lectura: corte de seguridad para no devolver archivos
            gigantes al LLM (saturaría contexto y memoria).
        timeout_ejecucion_segundos: corte para ejecutar_python.
    """

    directorios_permitidos: list[str] = field(default_factory=list)
    tools_habilitadas: list[str] = field(
        default_factory=lambda: [
            "leer_archivo",
            "listar_directorio",
            "buscar_en_archivos",
        ]
    )
    modo_escribir: ModoConfirmacion = "bloquear"
    modo_ejecutar: ModoConfirmacion = "bloquear"
    max_bytes_lectura: int = 256 * 1024  # 256 KB
    timeout_ejecucion_segundos: int = 10

    def ruta_permitida(self, ruta: str) -> bool:
        """¿La `ruta` está bajo alguno de los directorios permitidos?"""
        try:
            absoluta = Path(ruta).resolve()
        except Exception:
            return False
        for permitido in self.directorios_permitidos:
            try:
                base = Path(permitido).resolve()
                # Path.is_relative_to existe desde Python 3.9
                if absoluta == base or _es_relativa(absoluta, base):
                    return True
            except Exception:
                continue
        return False

    def tool_habilitada(self, nombre: str) -> bool:
        return nombre in self.tools_habilitadas


def _es_relativa(hijo: Path, padre: Path) -> bool:
    """Backport de Path.is_relative_to para versiones <3.9."""
    try:
        hijo.relative_to(padre)
        return True
    except ValueError:
        return False


# ── Persistencia ────────────────────────────────────────────────────

def _ruta_config() -> Path:
    home = Path.home()
    return home / ".explicador" / "mcp.json"


def cargar_permisos() -> PermisosMcp:
    """Carga permisos del disco. Si no existen, devuelve los defaults."""
    ruta = _ruta_config()
    if not ruta.exists():
        return PermisosMcp()
    try:
        data = json.loads(ruta.read_text(encoding="utf-8"))
        return PermisosMcp(**{
            k: v for k, v in data.items()
            if k in PermisosMcp.__dataclass_fields__
        })
    except Exception:
        # Si el JSON está corrupto, no rompemos al usuario — devolvemos
        # defaults seguros y le dejamos un mensaje en logs.
        print(
            f"[mcp_server.permisos] aviso: {ruta} corrupto, usando defaults",
            flush=True,
        )
        return PermisosMcp()


def guardar_permisos(p: PermisosMcp) -> None:
    """Persiste permisos en ~/.explicador/mcp.json."""
    ruta = _ruta_config()
    ruta.parent.mkdir(parents=True, exist_ok=True)
    ruta.write_text(
        json.dumps(asdict(p), indent=2, ensure_ascii=False),
        encoding="utf-8",
    )
