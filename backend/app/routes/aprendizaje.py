"""Registro verificable de intentos del estudiante para revisión docente."""

from __future__ import annotations

from datetime import datetime
from typing import Annotated, Literal
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import obtener_usuario_actual, requerir_rol
from app.database import get_db
from app.models.intento_aprendizaje import AsignacionEstudio, IntentoAprendizaje, RevisionIntento
from app.models.usuario import RolUsuario, Usuario
from app.services.curriculum_service import CurriculumService
from app.services.estudio_service import configuracion
from app.models.estudio import EntregaEstudio

router = APIRouter()


class IntentoCrear(BaseModel):
    leccion_id: str | None = Field(default=None, max_length=80)
    pregunta: str | None = Field(default=None, max_length=2000)
    modo: Literal["con_acompanamiento", "sin_acompanamiento", "bloqueado_post_test"]
    codigo_inicial: str = Field(min_length=1, max_length=10000)
    codigo_final: str = Field(min_length=1, max_length=10000)
    prediccion: str = Field(min_length=1, max_length=10000)
    explicacion_propia: str = Field(min_length=1, max_length=10000)
    pistas_usadas: int = Field(ge=0, le=20)
    duracion_segundos: int = Field(ge=0, le=86400)


class IntentoLeer(IntentoCrear):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    fase: str
    fecha_creacion: datetime


class IntentoRevision(IntentoLeer):
    usuario_id: UUID
    usuario_nombre: str
    usuario_email: str
    revision_docente: dict[str, object] | None = None


class RubricaDocente(BaseModel):
    comprension: int = Field(ge=0, le=4)
    codigo: int = Field(ge=0, le=4)
    casos_limite: int = Field(ge=0, le=2)
    observaciones: str = Field(default="", max_length=2000)


class AsignacionCrear(BaseModel):
    condicion: Literal["con_acompanamiento", "sin_acompanamiento"]
    fase: Literal["pre", "intervencion", "post"]


def modo_asignado(asignacion: AsignacionEstudio) -> str:
    return "bloqueado_post_test" if asignacion.fase in ("pre", "post") else asignacion.condicion


@router.get("/asignacion")
async def obtener_asignacion(
    usuario: Annotated[Usuario, Depends(obtener_usuario_actual)],
    sesion: Annotated[AsyncSession, Depends(get_db)],
) -> dict[str, object]:
    asignacion = await sesion.get(AsignacionEstudio, usuario.id)
    cfg = await configuracion(sesion)
    if asignacion is None:
        return {"asignado": False, "condicion": None, "fase": None, "modo_efectivo": None,
                "pendiente_asignacion": cfg['estudio_activo'] and usuario.rol == RolUsuario.ESTUDIANTE}
    return {
        "asignado": True,
        "condicion": asignacion.condicion,
        "fase": asignacion.fase,
        "modo_efectivo": modo_asignado(asignacion),
        "practica_guiada": cfg["practica_guiada"],
    }


@router.put("/asignaciones/{usuario_id}")
async def asignar_condicion(
    usuario_id: UUID,
    datos: AsignacionCrear,
    _docente: Annotated[
        Usuario, Depends(requerir_rol(RolUsuario.INVESTIGADOR, RolUsuario.ADMINISTRADOR))
    ],
    sesion: Annotated[AsyncSession, Depends(get_db)],
) -> dict[str, object]:
    if await sesion.get(Usuario, usuario_id) is None:
        raise HTTPException(status_code=404, detail="Participante no encontrado.")
    entregas = list((await sesion.scalars(select(EntregaEstudio).where(EntregaEstudio.usuario_id == usuario_id))).all())
    cfg = await configuracion(sesion)
    if cfg['estudio_activo'] and datos.fase in ('intervencion', 'post') and not any(e.fase == 'pre' and e.estado == 'enviado' for e in entregas):
        raise HTTPException(409, 'Con el estudio activo, primero se necesita un pretest enviado.')
    if entregas and any(e.condicion != datos.condicion for e in entregas):
        raise HTTPException(409, 'La condición queda fijada al iniciar el pretest. No cambies de grupo a mitad del estudio.')
    if datos.fase in ('intervencion', 'post') and any(e.fase == 'pre' and e.estado != 'enviado' for e in entregas):
        raise HTTPException(409, 'Primero se debe enviar el pretest, aun con respuestas incompletas.')
    asignacion = await sesion.get(AsignacionEstudio, usuario_id)
    orden = {'pre': 0, 'intervencion': 1, 'post': 2}
    if entregas and asignacion and orden[datos.fase] < orden[asignacion.fase]:
        raise HTTPException(409, 'Las fases del estudio solo avanzan; para otro pilotaje utiliza una cuenta nueva.')
    if asignacion is None:
        asignacion = AsignacionEstudio(usuario_id=usuario_id)
        sesion.add(asignacion)
    asignacion.condicion = datos.condicion
    asignacion.fase = datos.fase
    await sesion.commit()
    return {"usuario_id": str(usuario_id), "condicion": datos.condicion,
            "fase": datos.fase, "modo_efectivo": modo_asignado(asignacion)}


