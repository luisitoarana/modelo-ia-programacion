"""Configuración en memoria del proceso (caché de API keys, etc.).

Las API keys configuradas por el administrador se guardan CIFRADAS en la BD
(``ConfiguracionSistema``) y, además, se mantienen descifradas en este caché
de proceso para que el proveedor de IA las use sin tocar la BD en cada
llamada. Se hidrata al arrancar y se refresca cuando el admin las cambia.
"""

from __future__ import annotations

import threading

from app.config import settings


_lock = threading.Lock()
_cache: dict[str, str] = {}


# Claves estándar
GEMINI_API_KEY = "gemini_api_key"
DEEPSEEK_API_KEY = "deepseek_api_key"


def set_valor(clave: str, valor: str) -> None:
    with _lock:
        _cache[clave] = valor


def get_valor(clave: str) -> str:
    return _cache.get(clave, "")


def get_api_key(proveedor: str) -> str:
    """Resuelve la API key: primero la configurada por el admin, luego el .env."""
    proveedor = proveedor.lower()
    if proveedor == "gemini":
        return _cache.get(GEMINI_API_KEY) or settings.gemini_api_key
    if proveedor == "deepseek":
        return _cache.get(DEEPSEEK_API_KEY) or settings.deepseek_api_key
    return ""


def hidratar(valores: dict[str, str]) -> None:
    """Carga en bloque los valores descifrados (al arrancar)."""
    with _lock:
        _cache.update(valores)


def proveedores_configurados() -> list[str]:
    salida = []
    if get_api_key("gemini"):
        salida.append("gemini")
    if get_api_key("deepseek"):
        salida.append("deepseek")
    return salida
