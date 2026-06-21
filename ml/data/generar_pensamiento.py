"""Generador del tipo `pensamiento_programador` (chain-of-thought).

Cada ejemplo NO solo tiene instrucción → respuesta. Captura el proceso
mental que un programador senior tendría antes de escribir el código:

    aclaraciones que pediría
    restricciones implícitas
    alternativas consideradas (mín 2, una elegida)
    criterios de decisión

Esto es la pieza pedagógica más valiosa del dataset V2 — lo que distingue
a un modelo que "razona" de uno que "completa código".

Uso:
    python -m ml.data.generar_pensamiento \\
        --salida datasets/raw/pensamiento_v1.jsonl \\
        --n-por-objetivo 5 \\
        --tarea cot

Sirve como TEMPLATE para los otros 8 generadores del dataset V2:
estructura idéntica, lo único que cambia es el prompt y el parser.
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


# ════════════════════════════════════════════════════════════════════
# Objetivos: (tema, nivel) — problemas no triviales donde el "cómo decidir"
# importa más que el "cómo escribir el código".
# ════════════════════════════════════════════════════════════════════

OBJETIVOS: tuple[tuple[str, str], ...] = (
    # ── Backend / APIs ──
    ("api_rest", "intermedio"),
    ("api_rest", "avanzado"),
    ("autenticacion", "intermedio"),
    ("autenticacion", "avanzado"),
    ("autorizacion_rbac", "intermedio"),
    ("graphql", "intermedio"),
    ("websockets_tiempo_real", "intermedio"),
    ("webhooks_idempotentes", "avanzado"),

    # ── Bases de datos ──
    ("base_de_datos", "intermedio"),
    ("base_de_datos", "avanzado"),
    ("optimizacion_consulta", "avanzado"),
    ("modelado_datos_relacional", "intermedio"),
    ("transacciones_aislamiento", "avanzado"),
    ("migraciones_bd", "intermedio"),
    ("particionamiento_sharding", "avanzado"),
    ("nosql_vs_sql", "intermedio"),

    # ── Concurrencia y performance ──
    ("caching", "intermedio"),
    ("caching_invalidacion", "avanzado"),
    ("concurrencia", "intermedio"),
    ("concurrencia", "avanzado"),
    ("asyncio_avanzado", "avanzado"),
    ("colas_mensajes", "avanzado"),
    ("rate_limiting", "intermedio"),
    ("batch_vs_streaming", "avanzado"),

    # ── Arquitectura distribuida ──
    ("microservicios", "avanzado"),
    ("event_driven_arch", "avanzado"),
    ("cqrs_event_sourcing", "avanzado"),
    ("saga_distributed_tx", "avanzado"),
    ("api_gateway", "intermedio"),

    # ── Seguridad ──
    ("seguridad_api", "intermedio"),
    ("seguridad_api", "avanzado"),
    ("oauth2_openid", "avanzado"),
    ("gestion_secretos", "intermedio"),
    ("input_validation_sanitizing", "intermedio"),

    # ── Calidad de software ──
    ("testing", "intermedio"),
    ("testing_estrategia_capas", "avanzado"),
    ("manejo_errores", "intermedio"),
    ("logging_observabilidad", "intermedio"),
    ("observabilidad_avanzada", "avanzado"),

    # ── DevOps / infraestructura ──
    ("ci_cd", "intermedio"),
    ("ci_cd_pipelines_avanzados", "avanzado"),
    ("etl_pipeline", "avanzado"),
    ("contenedores_dockerfile", "intermedio"),

    # ── Data Engineering / ML Engineering ──
    ("inferencia_llm_local", "avanzado"),
    ("rag_vector_db", "avanzado"),
    ("monitoreo_modelos_ml", "avanzado"),
)


PROMPT_TEMPLATE = """Eres un programador senior con 10+ años de experiencia
generando UN ejemplo de dataset para entrenar un modelo educativo. Tu objetivo
es demostrar el PROCESO MENTAL COMPLETO de un senior, no solo el código.

Tema: {tema}
Nivel objetivo del estudiante: {nivel}

Genera {n} ejemplos distintos como un ARRAY JSON. Cada elemento debe seguir
ESTA estructura completa de razonamiento del programador (idea inspirada en
chain-of-thought + arquitectura senior):

  Problema → Análisis → Diseño → Código → Explicación → Errores → Mejoras

Estructura de cada elemento:

  "instruccion": petición realista en español (1-3 líneas) sobre {tema}.

  "pensamiento": objeto con TODO el proceso mental:
       "aclaraciones":           [1-3 preguntas que un senior pediría antes
                                  de tocar código; pueden quedar resueltas
                                  como suposiciones razonables].
       "restricciones_implicitas": [2-4 supuestos que el código asume].
       "requisitos_no_funcionales": [2-4 items sobre latencia objetivo,
                                  escalabilidad esperada, SLA, presupuesto,
                                  compatibilidad].
       "alternativas_consideradas": [3 objetos con la forma
                                  {{"opcion": "...", "elegida": bool,
                                   "razon": "..."}}, EXACTAMENTE 1 elegida].
       "criterios_decision":     [2-4 criterios que ordenaron las alternativas].
       "pasos_implementacion":   [4-7 pasos ordenados: cómo lo construyo].
       "errores_comunes":        [2-4 errores típicos que un junior cometería
                                  resolviendo este mismo problema].
       "mejoras_futuras":        [2-3 things que NO se implementan ahora
                                  pero deberían planearse para una v2].

  "salida": respuesta pedagógica completa (>=600 chars) que junte todo:
       1) Resumen del enfoque elegido (1 párrafo).
       2) Arquitectura de la solución (1 párrafo o diagrama textual).
       3) Código Python COMPLETO funcional en ```python ... ``` con type
          hints y docstrings.
       4) Explicación del código por bloques (qué hace cada parte y por qué).
       5) "Errores que evitar" — lista breve.
       6) "Cómo evolucionar esto en producción" — 1 párrafo final.

  "nivel": "{nivel}"
  "tema": "{tema}"