@router.post("/intentos", response_model=IntentoLeer, status_code=status.HTTP_201_CREATED)
async def registrar_intento(
    datos: IntentoCrear,
    usuario: Annotated[Usuario, Depends(obtener_usuario_actual)],
    sesion: Annotated[AsyncSession, Depends(get_db)],
) -> IntentoAprendizaje:
    if datos.leccion_id and CurriculumService.obtener_leccion(datos.leccion_id) is None:
        raise HTTPException(status_code=404, detail="Lección no encontrada.")
    asignacion = await sesion.get(AsignacionEstudio, usuario.id)
    campos = datos.model_dump()
    if asignacion is not None:
        if asignacion.fase in ('pre', 'post'):
            raise HTTPException(409, 'Los pre/post se entregan en el instrumento de evaluación, no como una práctica.')
        if asignacion.condicion == 'sin_acompanamiento':
            raise HTTPException(403, 'El grupo de generación directa no utiliza práctica guiada.')
        campos["modo"] = modo_asignado(asignacion)
        campos["fase"] = asignacion.fase
    intento = IntentoAprendizaje(usuario_id=usuario.id, **campos)
    sesion.add(intento)
    await sesion.commit()
    await sesion.refresh(intento)
    return intento


@router.get("/intentos", response_model=list[IntentoLeer])
async def listar_intentos(
    usuario: Annotated[Usuario, Depends(obtener_usuario_actual)],
    sesion: Annotated[AsyncSession, Depends(get_db)],
) -> list[IntentoAprendizaje]:
    resultados = await sesion.scalars(
        select(IntentoAprendizaje)
        .where(IntentoAprendizaje.usuario_id == usuario.id)
        .order_by(IntentoAprendizaje.fecha_creacion.desc())
        .limit(200)
    )
    return list(resultados.all())


@router.get("/investigacion/intentos", response_model=list[IntentoRevision])
async def revisar_intentos(
    _docente: Annotated[
        Usuario, Depends(requerir_rol(RolUsuario.INVESTIGADOR, RolUsuario.ADMINISTRADOR))
    ],
    sesion: Annotated[AsyncSession, Depends(get_db)],
    usuario_id: UUID | None = None,
    fase: Literal["practica", "pre", "intervencion", "post"] | None = None,
    offset: Annotated[int, Query(ge=0)] = 0,
    limite: Annotated[int, Query(ge=1, le=1000)] = 1000,
) -> list[dict[str, object]]:
    consulta = (
        select(IntentoAprendizaje, Usuario, RevisionIntento)
        .join(Usuario, Usuario.id == IntentoAprendizaje.usuario_id)
        .outerjoin(RevisionIntento, RevisionIntento.intento_id == IntentoAprendizaje.id)
    )
    if usuario_id is not None:
        consulta = consulta.where(IntentoAprendizaje.usuario_id == usuario_id)
    if fase is not None:
        consulta = consulta.where(IntentoAprendizaje.fase == fase)
    resultados = await sesion.execute(
        consulta.order_by(IntentoAprendizaje.fecha_creacion.desc(), IntentoAprendizaje.id.desc())
        .offset(offset).limit(limite)
    )
    revision = []
    for intento, estudiante, nota in resultados.all():
        campos = IntentoLeer.model_validate(intento).model_dump()
        campos.update(usuario_id=intento.usuario_id, usuario_nombre=estudiante.nombre,
                      usuario_email=estudiante.email)
        if nota is not None:
            campos["revision_docente"] = {
                "comprension": nota.comprension, "codigo": nota.codigo,
                "casos_limite": nota.casos_limite,
                "puntaje": nota.comprension + nota.codigo + nota.casos_limite,
                "observaciones": nota.observaciones,
                "docente_id": str(nota.docente_id),
                "fecha_actualizacion": nota.fecha_actualizacion.isoformat(),
            }
        revision.append(campos)
    return revision


@router.put("/investigacion/intentos/{intento_id}/revision")
async def calificar_intento(
    intento_id: UUID,
    rubrica: RubricaDocente,
    docente: Annotated[
        Usuario, Depends(requerir_rol(RolUsuario.INVESTIGADOR, RolUsuario.ADMINISTRADOR))
    ],
    sesion: Annotated[AsyncSession, Depends(get_db)],
) -> dict[str, object]:
    if await sesion.get(IntentoAprendizaje, intento_id) is None:
        raise HTTPException(status_code=404, detail="Intento no encontrado.")
    revision = await sesion.get(RevisionIntento, intento_id)
    if revision is None:
        revision = RevisionIntento(intento_id=intento_id)
        sesion.add(revision)
    revision.docente_id = docente.id
    revision.comprension = rubrica.comprension
    revision.codigo = rubrica.codigo
    revision.casos_limite = rubrica.casos_limite
    revision.observaciones = rubrica.observaciones.strip()
    await sesion.commit()
    return {"intento_id": str(intento_id), "puntaje": sum((rubrica.comprension, rubrica.codigo, rubrica.casos_limite)),
            "estado": "revisado_por_docente"}
