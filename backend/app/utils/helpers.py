"""Funciones de apoyo: hashing de contraseñas, JWT, helpers de tiempo."""

from __future__ import annotations

import uuid
from datetime import datetime, timedelta, timezone
from typing import Any

import bcrypt
import jwt
from jwt import InvalidTokenError as JWTError

from app.config import settings


# ---------- Contraseñas ----------

def hash_password(password: str) -> str:
    sal = bcrypt.gensalt(rounds=12)
    return bcrypt.hashpw(password.encode("utf-8"), sal).decode("utf-8")


def verificar_password(plano: str, hash_almacenado: str) -> bool:
    try:
        return bcrypt.checkpw(plano.encode("utf-8"), hash_almacenado.encode("utf-8"))
    except (ValueError, TypeError):
        return False


# ---------- JWT ----------

def crear_access_token(
    *,
    usuario_id: uuid.UUID,
    email: str,
    rol: str,
    minutos_expiracion: int | None = None,
) -> tuple[str, int]:
    """Crea un JWT firmado y devuelve (token, segundos_de_expiracion)."""
    minutos = minutos_expiracion or settings.access_token_expire_minutes
    ahora = datetime.now(timezone.utc)
    expira = ahora + timedelta(minutes=minutos)
    payload: dict[str, Any] = {
        "sub": str(usuario_id),
        "email": email,
        "rol": rol,
        "iat": int(ahora.timestamp()),
        "exp": int(expira.timestamp()),
    }
    token = jwt.encode(payload, settings.secret_key, algorithm=settings.jwt_algorithm)
    return token, minutos * 60


def decodificar_token(token: str) -> dict[str, Any]:
    """Decodifica y valida un JWT. Lanza JWTError si es inválido."""
    return jwt.decode(token, settings.secret_key, algorithms=[settings.jwt_algorithm])


# Re-export para que el resto del código atrape un solo nombre
JWTError = JWTError


def ahora_utc() -> datetime:
    return datetime.now(timezone.utc)
