"""Proveedores de IA: cliente unificado para Gemini y DeepSeek.

Define una interfaz común ``ProveedorIA`` y dos implementaciones
asíncronas con httpx. Cada proveedor devuelve un ``ResultadoLLM`` con
el texto bruto, los tokens consumidos y la latencia medida.

El orquestador (``ai_orchestrator.py`` y ``explanation_service.py``)
se encarga de parsear, validar y, si corresponde, disparar la
auto-curación de JSON.
"""

from __future__ import annotations

import time
from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from typing import Any

import httpx

from app.config import settings
from app.services import runtime_config
from app.utils.logger import obtener_logger


log = obtener_logger(__name__)


@dataclass(slots=True)
class ResultadoLLM:
    """Salida cruda + telemetría de una llamada al modelo."""

    texto: str
    tokens_entrada: int = 0
    tokens_salida: int = 0
    latencia_segundos: float = 0.0
    modelo: str = ""
    proveedor: str = ""
    payload_crudo: dict[str, Any] = field(default_factory=dict)

    @property
    def tokens_totales(self) -> int:
        return self.tokens_entrada + self.tokens_salida


class ProveedorIAError(RuntimeError):
    """Error específico al llamar a un proveedor IA externo."""


class ProveedorIA(ABC):
    """Contrato común de proveedores LLM."""

    etiqueta_fuente: str = ""  # valor que el LLM debe poner en "fuente_ia"
    nombre: str = ""

    @abstractmethod
    async def generar(
        self,
        *,
        sistema: str,
        usuario: str,
        temperatura: float,
        max_tokens: int,
        json_mode: bool = True,
    ) -> ResultadoLLM:
        """Llama al modelo y devuelve la respuesta cruda + telemetría.

        json_mode=True fuerza salida JSON (para el explicador estructurado);
        json_mode=False permite texto libre (para el chat conversacional).
        """

    @property
    def esta_configurado(self) -> bool:
        return True


# ---------------------------------------------------------------------------
# Gemini
# ---------------------------------------------------------------------------

