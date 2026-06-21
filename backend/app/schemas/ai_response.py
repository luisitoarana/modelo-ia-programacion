"""Schema estricto para las respuestas educativas de los LLMs.

Esta es la forma canónica que TODA respuesta de Gemini, DeepSeek o
modelo local debe cumplir. El backend valida con este schema y, si falla,
dispara el ciclo de auto-curación.
"""

from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator


NivelLiteral = Literal["basico", "intermedio", "avanzado"]
TemaLiteral = Literal[
    "variables", "bucles", "funciones", "oop", "algoritmos",
    "estructuras", "excepciones", "archivos", "otro",
]
TipoConceptoLiteral = Literal["sintactico", "logico", "algoritmico", "pedagogico"]
TipoActividadLiteral = Literal[
    "opcion_multiple", "completar_codigo", "traza_logica", "explicacion_libre"
]
FuenteLiteral = Literal["gemini", "deepseek-r1", "modelo-local"]


class ExplicacionLinea(BaseModel):
    """Explicación pedagógica de una línea de código."""

    model_config = ConfigDict(extra="forbid")

    linea_numero: int = Field(ge=1, description="Número de línea (base 1)")
    codigo_linea: str = Field(min_length=1, description="Contenido exacto de la línea")
    semantica: str = Field(min_length=1, description="Qué hace y por qué")
    impacto_en_memoria: str = Field(
        default="",
        description="Cómo afecta variables, referencias o estructuras en memoria",
    )


class ConceptoClave(BaseModel):
    """Concepto de programación identificado en la respuesta."""

    model_config = ConfigDict(extra="forbid")

    concepto: str = Field(min_length=1)
    definicion: str = Field(min_length=1)
    tipo: TipoConceptoLiteral


class AnalisisComplejidad(BaseModel):
    """Análisis de complejidad temporal y espacial."""

    model_config = ConfigDict(extra="forbid")

    temporal: str = Field(description='Notación Big-O temporal, p.ej. "O(n)"')
    espacial: str = Field(description='Notación Big-O espacial, p.ej. "O(1)"')
    justificacion: str = Field(min_length=1)


class ActividadEvaluativa(BaseModel):
    """Actividad pedagógica de comprensión algorítmica."""

    model_config = ConfigDict(extra="forbid")

    tipo: TipoActividadLiteral
    enunciado: str = Field(min_length=1)
    opciones: list[str] = Field(default_factory=list)
    respuesta_correcta: str = Field(min_length=1)
    retroalimentacion_esperada: str = Field(min_length=1)


class MetadataRespuestaIA(BaseModel):
    """Metadata operativa para trazabilidad y reportes."""

    model_config = ConfigDict(extra="allow")

    tokens_totales: int = Field(default=0, ge=0)
    latencia_segundos: float = Field(default=0.0, ge=0.0)


class RespuestaIAEducativa(BaseModel):
    """Respuesta educativa estructurada que retorna cualquier proveedor IA.

    Esta estructura es contractual: si el LLM no la respeta, el orquestador
    reintenta con instrucciones de corrección hasta 3 veces.
    """

    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    nivel: NivelLiteral
    tema: TemaLiteral
    pregunta: str = Field(min_length=1)
    codigo: str = Field(min_length=1)
    explicacion_general: str = Field(min_length=1)
    explicacion_linea_por_linea: list[ExplicacionLinea] = Field(default_factory=list)
    conceptos_clave: list[ConceptoClave] = Field(default_factory=list)
    analisis_complejidad: AnalisisComplejidad | None = None
    actividad_evaluativa: ActividadEvaluativa | None = None
    fuente_ia: FuenteLiteral
    metadata: MetadataRespuestaIA = Field(default_factory=MetadataRespuestaIA)

    @field_validator("codigo")
    @classmethod
    def codigo_sin_markdown(cls, v: str) -> str:
        """Garantiza que el código no venga envuelto en bloques markdown."""
        limpio = v.strip()
        if limpio.startswith("```"):
            # remover primera línea con fences y última si está
            lineas = limpio.splitlines()
            if lineas and lineas[0].startswith("```"):
                lineas = lineas[1:]
            if lineas and lineas[-1].strip() == "```":
                lineas = lineas[:-1]
            limpio = "\n".join(lineas).strip()
        return limpio
