"""Dependencias FastAPI para autenticación basada en JWT."""

from __future__ import annotations

import uuid
from typing import Annotated

from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models.usuario import RolUsuario, Usuario
from app.utils.helpers import JWTError, decodificar_token


oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/v1/auth/login", auto_error=True)


CREDENCIALES_INVALIDAS = HTTPException(
    status_code=status.HTTP_401_UNAUTHORIZED,
    detail="Credenciales inválidas o token expirado.",
    headers={"WWW-Authenticate": "Bearer"},
)


async def obtener_usuario_actual(
    token: Annotated[str, Depends(oauth2_scheme)],
    sesion: Annotated[AsyncSession, Depends(get_db)],
) -> Usuario:
    try:
        payload = decodificar_token(token)
    except JWTError as exc:
        raise CREDENCIALES_INVALIDAS from exc

    sub = payload.get("sub")
    if not sub:
        raise CREDENCIALES_INVALIDAS
    try:
        usuario_id = uuid.UUID(sub)
    except ValueError as exc:
        raise CREDENCIALES_INVALIDAS from exc

    usuario = await sesion.get(Usuario, usuario_id)
    if usuario is None or not usuario.activo:
        raise CREDENCIALES_INVALIDAS
    return usuario


def requerir_rol(*roles: RolUsuario):
    """Devuelve una dependencia FastAPI que restringe acceso por rol."""

    async def _verificar(
        usuario: Annotated[Usuario, Depends(obtener_usuario_actual)],
    ) -> Usuario:
        if usuario.rol not in roles:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="No tienes permiso para esta operación.",
            )
        return usuario

    return _verificar