class GeminiProvider(ProveedorIA):
    """Cliente async para la Generative Language API de Google."""

    nombre = "gemini"
    etiqueta_fuente = "gemini"

    def __init__(self) -> None:
        self.modelo = settings.gemini_model
        self.base_url = settings.gemini_base_url.rstrip("/")
        self.timeout = settings.gemini_timeout_seconds

    @property
    def api_key(self) -> str:
        # Resuelve dinámicamente: primero la configurada por el admin (BD), luego .env
        return runtime_config.get_api_key("gemini")

    @property
    def esta_configurado(self) -> bool:
        return bool(self.api_key)

    async def generar(
        self,
        *,
        sistema: str,
        usuario: str,
        temperatura: float,
        max_tokens: int,
        json_mode: bool = True,
    ) -> ResultadoLLM:
        if not self.esta_configurado:
            raise ProveedorIAError(
                "No hay API key de Gemini configurada. Configúrala en el panel de "
                "administrador."
            )

        url = f"{self.base_url}/models/{self.modelo}:generateContent"
        generation_config: dict[str, Any] = {
            "temperature": temperatura,
            "maxOutputTokens": max_tokens,
        }
        if json_mode:
            generation_config["responseMimeType"] = "application/json"
        cuerpo: dict[str, Any] = {
            "systemInstruction": {"role": "system", "parts": [{"text": sistema}]},
            "contents": [{"role": "user", "parts": [{"text": usuario}]}],
            "generationConfig": generation_config,
        }
        headers = {"Content-Type": "application/json"}
        params = {"key": self.api_key}

        inicio = time.perf_counter()
        try:
            async with httpx.AsyncClient(timeout=self.timeout) as cliente:
                resp = await cliente.post(url, json=cuerpo, headers=headers, params=params)
                resp.raise_for_status()
                data = resp.json()
        except httpx.HTTPStatusError as exc:
            log.error("Gemini HTTP %s: %s", exc.response.status_code, exc.response.text[:500])
            raise ProveedorIAError(
                f"Gemini respondió {exc.response.status_code}: {exc.response.text[:200]}"
            ) from exc
        except httpx.HTTPError as exc:
            log.exception("Fallo de red con Gemini")
            raise ProveedorIAError(f"Fallo de red con Gemini: {exc}") from exc

        latencia = time.perf_counter() - inicio
        texto = self._extraer_texto(data)
        uso = data.get("usageMetadata", {}) or {}

        return ResultadoLLM(
            texto=texto,
            tokens_entrada=int(uso.get("promptTokenCount", 0) or 0),
            tokens_salida=int(uso.get("candidatesTokenCount", 0) or 0),
            latencia_segundos=round(latencia, 4),
            modelo=self.modelo,
            proveedor=self.nombre,
            payload_crudo=data,
        )

    async def generar_multimodal(
        self,
        *,
        sistema: str,
        usuario: str,
        imagenes: list[tuple[bytes, str]],
        temperatura: float = 0.5,
        max_tokens: int = 2048,
    ) -> ResultadoLLM:
        """Versión multimodal de ``generar``: acepta una lista de imágenes.

        Cada imagen es una tupla (bytes_crudos, mime_type). Gemini Vision
        las recibe codificadas en base64 dentro del payload ``parts``.
        Ver docs/VISION_PLAN.md.
        """
        import base64

        if not self.esta_configurado:
            raise ProveedorIAError(
                "No hay API key de Gemini configurada. Configúrala en el panel de "
                "administrador."
            )

        url = f"{self.base_url}/models/{self.modelo}:generateContent"
        partes: list[dict[str, Any]] = [{"text": usuario}]
        for blob, mime in imagenes:
            partes.append({
                "inlineData": {
                    "mimeType": mime,
                    "data": base64.b64encode(blob).decode("ascii"),
                }
            })

        cuerpo: dict[str, Any] = {
            "systemInstruction": {"role": "system", "parts": [{"text": sistema}]},
            "contents": [{"role": "user", "parts": partes}],
            "generationConfig": {
                "temperature": temperatura,
                "maxOutputTokens": max_tokens,
            },
        }
        headers = {"Content-Type": "application/json"}
        params = {"key": self.api_key}

        inicio = time.perf_counter()
        try:
            async with httpx.AsyncClient(timeout=self.timeout) as cliente:
                resp = await cliente.post(
                    url, json=cuerpo, headers=headers, params=params
                )
                resp.raise_for_status()
                data = resp.json()
        except httpx.HTTPStatusError as exc:
            log.error(
                "Gemini Vision HTTP %s: %s",
                exc.response.status_code, exc.response.text[:500],
            )
            raise ProveedorIAError(
                f"Gemini Vision respondió {exc.response.status_code}: "
                f"{exc.response.text[:200]}"
            ) from exc
        except httpx.HTTPError as exc:
            log.exception("Fallo de red con Gemini Vision")
            raise ProveedorIAError(f"Fallo de red con Gemini Vision: {exc}") from exc

        latencia = time.perf_counter() - inicio
        texto = self._extraer_texto(data)
        uso = data.get("usageMetadata", {}) or {}

        return ResultadoLLM(
            texto=texto,
            tokens_entrada=int(uso.get("promptTokenCount", 0) or 0),
            tokens_salida=int(uso.get("candidatesTokenCount", 0) or 0),
            latencia_segundos=round(latencia, 4),
            modelo=self.modelo,
            proveedor=self.nombre,
            payload_crudo=data,
        )

    @staticmethod
    def _extraer_texto(data: dict[str, Any]) -> str:
        candidatos = data.get("candidates") or []
        if not candidatos:
            return ""
        partes = (candidatos[0].get("content") or {}).get("parts") or []
        fragmentos = [p.get("text", "") for p in partes if isinstance(p, dict)]
        return "".join(fragmentos).strip()


# ---------------------------------------------------------------------------
# DeepSeek
# ---------------------------------------------------------------------------

