"""Evidencia de una práctica guiada, sin calificación automática de la IA."""

from __future__ import annotations

import uuid

from sqlalchemy import ForeignKey, Integer, String, Text, Uuid
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base, TimestampMixin


class IntentoAprendizaje(Base, TimestampMixin):
    __tablename__ = "intentos_aprendizaje"

    id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid.uuid4)
    usuario_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("usuarios.id", ondelete="CASCADE"), nullable=False, index=True
    )
    leccion_id: Mapped[str | None] = mapped_column(String(80), nullable=True, index=True)
    pregunta: Mapped[str | None] = mapped_column(Text, nullable=True)
    modo: Mapped[str] = mapped_column(String(32), nullable=False)
    fase: Mapped[str] = mapped_column(String(20), nullable=False, default="practica")
    codigo_inicial: Mapped[str] = mapped_column(Text, nullable=False)
    codigo_final: Mapped[str] = mapped_column(Text, nullable=False)
    prediccion: Mapped[str] = mapped_column(Text, nullable=False)
    explicacion_propia: Mapped[str] = mapped_column(Text, nullable=False)
    pistas_usadas: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    duracion_segundos: Mapped[int] = mapped_column(Integer, nullable=False, default=0)


class AsignacionEstudio(Base, TimestampMixin):
    __tablename__ = "asignaciones_estudio"

    usuario_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("usuarios.id", ondelete="CASCADE"), primary_key=True
    )
    condicion: Mapped[str] = mapped_column(String(32), nullable=False)
    fase: Mapped[str] = mapped_column(String(20), nullable=False)


class RevisionIntento(Base, TimestampMixin):
    """Rúbrica aplicada por una persona; no hay calificación automática de IA."""

    __tablename__ = "revisiones_intentos"

    intento_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("intentos_aprendizaje.id", ondelete="CASCADE"), primary_key=True
    )
    docente_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True), ForeignKey("usuarios.id"), nullable=False
    )
    comprension: Mapped[int] = mapped_column(Integer, nullable=False)
    codigo: Mapped[int] = mapped_column(Integer, nullable=False)
    casos_limite: Mapped[int] = mapped_column(Integer, nullable=False)
    observaciones: Mapped[str] = mapped_column(Text, nullable=False, default="")
