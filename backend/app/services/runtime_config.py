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
GROQ_API_KEY = "groq_api_key"
OPENAI_API_KEY = "openai_api_key"
ANTHROPIC_API_KEY = "anthropic_api_key"
OPENROUTER_API_KEY = "openrouter_api_key"

CLAVES_PROVEEDOR = {
    "gemini": GEMINI_API_KEY,
    "deepseek": DEEPSEEK_API_KEY,
    "groq": GROQ_API_KEY,
    "openai": OPENAI_API_KEY,
    "anthropic": ANTHROPIC_API_KEY,
    "openrouter": OPENROUTER_API_KEY,
}


def set_valor(clave: str, valor: str) -> None:
    with _lock:
        _cache[clave] = valor


def get_valor(clave: str) -> str:
    return _cache.get(clave, "")


def get_api_key(proveedor: str) -> str:
    """Resuelve la API key: primero la configurada por el admin, luego el .env."""
    prov = proveedor.lower().strip()
    if prov in CLAVES_PROVEEDOR:
        clave = CLAVES_PROVEEDOR[prov]
        val = _cache.get(clave)
        if val:
            return val
    # Fallback a settings si existen
    if prov == "gemini":
        return getattr(settings, "gemini_api_key", "")
    if prov == "deepseek":
        return getattr(settings, "deepseek_api_key", "")
    if prov == "groq":
        return getattr(settings, "groq_api_key", "")
    if prov == "openai":
        return getattr(settings, "openai_api_key", "")
    if prov == "anthropic":
        return getattr(settings, "anthropic_api_key", "")
    if prov == "openrouter":
        return getattr(settings, "openrouter_api_key", "")
    return ""


def hidratar(valores: dict[str, str]) -> None:
    """Carga en bloque los valores descifrados (al arrancar)."""
    with _lock:
        _cache.update(valores)


def proveedores_configurados() -> list[str]:
    salida = []
    for prov in ("groq", "gemini", "deepseek", "openai", "anthropic", "openrouter"):
        if get_api_key(prov):
            salida.append(prov)
    return salida
