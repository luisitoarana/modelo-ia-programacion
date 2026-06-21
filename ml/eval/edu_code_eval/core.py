"""Núcleo de EduCodeEval — modelos de datos, runner, sistema de scoring.

La filosofía: cada tarea tiene una rúbrica explícita y verificable. El
score final es la combinación de:

    score_objetivo  (tests / AST / regex)   peso configurable
    score_subjetivo (reward models, juez)   peso configurable

por defecto 50/50.
"""

from __future__ import annotations

import ast
import json
import re
import subprocess
import sys
import tempfile
from dataclasses import dataclass, field, asdict
from enum import Enum
from pathlib import Path
from typing import Any, Callable


# ════════════════════════════════════════════════════════════════════
# Categorías del benchmark
# ════════════════════════════════════════════════════════════════════

class Categoria(str, Enum):
    """Las cinco dimensiones del benchmark."""

    GENERACION = "generacion"           # Resolver problema correctamente
    EXPLICACION = "explicacion"         # Explicación pedagógica
    SEGURIDAD = "seguridad"             # Detectar / corregir vulnerabilidades
    REFACTORIZACION = "refactorizacion" # Detectar antipatrones, mejorar código
    ENSENANZA = "ensenanza"             # Adaptar al nivel del estudiante


# Pesos por defecto del score global. Los puedes ajustar al perfil del
# modelo. Para un modelo educativo, la enseñanza pesa lo mismo que el
# resto, no menos.
PESOS_DEFAULT: dict[Categoria, float] = {
    Categoria.GENERACION:      1.0,
    Categoria.EXPLICACION:     1.2,
    Categoria.SEGURIDAD:       1.3,
    Categoria.REFACTORIZACION: 1.0,
    Categoria.ENSENANZA:       1.5,
}


# ════════════════════════════════════════════════════════════════════
# Verificadores objetivos (heurísticas verificables sin LLM)
# ════════════════════════════════════════════════════════════════════

def _codigo_compila(codigo: str) -> bool:
    """¿El código compila con ast.parse?"""
    try:
        ast.parse(codigo)
        return True
    except SyntaxError:
        return False


def _codigo_ejecuta_sin_excepcion(codigo: str, timeout: int = 5) -> bool:
    """Ejecuta el código en subprocess aislado. True si exit 0."""
    try:
        with tempfile.NamedTemporaryFile(
            mode="w", suffix=".py", delete=False, encoding="utf-8"
        ) as f:
            f.write(codigo)
            ruta = f.name
        r = subprocess.run(
            [sys.executable, ruta],
            capture_output=True, timeout=timeout,
        )
        return r.returncode == 0
    except (subprocess.TimeoutExpired, Exception):
        return False
    finally:
        try:
            Path(ruta).unlink(missing_ok=True)  # type: ignore[name-defined]
        except Exception:
            pass


def _pasa_unit_tests(codigo: str, tests: str, timeout: int = 10) -> bool:
    """Ejecuta `codigo` + `tests` juntos. True si los tests pasan."""
    bloque = codigo + "\n\n" + tests
    return _codigo_ejecuta_sin_excepcion(bloque, timeout)


def _menciona_vulnerabilidad(respuesta: str, nombre_vuln: str) -> bool:
    """¿La respuesta menciona la vulnerabilidad por su nombre?"""
    patrones = [
        nombre_vuln.lower(),
        nombre_vuln.replace(" ", "_").lower(),
        nombre_vuln.replace(" ", "-").lower(),
    ]
    return any(p in respuesta.lower() for p in patrones)


def _propone_codigo_seguro(respuesta: str, patrones_seguros: list[str]) -> bool:
    """¿La respuesta incluye al menos un patrón de código seguro?

    Ej: para SQL injection, espera ver `cursor.execute("... %s", (...))`
    o `?` parametrizado o sqlalchemy `.where(col == val)`.
    """
    return any(re.search(p, respuesta, re.IGNORECASE) for p in patrones_seguros)


