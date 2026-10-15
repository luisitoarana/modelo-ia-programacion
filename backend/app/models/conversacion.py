"""Modelos de conversación tipo chat (hilos + mensajes).

Soportan la experiencia conversacional de la web (estilo asistente IA):
varias conversaciones por usuario, cada una con su historial de mensajes.
"""

from __future__ import annotations

import enum
import uuid
from typing import TYPE_CHECKING, Any

from sqlalchemy import Boolean, Enum as SAEnum, Float, ForeignKey, Integer, String, Text
from sqlalchemy import JSON as JSONB, Uuid as UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.dialects.mysql import MEDIUMTEXT

from app.database import Base, TimestampMixin

if TYPE_CHECKING:
    from app.models.usuario import Usuario


class RolMensaje(str, enum.Enum):
    USUARIO = "usuario"
    ASISTENTE = "asistente"


class Conversacion(Base, TimestampMixin):
    """Un hilo de chat del usuario."""

    __tablename__ = "conversaciones"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    usuario_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("usuarios.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    titulo: Mapped[str] = mapped_column(String(160), nullable=False, default="Nueva conversación")
    proyecto: Mapped[str | None] = mapped_column(String(120), nullable=True)
    archivada: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)

    usuario: Mapped["Usuario"] = relationship()
    mensajes: Mapped[list["Mensaje"]] = relationship(
        back_populates="conversacion",
        cascade="all, delete-orphan",
        order_by="Mensaje.fecha_creacion",
    )

    def __repr__(self) -> str:
        return f"<Conversacion {self.id} '{self.titulo}'>"


class Mensaje(Base, TimestampMixin):
    """Un mensaje dentro de una conversación."""

    __tablename__ = "mensajes"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    conversacion_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("conversaciones.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    rol: Mapped[RolMensaje] = mapped_column(
        SAEnum(RolMensaje, name="rol_mensaje_enum"), nullable=False
    )
    contenido: Mapped[str] = mapped_column(Text().with_variant(MEDIUMTEXT(), "mysql"), nullable=False)

    # Trazabilidad de la respuesta del asistente.
    origen_respuesta: Mapped[str | None] = mapped_column(String(40), nullable=True)
    tokens_totales: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    latencia_segundos: Mapped[float] = mapped_column(Float, nullable=False, default=0.0)
    metadata_json: Mapped[dict[str, Any] | None] = mapped_column(JSONB, nullable=True)

    conversacion: Mapped["Conversacion"] = relationship(back_populates="mensajes")

    def __repr__(self) -> str:
        return f"<Mensaje {self.id} {self.rol.value}>"
