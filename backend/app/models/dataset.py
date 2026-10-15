"""Modelo DatasetEducativo: registros pedagógicos para análisis y fine-tuning."""

from __future__ import annotations

import enum
import uuid
from typing import TYPE_CHECKING, Any

from sqlalchemy import Boolean, Enum as SAEnum, ForeignKey, String, Text
from sqlalchemy import JSON as JSONB, Uuid as UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base, TimestampMixin
from app.models.consulta import FuenteIA

if TYPE_CHECKING:
    from app.models.actividad import Actividad
    from app.models.consulta import Consulta
    from app.models.evaluacion import Evaluacion
    from app.models.usuario import Usuario


class NivelEducativo(str, enum.Enum):
    BASICO = "basico"
    INTERMEDIO = "intermedio"
    AVANZADO = "avanzado"


class TemaProgramacion(str, enum.Enum):
    VARIABLES = "variables"
    BUCLES = "bucles"
    FUNCIONES = "funciones"
    OOP = "oop"
    ALGORITMOS = "algoritmos"
    ESTRUCTURAS = "estructuras"
    EXCEPCIONES = "excepciones"
    ARCHIVOS = "archivos"
    OTRO = "otro"


class DatasetEducativo(Base, TimestampMixin):
    """Registro educativo estructurado generado a partir de cada consulta IA.

    Sirve simultáneamente como historial pedagógico para el estudiante y
    como insumo para análisis académico, evaluación y fine-tuning futuro.
    """

    __tablename__ = "datasets_educativos"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    usuario_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("usuarios.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    consulta_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("consultas.id", ondelete="CASCADE"),
        nullable=False,
        unique=True,
        index=True,
    )

    nivel: Mapped[NivelEducativo] = mapped_column(
        SAEnum(NivelEducativo, name="nivel_educativo_enum"),
        nullable=False,
        index=True,
    )
    tema: Mapped[TemaProgramacion] = mapped_column(
        SAEnum(TemaProgramacion, name="tema_programacion_enum"),
        nullable=False,
        index=True,
    )

    pregunta: Mapped[str] = mapped_column(Text, nullable=False)
    codigo: Mapped[str] = mapped_column(Text, nullable=False)
    explicacion_general: Mapped[str] = mapped_column(Text, nullable=False)

    respuesta_json: Mapped[dict[str, Any]] = mapped_column(JSONB, nullable=False)
    conceptos_json: Mapped[dict[str, Any] | None] = mapped_column(JSONB, nullable=True)
    actividad_json: Mapped[dict[str, Any] | None] = mapped_column(JSONB, nullable=True)
    complejidad_json: Mapped[dict[str, Any] | None] = mapped_column(JSONB, nullable=True)
    explicacion_linea_json: Mapped[list[dict[str, Any]] | None] = mapped_column(
        JSONB, nullable=True
    )

    fuente_ia: Mapped[FuenteIA] = mapped_column(
        SAEnum(FuenteIA, name="fuente_ia_dataset_enum"), nullable=False
    )

    validado: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    validado_por: Mapped[str | None] = mapped_column(String(180), nullable=True)
    observaciones_validacion: Mapped[str | None] = mapped_column(Text, nullable=True)

    exportado_para_finetuning: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False
    )

    usuario: Mapped["Usuario"] = relationship(back_populates="datasets")
    consulta: Mapped["Consulta"] = relationship(back_populates="dataset")
    actividades: Mapped[list["Actividad"]] = relationship(
        back_populates="dataset", cascade="all, delete-orphan"
    )
    evaluaciones: Mapped[list["Evaluacion"]] = relationship(
        back_populates="dataset", cascade="all, delete-orphan"
    )

    def __repr__(self) -> str:
        return f"<DatasetEducativo {self.id} {self.nivel.value}/{self.tema.value}>"
