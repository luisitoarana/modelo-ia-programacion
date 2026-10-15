"""Modelo ConfiguracionSistema: pares clave-valor (API keys cifradas, flags).

Permite que el administrador configure el sistema desde la web (p.ej. las API
keys de Gemini/DeepSeek) sin editar el archivo .env. Los valores marcados como
secreto se almacenan CIFRADOS (Fernet derivado de SECRET_KEY).
"""

from __future__ import annotations

from sqlalchemy import Boolean, String, Text
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base, TimestampMixin


class ConfiguracionSistema(Base, TimestampMixin):
    __tablename__ = "configuracion_sistema"

    clave: Mapped[str] = mapped_column(String(80), primary_key=True)
    valor_cifrado: Mapped[str] = mapped_column(Text, nullable=False, default="")
    es_secreto: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    descripcion: Mapped[str | None] = mapped_column(String(255), nullable=True)
    actualizado_por: Mapped[str | None] = mapped_column(String(180), nullable=True)

    def __repr__(self) -> str:
        return f"<ConfiguracionSistema {self.clave} secreto={self.es_secreto}>"
