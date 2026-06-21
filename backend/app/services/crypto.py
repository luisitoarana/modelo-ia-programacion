"""Cifrado simétrico para secretos en la base de datos.

Usa Fernet (AES-128 en modo CBC + HMAC) con una clave derivada de
``settings.secret_key`` mediante SHA-256. Así no se requiere gestionar una
clave aparte: rota junto con SECRET_KEY.
"""

from __future__ import annotations

import base64
import hashlib
from functools import lru_cache

from cryptography.fernet import Fernet, InvalidToken

from app.config import settings


@lru_cache(maxsize=1)
def _fernet() -> Fernet:
    digest = hashlib.sha256(settings.secret_key.encode("utf-8")).digest()
    clave = base64.urlsafe_b64encode(digest)
    return Fernet(clave)


def cifrar(texto_plano: str) -> str:
    if texto_plano == "":
        return ""
    return _fernet().encrypt(texto_plano.encode("utf-8")).decode("utf-8")


def descifrar(token: str) -> str:
    if not token:
        return ""
    try:
        return _fernet().decrypt(token.encode("utf-8")).decode("utf-8")
    except (InvalidToken, ValueError):
        return ""


def enmascarar(secreto: str) -> str:
    """Devuelve una versión enmascarada para mostrar en la UI (••••1234)."""
    if not secreto:
        return ""
    if len(secreto) <= 4:
        return "••••"
    return "••••" + secreto[-4:]
