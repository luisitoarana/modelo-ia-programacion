"""Inicialización del sistema al arrancar: admin seed + caché de configuración."""

from __future__ import annotations

from sqlalchemy import select

from app.config import settings
from app.database import SessionLocal
from app.models.usuario import RolUsuario, Usuario
from app.services.config_service import ConfigService
from app.utils.helpers import hash_password
from app.utils.logger import obtener_logger


log = obtener_logger(__name__)


async def inicializar_sistema() -> None:
    """Crea el admin por defecto (si falta) y carga las API keys al caché."""
    async with SessionLocal() as sesion:
        # 1) Hidratar caché de API keys desde la BD (cifradas).
        try:
            cfg = ConfigService(sesion)
            n = await cfg.hidratar_cache()
            log.info("Configuración cargada: %s API key(s) activa(s) desde BD.", n)
        except Exception as exc:  # noqa: BLE001
            log.warning("No se pudo hidratar la configuración: %s", exc)

        # 2) Seed del administrador.
        if settings.admin_email:
            existe = await sesion.scalar(
                select(Usuario).where(Usuario.email == settings.admin_email)
            )
            if existe is None:
                admin = Usuario(
                    nombre=settings.admin_nombre,
                    email=settings.admin_email,
                    password_hash=hash_password(settings.admin_password),
                    rol=RolUsuario.ADMINISTRADOR,
                    activo=True,
                )
                sesion.add(admin)
                await sesion.commit()
                log.info("Administrador creado: %s", settings.admin_email)
            else:
                log.info("Administrador ya existe: %s", settings.admin_email)
