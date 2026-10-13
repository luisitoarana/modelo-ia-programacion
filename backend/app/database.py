"""Capa de persistencia: motor async, sesión y Base declarativa.

Usa SQLAlchemy 2.0 con asyncpg. Expone una dependencia FastAPI
``get_db`` para inyectar sesiones por request.
"""

from __future__ import annotations

from collections.abc import AsyncGenerator
from datetime import datetime
from typing import Any

from sqlalchemy import DateTime, MetaData, inspect, text
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


def _crear_engine():
    """Crea el engine con el pool correcto según el dialecto.

    SQLite (aiosqlite) usa `StaticPool` sin pool_size/max_overflow — pasar
    esos argumentos rompe la conexión. Postgres (asyncpg) sí usa el pool
    clásico configurado por settings.
    """
    url = settings.database_url
    kwargs: dict = {
        "echo": settings.database_echo,
        "future": True,
    }
    if url.startswith("sqlite"):
        # SQLite: connect_args=check_same_thread solo aplica a sync;
        # aiosqlite lo ignora. No usar pool_size ni pool_pre_ping.
        pass
    else:
        kwargs["pool_size"] = settings.database_pool_size
        kwargs["max_overflow"] = settings.database_max_overflow
        kwargs["pool_pre_ping"] = True
    return create_async_engine(url, **kwargs)


engine = _crear_engine()


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
        intento_aprendizaje,
        usuario,
    )

    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
        await conn.run_sync(actualizar_esquema_desarrollo)


def actualizar_esquema_desarrollo(conn) -> None:
    """Ampliaciones idempotentes: conserva las filas de instalaciones previas."""
    inspector = inspect(conn)
    tablas = set(inspector.get_table_names())
    if "intentos_aprendizaje" in tablas:
        columnas = {c["name"] for c in inspector.get_columns("intentos_aprendizaje")}
        if "pregunta" not in columnas:
            conn.execute(text("ALTER TABLE intentos_aprendizaje ADD COLUMN pregunta TEXT NULL"))
    if conn.dialect.name == "mysql" and "mensajes" in tablas:
        columnas = {c["name"]: c for c in inspector.get_columns("mensajes")}
        tipo = columnas.get("contenido", {}).get("type")
        if tipo is not None and tipo.__class__.__name__.upper() == "TEXT":
            conn.execute(text("ALTER TABLE mensajes MODIFY COLUMN contenido MEDIUMTEXT NOT NULL"))
