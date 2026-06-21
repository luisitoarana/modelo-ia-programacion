"""Logger central del sistema.

Salida por consola + archivo rotatorio. Nivel configurable vía settings.
"""

from __future__ import annotations

import logging
from logging.handlers import RotatingFileHandler
from pathlib import Path

from app.config import settings


_LOGGER_INICIALIZADO = False


def configurar_logging() -> None:
    """Configura los handlers globales una sola vez."""
    global _LOGGER_INICIALIZADO
    if _LOGGER_INICIALIZADO:
        return

    formato = logging.Formatter(
        fmt="%(asctime)s | %(levelname)-8s | %(name)s | %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )

    root = logging.getLogger()
    root.setLevel(settings.log_level)

    # Limpia handlers previos para evitar duplicados (recargas en dev)
    for h in list(root.handlers):
        root.removeHandler(h)

    consola = logging.StreamHandler()
    consola.setFormatter(formato)
    root.addHandler(consola)

    try:
        ruta = Path(settings.log_file)
        ruta.parent.mkdir(parents=True, exist_ok=True)
        archivo = RotatingFileHandler(
            ruta, maxBytes=5 * 1024 * 1024, backupCount=5, encoding="utf-8"
        )
        archivo.setFormatter(formato)
        root.addHandler(archivo)
    except OSError as exc:
        root.warning("No se pudo abrir archivo de log: %s", exc)

    _LOGGER_INICIALIZADO = True


def obtener_logger(nombre: str) -> logging.Logger:
    """Devuelve un logger configurado por módulo."""
    configurar_logging()
    return logging.getLogger(nombre)