REGLAS ESTRICTAS:
  - Solo el array JSON. Sin texto antes ni después. Sin wrapper de markdown.
  - El código Python DEBE compilar (sintaxis válida).
  - "salida" >= 600 caracteres.
  - Cada elemento debe atacar un PROBLEMA DISTINTO dentro del mismo tema, no
    variaciones triviales del mismo.
  - "alternativas_consideradas" debe incluir alternativas REALMENTE distintas
    (no la misma tecnología en versiones), con razones SUSTANTIVAS (no "es más
    popular").
  - "pasos_implementacion" deben ser accionables (no "implementar bien").
  - "errores_comunes" deben ser concretos, no genéricos.
"""


# ════════════════════════════════════════════════════════════════════
# Generación
# ════════════════════════════════════════════════════════════════════

async def generar_objetivo(
    pool: Pool, tema: str, nivel: str, n: int, *, temperatura: float
) -> list[EjemploEntrenamiento]:
    prompt = PROMPT_TEMPLATE.format(tema=tema, nivel=nivel, n=n)
    try:
        texto, proveedor = await pool.generar(
            prompt,
            tarea=Tarea.COT,
            temperatura=temperatura,
            max_tokens=4096,
            esperar_si_rate_limited=True,
        )
    except Exception as exc:
        print(f"  [!] {tema}/{nivel}: fallo generación: {exc}", file=sys.stderr)
        return []

    bruto = extraer_json_array(texto) or []
    ejemplos: list[EjemploEntrenamiento] = []
    for d in bruto:
        if not isinstance(d, dict):
            continue
        d.setdefault("tema", tema)
        d.setdefault("nivel", nivel)
        d["tipo"] = "pensamiento_programador"
        d["fuente"] = proveedor
        try:
            ejemplos.append(EjemploEntrenamiento.from_dict(d))
        except Exception:  # noqa: BLE001
            continue
    return ejemplos


async def generar_corpus(
    pool: Pool,
    salida: Path,
    *,
    n_por_objetivo: int,
    temperatura: float,
    objetivos: tuple[tuple[str, str], ...] = OBJETIVOS,
) -> dict[str, Any]:
    todos: list[EjemploEntrenamiento] = []
    descartados_por_motivo: dict[str, int] = {}
    inicio = time.time()

    for i, (tema, nivel) in enumerate(objetivos, 1):
        print(f"[{i:2d}/{len(objetivos)}] {tema}/{nivel} (n={n_por_objetivo})...", flush=True)
        lote = await generar_objetivo(
            pool, tema, nivel, n_por_objetivo, temperatura=temperatura
        )

        # Validación inmediata: rechazar basura antes de acumular.
        for ej in lote:
            ok, motivo = validar_ejemplo(ej)
            if ok:
                todos.append(ej)
            else:
                clave = motivo.split(":", 1)[0]
                descartados_por_motivo[clave] = descartados_por_motivo.get(clave, 0) + 1

        elapsed = time.time() - inicio
        print(
            f"    válidos hasta ahora: {len(todos)}  |  descartados: {sum(descartados_por_motivo.values())}  "
            f"|  {elapsed/60:.1f} min",
            flush=True,
        )

    # Dedup final.
    antes = len(todos)
    todos = deduplicar(todos)
    duplicados = antes - len(todos)

    guardar_jsonl(todos, salida)
    stats = estadisticas_corpus(todos)
    stats.update({
        "archivo": str(salida),
        "duplicados_eliminados": duplicados,
        "descartados_por_motivo": descartados_por_motivo,
        "tiempo_minutos": round((time.time() - inicio) / 60, 1),
        "pool_stats": pool.stats(),
    })
    return stats


# ════════════════════════════════════════════════════════════════════
# CLI
# ════════════════════════════════════════════════════════════════════

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--salida", required=True,
                        help="Ruta JSONL de salida (se crea el directorio)")
    parser.add_argument("--n-por-objetivo", type=int, default=5,
                        help="Cuántos ejemplos pedir por (tema, nivel)")
    parser.add_argument("--temperatura", type=float, default=0.9)
    parser.add_argument("--objetivos-archivo", default=None,
                        help="JSON opcional con [[tema, nivel], ...] que sobreescribe OBJETIVOS")
    args = parser.parse_args()

    objetivos = OBJETIVOS
    if args.objetivos_archivo:
        with open(args.objetivos_archivo, encoding="utf-8") as f:
            datos = json.load(f)
        objetivos = tuple((t, n) for t, n in datos)

    pool = Pool.desde_env()
    print(f"Pool de generadores activo: {pool.disponibles}")

    stats = asyncio.run(generar_corpus(
        pool,
        salida=Path(args.salida),
        n_por_objetivo=args.n_por_objetivo,
        temperatura=args.temperatura,
        objetivos=objetivos,
    ))

    print("\n=== RESULTADO ===")
    print(json.dumps(stats, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
