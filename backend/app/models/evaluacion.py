"""Modelo Evaluacion: respuestas de los estudiantes a actividades."""

from __future__ import annotations

import uuid
from typing import TYPE_CHECKING

from sqlalchemy import Float, ForeignKey, String, Text
from sqlalchemy import Uuid as UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base, TimestampMixin

if TYPE_CHECKING:
    from app.models.dataset import DatasetEducativo
    from app.models.usuario import Usuario


class Evaluacion(Base, TimestampMixin):
    """Resultado de una actividad respondida por un estudiante."""

    __tablename__ = "evaluaciones"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    usuario_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("usuarios.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    dataset_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("datasets_educativos.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )

    tipo_actividad: Mapped[str] = mapped_column(String(60), nullable=False)
    respuesta_estudiante: Mapped[str] = mapped_column(Text, nullable=False)
    respuesta_correcta: Mapped[str] = mapped_column(Text, nullable=False)
    puntaje: Mapped[float] = mapped_column(Float, nullable=False, default=0.0)
    retroalimentacion: Mapped[str | None] = mapped_column(Text, nullable=True)

    usuario: Mapped["Usuario"] = relationship(back_populates="evaluaciones")
    dataset: Mapped["DatasetEducativo"] = relationship(back_populates="evaluaciones")

    def __repr__(self) -> str:
        return f"<Evaluacion {self.id} puntaje={self.puntaje}>"