class DeepSeekProvider(ProveedorIA):
    """Cliente async para la API DeepSeek (interfaz tipo OpenAI Chat)."""

    nombre = "deepseek"
    etiqueta_fuente = "deepseek-r1"

    def __init__(self) -> None:
        self.modelo = settings.deepseek_model
        self.base_url = settings.deepseek_base_url.rstrip("/")
        self.timeout = settings.deepseek_timeout_seconds

    @property
    def api_key(self) -> str:
        return runtime_config.get_api_key("deepseek")

    @property
    def esta_configurado(self) -> bool:
        return bool(self.api_key)

    async def generar(
        self,
        *,
        sistema: str,
        usuario: str,
        temperatura: float,
        max_tokens: int,
        json_mode: bool = True,
    ) -> ResultadoLLM:
        if not self.esta_configurado:
            raise ProveedorIAError(
                "No hay API key de DeepSeek configurada. Configúrala en el panel de "
                "administrador."
            )

        url = f"{self.base_url}/chat/completions"
        cuerpo: dict[str, Any] = {
            "model": self.modelo,
            "messages": [
                {"role": "system", "content": sistema},
                {"role": "user", "content": usuario},
            ],
            "temperature": temperatura,
            "max_tokens": max_tokens,
            "stream": False,
        }
        if json_mode:
            cuerpo["response_format"] = {"type": "json_object"}
        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json",
        }

        inicio = time.perf_counter()
        try:
            async with httpx.AsyncClient(timeout=self.timeout) as cliente:
                resp = await cliente.post(url, json=cuerpo, headers=headers)
                resp.raise_for_status()
                data = resp.json()
        except httpx.HTTPStatusError as exc:
            log.error("DeepSeek HTTP %s: %s", exc.response.status_code, exc.response.text[:500])
            raise ProveedorIAError(
                f"DeepSeek respondió {exc.response.status_code}: {exc.response.text[:200]}"
            ) from exc
        except httpx.HTTPError as exc:
            log.exception("Fallo de red con DeepSeek")
            raise ProveedorIAError(f"Fallo de red con DeepSeek: {exc}") from exc

        latencia = time.perf_counter() - inicio
        eleccion = (data.get("choices") or [{}])[0]
        texto = ((eleccion.get("message") or {}).get("content") or "").strip()
        uso = data.get("usage", {}) or {}

        return ResultadoLLM(
            texto=texto,
            tokens_entrada=int(uso.get("prompt_tokens", 0) or 0),
            tokens_salida=int(uso.get("completion_tokens", 0) or 0),
            latencia_segundos=round(latencia, 4),
            modelo=self.modelo,
            proveedor=self.nombre,
            payload_crudo=data,
        )


# ---------------------------------------------------------------------------
# Groq (Ultra-Rápido 300-500 tokens/segundo · Nivel Gratuito de Alto Rendimiento)
# ---------------------------------------------------------------------------

class GroqProvider(ProveedorIA):
    """Cliente async para la API de Groq Cloud (hardware LPU de ultra-baja latencia)."""

    nombre = "groq"
    etiqueta_fuente = "motor-alta-velocidad"

    def __init__(self, modelo: str = "llama-3.3-70b-versatile") -> None:
        self.modelo = modelo
        self.base_url = "https://api.groq.com/openai/v1"
        self.timeout = 25.0

    @property
    def api_key(self) -> str:
        return runtime_config.get_api_key("groq")

    @property
    def esta_configurado(self) -> bool:
        return bool(self.api_key)

    async def generar(
        self,
        *,
        sistema: str,
        usuario: str,
        temperatura: float,
        max_tokens: int,
        json_mode: bool = False,
    ) -> ResultadoLLM:
        if not self.esta_configurado:
            raise ProveedorIAError("No hay API key de Groq configurada.")

        url = f"{self.base_url}/chat/completions"
        cuerpo: dict[str, Any] = {
            "model": self.modelo,
            "messages": [
                {"role": "system", "content": sistema},
                {"role": "user", "content": usuario},
            ],
            "temperature": temperatura,
            "max_tokens": max_tokens,
            "stream": False,
        }
        if json_mode:
            cuerpo["response_format"] = {"type": "json_object"}
        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json",
        }

        inicio = time.perf_counter()
        try:
            async with httpx.AsyncClient(timeout=self.timeout) as cliente:
                resp = await cliente.post(url, json=cuerpo, headers=headers)
                resp.raise_for_status()
                data = resp.json()
        except httpx.HTTPStatusError as exc:
            log.error("Groq HTTP %s: %s", exc.response.status_code, exc.response.text[:400])
            raise ProveedorIAError(
                f"Groq respondió {exc.response.status_code}: {exc.response.text[:200]}"
            ) from exc
        except httpx.HTTPError as exc:
            raise ProveedorIAError(f"Fallo de conexión con Groq: {exc}") from exc

        latencia = time.perf_counter() - inicio
        eleccion = (data.get("choices") or [{}])[0]
        texto = ((eleccion.get("message") or {}).get("content") or "").strip()
        uso = data.get("usage", {}) or {}

        return ResultadoLLM(
            texto=texto,
            tokens_entrada=int(uso.get("prompt_tokens", 0) or 0),
            tokens_salida=int(uso.get("completion_tokens", 0) or 0),
            latencia_segundos=round(latencia, 4),
            modelo=self.modelo,
            proveedor=self.nombre,
            payload_crudo=data,
        )


