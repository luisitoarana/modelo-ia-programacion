"""Currículo educativo estructurado.

Este módulo define el TEMARIO que dirige la generación proactiva de
conocimiento. No es un detalle de UI: es el corazón científico de la
construcción del dataset. Cada `ItemCurriculo` describe un objetivo de
aprendizaje concreto y un "prompt semilla" con el que las APIs (Gemini /
DeepSeek) generan conocimiento educativo, que luego se valida y almacena.

De este modo las APIs se usan como HERRAMIENTA para poblar la base de
conocimiento de forma sistemática y reproducible, no como motor final.
"""

from __future__ import annotations

from dataclasses import dataclass, field


@dataclass(slots=True, frozen=True)
class ItemCurriculo:
    """Una unidad atómica del temario a cubrir."""

    codigo: str                 # identificador estable, p.ej. "BAS-VAR-01"
    nivel: str                  # basico | intermedio | avanzado
    tema: str                   # variables | bucles | funciones | oop | algoritmos | ...
    titulo: str
    objetivo_aprendizaje: str   # qué debe comprender el estudiante
    prompt_semilla: str         # instrucción para que el LLM genere el material
    conceptos_esperados: list[str] = field(default_factory=list)


# ---------------------------------------------------------------------------
# Temario base (ampliable). Alineado con knowledge_base/ y la propuesta.
# ---------------------------------------------------------------------------

