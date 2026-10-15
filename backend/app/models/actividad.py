"""Modelo Actividad: ejercicios pedagógicos derivados del dataset educativo."""

from __future__ import annotations

import enum
import uuid
from typing import TYPE_CHECKING, Any

from sqlalchemy import Enum as SAEnum, ForeignKey, Integer, Text
from sqlalchemy import JSON as JSONB, Uuid as UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base, TimestampMixin

if TYPE_CHECKING:
    from app.models.dataset import DatasetEducativo


class TipoActividad(str, enum.Enum):
    OPCION_MULTIPLE = "opcion_multiple"
    COMPLETAR_CODIGO = "completar_codigo"
    TRAZA_LOGICA = "traza_logica"
    EXPLICACION_LIBRE = "explicacion_libre"


class Actividad(Base, TimestampMixin):
    """Actividad evaluativa de comprensión algorítmica."""

    __tablename__ = "actividades"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    dataset_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("datasets_educativos.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )

    tipo: Mapped[TipoActividad] = mapped_column(
        SAEnum(TipoActividad, name="tipo_actividad_enum"), nullable=False
    )
    enunciado: Mapped[str] = mapped_column(Text, nullable=False)
    opciones: Mapped[list[str] | None] = mapped_column(JSONB, nullable=True)
    respuesta_correcta: Mapped[str] = mapped_column(Text, nullable=False)
    retroalimentacion_esperada: Mapped[str | None] = mapped_column(Text, nullable=True)
    metadata_pedagogica: Mapped[dict[str, Any] | None] = mapped_column(
        JSONB, nullable=True
    )
    dificultad: Mapped[int] = mapped_column(Integer, nullable=False, default=1)

    dataset: Mapped["DatasetEducativo"] = relationship(back_populates="actividades")

    def __repr__(self) -> str:
        return f"<Actividad {self.id} tipo={self.tipo.value}>"