# ---------------------------------------------------------------------------
# OpenAI (GPT-4o / GPT-4o-mini · Modo Pro)
# ---------------------------------------------------------------------------

class OpenAIProvider(ProveedorIA):
    """Cliente async para OpenAI (GPT-4o)."""

    nombre = "openai"
    etiqueta_fuente = "motor-openai"

    def __init__(self, modelo: str = "gpt-4o") -> None:
        self.modelo = modelo
        self.base_url = "https://api.openai.com/v1"
        self.timeout = 45.0

    @property
    def api_key(self) -> str:
        return runtime_config.get_api_key("openai")

    @property
    def esta_configurado(self) -> bool:
        return bool(self.api_key)

    async def generar(
        self,
        *,
        sistema: str,
        usuario: str,
        temperatura: float,
        max_tokens: int,
        json_mode: bool = False,
    ) -> ResultadoLLM:
        if not self.esta_configurado:
            raise ProveedorIAError("No hay API key de OpenAI configurada.")

        url = f"{self.base_url}/chat/completions"
        cuerpo: dict[str, Any] = {
            "model": self.modelo,
            "messages": [
                {"role": "system", "content": sistema},
                {"role": "user", "content": usuario},
            ],
            "temperature": temperatura,
            "max_tokens": max_tokens,
            "stream": False,
        }
        if json_mode:
            cuerpo["response_format"] = {"type": "json_object"}
        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json",
        }

        inicio = time.perf_counter()
        try:
            async with httpx.AsyncClient(timeout=self.timeout) as cliente:
                resp = await cliente.post(url, json=cuerpo, headers=headers)
                resp.raise_for_status()
                data = resp.json()
        except httpx.HTTPError as exc:
            raise ProveedorIAError(f"Fallo de conexión con OpenAI: {exc}") from exc

        latencia = time.perf_counter() - inicio
        eleccion = (data.get("choices") or [{}])[0]
        texto = ((eleccion.get("message") or {}).get("content") or "").strip()
        uso = data.get("usage", {}) or {}

        return ResultadoLLM(
            texto=texto,
            tokens_entrada=int(uso.get("prompt_tokens", 0) or 0),
            tokens_salida=int(uso.get("completion_tokens", 0) or 0),
            latencia_segundos=round(latencia, 4),
            modelo=self.modelo,
            proveedor=self.nombre,
            payload_crudo=data,
        )


# ---------------------------------------------------------------------------
# Anthropic (Claude 3.5 Sonnet / Haiku · Modo Pro)
# ---------------------------------------------------------------------------

class AnthropicProvider(ProveedorIA):
    """Cliente async para Anthropic (Claude)."""

    nombre = "anthropic"
    etiqueta_fuente = "motor-claude"

    def __init__(self, modelo: str = "claude-3-5-sonnet-20241022") -> None:
        self.modelo = modelo
        self.base_url = "https://api.anthropic.com/v1"
        self.timeout = 45.0

    @property
    def api_key(self) -> str:
        return runtime_config.get_api_key("anthropic")

    @property
    def esta_configurado(self) -> bool:
        return bool(self.api_key)

    async def generar(
        self,
        *,
        sistema: str,
        usuario: str,
        temperatura: float,
        max_tokens: int,
        json_mode: bool = False,
    ) -> ResultadoLLM:
        if not self.esta_configurado:
            raise ProveedorIAError("No hay API key de Anthropic configurada.")

        url = f"{self.base_url}/messages"
        cuerpo: dict[str, Any] = {
            "model": self.modelo,
            "max_tokens": max_tokens,
            "system": sistema,
            "messages": [
                {"role": "user", "content": usuario},
            ],
            "temperature": temperatura,
        }
        headers = {
            "x-api-key": self.api_key,
            "anthropic-version": "2023-06-01",
            "Content-Type": "application/json",
        }

        inicio = time.perf_counter()
        try:
            async with httpx.AsyncClient(timeout=self.timeout) as cliente:
                resp = await cliente.post(url, json=cuerpo, headers=headers)
                resp.raise_for_status()
                data = resp.json()
        except httpx.HTTPError as exc:
            raise ProveedorIAError(f"Fallo de conexión con Anthropic: {exc}") from exc

        latencia = time.perf_counter() - inicio
        bloques = data.get("content", [])
        texto = "".join(b.get("text", "") for b in bloques if b.get("type") == "text").strip()
        uso = data.get("usage", {}) or {}

        return ResultadoLLM(
            texto=texto,
            tokens_entrada=int(uso.get("input_tokens", 0) or 0),
            tokens_salida=int(uso.get("output_tokens", 0) or 0),
            latencia_segundos=round(latencia, 4),
            modelo=self.modelo,
            proveedor=self.nombre,
            payload_crudo=data,
        )


