"""Generador de conocimiento dirigido por currículo.

Aquí es donde las APIs (Gemini / DeepSeek) cumplen su rol CORRECTO según la
investigación: son HERRAMIENTAS para poblar la base de conocimiento de forma
proactiva y sistemática, no el motor final.

Flujo por cada ítem del currículo:
    prompt semilla → API genera → validación de calidad (QualityEvaluator)
    → si aprueba: se almacena como UnidadConocimiento (candidato/validado)
    → si no aprueba: se descarta o se marca rechazado (con su puntaje)

Incluye comparación de proveedores: generar el mismo ítem con Gemini y
DeepSeek y contrastar la calidad — evidencia directa para la tesis.
"""

from __future__ import annotations

from dataclasses import dataclass, field

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.domain.curriculo import CURRICULO, ItemCurriculo
from app.models.conocimiento import (
    EstadoConocimiento,
    OrigenConocimiento,
    UnidadConocimiento,
)
from app.models.dataset import NivelEducativo, TemaProgramacion
from app.schemas.ai_response import RespuestaIAEducativa
from app.services.explanation_service import (
    ExplanationService,
    ExplicacionServiceError,
)
from app.services.quality_service import QualityEvaluator, ResultadoCalidad
from app.services.retrieval_service import construir_indice_texto
from app.utils.logger import obtener_logger


log = obtener_logger(__name__)

_ORIGEN_POR_PROVEEDOR = {
    "gemini": OrigenConocimiento.GENERADO_GEMINI,
    "deepseek": OrigenConocimiento.GENERADO_DEEPSEEK,
}


def _nivel(valor: str) -> NivelEducativo:
    try:
        return NivelEducativo(valor)
    except ValueError:
        return NivelEducativo.BASICO


def _tema(valor: str) -> TemaProgramacion:
    try:
        return TemaProgramacion(valor)
    except ValueError:
        return TemaProgramacion.OTRO


@dataclass(slots=True)
class ResultadoGeneracionItem:
    codigo_curriculo: str
    titulo: str
    proveedor: str
    exito: bool
    puntaje_calidad: float = 0.0
    aprobado: bool = False
    almacenado: bool = False
    unidad_id: str | None = None
    error: str | None = None


@dataclass(slots=True)
class ResumenGeneracion:
    total_items: int
    generados: int = 0
    aprobados: int = 0
    almacenados: int = 0
    fallidos: int = 0
    detalles: list[ResultadoGeneracionItem] = field(default_factory=list)


