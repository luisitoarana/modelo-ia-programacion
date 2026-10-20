import importlib.util
from pathlib import Path

import pytest
from sqlalchemy import select
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker

from app.database import Base
from app.models.usuario import Usuario, RolUsuario
from app.models.intento_aprendizaje import AsignacionEstudio
from app.utils.helpers import verificar_password

spec = importlib.util.spec_from_file_location('configurar_cuentas', Path(__file__).resolve().parents[1] / 'scripts/configurar_cuentas.py')
cuentas = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cuentas)


@pytest.mark.asyncio
async def test_demo_es_estudiante_sin_privilegios_y_no_reinicia_su_fase():
    motor = create_async_engine('sqlite+aiosqlite:///:memory:')
    try:
        async with motor.begin() as conexion:
            await conexion.run_sync(Base.metadata.create_all)
        async with async_sessionmaker(motor, expire_on_commit=False)() as sesion:
            await cuentas.configurar(sesion, demo=True)
            usuario = await sesion.scalar(select(Usuario).where(Usuario.email == cuentas.DEMO_EMAIL))
            assert usuario.rol == RolUsuario.ESTUDIANTE
            assert verificar_password(cuentas.DEMO_PASSWORD, usuario.password_hash)
            asignacion = await sesion.get(AsignacionEstudio, usuario.id)
            assert asignacion.fase == 'pre'
            asignacion.fase = 'post'
            await sesion.commit()
            await cuentas.configurar(sesion, demo=True)
            assert asignacion.fase == 'post'
            assert len(list((await sesion.scalars(select(Usuario))).all())) == 1
    finally:
        await motor.dispose()


@pytest.mark.asyncio
async def test_demo_no_puede_sobrescribir_una_cuenta_privilegiada():
    motor = create_async_engine('sqlite+aiosqlite:///:memory:')
    try:
        async with motor.begin() as conexion:
            await conexion.run_sync(Base.metadata.create_all)
        async with async_sessionmaker(motor, expire_on_commit=False)() as sesion:
            sesion.add(Usuario(nombre='Docente', email=cuentas.DEMO_EMAIL,
                               password_hash='hash-existente', rol=RolUsuario.ADMINISTRADOR))
            await sesion.commit()
            with pytest.raises(ValueError, match='privilegiada'):
                await cuentas.configurar(sesion, demo=True)
    finally:
        await motor.dispose()
