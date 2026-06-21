"""EduCodeEval — Benchmark pedagógico propio para LLMs especializados en
generación y explicación de código.

A diferencia de HumanEval / MBPP (que solo miden si el código pasa unit
tests), EduCodeEval evalúa CINCO dimensiones que son las que importan en un
modelo educativo:

    1. GENERACIÓN     — Resolver el problema correctamente.
    2. EXPLICACIÓN    — Explicar el razonamiento de manera pedagógica.
    3. SEGURIDAD      — Identificar y corregir vulnerabilidades.
    4. REFACTORIZACIÓN— Detectar antipatrones y mejorar código.
    5. ENSEÑANZA      — Adaptar la respuesta al nivel del estudiante.

Cada tarea del benchmark se evalúa con UN ensemble:
    - Tests automáticos (cuando aplica: ejecución, AST, regex).
    - 6 reward models propios (SEG/LEG/ESC/ARQ/REN/MAN).
    - Juez LLM (Gemini) cuando se requiere subjetividad pedagógica.

La salida es una tarjeta de calificación con score 0-100 por dimensión y
un score global ponderado para el modelo evaluado.
"""

from .core import (
    Tarea,
    Categoria,
    EduCodeEval,
    ResultadoTarea,
    ResultadoBenchmark,
    cargar_tareas,
)

__all__ = [
    "Tarea",
    "Categoria",
    "EduCodeEval",
    "ResultadoTarea",
    "ResultadoBenchmark",
    "cargar_tareas",
]
