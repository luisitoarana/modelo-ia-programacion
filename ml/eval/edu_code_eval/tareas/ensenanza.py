"""Categoría ENSEÑANZA — Capacidad de adaptar la explicación al nivel.

Lo que hace especial a un modelo educativo: el mismo concepto explicado
distinto según la audiencia (niño, principiante, intermedio, profesional).

Cada tarea pide explícitamente "explica X a un niño" o "explica X a un
profesional" y el verificador comprueba calibración de vocabulario,
densidad técnica y presencia o ausencia de bloques de código.
"""

from __future__ import annotations

import re
from typing import Any

from ..core import Tarea, Categoria, _vocabulario_calibrado


_JERGA = {
    "variable", "función", "funcion", "método", "metodo", "objeto",
    "iterador", "memoria", "bytecode", "compilador", "polimorf",
    "instanciar", "encapsul",
}


def _densidad_jerga(texto: str) -> float:
    palabras = texto.split()
    if not palabras:
        return 0.0
    encontradas = sum(1 for w in palabras if w.strip(".,;:()").lower() in _JERGA)
    return encontradas / len(palabras)


def _verificador_nino() -> callable:
    """Para 'explica a un niño': premia analogía, penaliza jerga y código."""
    def _verif(respuesta: str) -> dict[str, Any]:
        detalle: dict[str, Any] = {}
        score = 0.0
        baja = respuesta.lower()

        # 1. Longitud razonable (60-1000 chars).
        if 60 <= len(respuesta) <= 1500:
            score += 20.0
        elif len(respuesta) < 60:
            detalle["motivo_longitud"] = "muy corto"

        # 2. SIN código (un niño no entiende).
        if "```" not in respuesta:
            score += 25.0
        else:
            detalle["error"] = "incluye bloque de código (no apto para niño)"

        # 3. Densidad de jerga muy baja (<2%).
        dens = _densidad_jerga(respuesta)
        detalle["densidad_jerga"] = round(dens, 3)
        if dens < 0.02:
            score += 25.0
        elif dens < 0.05:
            score += 12.0

        # 4. Usa marcadores de analogía cotidiana.
        marcadores_analogia = [
            "imagina", "como si", "es como", "piensa en", "supon",
            "una caja", "un juego", "una receta",
        ]
        if any(m in baja for m in marcadores_analogia):
            score += 30.0
            detalle["analogia_detectada"] = True

        detalle["score"] = max(0.0, min(100.0, score))
        return detalle
    return _verif


def _verificador_principiante(
    *, conceptos_clave: list[str]
) -> callable:
    """Premia ejemplo Python simple + 1 concepto bien explicado."""
    def _verif(respuesta: str) -> dict[str, Any]:
        detalle: dict[str, Any] = {}
        score = 0.0
        baja = respuesta.lower()

        # 1. Longitud (200-2000 chars).
        if 200 <= len(respuesta) <= 2500:
            score += 20.0

        # 2. Incluye UN ejemplo de código.
        bloques = re.findall(r"```(?:python|py)?\s*\n?(.*?)```", respuesta, re.DOTALL)
        if bloques:
            score += 30.0
            detalle["bloques_codigo"] = len(bloques)
            # Penalizar si tiene demasiados (sobrecarga al principiante).
            if len(bloques) > 3:
                score -= 10.0

        # 3. Cobertura de conceptos clave (sin sobreflujo de jerga).
        cubiertos = [c for c in conceptos_clave if c.lower() in baja]
        detalle["conceptos_cubiertos"] = cubiertos
        score += 30.0 * (len(cubiertos) / max(1, len(conceptos_clave)))

        # 4. Densidad de jerga MODERADA (5-15%).
        dens = _densidad_jerga(respuesta)
        if 0.03 <= dens <= 0.12:
            score += 20.0

        detalle["score"] = max(0.0, min(100.0, score))
        return detalle
    return _verif


