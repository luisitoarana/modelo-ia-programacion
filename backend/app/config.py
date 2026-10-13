"""Configuración central del sistema usando Pydantic Settings v2.

Carga variables de entorno desde .env y las expone tipadas para el resto
de la aplicación. Centraliza credenciales de IA, base de datos y JWT.
"""

from __future__ import annotations

from functools import lru_cache
from pathlib import Path
from typing import Literal

from pydantic import Field, PostgresDsn, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Configuración global del sistema. Inmutable tras carga."""

    model_config = SettingsConfigDict(
        env_file=(Path(__file__).resolve().parents[2] / ".env", Path(__file__).resolve().parents[1] / ".env"),
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
        # Permite campos que empiezan con "model_" sin warnings de Pydantic.
        protected_namespaces=(),
    )

    # ----- Aplicación -----
    app_name: str = Field(default="Sistema Explicador Python IA")
    app_env: Literal["development", "staging", "production"] = Field(default="development")
    app_debug: bool = Field(default=True)
    app_host: str = Field(default="0.0.0.0")
    app_port: int = Field(default=8000)
    api_v1_prefix: str = Field(default="/api/v1")

    # ----- Seguridad / JWT -----
    secret_key: str = Field(default="cambia-esta-clave-en-produccion-por-favor-32chars")
    jwt_algorithm: str = Field(default="HS256")
    access_token_expire_minutes: int = Field(default=60 * 24)  # 24 h

    # ----- Administrador (seed automático al arrancar) -----
    admin_email: str = Field(default="admin@explicador.com")
    admin_password: str = Field(default="admin12345")
    admin_nombre: str = Field(default="Administrador")

    # ----- Base de datos -----
    database_url: str = Field(
        default="postgresql+asyncpg://postgres:postgres@localhost:5432/sistema_explicador",
    )
    database_echo: bool = Field(default=False)
    database_pool_size: int = Field(default=10)
    database_max_overflow: int = Field(default=20)

    # ----- Gemini API -----
    gemini_api_key: str = Field(default="")
    gemini_model: str = Field(default="gemini-2.0-flash")
    gemini_base_url: str = Field(
        default="https://generativelanguage.googleapis.com/v1beta"
    )
    gemini_timeout_seconds: float = Field(default=60.0)

    # ----- DeepSeek API -----
    deepseek_api_key: str = Field(default="")
    deepseek_model: str = Field(default="deepseek-chat")
    deepseek_base_url: str = Field(default="https://api.deepseek.com/v1")
    deepseek_timeout_seconds: float = Field(default=60.0)

    # ----- Orquestador IA -----
    ai_default_provider: Literal["gemini", "deepseek"] = Field(default="gemini")
    ai_default_temperature: float = Field(default=0.4)
    ai_max_retries_json_repair: int = Field(default=3)
    ai_max_output_tokens: int = Field(default=4096)

    # ----- LLM propio (modelo entrenado desde cero) -----
    # Cuando model_enabled=True y existe un checkpoint, el sistema responde con
    # el MODELO PROPIO (Usuario → Modelo propio → Respuesta). Las APIs quedan
    # restringidas a la generación de datos de entrenamiento.
    model_enabled: bool = Field(default=True)
    model_checkpoint_path: str = Field(
        default="training/checkpoints/C_350m_Final/checkpoint_ultimo.pt"
    )
    model_tokenizer_path: str = Field(default="")
    model_device: str = Field(default="auto")
    model_max_tokens: int = Field(default=380)
    model_temperature: float = Field(default=0.7)
    model_top_k: int = Field(default=40)

    # ----- Explorador de proyecto (capacidad de acceso a archivos) -----
    # Raíz que el sistema puede recorrer/leer (solo lectura). En Docker se
    # monta el proyecto en /proyecto.
    proyecto_root: str = Field(default=str(Path(__file__).resolve().parents[2]))

    # ----- CORS -----
    cors_origins: str = Field(default="http://localhost:3000,http://127.0.0.1:3000")

    # ----- Logging -----
    log_level: Literal["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"] = Field(default="INFO")
    log_file: str = Field(default="logs/sistema.log")

    @field_validator("secret_key")
    @classmethod
    def validar_secret_key(cls, v: str) -> str:
        if len(v) < 32:
            raise ValueError("secret_key debe tener al menos 32 caracteres")
        return v

    def model_post_init(self, __context: object) -> None:
        if self.is_production and (
            self.secret_key.startswith(("cambia-", "REEMPLAZAR"))
            or self.admin_password in ("admin12345", "REEMPLAZAR_POR_UNA_CLAVE_UNICA")
        ):
            raise ValueError("Produccion requiere SECRET_KEY y ADMIN_PASSWORD propios y seguros")

    @property
    def cors_origins_list(self) -> list[str]:
        return [o.strip() for o in self.cors_origins.split(",") if o.strip()]

    @property
    def is_production(self) -> bool:
        return self.app_env == "production"


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    """Devuelve la instancia única de Settings (singleton vía cache)."""
    return Settings()


settings = get_settings()
