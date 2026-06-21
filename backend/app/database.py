"""Capa de persistencia: motor async, sesión y Base declarativa.

Usa SQLAlchemy 2.0 con asyncpg. Expone una dependencia FastAPI
``get_db`` para inyectar sesiones por request.
"""

from __future__ import annotations

from collections.abc import AsyncGenerator
from datetime import datetime
from typing import Any

from sqlalchemy import DateTime, MetaData
from sqlalchemy.ext.asyncio import (
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column

from app.config import settings


NAMING_CONVENTION: dict[str, str] = {
    "ix": "ix_%(column_0_label)s",
    "uq": "uq_%(table_name)s_%(column_0_name)s",
    "ck": "ck_%(table_name)s_%(constraint_name)s",
    "fk": "fk_%(table_name)s_%(column_0_name)s_%(referred_table_name)s",
    "pk": "pk_%(table_name)s",
}


class Base(DeclarativeBase):
    """Base declarativa común con metadata nombrada y timestamps utilitarios."""

    metadata = MetaData(naming_convention=NAMING_CONVENTION)
    type_annotation_map: dict[Any, Any] = {}


class TimestampMixin:
    """Añade campos de creación y actualización automáticos."""

    fecha_creacion: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=datetime.utcnow,
        nullable=False,
    )
    fecha_actualizacion: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=datetime.utcnow,
        onupdate=datetime.utcnow,
        nullable=False,
    )


engine = create_async_engine(
    settings.database_url,
    echo=settings.database_echo,
    pool_size=settings.database_pool_size,
    max_overflow=settings.database_max_overflow,
    pool_pre_ping=True,
    future=True,
)


SessionLocal: async_sessionmaker[AsyncSession] = async_sessionmaker(
    bind=engine,
    autoflush=False,
    autocommit=False,
    expire_on_commit=False,
    class_=AsyncSession,
)


async def get_db() -> AsyncGenerator[AsyncSession, None]:
    """Dependencia FastAPI: provee una sesión async transaccional por request."""
    async with SessionLocal() as session:
        try:
            yield session
        except Exception:
            await session.rollback()
            raise
        finally:
            await session.close()


async def init_models() -> None:
    """Crea todas las tablas en la base si no existen. Usar solo en desarrollo."""
    # Importar modelos para que se registren en Base.metadata
    from app.models import (  # noqa: F401
        actividad,
        conocimiento,
        configuracion,
        consulta,
        conversacion,
        dataset,
        evaluacion,
        feedback,
        usuario,
    )

    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
