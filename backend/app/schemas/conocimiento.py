"""Schemas para currículo, generación y base de conocimiento."""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field


class ItemCurriculoOut(BaseModel):
    codigo: str
    nivel: str
    tema: str
    titulo: str
    objetivo_aprendizaje: str
    prompt_semilla: str
    conceptos_esperados: list[str]


class SolicitudGeneracionCurriculo(BaseModel):
    """Genera conocimiento para (un subconjunto de) el currículo."""

    proveedor: Literal["gemini", "deepseek"] = "gemini"
    nivel: Literal["basico", "intermedio", "avanzado"] | None = None
    limite: int | None = Field(default=None, ge=1, le=100)
    reemplazar: bool = False
    autovalidar_si_aprueba: bool = False


class ResultadoItemOut(BaseModel):
    codigo_curriculo: str
    titulo: str
    proveedor: str
    exito: bool
    puntaje_calidad: float = 0.0
    aprobado: bool = False
    almacenado: bool = False
    unidad_id: str | None = None
    error: str | None = None


class ResumenGeneracionOut(BaseModel):
    total_items: int
    generados: int
    aprobados: int
    almacenados: int
    fallidos: int
    detalles: list[ResultadoItemOut]


class UnidadConocimientoLeer(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    codigo_curriculo: str | None
    nivel: str
    tema: str
    objetivo_aprendizaje: str | None
    pregunta_canonica: str
    codigo: str
    explicacion_general: str
    respuesta_json: dict[str, Any]
    origen: str
    estado: str
    puntaje_calidad: float
    dimensiones_calidad: dict[str, Any] | None
    veces_reutilizada: int
    validado_por: str | None
    fecha_creacion: datetime


class ValidacionUnidad(BaseModel):
    aprobar: bool
    validado_por: str = Field(min_length=2, max_length=180)
    observaciones: str | None = Field(default=None, max_length=2000)


class EstadisticasConocimiento(BaseModel):
    total_unidades: int
    validadas: int
    candidatas: int
    rechazadas: int
    reutilizaciones_totales: int
    consultas_totales: int
    respondidas_desde_base: int
    respondidas_por_api: int
    tasa_independencia_api: float  # % de respuestas servidas sin API
    cobertura_curriculo: float     # % de items del currículo con unidad validada
