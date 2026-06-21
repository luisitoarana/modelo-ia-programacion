"""Motor educativo retrieval-first: el cerebro del sistema.

Este es el componente que corrige la desviación arquitectónica señalada en
la auditoría científica. En lugar de ser un intermediario que siempre llama
a una API externa, el motor:

    1) BUSCA primero en la base de conocimiento propia (UnidadConocimiento).
    2) Si encuentra una unidad validada suficientemente similar → responde
       desde el conocimiento propio (origen = "base_conocimiento"), SIN API.
    3) Solo si no hay match → usa la API como herramienta auxiliar, valida la
       calidad y ALMACENA el resultado como nuevo conocimiento candidato,
       de modo que el sistema aprende y la próxima vez no necesitará la API.

Así, conforme crece la base, el sistema depende cada vez menos de las APIs.
Las métricas de reutilización son evidencia directa para la investigación.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Literal

from sqlalchemy.ext.asyncio import AsyncSession

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
from app.services.retrieval_service import RetrievalService, construir_indice_texto
from app.utils.logger import obtener_logger


log = obtener_logger(__name__)

OrigenRespuesta = Literal["base_conocimiento", "api"]


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
class RespuestaMotor:
    """Resultado del motor educativo, con trazabilidad de procedencia."""

    respuesta: RespuestaIAEducativa
    origen: OrigenRespuesta
    score_recuperacion: float = 0.0
    unidad_id: str | None = None
    calidad: ResultadoCalidad | None = None
    intentos_reparacion: int = 0
    tokens_totales: int = 0
    latencia_segundos: float = 0.0
    proveedor: str | None = None


class EducationalEngine:
    """Orquestador educativo con estrategia recuperación-primero."""

    def __init__(
        self,
        sesion: AsyncSession,
        *,
        retrieval: RetrievalService | None = None,
        explanation: ExplanationService | None = None,
        quality: QualityEvaluator | None = None,
        almacenar_respuestas_api: bool = True,
    ) -> None:
        self.sesion = sesion
        self.retrieval = retrieval or RetrievalService(sesion)
        self.explanation = explanation or ExplanationService()
        self.quality = quality or QualityEvaluator()
        self.almacenar_api = almacenar_respuestas_api

    async def responder(
        self,
        *,
        prompt: str,
        nivel: str | None = None,
        tema: str | None = None,
        proveedor: str = "auto",
        temperatura: float | None = None,
        permitir_api: bool = True,
    ) -> RespuestaMotor:
        # 1) Recuperación-primero en la base de conocimiento propia.
        match = await self.retrieval.mejor_match(prompt, tema=tema, nivel=nivel)
        if match is not None:
            unidad = match.unidad
            unidad.veces_reutilizada += 1
            await self.sesion.flush()
            log.info(
                "Respuesta servida desde base de conocimiento (score=%.3f, unidad=%s)",
                match.score, unidad.id,
            )
            respuesta = RespuestaIAEducativa.model_validate(unidad.respuesta_json)
            return RespuestaMotor(
                respuesta=respuesta,
                origen="base_conocimiento",
                score_recuperacion=match.score,
                unidad_id=str(unidad.id),
                latencia_segundos=0.0,
            )

        if not permitir_api:
            raise ExplicacionServiceError(
                "No hay conocimiento propio para esta consulta y el uso de API "
                "está deshabilitado."
            )

        # 2) Sin match: usar la API como herramienta auxiliar.
        resultado = await self.explanation.explicar(
            prompt_estudiante=prompt,
            proveedor_nombre=proveedor,
            nivel=nivel,
            tema=tema,
            temperatura=temperatura,
        )
        respuesta = resultado.respuesta
        calidad = self.quality.evaluar(respuesta)

        unidad_id: str | None = None
        # 3) Aprender: almacenar como conocimiento candidato para futuras
        #    consultas (queda pendiente de validación humana salvo config).
        if self.almacenar_api:
            unidad_id = await self._almacenar_candidato(
                prompt=prompt,
                respuesta=respuesta,
                calidad=calidad,
                proveedor=resultado.resultado_llm.proveedor or proveedor,
            )

        return RespuestaMotor(
            respuesta=respuesta,
            origen="api",
            score_recuperacion=0.0,
            unidad_id=unidad_id,
            calidad=calidad,
            intentos_reparacion=resultado.intentos_reparacion,
            tokens_totales=resultado.tokens_totales,
            latencia_segundos=resultado.latencia_segundos,
            proveedor=resultado.resultado_llm.proveedor or proveedor,
        )

    async def _almacenar_candidato(
        self,
        *,
        prompt: str,
        respuesta: RespuestaIAEducativa,
        calidad: ResultadoCalidad,
        proveedor: str,
    ) -> str:
        origen = (
            OrigenConocimiento.GENERADO_DEEPSEEK
            if "deepseek" in (proveedor or "").lower()
            else OrigenConocimiento.GENERADO_GEMINI
        )
        estado = (
            EstadoConocimiento.CANDIDATO
            if calidad.aprobado
            else EstadoConocimiento.RECHAZADO
        )
        texto_busqueda, keywords = construir_indice_texto(
            pregunta=prompt,
            tema=respuesta.tema,
            nivel=respuesta.nivel,
            conceptos=[c.concepto for c in respuesta.conceptos_clave],
            objetivo=None,
        )
        unidad = UnidadConocimiento(
            codigo_curriculo=None,
            nivel=_nivel(respuesta.nivel),
            tema=_tema(respuesta.tema),
            objetivo_aprendizaje=None,
            pregunta_canonica=prompt,
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
        return str(unidad.id)
