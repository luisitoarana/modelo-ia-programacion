"""Generador de `pensamiento_autocritico` — Nivel 12 del documento de visión.

Cada ejemplo muestra cómo un programador genera una solución, la critica
a sí mismo, la mejora, vuelve a evaluarla. El modelo aprende a iterar
INTERNAMENTE sobre sus respuestas en lugar de quedarse con la primera.

Estructura:
    pensamiento.iteraciones = [
        {version: "A",       codigo: "...", critica: "<3 problemas en A>"},
        {version: "B",       codigo: "...", critica: "<2 problemas en B>"},
        {version: "C_final", codigo: "...", critica: "sin problemas significativos"}
    ]

Esto es el dataset que enseña razonamiento iterativo. Mucho más valioso
que más parámetros — un modelo de 350M con buen razonamiento iterativo
puede superar a uno de 1B que solo "completa".
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


# Problemas representativos donde la autocrítica realmente refina la solución.
PROBLEMAS: tuple[tuple[str, str], ...] = (
    # (problema, nivel)
    ("Parser robusto de CSV con headers y manejo de campos con comas y comillas", "intermedio"),
    ("Funcion de retry con backoff exponencial y jitter", "intermedio"),
    ("Implementacion de LRU cache thread-safe", "avanzado"),
    ("Validador de fechas en multiples formatos (es-PE, en-US, ISO)", "intermedio"),
    ("Rate limiter con sliding window de N requests por T segundos", "intermedio"),
    ("Funcion que serializa un grafo dirigido a JSON sin perder ciclos", "avanzado"),
    ("Cliente HTTP que pagina automaticamente hasta agotar resultados", "intermedio"),
    ("Funcion que parsea expresiones aritmeticas simples (precedencia)", "avanzado"),
    ("Implementacion de Promise/Future con timeout y cancellation", "avanzado"),
    ("Funcion que detecta y reporta dependencias circulares en un dict", "intermedio"),
    ("Endpoint que sube archivos grandes con streaming y resumacion", "avanzado"),
    ("Funcion que computa diff entre dos versiones de un documento (Myers)", "avanzado"),
    ("Mini-DSL para queries (parser + evaluador) con AND/OR/NOT", "avanzado"),
    ("Funcion que valida que una contrasena cumple politicas configurables", "intermedio"),
    ("Job scheduler que respeta dependencias entre tareas (DAG)", "avanzado"),
    ("Funcion que merge varios diccionarios anidados sin perder datos", "intermedio"),
    ("Implementacion de exponential backoff con circuit breaker", "avanzado"),
    ("Funcion que convierte tiempos relativos ('hace 2 dias') a datetime", "intermedio"),
    ("Pool de conexiones a BD con reaping de conexiones muertas", "avanzado"),
    ("Funcion que sanitiza un nombre de archivo para multiples OS", "intermedio"),
)


PROMPT_TEMPLATE = """Eres un programador senior demostrando como iterar
sobre tu propia solucion antes de entregarla. Genera UN ejemplo de
dataset que muestre 3 iteraciones de auto-critica.

Problema: {problema}

Devuelve un array JSON con UN elemento, con esta estructura:

[
  {{
    "instruccion": "Implementa: {problema}",
    "salida": "<respuesta final (solo la version C_final + breve explicacion de la evolucion), >=300 chars>",
    "nivel": "{nivel}",
    "tema": "razonamiento_iterativo",
    "tipo": "pensamiento_autocritico",
    "pensamiento": {{
      "iteraciones": [
        {{
          "version": "A",
          "codigo": "<codigo Python valido — version INICIAL razonable pero con problemas reales>",
          "critica": "<3 problemas concretos en A: bugs, edge cases no manejados, decisiones cuestionables. >=80 chars>"
        }},
        {{
          "version": "B",
          "codigo": "<codigo Python valido — version MEJORADA respondiendo a la critica de A>",
          "critica": "<1-2 problemas restantes en B: cosas que aun se pueden mejorar. >=60 chars>"
        }},
        {{
          "version": "C_final",
          "codigo": "<codigo Python valido — version FINAL production-grade>",
          "critica": "Sin problemas significativos."
        }}
      ]
    }}
  }}
]

REGLAS ESTRICTAS:
  - Solo el array JSON, sin texto antes o despues.
  - Las 3 versiones DEBEN compilar (ast.parse OK).
  - Las criticas deben senalar problemas REALES, no inventados ni cosmeticos.
  - Cada version debe ser estrictamente MEJOR que la anterior — no solo distinta.
  - "salida" es la respuesta final que se mostraria al estudiante: una breve
    explicacion del proceso + el codigo final (no las 3 versiones completas).
"""


async def generar_objetivo(
    pool: Pool, problema: str, nivel: str, *, temperatura: float
) -> list[EjemploEntrenamiento]:
    prompt = PROMPT_TEMPLATE.format(problema=problema, nivel=nivel)
    try:
        texto, proveedor = await pool.generar(
            prompt,
            tarea=Tarea.COT,
            temperatura=temperatura,
            max_tokens=4096,
            esperar_si_rate_limited=True,
        )
    except Exception as exc:
        print(f"  [!] {problema[:40]}: {exc}", file=sys.stderr)
        return []

    bruto = extraer_json_array(texto) or []
    ejemplos: list[EjemploEntrenamiento] = []
    for d in bruto:
        if not isinstance(d, dict):
            continue
        d["tipo"] = "pensamiento_autocritico"
        d.setdefault("tema", "razonamiento_iterativo")
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

    total = len(PROBLEMAS) * repeticiones
    contador = 0
    for problema, nivel in PROBLEMAS:
        for r in range(repeticiones):
            contador += 1
            print(f"[{contador:3d}/{total}] {problema[:50]} (rep {r+1})", flush=True)
            lote = await generar_objetivo(pool, problema, nivel, temperatura=temperatura)
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
    parser.add_argument("--repeticiones", type=int, default=3,
                        help="Cuantas veces pedir cada problema (variando temperatura)")
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
