"""Rutas del núcleo científico: generación y curaduría de conocimiento.

Estas rutas materializan el flujo de la investigación:
    currículo → generación (API auxiliar) → validación de calidad →
    base de conocimiento → reutilización (menos dependencia de API).
"""

from __future__ import annotations

import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import requerir_rol
from app.database import get_db
from app.domain import curriculo as cur
from app.models.conocimiento import (
    EstadoConocimiento,
    UnidadConocimiento,
)
from app.models.consulta import Consulta
from app.models.usuario import RolUsuario, Usuario
from app.schemas.conocimiento import (
    EstadisticasConocimiento,
    ItemCurriculoOut,
    ResultadoItemOut,
    ResumenGeneracionOut,
    SolicitudGeneracionCurriculo,
    UnidadConocimientoLeer,
    ValidacionUnidad,
)
from app.services.knowledge_generation_service import KnowledgeGenerationService


router = APIRouter()

_SOLO_INVESTIGADOR = requerir_rol(RolUsuario.INVESTIGADOR, RolUsuario.ADMINISTRADOR)


@router.get("/curriculo", response_model=list[ItemCurriculoOut], summary="Ver el currículo")
async def ver_curriculo(
    _u: Annotated[Usuario, Depends(_SOLO_INVESTIGADOR)],
) -> list[ItemCurriculoOut]:
    return [
        ItemCurriculoOut(
            codigo=i.codigo,
            nivel=i.nivel,
            tema=i.tema,
            titulo=i.titulo,
            objetivo_aprendizaje=i.objetivo_aprendizaje,
            prompt_semilla=i.prompt_semilla,
            conceptos_esperados=list(i.conceptos_esperados),
        )
        for i in cur.CURRICULO
    ]


@router.post(
    "/generar-item/{codigo}",
    response_model=ResultadoItemOut,
    summary="Generar conocimiento para un ítem del currículo",
)
async def generar_item(
    codigo: str,
    sesion: Annotated[AsyncSession, Depends(get_db)],
    _u: Annotated[Usuario, Depends(_SOLO_INVESTIGADOR)],
    proveedor: str = "gemini",
    reemplazar: bool = False,
    autovalidar: bool = False,
) -> ResultadoItemOut:
    item = cur.obtener_item(codigo)
    if item is None:
        raise HTTPException(status_code=404, detail=f"Ítem '{codigo}' no existe.")
    servicio = KnowledgeGenerationService(
        sesion, autovalidar_si_aprueba=autovalidar
    )
    detalle = await servicio.generar_item(item, proveedor=proveedor, reemplazar=reemplazar)
    await sesion.commit()
    return ResultadoItemOut(**detalle.__dict__)


@router.post(
    "/generar-curriculo",
    response_model=ResumenGeneracionOut,
    summary="Generar conocimiento para el currículo completo o un subconjunto",
)
async def generar_curriculo(
    payload: SolicitudGeneracionCurriculo,
    sesion: Annotated[AsyncSession, Depends(get_db)],
    _u: Annotated[Usuario, Depends(_SOLO_INVESTIGADOR)],
) -> ResumenGeneracionOut:
    servicio = KnowledgeGenerationService(
        sesion, autovalidar_si_aprueba=payload.autovalidar_si_aprueba
    )
    resumen = await servicio.generar_curriculo(
        proveedor=payload.proveedor,
        nivel=payload.nivel,
        limite=payload.limite,
        reemplazar=payload.reemplazar,
    )
    await sesion.commit()
    return ResumenGeneracionOut(
        total_items=resumen.total_items,
        generados=resumen.generados,
        aprobados=resumen.aprobados,
        almacenados=resumen.almacenados,
        fallidos=resumen.fallidos,
        detalles=[ResultadoItemOut(**d.__dict__) for d in resumen.detalles],
    )


@router.get(
    "/comparar/{codigo}",
    summary="Comparar la calidad de Gemini vs DeepSeek para un ítem",
)
async def comparar_proveedores(
    codigo: str,
    sesion: Annotated[AsyncSession, Depends(get_db)],
    _u: Annotated[Usuario, Depends(_SOLO_INVESTIGADOR)],
) -> dict[str, ResultadoItemOut]:
    item = cur.obtener_item(codigo)
    if item is None:
        raise HTTPException(status_code=404, detail=f"Ítem '{codigo}' no existe.")
    servicio = KnowledgeGenerationService(sesion)
    comparacion = await servicio.comparar_proveedores(item)
    await sesion.commit()
    return {k: ResultadoItemOut(**v.__dict__) for k, v in comparacion.items()}


