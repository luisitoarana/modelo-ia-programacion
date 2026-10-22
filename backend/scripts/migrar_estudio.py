"""Añade únicamente las tablas pre/post, sin borrar usuarios ni intentos."""
import asyncio
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from sqlalchemy import inspect
from app.database import engine, Base
from app.models.estudio import ConfiguracionEstudio, EntregaEstudio


def migrar(conexion):
    if not inspect(conexion).has_table('usuarios'):
        raise RuntimeError('Primero inicialice la base del sistema con su tabla de usuarios.')
    Base.metadata.create_all(conexion, tables=[ConfiguracionEstudio.__table__, EntregaEstudio.__table__])


async def main():
    try:
        async with engine.begin() as conexion:
            await conexion.run_sync(migrar)
        print('[OK] Tablas de estudio verificadas. Usuarios e intentos existentes conservados.')
    finally:
        await engine.dispose()


if __name__ == '__main__':
    asyncio.run(main())