def _verificador_profesional(
    *, conceptos_avanzados: list[str]
) -> callable:
    """Premia internals, edge cases y referencias técnicas densas."""
    def _verif(respuesta: str) -> dict[str, Any]:
        detalle: dict[str, Any] = {}
        score = 0.0
        baja = respuesta.lower()

        # 1. Longitud densa (>=500 chars).
        if len(respuesta) >= 500:
            score += 20.0
        else:
            detalle["motivo"] = "muy corto para profesional"

        # 2. Densidad alta de vocabulario técnico (>=4%).
        dens = _densidad_jerga(respuesta)
        if dens >= 0.04:
            score += 20.0
        detalle["densidad_jerga"] = round(dens, 3)

        # 3. Cobertura de conceptos avanzados.
        cubiertos = [c for c in conceptos_avanzados if c.lower() in baja]
        detalle["conceptos_avanzados_cubiertos"] = cubiertos
        score += 35.0 * (len(cubiertos) / max(1, len(conceptos_avanzados)))

        # 4. Menciona PEP / CPython / internals / edge cases.
        marcadores_pro = [
            "pep", "cpython", "internals", "edge case", "bytecode",
            "implementación", "implementacion", "complejidad",
            "trade-off", "tradeoff",
        ]
        if any(m in baja for m in marcadores_pro):
            score += 25.0
            detalle["referencia_pro"] = True

        detalle["score"] = max(0.0, min(100.0, score))
        return detalle
    return _verif


TAREAS: list[Tarea] = [

    # ── Mismo concepto, 3 niveles ──

    Tarea(
        id="ens_01_variable_nino",
        categoria=Categoria.ENSENANZA,
        prompt=(
            "Explícale a un niño de 9 años qué es una variable en "
            "programación. Usa una analogía cotidiana."
        ),
        descripcion="Variable explicada a un niño",
        verificador=_verificador_nino(),
    ),
    Tarea(
        id="ens_02_variable_principiante",
        categoria=Categoria.ENSENANZA,
        prompt=(
            "Explícale a un estudiante de primer semestre de programación "
            "qué es una variable en Python. Incluye un ejemplo corto."
        ),
        descripcion="Variable para principiante",
        verificador=_verificador_principiante(
            conceptos_clave=["asignar", "valor", "nombre", "memoria", "="],
        ),
    ),
    Tarea(
        id="ens_03_variable_profesional",
        categoria=Categoria.ENSENANZA,
        prompt=(
            "Explícale a un programador con 5 años de experiencia qué hace "
            "Python internamente cuando ejecuta `x = 5; x = 'hola'`. "
            "Menciona dynamic typing y referencias."
        ),
        descripcion="Variable para profesional (internals)",
        verificador=_verificador_profesional(
            conceptos_avanzados=[
                "dynamic typing", "tipado dinámico", "tipado dinamico",
                "referencia", "PyObject", "namespace",
            ],
        ),
    ),

    Tarea(
        id="ens_04_funcion_nino",
        categoria=Categoria.ENSENANZA,
        prompt="Explícale a un niño de 10 años qué es una función en programación.",
        descripcion="Función a un niño",
        verificador=_verificador_nino(),
    ),
    Tarea(
        id="ens_05_funcion_principiante",
        categoria=Categoria.ENSENANZA,
        prompt=(
            "Explícale a un principiante qué es una función en Python. "
            "Incluye un ejemplo de `def` con parámetro y return."
        ),
        descripcion="Función a un principiante",
        verificador=_verificador_principiante(
            conceptos_clave=["def", "parámetro", "parametro", "return", "llamar"],
        ),
    ),
    Tarea(
        id="ens_06_decorador_profesional",
        categoria=Categoria.ENSENANZA,
        prompt=(
            "Explícale a un dev senior qué es un decorador en Python. "
            "Aborda: clausura, función de orden superior, casos donde usar "
            "`functools.wraps`, y diferencia con metaclases."
        ),
        descripcion="Decorador a un profesional",
        verificador=_verificador_profesional(
            conceptos_avanzados=[
                "clausura", "closure", "orden superior",
                "wraps", "metaclase", "@",
            ],
        ),
    ),

    Tarea(
        id="ens_07_loop_nino",
        categoria=Categoria.ENSENANZA,
        prompt="Explícale a un niño qué es un bucle (loop) usando una analogía.",
        descripcion="Loop a un niño",
        verificador=_verificador_nino(),
    ),
]
