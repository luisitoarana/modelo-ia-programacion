"""Categoría EXPLICACIÓN — Capacidad pedagógica.

Las tareas pasan código + pregunta y la respuesta se evalúa por:
  - Longitud (no demasiado corta, no inflada).
  - Cobertura de conceptos esperados (por palabras clave).
  - Ausencia de errores técnicos (no mencionar cosas inexistentes).
  - Estructura pedagógica (qué hace, por qué, cuándo).
"""

from __future__ import annotations

from typing import Any

from ..core import Tarea, Categoria


def _verificador_explicacion(
    *,
    minimo_chars: int,
    conceptos_clave: list[str],
    errores_si_aparecen: list[str] | None = None,
    estructura_pedagogica: list[str] | None = None,
) -> callable:
    """Construye un verificador para tareas de explicación.

    Args:
        minimo_chars        — Longitud mínima de la respuesta.
        conceptos_clave     — Palabras/frases que DEBEN aparecer.
        errores_si_aparecen — Frases que NO deben aparecer (incorrectas).
        estructura_pedagogica — Marcadores de estructura ("qué hace",
                                "por qué", "cuándo", "ejemplo").
    """
    errores_si_aparecen = errores_si_aparecen or []
    estructura_pedagogica = estructura_pedagogica or []

    def _verif(respuesta: str) -> dict[str, Any]:
        detalle: dict[str, Any] = {
            "len_chars": len(respuesta),
            "conceptos_cubiertos": [],
            "conceptos_faltantes": [],
            "errores_detectados": [],
            "estructura_marcadores": [],
        }
        score = 0.0

        # 1. Longitud (0–30 puntos)
        if len(respuesta) >= minimo_chars:
            score += 30.0
        elif len(respuesta) >= minimo_chars * 0.5:
            score += 15.0
        else:
            detalle["motivo_longitud"] = (
                f"muy corta: {len(respuesta)} < {minimo_chars}"
            )

        # 2. Cobertura de conceptos (0–40 puntos)
        baja = respuesta.lower()
        for c in conceptos_clave:
            if c.lower() in baja:
                detalle["conceptos_cubiertos"].append(c)
            else:
                detalle["conceptos_faltantes"].append(c)
        cobertura = len(detalle["conceptos_cubiertos"]) / max(1, len(conceptos_clave))
        score += 40.0 * cobertura

        # 3. Estructura pedagógica (0–20 puntos)
        if estructura_pedagogica:
            for marca in estructura_pedagogica:
                if marca.lower() in baja:
                    detalle["estructura_marcadores"].append(marca)
            estructura_score = len(detalle["estructura_marcadores"]) / len(
                estructura_pedagogica
            )
            score += 20.0 * estructura_score
        else:
            score += 20.0

        # 4. Penalización por errores (resta hasta 30 puntos)
        for err in errores_si_aparecen:
            if err.lower() in baja:
                detalle["errores_detectados"].append(err)
        score -= 10.0 * len(detalle["errores_detectados"])
        score = max(0.0, min(100.0, score))

        detalle["score"] = score
        return detalle

    return _verif


TAREAS: list[Tarea] = [

    Tarea(
        id="exp_01_list_comprehension",
        categoria=Categoria.EXPLICACION,
        prompt=(
            "Explica qué hace este código y por qué es preferible a un loop "
            "for tradicional con .append():\n\n"
            "```python\n"
            "cuadrados_pares = [x**2 for x in range(20) if x % 2 == 0]\n"
            "```"
        ),
        descripcion="List comprehension con filtro",
        verificador=_verificador_explicacion(
            minimo_chars=300,
            conceptos_clave=[
                "comprehension", "iterar", "filtrar",
                "range", "lista", "más rápido",
            ],
            errores_si_aparecen=[
                "más lento que un for",
                "comprehension siempre mejor",
            ],
            estructura_pedagogica=["qué hace", "por qué", "ejemplo"],
        ),
    ),

    Tarea(
        id="exp_02_decorador",
        categoria=Categoria.EXPLICACION,
        prompt=(
            "Explica para qué sirve este decorador y cómo funciona:\n\n"
            "```python\n"
            "from functools import lru_cache\n\n"
            "@lru_cache(maxsize=128)\n"
            "def fib(n):\n"
            "    if n < 2: return n\n"
            "    return fib(n-1) + fib(n-2)\n"
            "```"
        ),
        descripcion="lru_cache y memoización",
        verificador=_verificador_explicacion(
            minimo_chars=350,
            conceptos_clave=[
                "memoización", "caché", "decorador",
                "recursiv", "complejidad",
            ],
            errores_si_aparecen=[
                "lru_cache hace que sea más lento",
            ],
            estructura_pedagogica=["qué hace", "por qué"],
        ),
    ),

    Tarea(
        id="exp_03_context_manager",
        categoria=Categoria.EXPLICACION,
        prompt=(
            "Explica por qué este código es preferible al equivalente con "
            "`f = open(...)` + `f.close()` al final:\n\n"
            "```python\n"
            "with open('datos.txt', 'r') as f:\n"
            "    contenido = f.read()\n"
            "```"
        ),
        descripcion="Context manager para archivos",
        verificador=_verificador_explicacion(
            minimo_chars=300,
            conceptos_clave=[
                "context manager", "with", "cierra",
                "excepción", "automátic",
            ],
            estructura_pedagogica=["qué hace", "por qué"],
        ),
    ),

    Tarea(
        id="exp_04_generadores",
        categoria=Categoria.EXPLICACION,
        prompt=(
            "Explica la diferencia entre:\n\n"
            "```python\n"
            "def lista():\n"
            "    return [x for x in range(1_000_000)]\n\n"
            "def generador():\n"
            "    return (x for x in range(1_000_000))\n"
            "```\n"
            "¿Cuándo conviene cada uno?"
        ),
        descripcion="Lista vs generator",
        verificador=_verificador_explicacion(
            minimo_chars=350,
            conceptos_clave=[
                "memoria", "lazy", "iterar",
                "generator", "yield",
            ],
            estructura_pedagogica=["cuándo", "ejemplo"],
        ),
    ),

    Tarea(
        id="exp_05_mutable_default",
        categoria=Categoria.EXPLICACION,
        prompt=(
            "¿Qué problema tiene este código? Explica por qué pasa y cómo "
            "corregirlo:\n\n"
            "```python\n"
            "def agregar(item, lista=[]):\n"
            "    lista.append(item)\n"
            "    return lista\n"
            "```"
        ),
        descripcion="Mutable default argument",
        verificador=_verificador_explicacion(
            minimo_chars=300,
            conceptos_clave=[
                "mutable", "compartid", "evaluación",
                "definición", "None",
            ],
            errores_si_aparecen=[
                "no tiene problema",
                "es correcto",
            ],
            estructura_pedagogica=["por qué", "cómo"],
        ),
    ),
]
