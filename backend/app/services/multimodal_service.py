"""Servicio de inferencia del modelo MULTIMODAL propio.

Carga ViT + Projector + LLM propios (entrenados con `ml/train_multimodal.py`)
y los expone al backend como `responder(texto, imagenes) -> texto`.

Defensivo: si no hay checkpoint o falta torch, reporta `disponible=False`
sin romper el resto del backend. La ruta multimodal devuelve entonces
"modelo de visión en entrenamiento" desde `chat_service`.

NO usa ninguna API externa para inferencia. Esa fue la decisión
arquitectónica explícita (ver `docs/VISION_PROPIA.md`).
"""

from __future__ import annotations

import asyncio
import io
import sys
import threading
import time
from dataclasses import dataclass
from pathlib import Path

from app.config import settings
from app.utils.logger import obtener_logger


log = obtener_logger(__name__)

_RAIZ = Path(__file__).resolve().parents[3]

_lock = threading.Lock()
_modelo = None              # ModeloMultimodal cargado en GPU/CPU
_tokenizer = None
_motivo_no_disponible: str | None = None
_intentado = False
_device = "cpu"


@dataclass(slots=True)
class RespuestaMultimodal:
    texto: str
    tokens_generados: int
    latencia_segundos: float
    device: str


def _asegurar_path_ml() -> None:
    raiz = str(_RAIZ)
    if raiz not in sys.path:
        sys.path.insert(0, raiz)


def _ruta_checkpoint() -> Path:
    """Prioridad: etapa B > etapa A."""
    candidatos = [
        _RAIZ / "runs" / "multimodal_b" / "best.pt",
        _RAIZ / "runs" / "multimodal_a" / "best.pt",
    ]
    for c in candidatos:
        if c.exists():
            return c
    return candidatos[-1]


def _cargar_modelo() -> None:
    """Carga el modelo multimodal una sola vez. Idempotente."""
    global _modelo, _tokenizer, _motivo_no_disponible, _intentado, _device

    with _lock:
        if _intentado:
            return
        _intentado = True

        try:
            _asegurar_path_ml()
            import torch
            from ml.model.multimodal_model import (
                ConfigMultimodal,
                ModeloMultimodal,
            )
            from ml.model.transformer_v2 import ModelConfigV2
            from ml.model.vision.vit_encoder import ViTConfig
            from ml.tokenizer.sp_tokenizer import SPTokenizer
            from ml.config import DIR_TOKENIZER
        except ImportError as exc:
            _motivo_no_disponible = f"Dependencias ML no disponibles: {exc}"
            log.info("[multimodal] %s", _motivo_no_disponible)
            return

        ckpt_path = _ruta_checkpoint()
        if not ckpt_path.exists():
            _motivo_no_disponible = (
                f"No hay checkpoint multimodal en {ckpt_path}. "
                f"Entrena con `python -m ml.train_multimodal --etapa a`."
            )
            log.info("[multimodal] %s", _motivo_no_disponible)
            return

        tok_path = Path(DIR_TOKENIZER) / "tokenizer.json"
        if not tok_path.exists():
            _motivo_no_disponible = f"Tokenizer no encontrado en {tok_path}."
            log.info("[multimodal] %s", _motivo_no_disponible)
            return

        try:
            _tokenizer = SPTokenizer.cargar(tok_path)
            _device = "cuda" if torch.cuda.is_available() else "cpu"

            # Reconstruir config consistente con el entrenamiento.
            cfg = ConfigMultimodal(
                vit=ViTConfig(
                    image_size=224, patch_size=16, embed_dim=384,
                    n_layer=6, n_head=6,
                ),
                llm=ModelConfigV2(
                    vocab_size=_tokenizer.vocab_size,
                    block_size=512,
                    n_layer=8, n_head=8, n_embd=512, n_kv_head=2,
                ),
            )
            _modelo = ModeloMultimodal(cfg).to(_device)

            ckpt = torch.load(ckpt_path, map_location=_device, weights_only=False)
            state = ckpt.get("model", ckpt)
            _modelo.load_state_dict(state, strict=False)
            _modelo.eval()
            log.info(
                "[multimodal] Cargado de %s en %s", ckpt_path.name, _device,
            )
        except Exception as exc:  # noqa: BLE001
            _motivo_no_disponible = f"Error al cargar checkpoint: {exc}"
            log.exception("[multimodal] %s", _motivo_no_disponible)
            _modelo = None


def modelo_disponible() -> bool:
    if not _intentado:
        _cargar_modelo()
    return _modelo is not None


def motivo_no_disponible() -> str | None:
    if not _intentado:
        _cargar_modelo()
    return _motivo_no_disponible


def _preparar_imagen(blob: bytes, image_size: int = 224):
    """bytes → tensor (1, 3, 224, 224) normalizado a [-1, 1]."""
    import torch
    from PIL import Image

    img = Image.open(io.BytesIO(blob)).convert("RGB")
    if img.size != (image_size, image_size):
        img = img.resize((image_size, image_size), Image.Resampling.BILINEAR)
    arr = torch.frombuffer(img.tobytes(), dtype=torch.uint8).clone()
    arr = arr.view(image_size, image_size, 3)
    arr = arr.permute(2, 0, 1).float() / 255.0
    arr = (arr - 0.5) / 0.5
    return arr.unsqueeze(0)


def _generar_sincrono(
    texto_usuario: str, imagenes: list[tuple[bytes, str]],
) -> RespuestaMultimodal:
    import torch

    if _modelo is None or _tokenizer is None:
        raise RuntimeError("Modelo multimodal no cargado")

    # Usamos solo la primera imagen por simplicidad (multi-imagen es trivial
    # de extender, pero mejor empezar simple).
    img_tensor = _preparar_imagen(imagenes[0][0]).to(_device)

    prompt = f"<usuario> {texto_usuario} <fin> <asistente> "
    ids = _tokenizer.encode(prompt)
    if _tokenizer.bos_id is not None:
        ids = [_tokenizer.bos_id] + ids
    idx = torch.tensor([ids], dtype=torch.long, device=_device)

    t0 = time.perf_counter()
    with torch.no_grad():
        token_eos = _tokenizer.encode("<fin>")
        token_eos = token_eos[0] if token_eos else None
        salida = _modelo.generar(
            imagenes=img_tensor,
            idx_texto=idx,
            max_new_tokens=200,
            temperatura=0.7,
            top_p=0.9,
            token_eos=token_eos,
        )
    latencia = time.perf_counter() - t0

    nuevos = salida[0, len(ids):].tolist()
    texto = _tokenizer.decode(nuevos).strip()
    texto = texto.replace("<fin>", "").strip() or "(sin respuesta)"

    return RespuestaMultimodal(
        texto=texto,
        tokens_generados=len(nuevos),
        latencia_segundos=round(latencia, 3),
        device=_device,
    )


async def responder(
    texto_usuario: str, imagenes: list[tuple[bytes, str]],
) -> RespuestaMultimodal:
    """Genera una respuesta a partir de texto + imágenes con el modelo propio.

    Ejecuta la inferencia en un thread aparte para no bloquear el event loop.
    """
    if not modelo_disponible():
        raise RuntimeError(motivo_no_disponible() or "Modelo no disponible")
    return await asyncio.to_thread(_generar_sincrono, texto_usuario, imagenes)
