"""Servicio de inferencia del LLM propio dentro del backend.

Puente entre el backend web y el paquete `ml/` (el modelo entrenado desde
cero). Materializa el flujo objetivo de la investigación:

    Usuario → Modelo propio → Respuesta

Diseño defensivo:
  - Importa `torch` y `ml` de forma perezosa (lazy). Si no están disponibles
    (p.ej. el contenedor del backend no tiene torch, o no hay checkpoint),
    el servicio reporta `disponible=False` con un motivo claro, sin romper la
    app. Así el sistema sigue operativo y la integración del modelo se activa
    en cuanto exista un checkpoint entrenado y torch instalado.
  - El motor se carga una sola vez (cache de proceso).
"""

from __future__ import annotations

import sys
import threading
from dataclasses import dataclass
from pathlib import Path

from app.config import settings
from app.utils.logger import obtener_logger


log = obtener_logger(__name__)

# Raíz del proyecto: backend/app/services/este_archivo.py -> parents[3]
_RAIZ = Path(__file__).resolve().parents[3]

_lock = threading.Lock()
_engine = None            # instancia perezosa de ml.inference.InferenceEngine
_motivo_no_disponible: str | None = None
_intentado = False


@dataclass(slots=True)
class RespuestaModeloPropio:
    texto: str
    tokens_generados: int
    latencia_segundos: float
    device: str
    num_parametros: int


def _asegurar_path_ml() -> None:
    raiz = str(_RAIZ)
    if raiz not in sys.path:
        sys.path.insert(0, raiz)


def _resolver_tokenizer_path() -> str | None:
    if settings.model_tokenizer_path:
        return settings.model_tokenizer_path
    return None


def _cargar_engine():
    """Carga (una vez) el motor de inferencia. Devuelve None si no es posible."""
    global _engine, _motivo_no_disponible, _intentado

    if _engine is not None:
        return _engine
    if _intentado and _engine is None:
        return None

    with _lock:
        if _engine is not None:
            return _engine
        _intentado = True

        if not settings.model_enabled:
            _motivo_no_disponible = "El modelo propio está deshabilitado (MODEL_ENABLED=false)."
            return None

        ckpt = Path(settings.model_checkpoint_path)
        if not ckpt.is_absolute():
            ckpt = _RAIZ / ckpt
        if not ckpt.exists():
            _motivo_no_disponible = (
                f"No existe el checkpoint en {ckpt}. Entrena un modelo con "
                "'python -m ml.train' primero."
            )
            log.warning(_motivo_no_disponible)
            return None

        try:
            _asegurar_path_ml()
            import torch  # noqa: F401  (verificación de disponibilidad)
            from ml.inference.engine import InferenceEngine
        except ImportError as exc:
            _motivo_no_disponible = (
                f"PyTorch o el paquete ml no están disponibles en este entorno: {exc}. "
                "Instala torch para servir el modelo propio."
            )
            log.warning(_motivo_no_disponible)
            return None

        try:
            _engine = InferenceEngine(
                str(ckpt),
                tokenizer_path=_resolver_tokenizer_path(),
                device=settings.model_device,
            )
            log.info(
                "Modelo propio cargado: %s params en %s",
                f"{_engine.num_parametros:,}", _engine.device,
            )
        except Exception as exc:  # noqa: BLE001
            _motivo_no_disponible = f"Fallo al cargar el modelo: {exc}"
            log.exception("No se pudo cargar el modelo propio")
            _engine = None
        return _engine


def estado_modelo() -> dict[str, object]:
    """Reporta si el modelo propio está disponible para inferencia."""
    engine = _cargar_engine()
    if engine is None:
        return {
            "disponible": False,
            "motivo": _motivo_no_disponible or "Desconocido",
            "checkpoint": settings.model_checkpoint_path,
            "habilitado": settings.model_enabled,
        }
    return {
        "disponible": True,
        "num_parametros": engine.num_parametros,
        "device": engine.device,
        "checkpoint": settings.model_checkpoint_path,
        "habilitado": True,
    }


def modelo_disponible() -> bool:
    return _cargar_engine() is not None


def responder_con_modelo(
    instruccion: str,
    *,
    entrada: str = "",
    max_tokens: int | None = None,
    temperatura: float | None = None,
) -> RespuestaModeloPropio:
    """Genera una respuesta con el LLM propio. Lanza RuntimeError si no está listo."""
    engine = _cargar_engine()
    if engine is None:
        raise RuntimeError(_motivo_no_disponible or "Modelo propio no disponible.")

    r = engine.responder(
        instruccion,
        entrada=entrada,
        max_nuevos_tokens=max_tokens or settings.model_max_tokens,
        temperatura=temperatura if temperatura is not None else settings.model_temperature,
        top_k=settings.model_top_k,
    )
    return RespuestaModeloPropio(
        texto=r.texto,
        tokens_generados=r.tokens_generados,
        latencia_segundos=r.latencia_segundos,
        device=r.device,
        num_parametros=engine.num_parametros,
    )
