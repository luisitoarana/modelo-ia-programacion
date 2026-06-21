"""Servicio de dataset educativo: persistencia y exportación JSONL."""

from __future__ import annotations

import json
import uuid
from pathlib import Path

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.consulta import FuenteIA
from app.models.dataset import DatasetEducativo, NivelEducativo, TemaProgramacion
from app.schemas.ai_response import RespuestaIAEducativa
from app.schemas.dataset import ExportacionJSONLPar
from app.utils.logger import obtener_logger


log = obtener_logger(__name__)


def _mapear_nivel(valor: str) -> NivelEducativo:
    try:
        return NivelEducativo(valor)
    except ValueError:
        return NivelEducativo.BASICO


def _mapear_tema(valor: str) -> TemaProgramacion:
    try:
        return TemaProgramacion(valor)
    except ValueError:
        return TemaProgramacion.OTRO


def _mapear_fuente(valor: str) -> FuenteIA:
    try:
        return FuenteIA(valor)
    except ValueError:
        return FuenteIA.GEMINI


class DatasetService:
    """Operaciones de alto nivel sobre el dataset educativo."""

    def __init__(self, sesion: AsyncSession) -> None:
        self.sesion = sesion

    async def registrar_desde_respuesta(
        self,
        *,
        usuario_id: uuid.UUID,
        consulta_id: uuid.UUID,
        respuesta: RespuestaIAEducativa,
    ) -> DatasetEducativo:
        """Crea (o reemplaza) el dataset educativo asociado a una consulta."""
        existente = await self.sesion.scalar(
            select(DatasetEducativo).where(DatasetEducativo.consulta_id == consulta_id)
        )
        if existente:
            log.info("Dataset existente para consulta %s, sobrescribiendo.", consulta_id)
            await self.sesion.delete(existente)
            await self.sesion.flush()

        registro = DatasetEducativo(
            usuario_id=usuario_id,
            consulta_id=consulta_id,
            nivel=_mapear_nivel(respuesta.nivel),
            tema=_mapear_tema(respuesta.tema),
            pregunta=respuesta.pregunta,
            codigo=respuesta.codigo,
            explicacion_general=respuesta.explicacion_general,
            respuesta_json=respuesta.model_dump(mode="json"),
            conceptos_json={"conceptos": [c.model_dump() for c in respuesta.conceptos_clave]},
            actividad_json=(
                respuesta.actividad_evaluativa.model_dump()
                if respuesta.actividad_evaluativa
                else None
            ),
            complejidad_json=(
                respuesta.analisis_complejidad.model_dump()
                if respuesta.analisis_complejidad
                else None
            ),
            explicacion_linea_json=[
                linea.model_dump() for linea in respuesta.explicacion_linea_por_linea
            ],
            fuente_ia=_mapear_fuente(respuesta.fuente_ia),
            validado=False,
        )
        self.sesion.add(registro)
        await self.sesion.flush()
        return registro

    async def marcar_validacion(
        self,
        *,
        dataset_id: uuid.UUID,
        validado: bool,
        validado_por: str,
        observaciones: str | None,
    ) -> DatasetEducativo:
        registro = await self.sesion.get(DatasetEducativo, dataset_id)
        if registro is None:
            raise LookupError(f"Dataset {dataset_id} no existe")
        registro.validado = validado
        registro.validado_por = validado_por
        registro.observaciones_validacion = observaciones
        await self.sesion.flush()
        return registro

    async def listar(
        self,
        *,
        solo_validados: bool = False,
        limite: int = 100,
    ) -> list[DatasetEducativo]:
        consulta = select(DatasetEducativo).order_by(
            DatasetEducativo.fecha_creacion.desc()
        )
        if solo_validados:
            consulta = consulta.where(DatasetEducativo.validado.is_(True))
        consulta = consulta.limit(limite)
        return list((await self.sesion.scalars(consulta)).all())

    async def exportar_jsonl(
        self,
        ruta_salida: Path,
        *,
        solo_validados: bool = True,
    ) -> tuple[int, Path]:
        """Exporta dataset como pares instruction/response en JSONL.

        Devuelve (cantidad_escrita, ruta_archivo).
        """
        registros = await self.listar(solo_validados=solo_validados, limite=10_000)
        ruta_salida.parent.mkdir(parents=True, exist_ok=True)
        cantidad = 0
        with ruta_salida.open("w", encoding="utf-8") as f:
            for reg in registros:
                par = self._a_par_finetuning(reg)
                f.write(json.dumps(par.model_dump(), ensure_ascii=False) + "\n")
                reg.exportado_para_finetuning = True
                cantidad += 1
        await self.sesion.flush()
        log.info("Exportados %s registros a %s", cantidad, ruta_salida)
        return cantidad, ruta_salida

    @staticmethod
    def _a_par_finetuning(reg: DatasetEducativo) -> ExportacionJSONLPar:
        """Convierte un registro en un par estilo Alpaca (instruction/output)."""
        instruccion = (
            "Explica y genera código Python para la siguiente solicitud "
            f"de un estudiante de nivel {reg.nivel.value} sobre el tema "
            f"{reg.tema.value}. Responde con JSON estructurado pedagógico."
        )
        salida = json.dumps(reg.respuesta_json, ensure_ascii=False)
        return ExportacionJSONLPar(
            instruction=instruccion,
            input=reg.pregunta,
            output=salida,
            metadata={
                "fuente_ia": reg.fuente_ia.value,
                "nivel": reg.nivel.value,
                "tema": reg.tema.value,
                "validado": reg.validado,
                "dataset_id": str(reg.id),
            },
        )

    async def estadisticas(self) -> dict[str, int]:
        total = await self.sesion.scalar(select(func.count(DatasetEducativo.id))) or 0
        validados = await self.sesion.scalar(
            select(func.count(DatasetEducativo.id)).where(
                DatasetEducativo.validado.is_(True)
            )
        ) or 0
        exportados = await self.sesion.scalar(
            select(func.count(DatasetEducativo.id)).where(
                DatasetEducativo.exportado_para_finetuning.is_(True)
            )
        ) or 0
        return {
            "total": int(total),
            "validados": int(validados),
            "exportados_finetuning": int(exportados),
            "pendientes_validacion": int(total) - int(validados),
        }
