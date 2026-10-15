"""Modelo Consulta: cada interacción del estudiante con el orquestador IA."""

from __future__ import annotations

import enum
import uuid
from typing import TYPE_CHECKING

from sqlalchemy import Enum as SAEnum, Float, ForeignKey, Integer, String, Text
from sqlalchemy import Uuid as UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base, TimestampMixin

if TYPE_CHECKING:
    from app.models.dataset import DatasetEducativo
    from app.models.usuario import Usuario


class EstadoConsulta(str, enum.Enum):
    PENDIENTE = "pendiente"
    EN_PROCESO = "en_proceso"
    COMPLETADA = "completada"
    FALLIDA = "fallida"
    JSON_INVALIDO = "json_invalido"


class FuenteIA(str, enum.Enum):
    GEMINI = "gemini"
    DEEPSEEK = "deepseek-r1"
    MODELO_LOCAL = "modelo-local"


class Consulta(Base, TimestampMixin):
    """Registro de cada consulta enviada al modelo de IA."""

    __tablename__ = "consultas"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    usuario_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("usuarios.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )

    prompt_original: Mapped[str] = mapped_column(Text, nullable=False)
    nivel_solicitado: Mapped[str | None] = mapped_column(String(40), nullable=True)
    tema_solicitado: Mapped[str | None] = mapped_column(String(60), nullable=True)

    modelo_usado: Mapped[FuenteIA] = mapped_column(
        SAEnum(FuenteIA, name="fuente_ia_enum"), nullable=False
    )
    temperatura: Mapped[float] = mapped_column(Float, nullable=False, default=0.4)
    tokens_entrada: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    tokens_salida: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    tokens_totales: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    latencia_segundos: Mapped[float] = mapped_column(Float, nullable=False, default=0.0)

    estado: Mapped[EstadoConsulta] = mapped_column(
        SAEnum(EstadoConsulta, name="estado_consulta_enum"),
        nullable=False,
        default=EstadoConsulta.PENDIENTE,
    )
    error_mensaje: Mapped[str | None] = mapped_column(Text, nullable=True)
    intentos_reparacion_json: Mapped[int] = mapped_column(
        Integer, nullable=False, default=0
    )

    # --- Trazabilidad retrieval-first (evidencia de dependencia de APIs) ---
    # "api" si se llamó a un proveedor externo; "base_conocimiento" si se
    # respondió desde el conocimiento propio reutilizable.
    origen_respuesta: Mapped[str] = mapped_column(
        String(30), nullable=False, default="api"
    )
    score_recuperacion: Mapped[float] = mapped_column(
        Float, nullable=False, default=0.0
    )
    unidad_conocimiento_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), nullable=True
    )
    puntaje_calidad: Mapped[float] = mapped_column(Float, nullable=False, default=0.0)

    usuario: Mapped["Usuario"] = relationship(back_populates="consultas")
    dataset: Mapped["DatasetEducativo | None"] = relationship(
        back_populates="consulta", uselist=False, cascade="all, delete-orphan"
    )

    def __repr__(self) -> str:
        return f"<Consulta {self.id} estado={self.estado.value}>"
