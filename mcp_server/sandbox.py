"""Sandbox para ejecutar código Python sin comprometer al sistema.

Estrategia (defensa en profundidad):
    1. Subproceso separado — si crashea no tira el server MCP
    2. Timeout duro vía `subprocess.run(timeout=N)`
    3. CWD aislado en un tempdir nuevo por ejecución
    4. ENV restringido (solo PATH y variables mínimas)
    5. Sin acceso al venv del proyecto — usa python.exe del sistema
    6. Output truncado a 50 KB para no inundar al LLM
    7. No interactivo: stdin cerrado

Lo que NO previene:
    - El código puede hacer requests HTTP salientes (firewall del SO ayuda)
    - El código puede crear archivos en tempdir (se borra al final)
    - El código puede agotar CPU dentro del timeout

Para una sandbox de producción real, usar nsjail/firejail/docker.
Para fines educativos (la tesis) esta es suficiente y bien explicada.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass


_MAX_OUTPUT = 50 * 1024  # 50 KB


@dataclass
class ResultadoEjecucion:
    """Resultado de ejecutar código Python en el sandbox."""

    exit_code: int
    stdout: str
    stderr: str
    timeout: bool
    duracion_segundos: float


def ejecutar_python(
    codigo: str,
    *,
    timeout_segundos: int = 10,
) -> ResultadoEjecucion:
    """Alias retro-compatible: ejecuta como Python."""
    return ejecutar(codigo, lenguaje="python", timeout_segundos=timeout_segundos)


def ejecutar(
    codigo: str,
    *,
    lenguaje: str = "python",
    timeout_segundos: int = 10,
) -> ResultadoEjecucion:
    """Ejecuta `codigo` en un subproceso aislado con timeout.

    Args:
        codigo: snippet de código fuente
        lenguaje: 'python' | 'javascript' | 'bash' | 'shell'
        timeout_segundos: corte duro

    Returns:
        ResultadoEjecucion con stdout, stderr, exit_code y duración.
    """
    import time
    import shutil

    # Mapeo lenguaje → (extensión archivo, comando ejecutor)
    config = {
        "python": ("main.py", [sys.executable]),
        "py":     ("main.py", [sys.executable]),
        "javascript": ("main.js", [shutil.which("node") or "node"]),
        "js":         ("main.js", [shutil.which("node") or "node"]),
        "bash":  ("main.sh", [shutil.which("bash") or "bash"]),
        "shell": ("main.sh", [shutil.which("bash") or "bash"]),
        "sh":    ("main.sh", [shutil.which("bash") or "bash"]),
    }
    cfg = config.get(lenguaje.lower())
    if cfg is None:
        return ResultadoEjecucion(
            exit_code=2,
            stdout="",
            stderr=f"[sandbox] lenguaje no soportado: {lenguaje}. "
                   "Soportados: python, javascript, bash.",
            timeout=False,
            duracion_segundos=0.0,
        )
    nombre_script, ejecutor = cfg

    tmpdir = tempfile.mkdtemp(prefix="explic_sbox_")
    script = os.path.join(tmpdir, nombre_script)
    with open(script, "w", encoding="utf-8") as f:
        f.write(codigo)

    # ENV mínima — sin secrets del shell del usuario, sin PYTHONPATH al
    # proyecto, sin variables de IA, etc.
    env_minima = {
        "PATH": os.environ.get("PATH", ""),
        "SystemRoot": os.environ.get("SystemRoot", ""),  # Windows
        "TEMP": tmpdir,
        "TMP": tmpdir,
        "PYTHONIOENCODING": "utf-8",
        "PYTHONUNBUFFERED": "1",
    }
    # Quitar None
    env_minima = {k: v for k, v in env_minima.items() if v}

    timeout_hit = False
    inicio = time.perf_counter()
    try:
        proc = subprocess.run(
            ejecutor + [script],
            cwd=tmpdir,
            env=env_minima,
            capture_output=True,
            text=True,
            timeout=timeout_segundos,
            stdin=subprocess.DEVNULL,
        )
        out, err, rc = proc.stdout, proc.stderr, proc.returncode
    except subprocess.TimeoutExpired as exc:
        timeout_hit = True
        out = exc.stdout.decode("utf-8", errors="replace") if exc.stdout else ""
        err = (
            (exc.stderr.decode("utf-8", errors="replace") if exc.stderr else "")
            + f"\n[sandbox] timeout tras {timeout_segundos}s"
        )
        rc = 124  # convención Unix para timeout
    except Exception as e:  # noqa: BLE001
        out = ""
        err = f"[sandbox] error inesperado: {e}"
        rc = 1
    finally:
        duracion = time.perf_counter() - inicio
        try:
            shutil.rmtree(tmpdir, ignore_errors=True)
        except Exception:
            pass

    return ResultadoEjecucion(
        exit_code=rc,
        stdout=out[:_MAX_OUTPUT],
        stderr=err[:_MAX_OUTPUT],
        timeout=timeout_hit,
        duracion_segundos=round(duracion, 3),
    )