def _vocabulario_calibrado(texto: str, nivel: str) -> bool:
    """Heurística suave para detectar si el texto está calibrado al nivel.

    nivel='nino': sin jerga técnica.
    nivel='profesional': con vocabulario técnico denso.
    """
    jerga = {
        "variable", "función", "funcion", "método", "metodo", "objeto",
        "iterador", "memoria", "bytecode", "compilador", "polimorf",
    }
    palabras_total = len(texto.split())
    if palabras_total == 0:
        return False
    encontradas = sum(1 for j in jerga if j in texto.lower())
    densidad = encontradas / max(palabras_total, 1)
    if nivel == "nino":
        return densidad < 0.01      # Casi cero jerga.
    if nivel == "profesional":
        return densidad > 0.02      # Densidad alta.
    return True                     # Niveles intermedios: pasa libre.


# ════════════════════════════════════════════════════════════════════
# Modelos de datos
# ════════════════════════════════════════════════════════════════════

@dataclass(slots=True)
class Tarea:
    """Una tarea del benchmark.

    Campos:
        id              — Identificador único.
        categoria       — Una de Categoria.
        prompt          — Lo que se le pasa al modelo.
        descripcion     — Para el reporte humano.
        verificador     — Función (respuesta: str) -> dict[str, Any]
                          con métricas objetivas. La función vive en
                          `tareas/<categoria>.py`.
        ejemplo_referencia — Respuesta humana ideal (opcional, para juez).
        contexto_extra  — Material que el verificador necesita.
        peso_objetivo   — 0..1, cuánto pesa la parte objetiva en el score
                          final de la tarea. Default 0.5.
    """
    id: str
    categoria: Categoria
    prompt: str
    descripcion: str
    verificador: Callable[[str], dict[str, Any]]
    ejemplo_referencia: str | None = None
    contexto_extra: dict[str, Any] = field(default_factory=dict)
    peso_objetivo: float = 0.5


@dataclass(slots=True)
class ResultadoTarea:
    """Resultado de evaluar UNA tarea."""
    tarea_id: str
    categoria: Categoria
    respuesta_modelo: str
    score_objetivo: float        # 0..100 según el verificador
    score_subjetivo: float       # 0..100 según juez/reward models (opcional)
    score_final: float           # combinación ponderada
    detalle: dict[str, Any]
    aprobada: bool               # score_final >= 60

    def to_dict(self) -> dict:
        d = asdict(self)
        d["categoria"] = self.categoria.value
        return d


@dataclass(slots=True)
class ResultadoBenchmark:
    """Resultado agregado de toda la corrida."""
    nombre_modelo: str
    n_tareas_total: int
    n_tareas_aprobadas: int
    score_por_categoria: dict[str, float]    # categoría → 0..100
    score_global: float                      # 0..100, ponderado
    tareas: list[ResultadoTarea]

    def to_dict(self) -> dict:
        return {
            "nombre_modelo": self.nombre_modelo,
            "n_tareas_total": self.n_tareas_total,
            "n_tareas_aprobadas": self.n_tareas_aprobadas,
            "porcentaje_aprobacion": round(
                100 * self.n_tareas_aprobadas / max(1, self.n_tareas_total), 2
            ),
            "score_por_categoria": {
                k: round(v, 2) for k, v in self.score_por_categoria.items()
            },
            "score_global": round(self.score_global, 2),
            "tareas": [t.to_dict() for t in self.tareas],
        }


# ════════════════════════════════════════════════════════════════════
# Runner del benchmark
# ════════════════════════════════════════════════════════════════════

