"""Modelo Usuario: estudiantes, investigadores y administradores."""

from __future__ import annotations

import enum
import uuid
from typing import TYPE_CHECKING

from sqlalchemy import Boolean, Enum as SAEnum, String
from sqlalchemy import Uuid as UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base, TimestampMixin

if TYPE_CHECKING:
    from app.models.consulta import Consulta
    from app.models.dataset import DatasetEducativo
    from app.models.evaluacion import Evaluacion


class RolUsuario(str, enum.Enum):
    """Roles autorizados en el sistema."""

    ESTUDIANTE = "estudiante"
    INVESTIGADOR = "investigador"
    ADMINISTRADOR = "administrador"


class Usuario(Base, TimestampMixin):
    """Cuenta de usuario del sistema educativo."""

    __tablename__ = "usuarios"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
    )
    nombre: Mapped[str] = mapped_column(String(120), nullable=False)
    email: Mapped[str] = mapped_column(
        String(180), nullable=False, unique=True, index=True
    )
    password_hash: Mapped[str] = mapped_column(String(255), nullable=False)
    rol: Mapped[RolUsuario] = mapped_column(
        SAEnum(RolUsuario, name="rol_usuario_enum"),
        nullable=False,
        default=RolUsuario.ESTUDIANTE,
    )
    institucion: Mapped[str | None] = mapped_column(String(200), nullable=True)
    nivel_academico: Mapped[str | None] = mapped_column(String(80), nullable=True)
    activo: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)

    consultas: Mapped[list["Consulta"]] = relationship(
        back_populates="usuario", cascade="all, delete-orphan"
    )
    datasets: Mapped[list["DatasetEducativo"]] = relationship(
        back_populates="usuario", cascade="all, delete-orphan"
    )
    evaluaciones: Mapped[list["Evaluacion"]] = relationship(
        back_populates="usuario", cascade="all, delete-orphan"
    )

    def __repr__(self) -> str:
        return f"<Usuario {self.email} rol={self.rol.value}>"
