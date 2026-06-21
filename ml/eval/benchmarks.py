"""Benchmarks para LLMs de código: HumanEval y MBPP.

═══════════════════════════════════════════════════════════════════
HumanEval (Chen et al., OpenAI 2021)
═══════════════════════════════════════════════════════════════════
164 problemas Python escritos a mano. Cada uno trae:
    - prompt: docstring + signatura de función
    - canonical_solution: solución de referencia
    - test: assertions que verifican la corrección

Métrica principal: **pass@1** = % de problemas que el modelo resuelve
en su primer intento (sin reintentos).

═══════════════════════════════════════════════════════════════════
MBPP (Mostly Basic Python Problems, Austin et al., Google 2021)
═══════════════════════════════════════════════════════════════════
974 problemas similares pero más simples. Aquí usamos un subset
traducido al español para alinear con nuestro corpus pedagógico.

═══════════════════════════════════════════════════════════════════
Cómo se ejecuta el código generado
═══════════════════════════════════════════════════════════════════
Reusamos el sandbox del MCP server (`mcp_server.sandbox.ejecutar`):
subprocess aislado con timeout, sin acceso al venv del proyecto.
Es el mismo sandbox que ya usa la app desktop.
"""

from __future__ import annotations

import json
import re
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable, Iterable

# Hacemos visible el mcp_server desde aquí.
_RAIZ = Path(__file__).resolve().parents[2]
if str(_RAIZ) not in sys.path:
    sys.path.insert(0, str(_RAIZ))


@dataclass
class ProblemaHumanEval:
    """Un problema del set HumanEval."""
    task_id: str
    prompt: str
    canonical_solution: str
    test: str          # bloque de tests que valida la solución
    entry_point: str   # nombre de la función a generar


@dataclass
class ResultadoBenchmark:
    """Resultado de evaluar un modelo en un set de problemas."""
    nombre: str
    n_problemas: int
    n_resueltos: int
    pass_at_1: float
    duracion_segundos: float
    detalles: list[dict] = field(default_factory=list)

    @property
    def pass_at_1_pct(self) -> str:
        return f"{self.pass_at_1 * 100:.1f}%"


# ════════════════════════════════════════════════════════════════════
# Carga de problemas
# ════════════════════════════════════════════════════════════════════

def cargar_humaneval(ruta_jsonl: Path) -> list[ProblemaHumanEval]:
    """Carga HumanEval desde JSONL. Si no existe, da instrucciones."""
    if not ruta_jsonl.exists():
        # Intentamos descargar/preparar un mini set local de muestra
        # con 10 problemas representativos para demos sin internet.
        return _humaneval_demo()
    problemas: list[ProblemaHumanEval] = []
    with ruta_jsonl.open("r", encoding="utf-8") as f:
        for linea in f:
            try:
                obj = json.loads(linea)
                problemas.append(ProblemaHumanEval(
                    task_id=obj.get("task_id", ""),
                    prompt=obj.get("prompt", ""),
                    canonical_solution=obj.get("canonical_solution", ""),
                    test=obj.get("test", ""),
                    entry_point=obj.get("entry_point", ""),
                ))
            except (json.JSONDecodeError, KeyError):
                continue
    return problemas


