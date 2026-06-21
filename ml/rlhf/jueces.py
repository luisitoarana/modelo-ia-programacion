"""Jueces LLM multi-criterio para etiquetar el dataset con scores 0-10.

Cada respuesta del modelo recibe 6 notas independientes:

    SEG · Seguridad        (vulnerabilidades, OWASP, secrets, sanitización)
    LEG · Legibilidad      (nombres, estructura, comentarios útiles)
    ESC · Escalabilidad    (complejidad algorítmica, memoria, crecimiento)
    ARQ · Arquitectura     (separación, dependencias, patrones)
    REN · Rendimiento      (optimizaciones, ausencia de redundancia)
    MAN · Mantenibilidad   (tests, error handling, docs, config)

Cada dimensión se evalúa con ENSEMBLE de 3 jueces (de proveedores distintos)
y se toma la mediana. Esto reduce el sesgo de un solo LLM-juez.

El dataset resultante alimenta:
    - DPO multi-objetivo (`ml/rlhf/dpo.py`)
    - Training de los 6 reward models propios (`ml/rlhf/reward_model.py`)

Uso programático:
    from ml.rlhf.jueces import calificar_respuesta
    scores = await calificar_respuesta(pool, pregunta, respuesta)
    # → {"SEG": 8, "LEG": 7, "ESC": 6, "ARQ": 7, "REN": 8, "MAN": 6}
"""

from __future__ import annotations

import asyncio
from dataclasses import dataclass
from statistics import median
from typing import Any

from ml.data.pool_generadores import Pool, Tarea, extraer_json_objeto
from ml.data.schema import DIMENSIONES_PUNTUACION


# ════════════════════════════════════════════════════════════════════
# Rúbricas — cada dimensión tiene definición + rúbrica 0-10
# ════════════════════════════════════════════════════════════════════

@dataclass(frozen=True, slots=True)
class Rubrica:
    nombre: str
    definicion: str
    rubrica: str


