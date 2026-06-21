"""Servicio de explicación: orquesta IA → JSON estricto con auto-curación.

Punto único de entrada para que las rutas obtengan una
``RespuestaIAEducativa`` validada a partir de un prompt de estudiante.
Encapsula:
  - Construcción del prompt pedagógico.
  - Llamada al proveedor seleccionado.
  - Parseo lenient del JSON.
  - Validación contra Pydantic.
  - Ciclo de auto-curación (reintenta pidiendo corrección al LLM).
"""

from __future__ import annotations

from dataclasses import dataclass

from pydantic import ValidationError

from app.config import settings
from app.schemas.ai_response import RespuestaIAEducativa
from app.services.ai_provider import (
    ProveedorIA,
    ProveedorIAError,
    ResultadoLLM,
    obtener_proveedor,
)
from app.services.prompt_pedagogico import (
    PROMPT_SISTEMA_PEDAGOGICO,
    construir_prompt_usuario,
)
from app.utils.json_repair import (
    JSONIrrecuperableError,
    construir_prompt_reparacion,
    parsear_json_lenient,
)
from app.utils.logger import obtener_logger


log = obtener_logger(__name__)


@dataclass(slots=True)
class ResultadoExplicacion:
    """Lo que devuelve el servicio al orquestador / rutas."""

    respuesta: RespuestaIAEducativa
    resultado_llm: ResultadoLLM
    intentos_reparacion: int

    @property
    def tokens_entrada(self) -> int:
        return self.resultado_llm.tokens_entrada

    @property
    def tokens_salida(self) -> int:
        return self.resultado_llm.tokens_salida

    @property
    def tokens_totales(self) -> int:
        return self.resultado_llm.tokens_totales

    @property
    def latencia_segundos(self) -> float:
        return self.resultado_llm.latencia_segundos


class ExplicacionServiceError(RuntimeError):
    """Error de alto nivel cuando ni siquiera la auto-curación logró validar."""


class ExplanationService:
    """Orquesta una solicitud educativa contra los proveedores LLM."""

    def __init__(
        self,
        *,
        max_reintentos_json: int | None = None,
        max_tokens: int | None = None,
    ) -> None:
        self.max_reintentos = (
            max_reintentos_json
            if max_reintentos_json is not None
            else settings.ai_max_retries_json_repair
        )
        self.max_tokens = max_tokens or settings.ai_max_output_tokens

    async def explicar(
        self,
        *,
        prompt_estudiante: str,
        proveedor_nombre: str = "auto",
        nivel: str | None = None,
        tema: str | None = None,
        temperatura: float | None = None,
    ) -> ResultadoExplicacion:
        proveedor: ProveedorIA = obtener_proveedor(proveedor_nombre)
        temp = (
            temperatura if temperatura is not None else settings.ai_default_temperature
        )

        sistema = PROMPT_SISTEMA_PEDAGOGICO
        usuario = construir_prompt_usuario(
            prompt_estudiante=prompt_estudiante,
            nivel=nivel,
            tema=tema,
            fuente_ia_etiqueta=proveedor.etiqueta_fuente,
        )

        try:
            resultado_llm = await proveedor.generar(
                sistema=sistema,
                usuario=usuario,
                temperatura=temp,
                max_tokens=self.max_tokens,
            )
        except ProveedorIAError as exc:
            log.error("Proveedor IA falló: %s", exc)
            raise ExplicacionServiceError(str(exc)) from exc

        respuesta, intentos = await self._validar_con_autocuracion(
            texto_inicial=resultado_llm.texto,
            proveedor=proveedor,
            sistema=sistema,
            usuario_original=usuario,
            temperatura=temp,
        )

        respuesta.metadata.tokens_totales = resultado_llm.tokens_totales
        respuesta.metadata.latencia_segundos = resultado_llm.latencia_segundos

        return ResultadoExplicacion(
            respuesta=respuesta,
            resultado_llm=resultado_llm,
            intentos_reparacion=intentos,
        )

    async def _validar_con_autocuracion(
        self,
        *,
        texto_inicial: str,
        proveedor: ProveedorIA,
        sistema: str,
        usuario_original: str,
        temperatura: float,
    ) -> tuple[RespuestaIAEducativa, int]:
        """Intenta parsear+validar. Si falla, pide corrección al LLM hasta N veces."""
        texto_actual = texto_inicial
        ultimo_error = ""
        for intento in range(self.max_reintentos + 1):
            try:
                bruto = parsear_json_lenient(texto_actual)
                return RespuestaIAEducativa.model_validate(bruto), intento
            except (JSONIrrecuperableError, ValidationError) as exc:
                ultimo_error = str(exc)
                log.warning(
                    "Intento %s: respuesta IA inválida (%s). Solicitando reparación.",
                    intento, type(exc).__name__,
                )
                if intento >= self.max_reintentos:
                    break
                prompt_reparacion = construir_prompt_reparacion(texto_actual, ultimo_error)
                try:
                    nuevo = await proveedor.generar(
                        sistema=sistema,
                        usuario=prompt_reparacion,
                        temperatura=max(0.0, min(temperatura, 0.2)),
                        max_tokens=self.max_tokens,
                    )
                except ProveedorIAError as exc_prov:
                    raise ExplicacionServiceError(
                        f"Reparación falló por error de proveedor: {exc_prov}"
                    ) from exc_prov
                texto_actual = nuevo.texto

        raise ExplicacionServiceError(
            f"No se obtuvo respuesta válida tras {self.max_reintentos} reintentos. "
            f"Último error: {ultimo_error}"
        )