def _humaneval_demo() -> list[ProblemaHumanEval]:
    """Mini set de 5 problemas auto-contenidos para validar el harness
    sin descargar HumanEval completo."""
    return [
        ProblemaHumanEval(
            task_id="demo/1",
            prompt='def add(a: int, b: int) -> int:\n    """Suma dos enteros."""\n',
            canonical_solution="    return a + b\n",
            test=(
                "def check(candidate):\n"
                "    assert candidate(1, 2) == 3\n"
                "    assert candidate(0, 0) == 0\n"
                "    assert candidate(-5, 5) == 0\n"
            ),
            entry_point="add",
        ),
        ProblemaHumanEval(
            task_id="demo/2",
            prompt=(
                "def es_primo(n: int) -> bool:\n"
                '    """Devuelve True si n es número primo, False en otro caso."""\n'
            ),
            canonical_solution=(
                "    if n < 2: return False\n"
                "    for i in range(2, int(n**0.5)+1):\n"
                "        if n % i == 0: return False\n"
                "    return True\n"
            ),
            test=(
                "def check(candidate):\n"
                "    assert candidate(2) == True\n"
                "    assert candidate(7) == True\n"
                "    assert candidate(15) == False\n"
                "    assert candidate(1) == False\n"
            ),
            entry_point="es_primo",
        ),
        ProblemaHumanEval(
            task_id="demo/3",
            prompt=(
                "def invertir_string(s: str) -> str:\n"
                '    """Devuelve la cadena invertida."""\n'
            ),
            canonical_solution="    return s[::-1]\n",
            test=(
                "def check(candidate):\n"
                "    assert candidate('hola') == 'aloh'\n"
                "    assert candidate('') == ''\n"
                "    assert candidate('a') == 'a'\n"
            ),
            entry_point="invertir_string",
        ),
        ProblemaHumanEval(
            task_id="demo/4",
            prompt=(
                "def factorial(n: int) -> int:\n"
                '    """Calcula n!"""\n'
            ),
            canonical_solution=(
                "    if n <= 1: return 1\n"
                "    r = 1\n"
                "    for i in range(2, n+1): r *= i\n"
                "    return r\n"
            ),
            test=(
                "def check(candidate):\n"
                "    assert candidate(0) == 1\n"
                "    assert candidate(5) == 120\n"
                "    assert candidate(10) == 3628800\n"
            ),
            entry_point="factorial",
        ),
        ProblemaHumanEval(
            task_id="demo/5",
            prompt=(
                "def fibonacci(n: int) -> int:\n"
                '    """Devuelve el n-ésimo número de Fibonacci (0-indexed)."""\n'
            ),
            canonical_solution=(
                "    a, b = 0, 1\n"
                "    for _ in range(n): a, b = b, a+b\n"
                "    return a\n"
            ),
            test=(
                "def check(candidate):\n"
                "    assert candidate(0) == 0\n"
                "    assert candidate(1) == 1\n"
                "    assert candidate(10) == 55\n"
            ),
            entry_point="fibonacci",
        ),
    ]


# ════════════════════════════════════════════════════════════════════
# Limpieza del output del modelo
# ════════════════════════════════════════════════════════════════════

def extraer_codigo_python(texto: str) -> str:
    """Quita comentarios markdown del código, **preservando indentación**.

    NO usar `.strip()` general — eso destruye la indentación necesaria
    para que el código esté dentro de la función del prompt.
    Solo se quitan los whitespace finales (no la sangría inicial).
    """
    # Si hay bloque ```python, extraerlo
    m = re.search(r"```(?:python|py)?\s*\n(.*?)```", texto, re.DOTALL)
    if m:
        # Quitamos saltos de línea finales pero NO la indentación inicial.
        return m.group(1).rstrip()
    # Si no hay bloque, asumir que el texto crudo ES el código.
    # Quitamos solo saltos finales y leading newlines (no el indent).
    return texto.rstrip().lstrip("\n")


def detener_en_funcion_siguiente(codigo: str) -> str:
    """El modelo puede generar varias funciones; quedarnos con la primera."""
    lineas = codigo.split("\n")
    salida: list[str] = []
    dentro_funcion = False
    for linea in lineas:
        if linea.startswith("def ") and dentro_funcion:
            break
        if linea.startswith("def "):
            dentro_funcion = True
        salida.append(linea)
    return "\n".join(salida)


# ════════════════════════════════════════════════════════════════════
# Ejecutor de tests sobre el código generado
# ════════════════════════════════════════════════════════════════════

def evaluar_problema(
    prompt: str,
    codigo_generado: str,
    test: str,
    entry_point: str,
    timeout: int = 5,
) -> tuple[bool, str]:
    """Compila prompt+codigo+test y los ejecuta en sandbox.

    Returns:
        (pasó, mensaje)
    """
    from mcp_server.sandbox import ejecutar  # type: ignore

    # Construir el script completo: prompt da la signatura + docstring,
    # codigo_generado tiene el cuerpo, test ejecuta check(entry_point).
    script = (
        f"{prompt}\n"
        f"{codigo_generado}\n\n"
        f"{test}\n\n"
        f"check({entry_point})\n"
        f"print('PASS')\n"
    )

    try:
        r = ejecutar(script, lenguaje="python", timeout_segundos=timeout)
    except Exception as e:  # noqa: BLE001
        return False, f"[sandbox error] {e}"

    if r.timeout:
        return False, "TIMEOUT"
    if r.exit_code != 0:
        # Captura la última línea del stderr (suele ser el error)
        err = (r.stderr or "").strip().splitlines()
        return False, (err[-1] if err else f"exit {r.exit_code}")
    if "PASS" not in r.stdout:
        return False, "no PASS en stdout"
    return True, "OK"


