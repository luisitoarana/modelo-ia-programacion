"""Generador de `explicacion_multinivel` — un concepto, 4 niveles pedagógicos.

Cada ejemplo enseña el MISMO concepto con 4 niveles de profundidad:

    nino           → analogía simple, sin jerga
    principiante   → definición clara + ejemplo concreto
    intermedio     → sintaxis precisa + cuándo se usa + cuidados
    profesional    → internals, edge cases, alternativas, rendimiento

Es la pieza pedagógica más visible — permite que el modelo final adapte
respuestas al nivel del estudiante.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import sys
import time
from pathlib import Path
from typing import Any

from ml.data.corpus import deduplicar, estadisticas_corpus, guardar_jsonl
from ml.data.pool_generadores import Pool, Tarea, extraer_json_array
from ml.data.schema import EjemploEntrenamiento
from ml.data.validadores import validar_ejemplo


# Conceptos típicamente difíciles donde el multinivel realmente importa.
OBJETIVOS: tuple[tuple[str, str], ...] = (
    # ── Fundamentos ──
    ("variables y tipos", "basico"),
    ("operadores y precedencia", "basico"),
    ("cadenas y formatting (f-strings)", "basico"),
    ("listas vs tuplas", "basico"),
    ("diccionarios", "basico"),
    ("sets y operaciones de conjunto", "basico"),
    ("control de flujo (if/elif/else)", "basico"),
    ("bucles (for/while/break/continue)", "basico"),
    ("funciones: argumentos posicionales vs nombrados", "basico"),
    ("alcance de variables y closures", "intermedio"),

    # ── Estructuras y patrones idiomáticos ──
    ("funciones lambda", "intermedio"),
    ("list comprehensions", "intermedio"),
    ("generadores y yield", "intermedio"),
    ("iteradores y el protocolo iterable", "intermedio"),
    ("decoradores", "intermedio"),
    ("decoradores con argumentos", "avanzado"),
    ("context managers (with)", "intermedio"),
    ("typing y type hints", "intermedio"),
    ("dataclasses", "intermedio"),
    ("pattern matching (match/case)", "intermedio"),

    # ── Orientación a objetos ──
    ("clases y metodos magicos (dunder)", "intermedio"),
    ("herencia y MRO", "intermedio"),
    ("composicion vs herencia", "intermedio"),
    ("clases abstractas (ABC)", "intermedio"),
    ("Protocols (typing) y duck typing", "intermedio"),
    ("metaclases", "avanzado"),
    ("descriptors", "avanzado"),
    ("__slots__", "avanzado"),

    # ── Concurrencia y rendimiento ──
    ("async/await", "avanzado"),
    ("event loop de asyncio", "avanzado"),
    ("GIL (Global Interpreter Lock)", "avanzado"),
    ("multiprocessing vs threading", "avanzado"),
    ("concurrent.futures (ThreadPool y ProcessPool)", "avanzado"),
    ("memoryview y zero-copy", "avanzado"),

    # ── Manejo de errores y depuración ──
    ("excepciones: try/except/else/finally", "basico"),
    ("excepciones personalizadas", "intermedio"),
    ("logging vs print", "intermedio"),

    # ── Stdlib útil ──
    ("itertools (chain, groupby, product)", "intermedio"),
    ("functools (lru_cache, partial, reduce)", "intermedio"),
    ("collections (Counter, defaultdict, deque)", "intermedio"),

    # ── Conceptos avanzados de Python ──
    ("metodos resolution order y super()", "avanzado"),
    ("weakref y ciclos de referencias", "avanzado"),
)


PROMPT_TEMPLATE = """Eres un educador de programacion con experiencia ensenando
desde ninos hasta programadores senior. Generas UN ejemplo de dataset que
explica el concepto "{concepto}" en CUATRO niveles distintos.

La idea pedagogica clave: MISMO CONCEPTO, CUATRO AUDIENCIAS, CUATRO ESTILOS.

El modelo entrenado con esto debe poder adaptar sus respuestas al nivel
del estudiante que pregunta — sin importar si es un nino curioso o un
programador veterano.

Devuelve EXACTAMENTE un objeto en un array JSON de 1 elemento.

Calibracion del vocabulario por nivel (CRITICA):

  NINO (8-12 anios):
    - Vocabulario cotidiano (juguetes, caja, receta, lista del super).
    - CERO jerga tecnica (nada de "iterador", "memoria", "compilador").
    - Una analogia central que cualquier ninia entienda.
    - Frases cortas. Tono amigable.
    - NO incluir codigo (un nino no entiende sintaxis aun).
    - 3-5 frases. Minimo 80 chars.

  PRINCIPIANTE (primer semestre de programacion):
    - Definicion CLARA en lenguaje simple.
    - Una analogia opcional (no obligatoria).
    - UN ejemplo Python CORTO (4-8 lineas) en ```python ... ```.
    - Apuntar a "para que sirve": utilidad practica.
    - SIN mencionar internals del interprete ni edge cases.
    - 4-7 frases. Minimo 200 chars.

  INTERMEDIO (estudiante con 6-18 meses programando):
    - Sintaxis precisa y completa.
    - Cuando usarlo vs cuando no usarlo.
    - Errores comunes que cometen los principiantes.
    - Ejemplo Python en ```python ... ``` con type hints.
    - Mencion ligera a alternativas (sin profundizar).
    - 5-9 frases. Minimo 350 chars.

  PROFESIONAL (programador con 3+ anios):
    - Internals del interprete (como CPython lo implementa).
    - Edge cases conocidos y workarounds.
    - Trade-offs de performance (cuando importa, cuando no).
    - Comparativa con alternativas (con razones tecnicas).
    - Patrones idiomaticos avanzados o gotchas.
    - Referencia a PEP relevante si aplica.
    - 6-12 frases. Minimo 500 chars.

