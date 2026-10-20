"""Aprovisionamiento explícito; nunca contiene credenciales privadas.

Ejecutar desde backend: .venv/Scripts/python scripts/configurar_cuentas.py --admin --demo
"""
import argparse
import asyncio
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from sqlalchemy import select
from app.config import settings
from app.database import SessionLocal, engine, init_models
from app.models.usuario import RolUsuario, Usuario
from app.models.intento_aprendizaje import AsignacionEstudio
from app.utils.helpers import hash_password

DEMO_EMAIL = "demo.estudiante@example.org"
DEMO_PASSWORD = "DemoPythonIA2026!"


async def configurar(sesion, *, admin=False, demo=False):
    if admin:
        if not settings.admin_email or not settings.admin_password:
            raise ValueError("Configure ADMIN_EMAIL y ADMIN_PASSWORD en backend/.env")
        usuario = await sesion.scalar(select(Usuario).where(Usuario.email == settings.admin_email))
        if usuario is None:
            usuario = Usuario(email=settings.admin_email, nombre=settings.admin_nombre)
            sesion.add(usuario)
        usuario.password_hash = hash_password(settings.admin_password)
        usuario.rol = RolUsuario.ADMINISTRADOR
        usuario.activo = True
    if demo:
        usuario = await sesion.scalar(select(Usuario).where(Usuario.email == DEMO_EMAIL))
        if usuario is not None and usuario.rol != RolUsuario.ESTUDIANTE:
            raise ValueError("La dirección de demostración ya pertenece a una cuenta privilegiada")
        if usuario is None:
            usuario = Usuario(email=DEMO_EMAIL, nombre="Estudiante de demostración",
                              rol=RolUsuario.ESTUDIANTE)
            sesion.add(usuario)
        usuario.password_hash = hash_password(DEMO_PASSWORD)
        usuario.activo = True
        await sesion.flush()
        asignacion = await sesion.get(AsignacionEstudio, usuario.id)
        if asignacion is None:
            sesion.add(AsignacionEstudio(usuario_id=usuario.id, condicion="con_acompanamiento", fase="pre"))
    await sesion.commit()


async def main(admin, demo):
    try:
        await init_models()
        async with SessionLocal() as sesion:
            await configurar(sesion, admin=admin, demo=demo)
        print("[OK] Cuentas solicitadas configuradas. No se muestran credenciales privadas.")
    finally:
        await engine.dispose()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--admin", action="store_true", help="Crear/actualizar administrador desde el .env privado")
    parser.add_argument("--demo", action="store_true", help="Crear/actualizar estudiante público de demostración")
    args = parser.parse_args()
    if not args.admin and not args.demo:
        parser.error("Seleccione --admin o --demo")
    asyncio.run(main(args.admin, args.demo))
