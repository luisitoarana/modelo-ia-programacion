"""Validador de calidad educativa automatizado.

Implementa una rúbrica COMPUTABLE (alineada con
research/instrumentos_evaluacion.md) que evalúa cada respuesta generada por
una IA antes de incorporarla a la base de conocimiento o al dataset.

Esto es central para la investigación: convierte la validación —antes solo
humana— en un proceso reproducible y medible. La validación humana sigue
existiendo (rol investigador), pero este evaluador actúa como primer filtro
objetivo y como métrica comparable entre proveedores.

No depende de ninguna API externa: usa análisis estático (AST) y heurísticas
locales. Cada dimensión puntúa 0, 1 o 2; el total va de 0 a 12.
"""

from __future__ import annotations

import ast
import re
from dataclasses import dataclass, field

from app.schemas.ai_response import RespuestaIAEducativa


UMBRAL_APROBACION_DEFECTO = 9.0   # sobre 12 (igual que la rúbrica humana)
_RE_BIG_O = re.compile(r"O\s*\(", re.IGNORECASE)


@dataclass(slots=True)
class ResultadoCalidad:
    """Desglose de la evaluación de calidad educativa."""

    puntaje_total: float
    maximo: float
    dimensiones: dict[str, float]
    observaciones: list[str] = field(default_factory=list)
    aprobado: bool = False

    @property
    def porcentaje(self) -> float:
        return round((self.puntaje_total / self.maximo) * 100, 1) if self.maximo else 0.0

    def to_dict(self) -> dict[str, object]:
        return {
            "puntaje_total": self.puntaje_total,
            "maximo": self.maximo,
            "porcentaje": self.porcentaje,
            "aprobado": self.aprobado,
            "dimensiones": self.dimensiones,
            "observaciones": self.observaciones,
        }