CURRICULO: tuple[ItemCurriculo, ...] = (
    # ---------------- BÁSICO ----------------
    ItemCurriculo(
        codigo="BAS-VAR-01",
        nivel="basico",
        tema="variables",
        titulo="Variables y asignación",
        objetivo_aprendizaje=(
            "Comprender que una variable es una referencia a un objeto en memoria "
            "y cómo la reasignación cambia a qué objeto apunta."
        ),
        prompt_semilla=(
            "Explica qué es una variable en Python con un ejemplo mínimo que "
            "declare tres variables de distinto tipo y muestre su uso."
        ),
        conceptos_esperados=["variable", "asignación", "referencia", "tipo dinámico"],
    ),
    ItemCurriculo(
        codigo="BAS-TIP-01",
        nivel="basico",
        tema="variables",
        titulo="Tipos de datos primitivos",
        objetivo_aprendizaje=(
            "Distinguir int, float, str y bool, y anticipar operaciones válidas "
            "según el tipo."
        ),
        prompt_semilla=(
            "Genera un programa corto que use int, float, str y bool, y explica "
            "qué operaciones son válidas con cada tipo."
        ),
        conceptos_esperados=["int", "float", "str", "bool", "casting"],
    ),
    ItemCurriculo(
        codigo="BAS-CON-01",
        nivel="basico",
        tema="bucles",
        titulo="Condicionales if/elif/else",
        objetivo_aprendizaje=(
            "Tomar decisiones lógicas con condicionales y comprender la evaluación "
            "de verdad (truthiness)."
        ),
        prompt_semilla=(
            "Genera un programa que clasifique una nota numérica en aprobado, "
            "recuperación o desaprobado usando if/elif/else, y explica la lógica."
        ),
        conceptos_esperados=["condicional", "comparación", "truthiness", "rama"],
    ),
    ItemCurriculo(
        codigo="BAS-BUC-01",
        nivel="basico",
        tema="bucles",
        titulo="Bucle for y acumulación",
        objetivo_aprendizaje=(
            "Diferenciar iteración de acumulación calculando un promedio con un "
            "bucle for."
        ),
        prompt_semilla=(
            "Genera una función que calcule el promedio de una lista de notas con "
            "un bucle for y explica la diferencia entre iterar y acumular."
        ),
        conceptos_esperados=["for", "iteración", "acumulador", "promedio"],
    ),
    ItemCurriculo(
        codigo="BAS-BUC-02",
        nivel="basico",
        tema="bucles",
        titulo="Bucle while y condición de parada",
        objetivo_aprendizaje=(
            "Comprender la condición de parada y el riesgo de bucles infinitos."
        ),
        prompt_semilla=(
            "Genera un ejemplo con while que cuente regresivamente desde 5 y "
            "explica la condición de parada y cómo evitar un bucle infinito."
        ),
        conceptos_esperados=["while", "condición de parada", "bucle infinito"],
    ),
    # ---------------- INTERMEDIO hola  ----------------
    ItemCurriculo(
        codigo="INT-FUN-01",
        nivel="intermedio",
        tema="funciones",
        titulo="Funciones y parámetros",
        objetivo_aprendizaje=(
            "Definir funciones con parámetros, valores por defecto y retorno, y "
            "comprender el concepto de función pura."
        ),
        prompt_semilla=(
            "Genera una función que calcule el área de un triángulo con parámetros "
            "y valor de retorno, y explica qué la haría una función pura."
        ),
        conceptos_esperados=["función", "parámetro", "return", "función pura"],
    ),
    ItemCurriculo(
        codigo="INT-LIS-01",
        nivel="intermedio",
        tema="estructuras",
        titulo="Listas y comprehensions",
        objetivo_aprendizaje=(
            "Manipular listas y expresar transformaciones con list comprehensions."
        ),
        prompt_semilla=(
            "Genera un ejemplo que filtre las notas aprobatorias de una lista usando "
            "una list comprehension y explica su ventaja frente a un for clásico."
        ),
        conceptos_esperados=["lista", "comprehension", "filtro", "mutabilidad"],
    ),
    ItemCurriculo(
        codigo="INT-DIC-01",
        nivel="intermedio",
        tema="estructuras",
        titulo="Diccionarios",
        objetivo_aprendizaje=(
            "Modelar datos clave-valor con diccionarios y recorrerlos."
        ),
        prompt_semilla=(
            "Genera un programa que cuente la frecuencia de palabras en un texto "
            "usando un diccionario y explica el acceso O(1) promedio."
        ),
        conceptos_esperados=["diccionario", "clave", "hashing", "items"],
    ),
    ItemCurriculo(
        codigo="INT-EXC-01",
        nivel="intermedio",
        tema="excepciones",
        titulo="Manejo de excepciones",
        objetivo_aprendizaje=(
            "Controlar errores con try/except y comprender por qué no silenciarlos."
        ),
        prompt_semilla=(
            "Genera un ejemplo que convierta entrada de texto a entero manejando "
            "ValueError con try/except y explica las buenas prácticas."
        ),
        conceptos_esperados=["excepción", "try/except", "ValueError", "robustez"],
    ),
    # ---------------- OOP ----------------
    ItemCurriculo(
        codigo="OOP-CLS-01",
        nivel="intermedio",
        tema="oop",
        titulo="Clases y objetos",
        objetivo_aprendizaje=(
            "Separar estado y comportamiento definiendo una clase con atributos y "
            "métodos."
        ),
        prompt_semilla=(
            "Genera una clase Estudiante con atributos y un método, instánciala y "
            "explica la diferencia entre clase y objeto."
        ),
        conceptos_esperados=["clase", "objeto", "atributo", "método", "constructor"],
    ),
    ItemCurriculo(
        codigo="OOP-HER-01",
        nivel="avanzado",
        tema="oop",
        titulo="Herencia y polimorfismo",
        objetivo_aprendizaje=(
            "Reutilizar comportamiento con herencia y aplicar polimorfismo."
        ),
        prompt_semilla=(
            "Genera un ejemplo con una clase padre Persona y una hija Estudiante que "
            "sobreescriba un método, y explica el polimorfismo con super()."
        ),
        conceptos_esperados=["herencia", "clase padre", "clase hija", "polimorfismo", "super"],
    ),
    # ---------------- ALGORITMOS ----------------
    ItemCurriculo(
        codigo="ALG-BUS-01",
        nivel="intermedio",
        tema="algoritmos",
        titulo="Búsqueda lineal vs binaria",
        objetivo_aprendizaje=(
            "Comparar búsqueda lineal O(n) y binaria O(log n) y su condición de uso."
        ),
        prompt_semilla=(
            "Genera la implementación de búsqueda binaria y explica por qué requiere "
            "una lista ordenada y cómo divide el problema a la mitad."
        ),
        conceptos_esperados=["búsqueda lineal", "búsqueda binaria", "O(log n)", "orden"],
    ),
    ItemCurriculo(
        codigo="ALG-ORD-01",
        nivel="intermedio",
        tema="algoritmos",
        titulo="Ordenamiento burbuja",
        objetivo_aprendizaje=(
            "Comprender bucles anidados y una mejora con early-exit en burbuja."
        ),
        prompt_semilla=(
            "Genera el ordenamiento burbuja con la optimización de salida temprana y "
            "explica su complejidad en el mejor y peor caso."
        ),
        conceptos_esperados=["ordenamiento", "burbuja", "bucle anidado", "complejidad"],
    ),
    ItemCurriculo(
        codigo="ALG-REC-01",
        nivel="avanzado",
        tema="algoritmos",
        titulo="Recursividad",
        objetivo_aprendizaje=(
            "Identificar caso base y caso recursivo, y el rol de la pila de llamadas."
        ),
        prompt_semilla=(
            "Genera una función recursiva para el factorial y explica el caso base, "
            "el caso recursivo y la pila de llamadas."
        ),
        conceptos_esperados=["recursividad", "caso base", "caso recursivo", "pila"],
    ),
)


def items_por_nivel(nivel: str) -> list[ItemCurriculo]:
    return [i for i in CURRICULO if i.nivel == nivel]


def items_por_tema(tema: str) -> list[ItemCurriculo]:
    return [i for i in CURRICULO if i.tema == tema]


def obtener_item(codigo: str) -> ItemCurriculo | None:
    for i in CURRICULO:
        if i.codigo == codigo:
            return i
    return None


def total_items() -> int:
    return len(CURRICULO)
