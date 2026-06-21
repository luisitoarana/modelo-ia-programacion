"""Categoría GENERACIÓN — Resolver el problema correctamente.

Cada tarea define el prompt + tests unitarios que la respuesta debe pasar.
El verificador extrae el código de la respuesta (con regex) y lo ejecuta
con los tests.
"""

from __future__ import annotations

import re
from typing import Any

from ..core import Tarea, Categoria, _codigo_compila, _pasa_unit_tests


_FENCE_RE = re.compile(r"```(?:python|py)?\s*\n?(.*?)```", re.DOTALL | re.IGNORECASE)


def _extraer_codigo(respuesta: str) -> str:
    """Extrae el primer bloque de código Python de la respuesta."""
    m = _FENCE_RE.search(respuesta)
    return m.group(1).strip() if m else respuesta.strip()


def _verificador_con_tests(tests: str) -> callable:
    """Construye un verificador que ejecuta tests sobre el código extraído."""

    def _verif(respuesta: str) -> dict[str, Any]:
        codigo = _extraer_codigo(respuesta)
        detalle: dict[str, Any] = {
            "codigo_extraido_chars": len(codigo),
            "compila": False,
            "pasa_tests": False,
        }
        if not codigo:
            detalle["score"] = 0.0
            detalle["motivo"] = "sin código en la respuesta"
            return detalle

        if not _codigo_compila(codigo):
            detalle["score"] = 10.0
            detalle["motivo"] = "código no compila"
            return detalle
        detalle["compila"] = True

        if _pasa_unit_tests(codigo, tests):
            detalle["pasa_tests"] = True
            detalle["score"] = 100.0
        else:
            detalle["score"] = 50.0
            detalle["motivo"] = "compila pero no pasa los tests"
        return detalle

    return _verif


# ════════════════════════════════════════════════════════════════════
# Tareas
# ════════════════════════════════════════════════════════════════════

TAREAS: list[Tarea] = [

    Tarea(
        id="gen_01_fibonacci",
        categoria=Categoria.GENERACION,
        prompt=(
            "Escribe una función Python llamada `fibonacci(n)` que retorne "
            "el n-ésimo número de Fibonacci (con fibonacci(0)=0, "
            "fibonacci(1)=1). Debe funcionar para n hasta 100 sin recursión "
            "exponencial."
        ),
        descripcion="Fibonacci eficiente",
        verificador=_verificador_con_tests("""
assert fibonacci(0) == 0
assert fibonacci(1) == 1
assert fibonacci(10) == 55
assert fibonacci(20) == 6765
assert fibonacci(50) == 12586269025
"""),
    ),

    Tarea(
        id="gen_02_palindromo",
        categoria=Categoria.GENERACION,
        prompt=(
            "Escribe `es_palindromo(s: str) -> bool` que retorne True si `s` "
            "es palíndromo ignorando mayúsculas, espacios y signos de "
            "puntuación. 'Anita lava la tina' debe dar True."
        ),
        descripcion="Detector de palíndromos con normalización",
        verificador=_verificador_con_tests("""
assert es_palindromo("Anita lava la tina") is True
assert es_palindromo("Sé verlas al revés") is True
assert es_palindromo("hola") is False
assert es_palindromo("") is True
assert es_palindromo("a.") is True
"""),
    ),

    Tarea(
        id="gen_03_frecuencias",
        categoria=Categoria.GENERACION,
        prompt=(
            "Escribe `top_k_palabras(texto: str, k: int) -> list[tuple[str, int]]` "
            "que retorne las k palabras más frecuentes con sus conteos, ordenadas "
            "por frecuencia descendente y alfabéticamente como desempate. "
            "Ignora mayúsculas y signos de puntuación."
        ),
        descripcion="Top-k palabras con desempate alfabético",
        verificador=_verificador_con_tests("""
r = top_k_palabras("hola hola mundo Hola, mundo. adios", 2)
assert r == [("hola", 3), ("mundo", 2)], f"Got: {r}"
r = top_k_palabras("a a b b c", 3)
assert r == [("a", 2), ("b", 2), ("c", 1)], f"Got: {r}"
"""),
    ),

    Tarea(
        id="gen_04_busqueda_binaria",
        categoria=Categoria.GENERACION,
        prompt=(
            "Implementa `busqueda_binaria(lista: list[int], objetivo: int) -> int` "
            "que retorne el índice del objetivo o -1 si no está. Lista ordenada "
            "ascendente."
        ),
        descripcion="Búsqueda binaria iterativa",
        verificador=_verificador_con_tests("""
assert busqueda_binaria([1, 3, 5, 7, 9], 5) == 2
assert busqueda_binaria([1, 3, 5, 7, 9], 1) == 0
assert busqueda_binaria([1, 3, 5, 7, 9], 9) == 4
assert busqueda_binaria([1, 3, 5, 7, 9], 4) == -1
assert busqueda_binaria([], 1) == -1
"""),
    ),

    Tarea(
        id="gen_05_validar_email",
        categoria=Categoria.GENERACION,
        prompt=(
            "Escribe `es_email_valido(s: str) -> bool` que valide un email "
            "simple: parte local con letras/números/_/.-, una @, dominio con "
            "al menos un punto y extensión de 2-6 letras."
        ),
        descripcion="Validador de email con regex",
        verificador=_verificador_con_tests("""
assert es_email_valido("user@example.com") is True
assert es_email_valido("a.b-c_d@sub.dominio.co") is True
assert es_email_valido("sin_arroba.com") is False
assert es_email_valido("@example.com") is False
assert es_email_valido("user@.com") is False
"""),
    ),

    Tarea(
        id="gen_06_dedup_preservando_orden",
        categoria=Categoria.GENERACION,
        prompt=(
            "Escribe `dedup_preservando_orden(items: list) -> list` que "
            "elimine duplicados manteniendo el orden de primera aparición. "
            "Debe correr en O(n) tiempo."
        ),
        descripcion="Dedup O(n) preservando orden",
        verificador=_verificador_con_tests("""
assert dedup_preservando_orden([1, 2, 3, 2, 1, 4]) == [1, 2, 3, 4]
assert dedup_preservando_orden(["a", "b", "a", "c"]) == ["a", "b", "c"]
assert dedup_preservando_orden([]) == []
assert dedup_preservando_orden([1, 1, 1]) == [1]
"""),
    ),

    Tarea(
        id="gen_07_anagrama",
        categoria=Categoria.GENERACION,
        prompt=(
            "Escribe `son_anagramas(a: str, b: str) -> bool` que determine si "
            "dos strings son anagramas, ignorando mayúsculas y espacios."
        ),
        descripcion="Anagramas case-insensitive sin espacios",
        verificador=_verificador_con_tests("""
assert son_anagramas("listen", "silent") is True
assert son_anagramas("Astronomer", "Moon starer") is True
assert son_anagramas("hola", "adios") is False
assert son_anagramas("", "") is True
"""),
    ),

    Tarea(
        id="gen_08_promedio_seguro",
        categoria=Categoria.GENERACION,
        prompt=(
            "Escribe `promedio(nums: list[float]) -> float` que calcule el "
            "promedio. Si la lista está vacía debe lanzar ValueError con un "
            "mensaje claro."
        ),
        descripcion="Promedio con manejo de lista vacía",
        verificador=_verificador_con_tests("""
assert promedio([1.0, 2.0, 3.0]) == 2.0
assert promedio([10.0]) == 10.0
try:
    promedio([])
    raise AssertionError("Debió lanzar ValueError")
except ValueError:
    pass
"""),
    ),
]