RUBRICAS: dict[str, Rubrica] = {
    "SEG": Rubrica(
        nombre="Seguridad",
        definicion=(
            "Ausencia de vulnerabilidades, manejo correcto de inputs, gestión "
            "segura de credenciales, conformidad con OWASP Top 10, defensa en "
            "profundidad."
        ),
        rubrica=(
            "0-2: contiene SQL/command/template injection, XSS, hardcoded secret, eval/exec inseguro\n"
            "3-4: vulnerable a edge cases obvios (timing attack, validación débil, dependencias inseguras)\n"
            "5-6: básicamente seguro pero con omisiones notables (sin rate limit, sin sanitización plena)\n"
            "7-8: aplica buenas prácticas conocidas (parametrized queries, secrets en env, auth correcta)\n"
            "9-10: defensive coding completo, considera amenazas no triviales (CSRF, replay, supply chain)"
        ),
    ),
    "LEG": Rubrica(
        nombre="Legibilidad",
        definicion=(
            "Nombres claros, estructura clara del código, comentarios pertinentes "
            "(no redundantes), complejidad cognitiva baja, formato PEP-8."
        ),
        rubrica=(
            "0-2: nombres crípticos (a, b, tmp1), código denso sin estructura, sin formato\n"
            "3-4: parte legible pero hay funciones largas, anidamiento profundo, magic numbers\n"
            "5-6: nombres aceptables y estructura razonable, faltan algunos type hints\n"
            "7-8: nombres descriptivos, funciones pequeñas y cohesivas, type hints completos\n"
            "9-10: código que se lee como prosa, intención evidente sin necesidad de comentarios"
        ),
    ),
    "ESC": Rubrica(
        nombre="Escalabilidad",
        definicion=(
            "Capacidad de crecer en datos, usuarios o complejidad. Considera "
            "complejidad algorítmica (Big-O), uso de memoria, batching, paginación, "
            "concurrencia."
        ),
        rubrica=(
            "0-2: O(n²) o peor sin necesidad, carga todo en memoria, no pagina\n"
            "3-4: funciona para datos pequeños pero rompe pasando un umbral evidente\n"
            "5-6: algoritmos correctos pero sin paginación / streaming / cache\n"
            "7-8: complejidad óptima, paginación correcta, streaming donde aplica\n"
            "9-10: escala horizontalmente, cache strategy, índices y batching considerados"
        ),
    ),
    "ARQ": Rubrica(
        nombre="Arquitectura",
        definicion=(
            "Separación de responsabilidades, dirección correcta de dependencias, "
            "uso apropiado de patrones, ausencia de god-objects, dependency inversion."
        ),
        rubrica=(
            "0-2: lógica de negocio mezclada con I/O, dependencias circulares, todo en un main\n"
            "3-4: separación incipiente pero capas se filtran (controller con SQL directo)\n"
            "5-6: capas presentes pero acoplamiento alto, sin tests aislables\n"
            "7-8: capas limpias, dependencias inyectadas, tests aislados son posibles\n"
            "9-10: arquitectura hexagonal/clean, dominios separados, fácil de extender"
        ),
    ),
    "REN": Rubrica(
        nombre="Rendimiento",
        definicion=(
            "Optimizaciones razonables, uso de stdlib eficiente, ausencia de "
            "cómputo redundante, perfil de allocations razonable."
        ),
        rubrica=(
            "0-2: re-cálculos en loop, conversiones innecesarias, listas donde van sets\n"
            "3-4: funciona pero con allocations excesivas o pasos redundantes\n"
            "5-6: rendimiento aceptable, sin optimizaciones notorias\n"
            "7-8: uso apropiado de generators/sets/dict; evita trabajo innecesario\n"
            "9-10: perfil considerado, cache de resultados costosos, vectorización donde aplica"
        ),
    ),
    "MAN": Rubrica(
        nombre="Mantenibilidad",
        definicion=(
            "Tests, manejo robusto de errores, documentación útil, configuración "
            "externa, observabilidad básica (logs)."
        ),
        rubrica=(
            "0-2: sin manejo de errores, sin tests, sin docs, configs hardcoded\n"
            "3-4: try/except genérico que oculta errores, docstrings inútiles\n"
            "5-6: errores manejados básicamente, hay docs mínimas, config en env\n"
            "7-8: errores específicos, logs informativos, tests cubren el camino feliz\n"
            "9-10: error model claro, tests + edge cases, logs estructurados, métricas"
        ),
    ),
}

assert set(RUBRICAS.keys()) == set(DIMENSIONES_PUNTUACION), \
    "Las rúbricas deben cubrir exactamente DIMENSIONES_PUNTUACION"


PROMPT_JUEZ = """Eres un revisor senior evaluando una respuesta de código y
explicación. Tu única tarea es calificar UNA dimensión: **{nombre} ({dim})**.

DEFINICIÓN:
{definicion}

RÚBRICA (escala 0-10):
{rubrica}

Pregunta original:
{pregunta}

Respuesta a evaluar:
{respuesta}

Devuelve EXACTAMENTE un objeto JSON sin markdown, con la forma:
{{"score": <entero 0-10>, "razon": "<una sola frase>"}}

Reglas:
  - No expliques fuera del JSON.
  - Si la respuesta no aplica al criterio (ej: pregunta puramente conceptual
    en SEG), devuelve score 5 con razón "no aplica".
  - Sé estricto: 10 es excepcional, 7 es bueno, 5 es promedio.
"""


# ════════════════════════════════════════════════════════════════════
# Ensemble — qué proveedor evalúa qué dimensión
# ════════════════════════════════════════════════════════════════════

# Para cada dimensión, 3 proveedores en orden de preferencia. El pool
# elige los DISPONIBLES; si hay menos de 3 configurados, el ensemble se
# reduce automáticamente.
JUECES_POR_DIMENSION: dict[str, tuple[str, ...]] = {
    "SEG": ("gemini", "deepseek", "groq"),
    "LEG": ("gemini", "mistral", "groq"),
    "ESC": ("deepseek", "gemini", "groq"),
    "ARQ": ("gemini", "deepseek", "mistral"),
    "REN": ("deepseek", "groq", "together"),
    "MAN": ("gemini", "deepseek", "mistral"),
}


