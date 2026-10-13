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
_modelo_activo_id = "auto"
_motivo_no_disponible: str | None = None
_intentado = False

# Catálogo de modelos del proyecto (para conmutación en caliente)
CATALOGO_MODELOS = {
    "propio_30m": {
        "id": "propio_30m",
        "nombre": "Smoke Test (30M)",
        "descripcion": "Ultraligero · 1,000 pasos (loss 3.93)",
        "params": "30M",
        "rutas": [
            "training/checkpoints/smoke_test_30M/checkpoint_ultimo.pt",
        ],
    },
    "propio_88m": {
        "id": "propio_88m",
        "nombre": "Modelo A (88M)",
        "descripcion": "Ultrarrápido · Baseline ligera (5K pasos)",
        "params": "88M",
        "rutas": [
            "training/checkpoints/modelo_grande_88m_5k.pt",
            "training/checkpoints/checkpoint_88m.pt",
            "training/checkpoints/v1_best.pt",
            "training/checkpoints/modelo_88m.pt",
        ],
    },
    "propio_150m_5k": {
        "id": "propio_150m_5k",
        "nombre": "Modelo B (150M - 5K)",
        "descripcion": "Intermedio · SFT 5,000 pasos (loss 1.86)",
        "params": "150M",
        "rutas": [
            "training/checkpoints/B_sft_5k/checkpoint_ultimo.pt",
        ],
    },
    "propio_150m": {
        "id": "propio_150m",
        "nombre": "Modelo B v2 (150M - 15K)",
        "descripcion": "Recomendado · SFT ampliado (15K pasos, loss 1.41)",
        "params": "150M",
        "rutas": [
            "training/checkpoints/B_sft_15k/checkpoint_ultimo.pt",
            "training/checkpoints/b_150m_15k.pt",
            "training/checkpoints/v2_best.pt",
        ],
    },
    "propio_350m_5k": {
        "id": "propio_350m_5k",
        "nombre": "Modelo C (350M - 5K)",
        "descripcion": "Checkpoint intermedio · 5,000 pasos",
        "params": "350M",
        "rutas": [
            "training/checkpoints/C_350m_5k/checkpoint_ultimo.pt",
        ],
    },
    "propio_350m": {
        "id": "propio_350m",
        "nombre": "Modelo C (350M - Final 18.6K)",
        "descripcion": "Modelo Estrella · 18,600 pasos (loss 1.80, 173h train)",
        "params": "350M",
        "rutas": [
            "training/checkpoints/C_350m_Final/checkpoint_ultimo.pt",
            "training/checkpoints/c_350m_18k.pt",
            "training/checkpoints/c_350m_final.pt",
        ],
    },
}


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
    tok_v2 = _RAIZ / "ml" / "tokenizer" / "artefactos" / "sp_v2_16k.model"
    if tok_v2.exists():
        return str(tok_v2)
    return None


def _resolver_checkpoint_ruta(modelo_id: str | None = None) -> Path | None:
    """Busca el archivo de checkpoint en disco para el modelo solicitado o el configurado."""
    mid = modelo_id or _modelo_activo_id
    if mid in CATALOGO_MODELOS:
        for r in CATALOGO_MODELOS[mid]["rutas"]:
            p = _RAIZ / r
            if p.exists():
                return p

    # Si es "auto" o None, buscar en orden de preferencia
    orden_preferencia = ["propio_150m", "propio_350m", "propio_88m", "propio_30m"]
    for pref in orden_preferencia:
        if pref in CATALOGO_MODELOS:
            for r in CATALOGO_MODELOS[pref]["rutas"]:
                p = _RAIZ / r
                if p.exists():
                    return p

    # Fallback al path por defecto en settings
    ckpt = Path(settings.model_checkpoint_path)
    if not ckpt.is_absolute():
        ckpt = _RAIZ / ckpt
    if ckpt.exists():
        return ckpt

    # Búsqueda heurística en training/checkpoints
    chk_dir = _RAIZ / "training" / "checkpoints"
    if chk_dir.exists():
        pts = list(chk_dir.glob("**/*.pt"))
        if pts:
            return pts[0]
    return None


def modelos_disponibles_info() -> list[dict[str, object]]:
    """Devuelve la lista de modelos locales y su disponibilidad en disco."""
    resultado = []
    for mid, info in CATALOGO_MODELOS.items():
        ruta_encontrada = None
        for r in info["rutas"]:
            p = _RAIZ / r
            if p.exists():
                ruta_encontrada = str(r)
                break
        resultado.append({
            "id": mid,
            "nombre": info["nombre"],
            "descripcion": info["descripcion"],
            "params": info["params"],
            "disponible": ruta_encontrada is not None,
            "ruta": ruta_encontrada,
            "activo": mid == _modelo_activo_id,
        })
    return resultado


def cambiar_modelo(modelo_id: str) -> bool:
    """Conmuta el modelo activo en VRAM (descarga el anterior y carga el nuevo)."""
    global _engine, _modelo_activo_id, _motivo_no_disponible, _intentado
    with _lock:
        ruta = _resolver_checkpoint_ruta(modelo_id)
        if ruta is None:
            _motivo_no_disponible = f"No se encontró checkpoint para el modelo '{modelo_id}'."
            return False

        try:
            _asegurar_path_ml()
            import torch
            if torch.cuda.is_available():
                torch.cuda.empty_cache()
            from ml.inference.engine import InferenceEngine

            _engine = InferenceEngine(
                str(ruta),
                tokenizer_path=_resolver_tokenizer_path(),
                device=settings.model_device,
            )
            _modelo_activo_id = modelo_id
            _motivo_no_disponible = None
            log.info("Modelo conmutado a %s (%s params)", modelo_id, f"{_engine.num_parametros:,}")
            return True
        except Exception as exc:
            _motivo_no_disponible = f"Fallo al conmutar modelo: {exc}"
            log.exception("Error al cambiar modelo")
            return False


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
            # Si hay checkpoints en disco, lo habilitamos automáticamente para facilitar la validación
            chk_detectado = _resolver_checkpoint_ruta()
            if not chk_detectado:
                _motivo_no_disponible = "El modelo propio está deshabilitado y no se hallaron checkpoints."
                return None
        else:
            chk_detectado = _resolver_checkpoint_ruta()

        if chk_detectado is None:
            _motivo_no_disponible = "No se hallaron checkpoints de modelos entrenados en training/checkpoints/."
            log.warning(_motivo_no_disponible)
            return None

        try:
            _asegurar_path_ml()
            import torch  # noqa: F401
            from ml.inference.engine import InferenceEngine
        except ImportError as exc:
            _motivo_no_disponible = (
                f"PyTorch o el paquete ml no están disponibles en este entorno: {exc}."
            )
            log.warning(_motivo_no_disponible)
            return None

        try:
            _engine = InferenceEngine(
                str(chk_detectado),
                tokenizer_path=_resolver_tokenizer_path(),
                device=settings.model_device,
            )
            log.info(
                "Modelo propio cargado: %s params en %s (desde %s)",
                f"{_engine.num_parametros:,}", _engine.device, chk_detectado.name
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
            "modelos_locales": modelos_disponibles_info(),
        }
    return {
        "disponible": True,
        "modelo_activo": _modelo_activo_id,
        "num_parametros": engine.num_parametros,
        "device": engine.device,
        "checkpoint": str(getattr(engine, "checkpoint_path", settings.model_checkpoint_path)),
        "habilitado": True,
        "modelos_locales": modelos_disponibles_info(),
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