# ════════════════════════════════════════════════════════════════════
# Runner del benchmark
# ════════════════════════════════════════════════════════════════════

def correr_humaneval(
    problemas: list[ProblemaHumanEval],
    generar_fn: Callable[[str], str],
    nombre_modelo: str = "modelo",
    *,
    timeout_test: int = 5,
    verbose: bool = True,
) -> ResultadoBenchmark:
    """Itera HumanEval, genera, evalúa.

    Args:
        problemas: lista de problemas a evaluar.
        generar_fn: función que recibe `prompt` y devuelve string con código.
                    Puede ser un wrapper de cualquier modelo
                    (propio, Gemini, DeepSeek).
        nombre_modelo: para los logs y la tabla final.
        timeout_test: segundos por ejecución.
        verbose: imprimir progreso por problema.

    Returns:
        ResultadoBenchmark con métricas + detalle por problema.
    """
    inicio = time.time()
    detalles = []
    n_ok = 0

    for i, p in enumerate(problemas, 1):
        t_gen = time.time()
        try:
            generado_bruto = generar_fn(p.prompt)
        except Exception as e:  # noqa: BLE001
            generado_bruto = f"# ERROR generando: {e}"
        codigo = extraer_codigo_python(generado_bruto)
        codigo = detener_en_funcion_siguiente(codigo)

        paso, mensaje = evaluar_problema(
            p.prompt, codigo, p.test, p.entry_point, timeout=timeout_test,
        )
        if paso:
            n_ok += 1
        detalles.append({
            "task_id": p.task_id,
            "paso": paso,
            "mensaje": mensaje,
            "codigo_generado": codigo[:500],
            "duracion_generacion_s": round(time.time() - t_gen, 2),
        })
        if verbose:
            # ASCII para evitar problemas de encoding en consolas Windows cp1252.
            simbolo = "[OK]" if paso else "[X ]"
            print(
                f"  [{i:3d}/{len(problemas)}] {simbolo} {p.task_id:<15} "
                f"{mensaje[:80]}"
            )

    dur = time.time() - inicio
    pass_at_1 = n_ok / max(1, len(problemas))
    return ResultadoBenchmark(
        nombre=nombre_modelo,
        n_problemas=len(problemas),
        n_resueltos=n_ok,
        pass_at_1=pass_at_1,
        duracion_segundos=dur,
        detalles=detalles,
    )


# ════════════════════════════════════════════════════════════════════
# Formato Markdown para la tesis
# ════════════════════════════════════════════════════════════════════

def resultado_a_markdown(r: ResultadoBenchmark, contexto: str = "") -> str:
    """Genera un capítulo Markdown con la tabla, gráficos y detalle."""
    pct = r.pass_at_1 * 100
    md = []
    md.append(f"# Benchmark: {r.nombre}")
    md.append("")
    if contexto:
        md.append(contexto)
        md.append("")
    md.append("## Resultados")
    md.append("")
    md.append("| Métrica | Valor |")
    md.append("|---|---|")
    md.append(f"| Total problemas | {r.n_problemas} |")
    md.append(f"| Resueltos | **{r.n_resueltos}** |")
    md.append(f"| **pass@1** | **{pct:.1f}%** |")
    md.append(f"| Duración total | {r.duracion_segundos:.1f}s |")
    md.append(f"| Tiempo promedio por problema | {r.duracion_segundos/max(1, r.n_problemas):.2f}s |")
    md.append("")
    md.append("## Detalle por problema")
    md.append("")
    md.append("| task_id | resultado | mensaje |")
    md.append("|---|---|---|")
    for d in r.detalles:
        simbolo = "✓" if d["paso"] else "✗"
        msg = (d["mensaje"] or "")[:80].replace("|", "\\|")
        md.append(f"| `{d['task_id']}` | {simbolo} | {msg} |")
    return "\n".join(md)


def comparar_resultados(resultados: list[ResultadoBenchmark]) -> str:
    """Tabla comparativa lista para el capítulo de Resultados."""
    md = []
    md.append("# Comparativa entre modelos")
    md.append("")
    md.append("| Modelo | Problemas | Resueltos | pass@1 | Tiempo prom. (s) |")
    md.append("|---|---|---|---|---|")
    for r in resultados:
        md.append(
            f"| **{r.nombre}** | {r.n_problemas} | {r.n_resueltos} | "
            f"**{r.pass_at_1 * 100:.1f}%** | "
            f"{r.duracion_segundos / max(1, r.n_problemas):.2f} |"
        )
    return "\n".join(md)
