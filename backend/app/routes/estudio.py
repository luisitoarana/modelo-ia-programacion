"""Pre/post independientes: sin IA, con envío explícito y revisión humana."""
from datetime import datetime, timezone
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm.exc import StaleDataError

from app.core.security import obtener_usuario_actual, requerir_rol
from app.database import get_db
from app.models.usuario import Usuario, RolUsuario
from app.models.intento_aprendizaje import AsignacionEstudio
from app.models.estudio import ConfiguracionEstudio, EntregaEstudio
from app.routes.aprendizaje import RubricaDocente
from app.services.estudio_service import BANCO, VERSION, configuracion, preguntas, puntaje, comparar

router = APIRouter()
DB = Annotated[AsyncSession, Depends(get_db)]
Actual = Annotated[Usuario, Depends(obtener_usuario_actual)]
Docente = Annotated[Usuario, Depends(requerir_rol(RolUsuario.ADMINISTRADOR, RolUsuario.INVESTIGADOR))]


class Configurar(BaseModel):
    estudio_activo: bool = False
    pre_abierto: bool
    post_abierto: bool
    practica_guiada: bool
    preguntas_activas: list[str] = Field(min_length=1, max_length=6)


class Respuesta(BaseModel):
    codigo: str = Field(default='', max_length=20000)
    explicacion: str = Field(default='', max_length=10000)
    sin_responder: bool = False


class Guardar(BaseModel):
    respuestas: dict[str, Respuesta] = Field(max_length=6)
    finalizar: bool = False
    revision: int = Field(ge=1)


async def persistir(db):
    try:
        await db.commit()
    except (IntegrityError, StaleDataError) as exc:
        await db.rollback()
        raise HTTPException(409, 'Otra solicitud modificó la entrega. Actualiza antes de continuar.') from exc


def serializar(e, docente=False):
    def utc(fecha):
        return fecha.replace(tzinfo=timezone.utc) if fecha and fecha.tzinfo is None else fecha
    datos = dict(id=str(e.id), fase=e.fase, condicion=e.condicion, version=e.version,
                 estado=e.estado, preguntas=e.preguntas, respuestas=e.respuestas,
                 iniciada_en=utc(e.fecha_creacion), enviada_en=utc(e.enviada_en), revision=e.revision)
    if docente:
        datos.update(usuario_id=str(e.usuario_id), seudonimo='P-' + e.usuario_id.hex[:8],
                     revisiones=e.revisiones, puntaje=puntaje(e), maximo=len(e.preguntas)*10)
    return datos


@router.get('/configuracion')
async def leer_configuracion(_u: Docente, db: DB):
    return dict(**await configuracion(db), banco=BANCO, version=VERSION)


@router.put('/configuracion')
async def guardar_configuracion(datos: Configurar, _u: Docente, db: DB):
    ids = datos.preguntas_activas
    if len(ids) != len(set(ids)) or set(ids) - {p['id'] for p in BANCO}:
        raise HTTPException(422, 'Selecciona preguntas existentes, sin duplicados.')
    if {p['modulo'] for p in BANCO if p['id'] in ids} != {1, 2, 3}:
        raise HTTPException(422, 'Conserva al menos una pregunta de cada módulo.')
    fila = await db.get(ConfiguracionEstudio, 1)
    if fila is None:
        fila = ConfiguracionEstudio(id=1)
        db.add(fila)
    fila.datos = datos.model_dump()
    await persistir(db)
    return dict(estado='configurado')


@router.get('/actual')
async def actual(u: Actual, db: DB):
    asignacion = await db.get(AsignacionEstudio, u.id)
    cfg = await configuracion(db)
    if not asignacion:
        return dict(asignado=False, fase=None, abierto=False,
                    pendiente_asignacion=cfg['estudio_activo'] and u.rol == RolUsuario.ESTUDIANTE)
    fase = asignacion.fase
    entrega = await db.scalar(select(EntregaEstudio).where(EntregaEstudio.usuario_id == u.id, EntregaEstudio.fase == fase))
    return dict(asignado=True, fase=fase, condicion=asignacion.condicion,
                abierto=cfg.get(fase + '_abierto', False), practica_guiada=cfg['practica_guiada'],
                entrega=serializar(entrega) if entrega else None,
                tareas=[dict(id=p['id'], modulo=p['modulo'], consigna=p['practica']) for p in BANCO]
                if fase == 'intervencion' else [])


@router.get('/docente/vista-previa/{fase}')
async def vista_previa(fase: str, _u: Docente, db: DB):
    """Inspección docente incluso con la evaluación cerrada; no crea entregas."""
    if fase not in ('pre', 'post'):
        raise HTTPException(422, 'Selecciona pre o post.')
    cfg = await configuracion(db)
    return dict(fase=fase, version=VERSION, vista_previa=True,
                abierto_estudiantes=cfg[fase + '_abierto'],
                preguntas=preguntas(fase, cfg['preguntas_activas']))


@router.post('/iniciar')
async def iniciar(u: Actual, db: DB):
    if u.rol != RolUsuario.ESTUDIANTE:
        raise HTTPException(403, 'Usa una cuenta de estudiante para rendir el instrumento.')
    a = await db.get(AsignacionEstudio, u.id)
    if not a or a.fase not in ('pre', 'post'):
        raise HTTPException(409, 'El docente debe asignar una fase pre o post.')
    cfg = await configuracion(db)
    if not cfg[a.fase + '_abierto']:
        raise HTTPException(403, 'El docente todavía no ha abierto esta evaluación.')
    existente = await db.scalar(select(EntregaEstudio).where(EntregaEstudio.usuario_id == u.id, EntregaEstudio.fase == a.fase))
    if existente:
        return serializar(existente)
    pre = await db.scalar(select(EntregaEstudio).where(EntregaEstudio.usuario_id == u.id, EntregaEstudio.fase == 'pre'))
    if a.fase == 'post' and (not pre or pre.estado != 'enviado'):
        raise HTTPException(409, 'Primero se necesita un pretest enviado, incluso si hubo preguntas sin responder.')
    ids = [p['id'] for p in pre.preguntas] if a.fase == 'post' else cfg['preguntas_activas']
    e = EntregaEstudio(usuario_id=u.id, fase=a.fase, condicion=a.condicion, version=VERSION,
                      preguntas=preguntas(a.fase, ids), respuestas={}, revisiones={})
    db.add(e)
    await persistir(db)
    await db.refresh(e)
    return serializar(e)


