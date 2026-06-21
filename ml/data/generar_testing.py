"""Generador de `testing_complejidad` — tests + analisis Big-O.

Cada ejemplo toma una funcion y produce:
    - unit tests (happy path + edge cases)
    - integration test cuando aplica
    - analisis de complejidad temporal y espacial
    - benchmark si vale la pena

La mayoria de modelos open son malos generando tests; este dataset
ataca directamente esa debilidad.
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


# 25 funciones / casos representativos. Mezcla simples + complejos.
CASOS: tuple[tuple[str, str], ...] = (
    ("funcion que busca el elemento maximo en una lista", "basico"),
    ("funcion que verifica si un string es palindromo", "basico"),
    ("funcion que cuenta vocales en un texto", "basico"),
    ("funcion que retorna fibonacci(n)", "intermedio"),
    ("funcion que verifica si un numero es primo", "basico"),
    ("funcion que aplica merge sort a una lista", "intermedio"),
    ("funcion que busca un elemento con binary search", "intermedio"),
    ("funcion que detecta ciclos en una lista enlazada", "intermedio"),
    ("funcion que valida un email", "basico"),
    ("funcion que parsea un CSV con headers", "intermedio"),
    ("funcion que rate-limita llamadas en una ventana deslizante", "intermedio"),
    ("funcion que serializa/deserializa un arbol binario", "avanzado"),
    ("funcion que detecta anagramas entre dos strings", "intermedio"),
    ("funcion que encuentra el LCS (longest common subsequence)", "avanzado"),
    ("funcion que verifica balanceo de parentesis", "basico"),
    ("funcion que paginar resultados con cursor", "intermedio"),
    ("funcion que computa media movil sobre un stream", "intermedio"),
    ("funcion que aplica BFS sobre un grafo", "intermedio"),
    ("funcion que invierte una lista enlazada", "intermedio"),
    ("clase LRU cache de tamano N", "avanzado"),
    ("funcion que parsea fechas en multiples formatos", "intermedio"),
    ("funcion que genera passwords seguros", "basico"),
    ("clase rate limiter con leaky bucket", "avanzado"),
    ("funcion que deduplica una lista preservando orden", "basico"),
    ("funcion que computa el N-esimo numero feo (ugly number)", "avanzado"),
)


PROMPT_TEMPLATE = """Eres un ingeniero senior. Genera un ejemplo de dataset
que muestre, para esta funcion, TESTS + analisis de complejidad.

Funcion / caso: {caso}
Nivel objetivo: {nivel}

Devuelve un array JSON de UN elemento. Estructura:

[
  {{
    "instruccion": "Implementa y testea: {caso}",
    "salida": "<respuesta pedagogica completa (>=400 chars) que incluya:
       1) Implementacion en ```python ... ``` (codigo limpio, type hints);
       2) Unit tests en ```python ... ``` usando pytest:
          - happy path (al menos 2 casos),
          - edge cases (lista vacia, valor unico, valor negativo, tipos invalidos),
          - parametrizacion cuando aplique con @pytest.mark.parametrize;
       3) Cuando aplique, integration test corto;
       4) Analisis de complejidad temporal Big-O con justificacion;
       5) Analisis de complejidad espacial;
       6) Cuando se justifica una version mas eficiente (y cual seria)>",
    "nivel": "{nivel}",
    "tema": "testing_complejidad",
    "tipo": "testing_complejidad",
    "tags": ["testing", "complejidad", "pytest"]
  }}
]

REGLAS:
  - Solo el array JSON.
  - Todo el codigo Python (implementacion + tests) debe COMPILAR.
  - Los tests deben ser TESTS REALES (asserts concretos), no placeholders.
  - El analisis Big-O debe estar JUSTIFICADO, no solo el resultado.
"""


async def generar_objetivo(
    pool: Pool, caso: str, nivel: str, *, temperatura: float
) -> list[EjemploEntrenamiento]:
    prompt = PROMPT_TEMPLATE.format(caso=caso, nivel=nivel)
    try:
        texto, proveedor = await pool.generar(
            prompt, tarea=Tarea.CODIGO, temperatura=temperatura,
            max_tokens=4096, esperar_si_rate_limited=True,
        )
    except Exception as exc:
        print(f"  [!] {caso[:40]}: {exc}", file=sys.stderr)
        return []

    bruto = extraer_json_array(texto) or []
    ejemplos: list[EjemploEntrenamiento] = []
    for d in bruto:
        if not isinstance(d, dict):
            continue
        d["tipo"] = "testing_complejidad"
        d.setdefault("tema", "testing_complejidad")
        d.setdefault("nivel", nivel)
        d["fuente"] = proveedor
        try:
            ejemplos.append(EjemploEntrenamiento.from_dict(d))
        except Exception:  # noqa: BLE001
            continue
    return ejemplos


async def generar_corpus(
    pool: Pool, salida: Path, *, repeticiones: int, temperatura: float,
) -> dict[str, Any]:
    todos: list[EjemploEntrenamiento] = []
    descartes: dict[str, int] = {}
    inicio = time.time()

    total = len(CASOS) * repeticiones
    contador = 0
    for caso, nivel in CASOS:
        for r in range(repeticiones):
            contador += 1
            print(f"[{contador:3d}/{total}] {caso[:55]} (rep {r+1})", flush=True)
            lote = await generar_objetivo(pool, caso, nivel, temperatura=temperatura)
            for ej in lote:
                ok, motivo = validar_ejemplo(ej)
                if ok:
                    todos.append(ej)
                else:
                    k = motivo.split(":", 1)[0]
                    descartes[k] = descartes.get(k, 0) + 1

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
    parser.add_argument("--repeticiones", type=int, default=4)
    parser.add_argument("--temperatura", type=float, default=0.85)
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
