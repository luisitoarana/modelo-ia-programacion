"""Servicio de configuración del sistema (persistencia cifrada + caché)."""

from __future__ import annotations

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.configuracion import ConfiguracionSistema
from app.services import runtime_config
from app.services.crypto import cifrar, descifrar, enmascarar
from app.utils.logger import obtener_logger


log = obtener_logger(__name__)

# Definición de claves gestionables y su metadato.
CLAVES_API = {
    runtime_config.GEMINI_API_KEY: "API key de Google Gemini",
    runtime_config.DEEPSEEK_API_KEY: "API key de DeepSeek",
    runtime_config.GROQ_API_KEY: "API key de Groq",
    runtime_config.OPENAI_API_KEY: "API key de OpenAI",
    runtime_config.ANTHROPIC_API_KEY: "API key de Anthropic",
    runtime_config.OPENROUTER_API_KEY: "API key de OpenRouter",
}


class ConfigService:
    def __init__(self, sesion: AsyncSession) -> None:
        self.sesion = sesion

    async def hidratar_cache(self) -> int:
        """Carga las API keys descifradas al caché de proceso. Devuelve cuántas."""
        filas = list((await self.sesion.scalars(select(ConfiguracionSistema))).all())
        valores: dict[str, str] = {}
        for fila in filas:
            valor = descifrar(fila.valor_cifrado) if fila.es_secreto else fila.valor_cifrado
            valores[fila.clave] = valor
        runtime_config.hidratar(valores)
        return sum(1 for v in valores.values() if v)

    async def set_api_key(self, clave: str, valor: str, *, actualizado_por: str) -> None:
        if clave not in CLAVES_API:
            raise ValueError(f"Clave de API desconocida: {clave}")
        fila = await self.sesion.get(ConfiguracionSistema, clave)
        cifrado = cifrar(valor)
        if fila is None:
            fila = ConfiguracionSistema(
                clave=clave,
                valor_cifrado=cifrado,
                es_secreto=True,
                descripcion=CLAVES_API[clave],
                actualizado_por=actualizado_por,
            )
            self.sesion.add(fila)
        else:
            fila.valor_cifrado = cifrado
            fila.actualizado_por = actualizado_por
        await self.sesion.flush()
        runtime_config.set_valor(clave, valor)
        log.info("API key '%s' actualizada por %s", clave, actualizado_por)

    async def estado_api_keys(self) -> dict[str, dict[str, object]]:
        """Estado (sin exponer el secreto) de cada API key gestionable."""
        salida: dict[str, dict[str, object]] = {}
        for clave, desc in CLAVES_API.items():
            fila = await self.sesion.get(ConfiguracionSistema, clave)
            valor = descifrar(fila.valor_cifrado) if fila else ""
            salida[clave] = {
                "descripcion": desc,
                "configurada": bool(valor),
                "vista": enmascarar(valor),
                "actualizado_por": fila.actualizado_por if fila else None,
            }
        return salida