class EduCodeEval:
    """Ejecuta el benchmark sobre un modelo dado.

    El "modelo" es cualquier callable que recibe un prompt (str) y devuelve
    una respuesta (str). Esto permite evaluar tanto LLMs locales como APIs.

    Uso típico:
        modelo = lambda prompt: mi_llm.generar(prompt)
        bench = EduCodeEval(tareas=cargar_tareas())
        resultado = bench.ejecutar(modelo, nombre_modelo="modelo_C_v1")
        print(json.dumps(resultado.to_dict(), indent=2))
    """

    def __init__(
        self,
        tareas: list[Tarea],
        *,
        pesos_categoria: dict[Categoria, float] | None = None,
        juez_subjetivo: Callable[[Tarea, str], float] | None = None,
    ):
        self.tareas = tareas
        self.pesos = pesos_categoria or PESOS_DEFAULT
        self.juez = juez_subjetivo  # callable opcional para score subjetivo

    def ejecutar(
        self,
        modelo: Callable[[str], str],
        *,
        nombre_modelo: str = "modelo",
    ) -> ResultadoBenchmark:
        resultados: list[ResultadoTarea] = []
        for tarea in self.tareas:
            respuesta = modelo(tarea.prompt)
            r = self._evaluar_tarea(tarea, respuesta)
            resultados.append(r)
            print(f"  [{r.tarea_id:<24}] {r.categoria.value:<15} "
                  f"obj={r.score_objetivo:5.1f}  subj={r.score_subjetivo:5.1f}  "
                  f"final={r.score_final:5.1f}  {'OK' if r.aprobada else 'FAIL'}",
                  flush=True)

        # Agregar por categoría
        por_cat: dict[str, list[float]] = {}
        for r in resultados:
            por_cat.setdefault(r.categoria.value, []).append(r.score_final)
        score_por_categoria = {
            cat: sum(scores) / len(scores) for cat, scores in por_cat.items()
        }

        # Score global ponderado
        suma_pond = 0.0
        suma_pesos = 0.0
        for cat_str, score in score_por_categoria.items():
            peso = self.pesos.get(Categoria(cat_str), 1.0)
            suma_pond += score * peso
            suma_pesos += peso
        score_global = suma_pond / suma_pesos if suma_pesos > 0 else 0.0

        return ResultadoBenchmark(
            nombre_modelo=nombre_modelo,
            n_tareas_total=len(resultados),
            n_tareas_aprobadas=sum(1 for r in resultados if r.aprobada),
            score_por_categoria=score_por_categoria,
            score_global=score_global,
            tareas=resultados,
        )

    def _evaluar_tarea(self, tarea: Tarea, respuesta: str) -> ResultadoTarea:
        # 1. Score objetivo: el verificador devuelve detalle + un float 0..100
        detalle = tarea.verificador(respuesta)
        score_obj = float(detalle.get("score", 0.0))

        # 2. Score subjetivo: opcional, vía juez LLM o reward models
        if self.juez is not None:
            try:
                score_subj = float(self.juez(tarea, respuesta))
            except Exception as exc:
                score_subj = score_obj  # fallback neutro
                detalle["error_juez"] = str(exc)[:200]
        else:
            score_subj = score_obj  # sin juez = score subjetivo = objetivo

        # 3. Score final ponderado
        po = max(0.0, min(1.0, tarea.peso_objetivo))
        score_final = po * score_obj + (1 - po) * score_subj

        return ResultadoTarea(
            tarea_id=tarea.id,
            categoria=tarea.categoria,
            respuesta_modelo=respuesta[:4000],   # truncar para no hinchar disk
            score_objetivo=score_obj,
            score_subjetivo=score_subj,
            score_final=score_final,
            detalle=detalle,
            aprobada=score_final >= 60.0,
        )


# ════════════════════════════════════════════════════════════════════
# Loader de tareas
# ════════════════════════════════════════════════════════════════════

def cargar_tareas() -> list[Tarea]:
    """Carga TODAS las tareas del benchmark.

    Importa los módulos `tareas/<categoria>.py` y junta sus listas.
    Cada módulo expone `TAREAS: list[Tarea]`.
    """
    from .tareas import generacion, explicacion, seguridad, refactorizacion, ensenanza
    out: list[Tarea] = []
    out.extend(generacion.TAREAS)
    out.extend(explicacion.TAREAS)
    out.extend(seguridad.TAREAS)
    out.extend(refactorizacion.TAREAS)
    out.extend(ensenanza.TAREAS)
    return out


# Helpers compartidos para que los verificadores los importen
__all__ = [
    "Tarea", "Categoria", "EduCodeEval",
    "ResultadoTarea", "ResultadoBenchmark", "cargar_tareas",
    "_codigo_compila", "_codigo_ejecuta_sin_excepcion",
    "_pasa_unit_tests", "_menciona_vulnerabilidad",
    "_propone_codigo_seguro", "_vocabulario_calibrado",
]