class KnowledgeGenerationService:
    """Orquesta la generación proactiva de conocimiento por currículo."""

    def __init__(
        self,
        sesion: AsyncSession,
        *,
        explanation_service: ExplanationService | None = None,
        quality_evaluator: QualityEvaluator | None = None,
        autovalidar_si_aprueba: bool = False,
    ) -> None:
        self.sesion = sesion
        self.explanation = explanation_service or ExplanationService()
        self.quality = quality_evaluator or QualityEvaluator()
        # Si True, las unidades que pasan el filtro automático quedan VALIDADO
        # (reutilizables de inmediato). Si False, quedan CANDIDATO a revisión
        # humana. Para rigor científico, por defecto exige revisión humana.
        self.autovalidar = autovalidar_si_aprueba

    async def generar_item(
        self,
        item: ItemCurriculo,
        *,
        proveedor: str = "gemini",
        reemplazar: bool = False,
    ) -> ResultadoGeneracionItem:
        """Genera, valida y (si corresponde) almacena un ítem del currículo."""
        origen = _ORIGEN_POR_PROVEEDOR.get(proveedor, OrigenConocimiento.GENERADO_GEMINI)

        existente = await self.sesion.scalar(
            select(UnidadConocimiento).where(
                UnidadConocimiento.codigo_curriculo == item.codigo,
                UnidadConocimiento.origen == origen,
            )
        )
        if existente and not reemplazar:
            return ResultadoGeneracionItem(
                codigo_curriculo=item.codigo,
                titulo=item.titulo,
                proveedor=proveedor,
                exito=True,
                puntaje_calidad=existente.puntaje_calidad,
                aprobado=existente.estado != EstadoConocimiento.RECHAZADO,
                almacenado=False,
                unidad_id=str(existente.id),
            )

        try:
            resultado = await self.explanation.explicar(
                prompt_estudiante=item.prompt_semilla,
                proveedor_nombre=proveedor,
                nivel=item.nivel,
                tema=item.tema,
            )
        except ExplicacionServiceError as exc:
            log.warning("Generación falló para %s (%s): %s", item.codigo, proveedor, exc)
            return ResultadoGeneracionItem(
                codigo_curriculo=item.codigo,
                titulo=item.titulo,
                proveedor=proveedor,
                exito=False,
                error=str(exc)[:500],
            )

        respuesta = resultado.respuesta
        calidad = self.quality.evaluar(respuesta)

        if existente and reemplazar:
            await self.sesion.delete(existente)
            await self.sesion.flush()

        unidad = await self._almacenar(
            item=item,
            respuesta=respuesta,
            calidad=calidad,
            origen=origen,
        )

        return ResultadoGeneracionItem(
            codigo_curriculo=item.codigo,
            titulo=item.titulo,
            proveedor=proveedor,
            exito=True,
            puntaje_calidad=calidad.puntaje_total,
            aprobado=calidad.aprobado,
            almacenado=True,
            unidad_id=str(unidad.id),
        )

    async def _almacenar(
        self,
        *,
        item: ItemCurriculo,
        respuesta: RespuestaIAEducativa,
        calidad: ResultadoCalidad,
        origen: OrigenConocimiento,
    ) -> UnidadConocimiento:
        if not calidad.aprobado:
            estado = EstadoConocimiento.RECHAZADO
        elif self.autovalidar:
            estado = EstadoConocimiento.VALIDADO
        else:
            estado = EstadoConocimiento.CANDIDATO

        texto_busqueda, keywords = construir_indice_texto(
            pregunta=item.prompt_semilla,
            tema=item.tema,
            nivel=item.nivel,
            conceptos=[c.concepto for c in respuesta.conceptos_clave]
            + item.conceptos_esperados,
            objetivo=item.objetivo_aprendizaje,
        )

        unidad = UnidadConocimiento(
            codigo_curriculo=item.codigo,
            nivel=_nivel(respuesta.nivel),
            tema=_tema(respuesta.tema),
            objetivo_aprendizaje=item.objetivo_aprendizaje,
            pregunta_canonica=item.prompt_semilla,
            codigo=respuesta.codigo,
            explicacion_general=respuesta.explicacion_general,
            respuesta_json=respuesta.model_dump(mode="json"),
            texto_busqueda=texto_busqueda,
            keywords=keywords,
            origen=origen,
            estado=estado,
            puntaje_calidad=calidad.puntaje_total,
            dimensiones_calidad=calidad.to_dict(),
        )
        self.sesion.add(unidad)
        await self.sesion.flush()
        return unidad

    async def generar_curriculo(
        self,
        *,
        proveedor: str = "gemini",
        nivel: str | None = None,
        limite: int | None = None,
        reemplazar: bool = False,
    ) -> ResumenGeneracion:
        """Genera conocimiento para (un subconjunto de) el currículo."""
        items = [i for i in CURRICULO if nivel is None or i.nivel == nivel]
        if limite is not None:
            items = items[:limite]

        resumen = ResumenGeneracion(total_items=len(items))
        for item in items:
            detalle = await self.generar_item(
                item, proveedor=proveedor, reemplazar=reemplazar
            )
            resumen.detalles.append(detalle)
            if detalle.exito:
                resumen.generados += 1
                if detalle.aprobado:
                    resumen.aprobados += 1
                if detalle.almacenado:
                    resumen.almacenados += 1
            else:
                resumen.fallidos += 1

        await self.sesion.flush()
        return resumen

    async def comparar_proveedores(
        self, item: ItemCurriculo
    ) -> dict[str, ResultadoGeneracionItem]:
        """Genera el mismo ítem con Gemini y DeepSeek para comparar calidad."""
        salida: dict[str, ResultadoGeneracionItem] = {}
        for proveedor in ("gemini", "deepseek"):
            salida[proveedor] = await self.generar_item(
                item, proveedor=proveedor, reemplazar=True
            )
        return salida