@router.put('/entregas/{entrega_id}')
async def guardar(entrega_id: UUID, datos: Guardar, u: Actual, db: DB):
    e = await db.get(EntregaEstudio, entrega_id)
    if not e or e.usuario_id != u.id:
        raise HTTPException(404, 'Entrega no encontrada.')
    a = await db.get(AsignacionEstudio, u.id)
    if not a or a.fase != e.fase:
        raise HTTPException(403, 'Esta entrega pertenece a otra fase del estudio.')
    if e.estado == 'enviado':
        if datos.finalizar:
            return serializar(e)
        raise HTTPException(409, 'La entrega final no se puede modificar.')
    cfg = await configuracion(db)
    if not a or a.fase != e.fase or a.condicion != e.condicion or not cfg[e.fase + '_abierto']:
        raise HTTPException(403, 'La fase está cerrada o la asignación cambió. El borrador anterior se conserva.')
    if datos.revision != e.revision:
        raise HTTPException(409, 'Hay una versión más reciente. Actualiza la entrega.')
    ids = {p['id'] for p in e.preguntas}
    if set(datos.respuestas) - ids:
        raise HTTPException(422, 'La respuesta no pertenece a este instrumento.')
    respuestas = dict(e.respuestas)
    for clave, valor in datos.respuestas.items():
        r = valor.model_dump()
        if r['sin_responder'] and (r['codigo'].strip() or r['explicacion'].strip()):
            raise HTTPException(422, 'No marques sin responder una pregunta que contiene texto.')
        respuestas[clave] = r
    if datos.finalizar:
        for clave in ids:
            respuestas.setdefault(clave, dict(codigo='', explicacion='', sin_responder=True))
            if not respuestas[clave]['codigo'].strip() and not respuestas[clave]['explicacion'].strip():
                respuestas[clave]['sin_responder'] = True
        e.estado = 'enviado'
        e.enviada_en = datetime.now(timezone.utc)
    e.respuestas = respuestas
    await persistir(db)
    await db.refresh(e)
    return serializar(e)


@router.get('/docente/resumen')
async def resumen(_u: Docente, db: DB):
    usuarios = list((await db.scalars(select(Usuario).where(Usuario.rol == RolUsuario.ESTUDIANTE).order_by(Usuario.fecha_creacion))).all())
    entregas = list((await db.scalars(select(EntregaEstudio).order_by(EntregaEstudio.fecha_creacion))).all())
    asignaciones = {a.usuario_id: a for a in (await db.scalars(select(AsignacionEstudio))).all()}
    participantes = []
    for u in usuarios:
        propias = {e.fase: e for e in entregas if e.usuario_id == u.id}
        a = asignaciones.get(u.id)
        participantes.append(dict(usuario_id=str(u.id), nombre=u.nombre, email=u.email,
                                  seudonimo='P-' + u.id.hex[:8], demostracion=u.email == 'demo.estudiante@example.org',
                                  condicion=a.condicion if a else None, fase=a.fase if a else None,
                                  comparacion=comparar(propias.get('pre'), propias.get('post'))))
    return dict(participantes=participantes, entregas=[serializar(e, True) for e in entregas], version=VERSION)


@router.put('/docente/autorizar/{usuario_id}')
async def autorizar_docente(usuario_id: UUID, _admin: Annotated[Usuario, Depends(requerir_rol(RolUsuario.ADMINISTRADOR))], db: DB):
    u = await db.get(Usuario, usuario_id)
    if not u:
        raise HTTPException(404, 'Usuario no encontrado.')
    if u.email.lower() == 'demo.estudiante@example.org':
        raise HTTPException(409, 'La cuenta pública de demostración nunca puede ser docente.')
    entrega = await db.scalar(select(EntregaEstudio.id).where(EntregaEstudio.usuario_id == usuario_id).limit(1))
    if entrega or u.rol != RolUsuario.ESTUDIANTE:
        raise HTTPException(409, 'Utiliza una cuenta nueva de docente, sin entregas de participante.')
    u.rol = RolUsuario.INVESTIGADOR
    await persistir(db)
    return dict(estado='docente_autorizado', usuario_id=str(usuario_id))


@router.put('/docente/entregas/{entrega_id}/preguntas/{pregunta_id}')
async def revisar(entrega_id: UUID, pregunta_id: str, rubrica: RubricaDocente, docente: Docente, db: DB):
    e = await db.get(EntregaEstudio, entrega_id)
    if not e or pregunta_id not in {p['id'] for p in e.preguntas}:
        raise HTTPException(404, 'Entrega o pregunta no encontrada.')
    if e.estado != 'enviado':
        raise HTTPException(409, 'Solo se califican entregas finales.')
    e.revisiones = dict(e.revisiones, **{pregunta_id: dict(**rubrica.model_dump(),
        docente_id=str(docente.id), revisada_en=datetime.now(timezone.utc).isoformat())})
    await persistir(db)
    return dict(estado='revisado_por_docente', puntaje=puntaje(e))