class QualityEvaluator:
    """Evalúa la calidad pedagógica de una RespuestaIAEducativa."""

    def __init__(self, umbral_aprobacion: float = UMBRAL_APROBACION_DEFECTO) -> None:
        self.umbral = umbral_aprobacion

    def evaluar(self, respuesta: RespuestaIAEducativa) -> ResultadoCalidad:
        observaciones: list[str] = []
        dim: dict[str, float] = {}

        dim["correccion_codigo"] = self._dim_correccion_codigo(respuesta, observaciones)
        dim["coherencia_explicacion"] = self._dim_coherencia(respuesta, observaciones)
        dim["calidad_explicacion"] = self._dim_calidad_explicacion(respuesta, observaciones)
        dim["conceptos_clave"] = self._dim_conceptos(respuesta, observaciones)
        dim["adecuacion_nivel"] = self._dim_adecuacion_nivel(respuesta, observaciones)
        dim["actividad_evaluativa"] = self._dim_actividad(respuesta, observaciones)

        total = float(sum(dim.values()))
        maximo = float(len(dim) * 2)
        aprobado = total >= self.umbral

        return ResultadoCalidad(
            puntaje_total=total,
            maximo=maximo,
            dimensiones=dim,
            observaciones=observaciones,
            aprobado=aprobado,
        )

    # ------------------------------------------------------------------
    # Dimensiones de la rúbrica
    # ------------------------------------------------------------------

    @staticmethod
    def _dim_correccion_codigo(
        r: RespuestaIAEducativa, obs: list[str]
    ) -> float:
        codigo = (r.codigo or "").strip()
        if not codigo:
            obs.append("El código está vacío.")
            return 0.0
        try:
            ast.parse(codigo)
        except SyntaxError as exc:
            obs.append(f"El código no compila (SyntaxError línea {exc.lineno}).")
            return 0.0
        # 2 si parsea y tiene al menos una definición/estructura sustantiva.
        tiene_estructura = bool(
            re.search(r"\b(def|class|for|while|if|return)\b", codigo)
        )
        if not tiene_estructura:
            obs.append("El código es sintácticamente válido pero trivial.")
            return 1.0
        return 2.0

    @staticmethod
    def _dim_coherencia(r: RespuestaIAEducativa, obs: list[str]) -> float:
        lineas_codigo = [l for l in (r.codigo or "").splitlines() if l.strip()]
        explicadas = r.explicacion_linea_por_linea or []
        if not lineas_codigo:
            return 0.0
        if not explicadas:
            obs.append("No hay explicación línea por línea.")
            return 0.0
        cobertura = len(explicadas) / max(len(lineas_codigo), 1)
        if cobertura >= 0.6:
            return 2.0
        if cobertura >= 0.3:
            obs.append("La explicación línea por línea cubre pocas líneas del código.")
            return 1.0
        obs.append("La cobertura de explicación por línea es muy baja.")
        return 0.0

    @staticmethod
    def _dim_calidad_explicacion(r: RespuestaIAEducativa, obs: list[str]) -> float:
        texto = (r.explicacion_general or "").strip()
        palabras = len(texto.split())
        # Busca señales pedagógicas del "por qué", no solo el "qué".
        explica_porque = bool(
            re.search(r"\b(porque|por qué|permite|sirve para|de modo que|así)\b",
                      texto, re.IGNORECASE)
        )
        if palabras < 12:
            obs.append("La explicación general es demasiado breve.")
            return 0.0
        if palabras >= 30 and explica_porque:
            return 2.0
        if not explica_porque:
            obs.append("La explicación describe el 'qué' pero poco el 'por qué'.")
        return 1.0

    @staticmethod
    def _dim_conceptos(r: RespuestaIAEducativa, obs: list[str]) -> float:
        conceptos = r.conceptos_clave or []
        validos = [
            c for c in conceptos
            if (c.concepto or "").strip() and (c.definicion or "").strip()
        ]
        if len(validos) >= 3:
            return 2.0
        if len(validos) >= 1:
            return 1.0
        obs.append("No se identificaron conceptos clave con definición.")
        return 0.0

    @staticmethod
    def _dim_adecuacion_nivel(r: RespuestaIAEducativa, obs: list[str]) -> float:
        # Heurística por complejidad del código vs. nivel declarado.
        codigo = r.codigo or ""
        usa_oop = bool(re.search(r"\bclass\b", codigo))
        usa_recursion_o_comp = bool(
            re.search(r"\b(lambda|yield)\b", codigo)
            or "[" in codigo and "for" in codigo
        )
        nivel = r.nivel
        if nivel == "basico" and usa_oop:
            obs.append("Nivel 'basico' pero el código usa OOP (posible desajuste).")
            return 1.0
        if nivel == "avanzado" and not (usa_oop or usa_recursion_o_comp):
            obs.append("Nivel 'avanzado' pero el código parece elemental.")
            return 1.0
        return 2.0

    @staticmethod
    def _dim_actividad(r: RespuestaIAEducativa, obs: list[str]) -> float:
        act = r.actividad_evaluativa
        if act is None:
            obs.append("No incluye actividad evaluativa.")
            return 0.0
        if not (act.enunciado or "").strip() or not (act.respuesta_correcta or "").strip():
            obs.append("La actividad evaluativa está incompleta.")
            return 0.0
        if act.tipo == "opcion_multiple" and len(act.opciones or []) < 2:
            obs.append("La actividad de opción múltiple tiene menos de 2 opciones.")
            return 1.0
        if not (act.retroalimentacion_esperada or "").strip():
            return 1.0
        return 2.0


# Complejidad temporal/espacial: dimensión informativa adicional (no penaliza
# el total pero se registra para análisis).
def reporta_complejidad(r: RespuestaIAEducativa) -> bool:
    c = r.analisis_complejidad
    if c is None:
        return False
    return bool(_RE_BIG_O.search(c.temporal or "")) and bool(
        _RE_BIG_O.search(c.espacial or "")
    )
