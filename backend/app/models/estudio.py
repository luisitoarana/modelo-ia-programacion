"""Instrumentos congelados por participante; separados de las prácticas."""
import uuid
from datetime import datetime
from sqlalchemy import JSON, DateTime, ForeignKey, Integer, String, UniqueConstraint, Uuid
from sqlalchemy.orm import Mapped, mapped_column
from app.database import Base, TimestampMixin


class ConfiguracionEstudio(Base, TimestampMixin):
    __tablename__ = 'configuracion_estudio'
    id: Mapped[int] = mapped_column(primary_key=True)
    datos: Mapped[dict] = mapped_column(JSON, nullable=False)


class EntregaEstudio(Base, TimestampMixin):
    __tablename__ = 'entregas_estudio'
    __table_args__ = (UniqueConstraint('usuario_id', 'fase'),)
    id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid.uuid4)
    usuario_id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), ForeignKey('usuarios.id'), index=True)
    fase: Mapped[str] = mapped_column(String(20))
    condicion: Mapped[str] = mapped_column(String(32))
    version: Mapped[str] = mapped_column(String(40), default='piloto-6-v1')
    estado: Mapped[str] = mapped_column(String(20), default='borrador')
    preguntas: Mapped[list] = mapped_column(JSON)
    respuestas: Mapped[dict] = mapped_column(JSON, default=dict)
    revisiones: Mapped[dict] = mapped_column(JSON, default=dict)
    enviada_en: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    revision: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    __mapper_args__ = {'version_id_col': revision}
