"""Schemas Pydantic para el dominio Usuario y autenticación."""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_validator


RolLiteral = Literal["estudiante", "investigador", "administrador"]


class UsuarioBase(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    nombre: str = Field(min_length=2, max_length=120)
    email: EmailStr
    rol: RolLiteral = "estudiante"
    institucion: str | None = Field(default=None, max_length=200)
    nivel_academico: str | None = Field(default=None, max_length=80)


class UsuarioCrear(UsuarioBase):
    password: str = Field(min_length=8, max_length=128)

    @field_validator('password')
    @classmethod
    def longitud_bcrypt(cls, valor: str) -> str:
        if len(valor.encode('utf-8')) > 72:
            raise ValueError('La contraseña debe ocupar como máximo 72 bytes UTF-8')
        return valor


class UsuarioLogin(BaseModel):
    email: EmailStr
    password: str = Field(min_length=4)


class UsuarioLeer(UsuarioBase):
    id: uuid.UUID
    activo: bool
    fecha_creacion: datetime


class Token(BaseModel):
    access_token: str
    token_type: str = "bearer"
    expires_in_seconds: int


class TokenData(BaseModel):
    usuario_id: uuid.UUID
    email: str
    rol: RolLiteral
