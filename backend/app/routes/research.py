"""Rutas para reportes y métricas de investigación científica."""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import requerir_rol
from app.database import get_db
from app.models.consulta import Consulta, EstadoConsulta, FuenteIA
from app.models.dataset import DatasetEducativo, NivelEducativo, TemaProgramacion
from app.models.evaluacion import Evaluacion
from app.models.usuario import RolUsuario, Usuario


router = APIRouter()


@router.get("/reporte-general", summary="Reporte global para la investigación")
async def reporte_general(
    sesion: Annotated[AsyncSession, Depends(get_db)],
    _u: Annotated[
        Usuario,
        Depends(requerir_rol(RolUsuario.INVESTIGADOR, RolUsuario.ADMINISTRADOR)),
    ],
) -> dict[str, object]:
    usuarios_total = await sesion.scalar(select(func.count(Usuario.id))) or 0
    consultas_total = await sesion.scalar(select(func.count(Consulta.id))) or 0
    consultas_ok = await sesion.scalar(
        select(func.count(Consulta.id)).where(
            Consulta.estado == EstadoConsulta.COMPLETADA
        )
    ) or 0
    consultas_fallidas = await sesion.scalar(
        select(func.count(Consulta.id)).where(
            Consulta.estado == EstadoConsulta.FALLIDA
        )
    ) or 0
    dataset_total = await sesion.scalar(select(func.count(DatasetEducativo.id))) or 0
    dataset_validado = await sesion.scalar(
        select(func.count(DatasetEducativo.id)).where(
            DatasetEducativo.validado.is_(True)
        )
    ) or 0
    latencia_promedio = await sesion.scalar(
        select(func.avg(Consulta.latencia_segundos)).where(
            Consulta.estado == EstadoConsulta.COMPLETADA
        )
    )

    por_fuente: dict[str, int] = {}
    for fuente in FuenteIA:
        cnt = await sesion.scalar(
            select(func.count(Consulta.id)).where(Consulta.modelo_usado == fuente)
        ) or 0
        por_fuente[fuente.value] = int(cnt)

    por_nivel: dict[str, int] = {}
    for nivel in NivelEducativo:
        cnt = await sesion.scalar(
            select(func.count(DatasetEducativo.id)).where(
                DatasetEducativo.nivel == nivel
            )
        ) or 0
        por_nivel[nivel.value] = int(cnt)

    por_tema: dict[str, int] = {}
    for tema in TemaProgramacion:
        cnt = await sesion.scalar(
            select(func.count(DatasetEducativo.id)).where(
                DatasetEducativo.tema == tema
            )
        ) or 0
        por_tema[tema.value] = int(cnt)

    puntaje_promedio = await sesion.scalar(
        select(func.avg(Evaluacion.puntaje)).where(
            Evaluacion.tipo_actividad != "explicacion_libre"
        )
    )

    return {
        "usuarios_total": int(usuarios_total),
        "consultas": {
            "total": int(consultas_total),
            "completadas": int(consultas_ok),
            "fallidas": int(consultas_fallidas),
            "latencia_promedio_seg": float(latencia_promedio or 0.0),
            "por_fuente": por_fuente,
        },
        "dataset": {
            "total": int(dataset_total),
            "validados": int(dataset_validado),
            "por_nivel": por_nivel,
            "por_tema": por_tema,
        },
        "evaluaciones": {
            "puntaje_promedio": float(puntaje_promedio or 0.0),
        },
    }
