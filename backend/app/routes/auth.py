"""Rutas de autenticación: registro y login con JWT."""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import obtener_usuario_actual
from app.database import get_db
from app.models.usuario import RolUsuario, Usuario
from app.schemas.usuario import Token, UsuarioCrear, UsuarioLeer, UsuarioLogin
from app.utils.helpers import crear_access_token, hash_password, verificar_password


router = APIRouter()


class CambioClave(BaseModel):
    actual: str
    nueva: str = Field(min_length=10, max_length=128)


@router.put("/clave", summary="Cambiar la contraseña de la cuenta actual")
async def cambiar_clave(
    datos: CambioClave,
    usuario: Annotated[Usuario, Depends(obtener_usuario_actual)],
    sesion: Annotated[AsyncSession, Depends(get_db)],
) -> dict[str, str]:
    if not verificar_password(datos.actual, usuario.password_hash):
        raise HTTPException(status_code=400, detail="La contraseña actual es incorrecta.")
    if datos.actual == datos.nueva:
        raise HTTPException(status_code=400, detail="La nueva contraseña debe ser diferente.")
    usuario.password_hash = hash_password(datos.nueva)
    await sesion.commit()
    return {"estado": "ok"}


@router.post(
    "/registro",
    response_model=UsuarioLeer,
    status_code=status.HTTP_201_CREATED,
    summary="Registrar nuevo usuario",
)
async def registrar(
    datos: UsuarioCrear,
    sesion: Annotated[AsyncSession, Depends(get_db)],
) -> Usuario:
    existente = await sesion.scalar(select(Usuario).where(Usuario.email == datos.email))
    if existente is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="El correo ya está registrado.",
        )
    # Las condiciones de investigación solo las asigna personal autorizado.
    # El registro público crea estudiantes; investigadores se aprovisionan aparte.
    rol = RolUsuario(datos.rol)
    if rol is not RolUsuario.ESTUDIANTE:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="El registro público solo permite cuentas de estudiante.",
        )
    usuario = Usuario(
        nombre=datos.nombre,
        email=datos.email,
        password_hash=hash_password(datos.password),
        rol=rol,
        institucion=datos.institucion,
        nivel_academico=datos.nivel_academico,
    )
    sesion.add(usuario)
    try:
        await sesion.commit()
    except IntegrityError as exc:
        await sesion.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="No se pudo crear el usuario (conflicto de integridad).",
        ) from exc
    await sesion.refresh(usuario)
    return usuario


@router.post("/login", response_model=Token, summary="Iniciar sesión y obtener JWT")
async def login(
    credenciales: UsuarioLogin,
    sesion: Annotated[AsyncSession, Depends(get_db)],
) -> Token:
    usuario = await sesion.scalar(
        select(Usuario).where(Usuario.email == credenciales.email)
    )
    if usuario is None or not verificar_password(
        credenciales.password, usuario.password_hash
    ):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Credenciales inválidas.",
        )
    if not usuario.activo:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Cuenta desactivada.",
        )
    token, segundos = crear_access_token(
        usuario_id=usuario.id,
        email=usuario.email,
        rol=usuario.rol.value,
    )
    return Token(access_token=token, expires_in_seconds=segundos)


@router.get("/yo", response_model=UsuarioLeer, summary="Perfil del usuario autenticado")
async def perfil_actual(
    usuario: Annotated[Usuario, Depends(obtener_usuario_actual)],
) -> Usuario:
    return usuario
