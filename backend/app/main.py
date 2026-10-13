"""Entrypoint FastAPI del Sistema Explicador Python IA."""

from __future__ import annotations

from contextlib import asynccontextmanager
from typing import AsyncIterator

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app import __version__
from app.config import settings
from app.database import init_models
from app.routes import api_router
from app.services.ai_provider import proveedores_disponibles
from app.utils.logger import configurar_logging, obtener_logger


configurar_logging()
log = obtener_logger(__name__)


@asynccontextmanager
async def lifespan(_app: FastAPI) -> AsyncIterator[None]:
    log.info(
        "Iniciando %s v%s (env=%s)",
        settings.app_name, __version__, settings.app_env,
    )
    if not settings.is_production:
        try:
            await init_models()
            log.info("Tablas creadas/verificadas (modo desarrollo).")
        except Exception as exc:  # noqa: BLE001
            log.error("No se pudo inicializar la BD: %s", exc)
            raise
    # Seed del administrador + carga de API keys configuradas (cifradas).
    try:
        from app.services.bootstrap import inicializar_sistema

        await inicializar_sistema()
    except Exception as exc:  # noqa: BLE001
        log.error("Bootstrap del sistema incompleto: %s", exc)
        raise
    yield
    # Cerrar el subproceso del MCP server si quedó vivo
    try:
        from app.services.mcp_client import cerrar_cliente_mcp

        await cerrar_cliente_mcp()
    except Exception as exc:  # noqa: BLE001
        log.debug("Error al cerrar cliente MCP: %s", exc)
    log.info("Apagando %s.", settings.app_name)


def crear_app() -> FastAPI:
    app = FastAPI(
        title=settings.app_name,
        version=__version__,
        description=(
            "Plataforma educativa basada en LLMs para generación y "
            "explicación automática de código Python orientada al "
            "fortalecimiento de la comprensión algorítmica en estudiantes "
            "de educación superior."
        ),
        lifespan=lifespan,
        docs_url="/docs",
        redoc_url="/redoc",
        openapi_url=f"{settings.api_v1_prefix}/openapi.json",
    )

    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins_list,
        # Permite cualquier puerto de localhost/127.0.0.1 (útil para la app
        # Flutter web, que usa un puerto dinámico). Solo afecta a navegadores.
        allow_origin_regex=None if settings.is_production else r"http://(localhost|127\.0\.0\.1)(:\d+)?",
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    app.include_router(api_router, prefix=settings.api_v1_prefix)

    @app.get("/", tags=["Sistema"])
    async def raiz() -> dict[str, str]:
        return {
            "sistema": settings.app_name,
            "version": __version__,
            "docs": "/docs",
            "api": settings.api_v1_prefix,
        }

    @app.get("/health", tags=["Sistema"])
    async def health() -> JSONResponse:
        return JSONResponse(
            {
                "status": "ok",
                "version": __version__,
                "env": settings.app_env,
                "proveedores_ia_configurados": proveedores_disponibles(),
            }
        )

    return app


app = crear_app()


if __name__ == "__main__":  # pragma: no cover
    import uvicorn

    uvicorn.run(
        "app.main:app",
        host=settings.app_host,
        port=settings.app_port,
        reload=settings.app_debug,
    )
