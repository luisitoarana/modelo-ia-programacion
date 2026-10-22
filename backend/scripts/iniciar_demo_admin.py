"""Servidor de demostración aislado: no carga backend/.env ni sus datos privados.

Desde backend: .venv/Scripts/python scripts/iniciar_demo_admin.py
Use --preparar para crear las cuentas sin dejar el servidor ejecutándose.
"""
import argparse
import asyncio
import os
from pathlib import Path
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--preparar', action='store_true')
    args = parser.parse_args()
    os.environ['PYTHONIA_DEMO_AISLADA'] = '1'
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    from configurar_cuentas import main as configurar
    asyncio.run(configurar(admin=True, demo=True))
    print('[DEMO] BD y sesión independientes. Administrador público: demo.admin@example.org')
    if not args.preparar:
        import uvicorn
        uvicorn.run('app.main:app', host='127.0.0.1', port=8766)


if __name__ == '__main__':
    main()