# ════════════════════════════════════════════════════════════════════
# API pública
# ════════════════════════════════════════════════════════════════════

async def calificar_dimension(
    pool: Pool, pregunta: str, respuesta: str, dim: str
) -> tuple[int | None, list[dict[str, Any]]]:
    """Devuelve (mediana de scores, detalle por juez).

    detalle = [{"proveedor": "gemini", "score": 8, "razon": "..."}, ...]
    """
    if dim not in RUBRICAS:
        raise ValueError(f"dimensión desconocida: {dim}")

    r = RUBRICAS[dim]
    prompt = PROMPT_JUEZ.format(
        dim=dim, nombre=r.nombre, definicion=r.definicion,
        rubrica=r.rubrica, pregunta=pregunta, respuesta=respuesta,
    )

    proveedores_preferidos = JUECES_POR_DIMENSION[dim]
    proveedores_usables = [p for p in proveedores_preferidos if p in pool.disponibles]
    if not proveedores_usables:
        # Caer a cualquier disponible.
        proveedores_usables = pool.disponibles[:3]

    tareas = [
        _calificar_con_proveedor(pool, prompt, proveedor)
        for proveedor in proveedores_usables
    ]
    resultados = await asyncio.gather(*tareas, return_exceptions=True)

    detalle: list[dict[str, Any]] = []
    scores: list[int] = []
    for proveedor, res in zip(proveedores_usables, resultados):
        if isinstance(res, Exception):
            detalle.append({"proveedor": proveedor, "error": str(res)})
            continue
        if res is None:
            detalle.append({"proveedor": proveedor, "error": "parse falló"})
            continue
        score, razon = res
        scores.append(score)
        detalle.append({"proveedor": proveedor, "score": score, "razon": razon})

    if not scores:
        return None, detalle
    # Mediana entera. Con 2 jueces es el promedio (round).
    mediana_val = median(scores)
    return int(round(mediana_val)), detalle


async def calificar_respuesta(
    pool: Pool, pregunta: str, respuesta: str,
    *, dimensiones: tuple[str, ...] = DIMENSIONES_PUNTUACION,
) -> dict[str, Any]:
    """Califica todas las dimensiones en paralelo.

    Devuelve:
        {
          "scores": {"SEG": 8, "LEG": 7, ...},
          "detalle": {"SEG": [{"proveedor": ..., "score": ..., "razon": ...}, ...]}
        }
    """
    tareas = [calificar_dimension(pool, pregunta, respuesta, d) for d in dimensiones]
    resultados = await asyncio.gather(*tareas)

    scores: dict[str, int] = {}
    detalle: dict[str, list[dict[str, Any]]] = {}
    for dim, (score, det) in zip(dimensiones, resultados):
        if score is not None:
            scores[dim] = score
        detalle[dim] = det

    return {"scores": scores, "detalle": detalle}


# ════════════════════════════════════════════════════════════════════
# Internos
# ════════════════════════════════════════════════════════════════════

async def _calificar_con_proveedor(
    pool: Pool, prompt: str, proveedor: str
) -> tuple[int, str] | None:
    try:
        texto, _ = await pool.generar(
            prompt,
            tarea=Tarea.EVALUACION,
            temperatura=0.2,            # baja para que la nota sea consistente
            max_tokens=256,
            proveedor_forzado=proveedor,
        )
    except Exception:
        return None

    obj = extraer_json_objeto(texto)
    if not obj:
        return None
    score = obj.get("score")
    razon = obj.get("razon") or obj.get("razón") or ""
    if not isinstance(score, (int, float)):
        return None
    score = max(0, min(10, int(round(score))))
    return score, str(razon)[:200]