# ---------------------------------------------------------------------------
# OpenRouter (Modelos gratuitos y multimodelo)
# ---------------------------------------------------------------------------

class OpenRouterProvider(ProveedorIA):
    """Cliente async para OpenRouter (acceso a modelos libres y comerciales)."""

    nombre = "openrouter"
    etiqueta_fuente = "motor-openrouter"

    def __init__(self, modelo: str = "google/gemini-2.0-flash-exp:free") -> None:
        self.modelo = modelo
        self.base_url = "https://openrouter.ai/api/v1"
        self.timeout = 35.0

    @property
    def api_key(self) -> str:
        return runtime_config.get_api_key("openrouter")

    @property
    def esta_configurado(self) -> bool:
        return bool(self.api_key)

    async def generar(
        self,
        *,
        sistema: str,
        usuario: str,
        temperatura: float,
        max_tokens: int,
        json_mode: bool = False,
    ) -> ResultadoLLM:
        if not self.esta_configurado:
            raise ProveedorIAError("No hay API key de OpenRouter configurada.")

        url = f"{self.base_url}/chat/completions"
        cuerpo: dict[str, Any] = {
            "model": self.modelo,
            "messages": [
                {"role": "system", "content": sistema},
                {"role": "user", "content": usuario},
            ],
            "temperature": temperatura,
            "max_tokens": max_tokens,
        }
        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json",
        }

        inicio = time.perf_counter()
        try:
            async with httpx.AsyncClient(timeout=self.timeout) as cliente:
                resp = await cliente.post(url, json=cuerpo, headers=headers)
                resp.raise_for_status()
                data = resp.json()
        except httpx.HTTPError as exc:
            raise ProveedorIAError(f"Fallo de conexión con OpenRouter: {exc}") from exc

        latencia = time.perf_counter() - inicio
        eleccion = (data.get("choices") or [{}])[0]
        texto = ((eleccion.get("message") or {}).get("content") or "").strip()
        uso = data.get("usage", {}) or {}

        return ResultadoLLM(
            texto=texto,
            tokens_entrada=int(uso.get("prompt_tokens", 0) or 0),
            tokens_salida=int(uso.get("completion_tokens", 0) or 0),
            latencia_segundos=round(latencia, 4),
            modelo=self.modelo,
            proveedor=self.nombre,
            payload_crudo=data,
        )


# ---------------------------------------------------------------------------
# Registro / fábrica
# ---------------------------------------------------------------------------

_REGISTRO: dict[str, ProveedorIA] = {}


def obtener_proveedor(nombre: str) -> ProveedorIA:
    """Devuelve el proveedor pedido o resuelve "auto" por configuración."""
    clave = nombre.lower().strip()
    if clave == "auto":
        clave = settings.ai_default_provider

    if clave not in _REGISTRO:
        if clave == "groq":
            _REGISTRO[clave] = GroqProvider()
        elif clave == "gemini":
            _REGISTRO[clave] = GeminiProvider()
        elif clave == "deepseek":
            _REGISTRO[clave] = DeepSeekProvider()
        elif clave == "openai":
            _REGISTRO[clave] = OpenAIProvider()
        elif clave == "anthropic":
            _REGISTRO[clave] = AnthropicProvider()
        elif clave == "openrouter":
            _REGISTRO[clave] = OpenRouterProvider()
        else:
            raise ProveedorIAError(f"Proveedor IA desconocido: {nombre!r}")
    return _REGISTRO[clave]


def proveedores_disponibles() -> list[str]:
    """Lista de proveedores con credenciales configuradas."""
    candidatos = [
        GroqProvider(),
        GeminiProvider(),
        DeepSeekProvider(),
        OpenAIProvider(),
        AnthropicProvider(),
        OpenRouterProvider(),
    ]
    return [p.nombre for p in candidatos if p.esta_configurado]