Estructura del JSON:

[
  {{
    "instruccion": "Explica que es {concepto}" o variante (varia: "Como
                    funciona {concepto}?", "Cuando usar {concepto}?",
                    "Por que existe {concepto}?").
    "tema":        "{tema_simple}",
    "nivel":       "{nivel}",
    "tipo":        "explicacion_multinivel",
    "salida":      "<resumen breve de 2-3 lineas del concepto a nivel
                    general; sirve como teaser>",
    "explicacion_por_nivel": {{
      "nino":         "<analogia para nino segun la calibracion arriba>",
      "principiante": "<explicacion para principiante + codigo>",
      "intermedio":   "<explicacion para intermedio + codigo + cuidados>",
      "profesional":  "<explicacion para profesional + internals + edge cases>"
    }}
  }}
]

REGLAS ESTRICTAS:
  - Solo el array JSON. Sin texto antes / despues. Sin wrapper markdown.
  - Los 4 niveles DEBEN ser ESCRITOS DESDE CERO para esa audiencia, NO
    es una version "podada" del nivel superior.
  - NO copies frases entre niveles. Cada nivel usa su propio vocabulario.
  - "nino" NO contiene codigo, NO contiene palabras como
    "objeto", "variable", "funcion", "iterador", "memoria", "metodo".
  - "principiante" tiene UN ejemplo basico con UN concepto demostrado.
  - "intermedio" agrega cuando NO usar el concepto.
  - "profesional" debe sentirse escrita por alguien que LEYO el codigo
    fuente de CPython (PEP, byte code, dunder methods).
  - El codigo Python en fences DEBE compilar.
  - Idioma: espanol neutro de Latinoamerica.
"""


def _tema_simple(concepto: str) -> str:
    """Extrae un tema corto del concepto para el campo 'tema'."""
    base = concepto.lower().split("(")[0].split("vs")[0].strip()
    return base.replace(" ", "_")[:30] or "otro"


async def generar_objetivo(
    pool: Pool, concepto: str, nivel: str, *, temperatura: float
) -> list[EjemploEntrenamiento]:
    prompt = PROMPT_TEMPLATE.format(
        concepto=concepto, nivel=nivel, tema_simple=_tema_simple(concepto),
    )
    try:
        texto, proveedor = await pool.generar(
            prompt,
            tarea=Tarea.EXPLICACION,
            temperatura=temperatura,
            max_tokens=3072,
            esperar_si_rate_limited=True,
        )
    except Exception as exc:
        print(f"  [!] {concepto}: {exc}", file=sys.stderr)
        return []

    bruto = extraer_json_array(texto) or []
    ejemplos: list[EjemploEntrenamiento] = []
    for d in bruto:
        if not isinstance(d, dict):
            continue
        d["tipo"] = "explicacion_multinivel"
        d.setdefault("nivel", nivel)
        d.setdefault("tema", _tema_simple(concepto))
        d["fuente"] = proveedor
        try:
            ejemplos.append(EjemploEntrenamiento.from_dict(d))
        except Exception:  # noqa: BLE001
            continue
    return ejemplos


async def generar_corpus(
    pool: Pool, salida: Path, *,
    repeticiones: int, temperatura: float,
    objetivos: tuple[tuple[str, str], ...] = OBJETIVOS,
) -> dict[str, Any]:
    todos: list[EjemploEntrenamiento] = []
    descartes: dict[str, int] = {}
    inicio = time.time()

    total_iter = len(objetivos) * repeticiones
    contador = 0
    for concepto, nivel in objetivos:
        for r in range(repeticiones):
            contador += 1
            print(f"[{contador:3d}/{total_iter}] {concepto} (rep {r+1})...", flush=True)
            lote = await generar_objetivo(pool, concepto, nivel, temperatura=temperatura)
            for ej in lote:
                ok, motivo = validar_ejemplo(ej)
                if ok:
                    todos.append(ej)
                else:
                    descartes[motivo.split(":", 1)[0]] = descartes.get(motivo.split(":", 1)[0], 0) + 1

    antes = len(todos)
    todos = deduplicar(todos)
    guardar_jsonl(todos, salida)

    stats = estadisticas_corpus(todos)
    stats.update({
        "archivo": str(salida),
        "duplicados_eliminados": antes - len(todos),
        "descartados_por_motivo": descartes,
        "tiempo_minutos": round((time.time() - inicio) / 60, 1),
        "pool_stats": pool.stats(),
    })
    return stats


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--salida", required=True)
    parser.add_argument("--repeticiones", type=int, default=3,
                        help="Cuántas veces pedir cada concepto (para variar)")
    parser.add_argument("--temperatura", type=float, default=0.9)
    args = parser.parse_args()

    pool = Pool.desde_env()
    print(f"Pool activo: {pool.disponibles}")

    stats = asyncio.run(generar_corpus(
        pool, Path(args.salida),
        repeticiones=args.repeticiones, temperatura=args.temperatura,
    ))
    print("\n=== RESULTADO ===")
    print(json.dumps(stats, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
