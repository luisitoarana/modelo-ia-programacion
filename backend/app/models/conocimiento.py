"""Modelo UnidadConocimiento: la base de conocimiento consultable.

Cada fila es una unidad educativa validada (pregunta canónica + respuesta
pedagógica estructurada) que el sistema puede REUTILIZAR para responder sin
volver a llamar a una API externa. Es el activo que permite que el sistema
sea cada vez MENOS dependiente de Gemini/DeepSeek conforme crece.

Diferencia con DatasetEducativo:
- DatasetEducativo = registro histórico de CADA interacción (trazabilidad).
- UnidadConocimiento = conocimiento curado, deduplicado y reutilizable
  (el cerebro del sistema, indexado para recuperación).
"""

from __future__ import annotations

import enum
import uuid
from typing import Any

from sqlalchemy import (
    Boolean,
    Enum as SAEnum,
    Float,
    Integer,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy import JSON as JSONB, Uuid as UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base, TimestampMixin
from app.models.dataset import NivelEducativo, TemaProgramacion


class OrigenConocimiento(str, enum.Enum):
    """De dónde proviene la unidad de conocimiento."""

    GENERADO_GEMINI = "generado_gemini"
    GENERADO_DEEPSEEK = "generado_deepseek"
    CURADO_HUMANO = "curado_humano"
    MODELO_LOCAL = "modelo_local"


class EstadoConocimiento(str, enum.Enum):
    """Ciclo de vida de la unidad dentro de la base de conocimiento."""

    CANDIDATO = "candidato"          # generado, pendiente de validación
    VALIDADO = "validado"            # apto para reutilización y fine-tuning
    RECHAZADO = "rechazado"          # no cumple calidad mínima


class UnidadConocimiento(Base, TimestampMixin):
    """Unidad de conocimiento educativo curada y reutilizable."""

    __tablename__ = "unidades_conocimiento"
    __table_args__ = (
        UniqueConstraint("codigo_curriculo", "origen", name="uq_unidad_curriculo_origen"),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )

    # Vínculo opcional con el temario que la originó (None si vino de un
    # estudiante de forma reactiva).
    codigo_curriculo: Mapped[str | None] = mapped_column(
        String(40), nullable=True, index=True
    )

    nivel: Mapped[NivelEducativo] = mapped_column(
        SAEnum(NivelEducativo, name="nivel_conocimiento_enum"),
        nullable=False,
        index=True,
    )
    tema: Mapped[TemaProgramacion] = mapped_column(
        SAEnum(TemaProgramacion, name="tema_conocimiento_enum"),
        nullable=False,
        index=True,
    )

    objetivo_aprendizaje: Mapped[str | None] = mapped_column(Text, nullable=True)
    pregunta_canonica: Mapped[str] = mapped_column(Text, nullable=False)
    codigo: Mapped[str] = mapped_column(Text, nullable=False)
    explicacion_general: Mapped[str] = mapped_column(Text, nullable=False)

    # Respuesta pedagógica completa (contrato RespuestaIAEducativa serializado).
    respuesta_json: Mapped[dict[str, Any]] = mapped_column(JSONB, nullable=False)

    # --- Recuperación (retrieval local, sin API) ---
    texto_busqueda: Mapped[str] = mapped_column(Text, nullable=False, default="")
    keywords: Mapped[str] = mapped_column(Text, nullable=False, default="")

    # --- Procedencia y calidad ---
    origen: Mapped[OrigenConocimiento] = mapped_column(
        SAEnum(OrigenConocimiento, name="origen_conocimiento_enum"), nullable=False
    )
    estado: Mapped[EstadoConocimiento] = mapped_column(
        SAEnum(EstadoConocimiento, name="estado_conocimiento_enum"),
        nullable=False,
        default=EstadoConocimiento.CANDIDATO,
        index=True,
    )
    puntaje_calidad: Mapped[float] = mapped_column(Float, nullable=False, default=0.0)
    dimensiones_calidad: Mapped[dict[str, Any] | None] = mapped_column(
        JSONB, nullable=True
    )

    # --- Validación humana ---
    validado_por: Mapped[str | None] = mapped_column(String(180), nullable=True)
    observaciones_validacion: Mapped[str | None] = mapped_column(Text, nullable=True)

    # --- Métricas de reutilización (evidencia de menor dependencia de APIs) ---
    veces_reutilizada: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    exportado_para_finetuning: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False
    )

    def __repr__(self) -> str:
        return (
            f"<UnidadConocimiento {self.id} {self.nivel.value}/{self.tema.value} "
            f"calidad={self.puntaje_calidad} estado={self.estado.value}>"
        )