@router.get(
    "/unidades",
    response_model=list[UnidadConocimientoLeer],
    summary="Listar unidades de la base de conocimiento",
)
async def listar_unidades(
    sesion: Annotated[AsyncSession, Depends(get_db)],
    _u: Annotated[Usuario, Depends(_SOLO_INVESTIGADOR)],
    estado: str | None = None,
    limite: int = 100,
) -> list[UnidadConocimiento]:
    stmt = select(UnidadConocimiento).order_by(
        UnidadConocimiento.puntaje_calidad.desc()
    )
    if estado:
        try:
            stmt = stmt.where(UnidadConocimiento.estado == EstadoConocimiento(estado))
        except ValueError:
            raise HTTPException(status_code=400, detail=f"Estado inválido: {estado}")
    stmt = stmt.limit(min(max(limite, 1), 500))
    return list((await sesion.scalars(stmt)).all())


@router.post(
    "/unidad/{unidad_id}/validar",
    response_model=UnidadConocimientoLeer,
    summary="Validar o rechazar una unidad de conocimiento",
)
async def validar_unidad(
    unidad_id: uuid.UUID,
    datos: ValidacionUnidad,
    sesion: Annotated[AsyncSession, Depends(get_db)],
    _u: Annotated[Usuario, Depends(_SOLO_INVESTIGADOR)],
) -> UnidadConocimiento:
    unidad = await sesion.get(UnidadConocimiento, unidad_id)
    if unidad is None:
        raise HTTPException(status_code=404, detail="Unidad no encontrada.")
    unidad.estado = (
        EstadoConocimiento.VALIDADO if datos.aprobar else EstadoConocimiento.RECHAZADO
    )
    unidad.validado_por = datos.validado_por
    unidad.observaciones_validacion = datos.observaciones
    await sesion.commit()
    await sesion.refresh(unidad)
    return unidad


@router.get(
    "/estadisticas",
    response_model=EstadisticasConocimiento,
    summary="Métricas de la base de conocimiento e independencia de APIs",
)
async def estadisticas_conocimiento(
    sesion: Annotated[AsyncSession, Depends(get_db)],
    _u: Annotated[Usuario, Depends(_SOLO_INVESTIGADOR)],
) -> EstadisticasConocimiento:
    total = await sesion.scalar(select(func.count(UnidadConocimiento.id))) or 0
    validadas = await sesion.scalar(
        select(func.count(UnidadConocimiento.id)).where(
            UnidadConocimiento.estado == EstadoConocimiento.VALIDADO
        )
    ) or 0
    candidatas = await sesion.scalar(
        select(func.count(UnidadConocimiento.id)).where(
            UnidadConocimiento.estado == EstadoConocimiento.CANDIDATO
        )
    ) or 0
    rechazadas = await sesion.scalar(
        select(func.count(UnidadConocimiento.id)).where(
            UnidadConocimiento.estado == EstadoConocimiento.RECHAZADO
        )
    ) or 0
    reutilizaciones = await sesion.scalar(
        select(func.coalesce(func.sum(UnidadConocimiento.veces_reutilizada), 0))
    ) or 0

    consultas_total = await sesion.scalar(select(func.count(Consulta.id))) or 0
    desde_base = await sesion.scalar(
        select(func.count(Consulta.id)).where(
            Consulta.origen_respuesta == "base_conocimiento"
        )
    ) or 0
    por_api = int(consultas_total) - int(desde_base)

    tasa_independencia = (
        round((int(desde_base) / int(consultas_total)) * 100, 1)
        if consultas_total else 0.0
    )

    # Cobertura del currículo: ítems con al menos una unidad validada.
    codigos_validados = set(
        (
            await sesion.scalars(
                select(UnidadConocimiento.codigo_curriculo).where(
                    UnidadConocimiento.estado == EstadoConocimiento.VALIDADO,
                    UnidadConocimiento.codigo_curriculo.is_not(None),
                )
            )
        ).all()
    )
    total_curriculo = cur.total_items()
    cobertura = (
        round((len(codigos_validados) / total_curriculo) * 100, 1)
        if total_curriculo else 0.0
    )

    return EstadisticasConocimiento(
        total_unidades=int(total),
        validadas=int(validadas),
        candidatas=int(candidatas),
        rechazadas=int(rechazadas),
        reutilizaciones_totales=int(reutilizaciones),
        consultas_totales=int(consultas_total),
        respondidas_desde_base=int(desde_base),
        respondidas_por_api=int(por_api),
        tasa_independencia_api=tasa_independencia,
        cobertura_curriculo=cobertura,
    )
