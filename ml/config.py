"""Configuración del modelo y del entrenamiento.

Define dataclasses tipadas y presets dimensionados para una GPU modesta
(RTX 2050, 4 GB) o CPU. Todo es device-agnostic.
"""

from __future__ import annotations

import json
from dataclasses import asdict, dataclass, field
from pathlib import Path


# Rutas base del proyecto (este archivo: <raiz>/ml/config.py)
RAIZ = Path(__file__).resolve().parents[1]
DIR_DATASETS = RAIZ / "datasets"
DIR_ML = RAIZ / "ml"
DIR_CHECKPOINTS = RAIZ / "training" / "checkpoints"
DIR_EXPERIMENTOS = RAIZ / "training" / "experiments"
DIR_TOKENIZER = DIR_ML / "tokenizer" / "artefactos"


@dataclass(slots=True)
class ModelConfig:
    """Hiperparámetros de la arquitectura Transformer decoder."""

    vocab_size: int = 8000          # lo fija el tokenizer entrenado
    block_size: int = 256           # longitud de contexto (tokens)
    n_layer: int = 6                # bloques Transformer
    n_head: int = 6                 # cabezas de atención
    n_embd: int = 384               # dimensión de embedding (múltiplo de n_head)
    dropout: float = 0.1
    bias: bool = True               # usar bias en linears y layernorm
    tie_weights: bool = True        # compartir embedding y LM head

    def __post_init__(self) -> None:
        if self.n_embd % self.n_head != 0:
            raise ValueError(
                f"n_embd ({self.n_embd}) debe ser múltiplo de n_head ({self.n_head})"
            )

    @property
    def head_dim(self) -> int:
        return self.n_embd // self.n_head

    def to_dict(self) -> dict:
        return asdict(self)

    @classmethod
    def from_dict(cls, d: dict) -> "ModelConfig":
        campos = {k: v for k, v in d.items() if k in cls.__slots__}  # type: ignore[attr-defined]
        return cls(**campos)


@dataclass(slots=True)
class TrainConfig:
    """Hiperparámetros del entrenamiento."""

    # Datos
    dataset_jsonl: str = str(DIR_DATASETS / "processed" / "corpus_entrenamiento.jsonl")
    val_split: float = 0.1
    test_split: float = 0.1
    seed: int = 1337

    # Optimización
    batch_size: int = 16
    grad_accum_steps: int = 2       # batch efectivo = batch_size * grad_accum
    learning_rate: float = 3e-4
    min_lr: float = 3e-5
    weight_decay: float = 0.1
    beta1: float = 0.9
    beta2: float = 0.95
    grad_clip: float = 1.0

    # Schedule
    max_iters: int = 5000
    warmup_iters: int = 200
    lr_decay: bool = True

    # Evaluación / logging
    eval_interval: int = 250
    eval_iters: int = 50
    log_interval: int = 20

    # Sistema
    device: str = "auto"            # auto | cuda | cpu
    dtype: str = "auto"             # auto | float32 | bfloat16 | float16
    compile_model: bool = False     # torch.compile (puede fallar en Windows)
    num_workers: int = 2

    # Salida
    nombre_experimento: str = "exp01"
    checkpoint_dir: str = str(DIR_CHECKPOINTS)

    def to_dict(self) -> dict:
        return asdict(self)

    @classmethod
    def from_dict(cls, d: dict) -> "TrainConfig":
        campos = {k: v for k, v in d.items() if k in cls.__slots__}  # type: ignore[attr-defined]
        return cls(**campos)


# ---------------------------------------------------------------------------
# Presets
# ---------------------------------------------------------------------------

def preset_nano() -> ModelConfig:
    """~1-3M parámetros. Para pruebas rápidas en CPU."""
    return ModelConfig(block_size=128, n_layer=4, n_head=4, n_embd=128)


def preset_pequeno() -> ModelConfig:
    """~15-20M parámetros. Recomendado para RTX 2050 (4 GB)."""
    return ModelConfig(block_size=256, n_layer=6, n_head=6, n_embd=384)


def preset_mediano() -> ModelConfig:
    """~40-60M parámetros. Requiere ≥6 GB VRAM o entrenamiento largo en CPU."""
    return ModelConfig(block_size=384, n_layer=8, n_head=8, n_embd=512)


def preset_experto() -> ModelConfig:
    """~55-70M parámetros. OPTIMIZADO para RTX 2050 (4 GB) entrenando largo.

    Filosofía: "el mejor modelo posible que cabe en 4 GB". Más capas que
    `mediano`, mismo embedding, contexto MAYOR (512 tokens) para capturar
    archivos Python enteros pequeños. Pensado para correr 1-2 meses con
    gradient_checkpointing activo en train.py.

    Comparado con mediano:
      - +50% de capas (12 vs 8) → más profundidad de razonamiento
      - +33% de contexto (512 vs 384) → ve más código de una vez
      - Vocab 16k (vs 8k) → mejor tokenización de Python e inglés
    """
    return ModelConfig(
        block_size=512,
        n_layer=12,
        n_head=8,
        n_embd=512,
        vocab_size=16000,
    )


def preset_grande() -> ModelConfig:
    """~120M parámetros (similar a GPT-2 small).

    Hardware:
      - RTX 2050 4 GB: NO entra sin offloading + grad checkpointing.
      - RTX 3060 8-12 GB: entrena cómodo con batch_size=4-8.
      - RTX 3090/4090 24 GB: muy holgado.
    Tiempo en RTX 3060: ~6-24 h para 4000 iters con buen dataset.
    """
    return ModelConfig(block_size=512, n_layer=12, n_head=12, n_embd=768)


def preset_xl() -> ModelConfig:
    """~350M parámetros (similar a GPT-2 medium).

    Hardware:
      - RTX 2050 4 GB: imposible incluso con todos los trucos.
      - RTX 3060/4060: muy apretado, batch=1 + offload.
      - RTX 3090/4090 24 GB: cómodo con batch=2-4 + grad accum.
      - A100 40 GB: holgado.
    Tiempo en RTX 4090: ~1-3 días para 10k iters.
    """
    return ModelConfig(block_size=512, n_layer=24, n_head=16, n_embd=1024)


def preset_xxl() -> ModelConfig:
    """~1.3B parámetros (similar a GPT-2 large→XL).

    Hardware:
      - Necesita 48+ GB VRAM o multi-GPU con DeepSpeed/FSDP.
      - Recomendado: 2× A100 80 GB o 1× H100.
    Tiempo: 1-2 semanas en hardware adecuado.

    Para tu RTX 2050: usa fine-tuning QLoRA de un modelo open-source
    de tamaño parecido en su lugar — entra en 4 GB y aprovecha que
    ya está pre-entrenado. Ver ml/finetune.py.
    """
    return ModelConfig(block_size=1024, n_layer=40, n_head=22, n_embd=1408)


PRESETS = {
    "nano": preset_nano,
    "pequeno": preset_pequeno,
    "mediano": preset_mediano,
    "experto": preset_experto,
    "grande": preset_grande,
    "xl": preset_xl,
    "xxl": preset_xxl,
}


# ─────────────────────────────────────────────────────────────────────
# Presets v2 (SOTA: RoPE + GQA + SwiGLU + RMSNorm + FlashAttention)
# ─────────────────────────────────────────────────────────────────────

def preset_sota_experto():
    """~50M parámetros con arquitectura moderna (Llama-like).

    Comparable en tamaño al preset_experto v1 pero con:
        - GQA (n_head=8 / n_kv_head=2) → KV cache 4× más chico
        - RoPE → contexto extrapolable
        - SwiGLU + RMSNorm
        - FlashAttention vía F.scaled_dot_product_attention

    Pensado para entrenar en RTX 2050 (4 GB) en tiempos similares al v1.
    """
    from ml.model.transformer_v2 import ModelConfigV2
    return ModelConfigV2(
        vocab_size=16000,
        block_size=512,
        n_layer=8,
        n_head=8,
        n_kv_head=2,        # GQA (factor 4)
        n_embd=512,
        dropout=0.0,
        rope_theta=10_000.0,
        swiglu_mult=8 / 3,
        norm_eps=1e-6,
        bias=False,
        tie_weights=True,
    )


def preset_sota_grande():
    """~120M parámetros (escala GPT-2 small, arquitectura moderna).

    Hardware: necesita ≥ 8 GB VRAM o batch chico con gradient accum.
    """
    from ml.model.transformer_v2 import ModelConfigV2
    return ModelConfigV2(
        vocab_size=16000,
        block_size=1024,
        n_layer=12,
        n_head=12,
        n_kv_head=4,        # GQA (factor 3)
        n_embd=768,
        dropout=0.0,
        rope_theta=10_000.0,
        swiglu_mult=8 / 3,
        bias=False,
        tie_weights=True,
    )


def preset_sota_b():
    """Modelo B del PLAN_ENTRENAMIENTO_V2 — ~120M parámetros reales.

    Hardware:
      - RTX 2050 4GB con gradient_checkpointing: cabe (batch 2, grad accum 16)
      - Kaggle T4 16GB: cómodo
    Tiempo training estimado (5 fases): ~30h en T4.

    Vs sota_grande: swiglu_mult=4 (Llama original) en lugar de 8/3, sube n_layer
    a 16 para alcanzar el conteo de 120M reales.
    """
    from ml.model.transformer_v2 import ModelConfigV2
    return ModelConfigV2(
        vocab_size=16000,
        block_size=1024,
        n_layer=16,
        n_head=12,
        n_kv_head=4,        # GQA factor 3
        n_embd=768,
        dropout=0.0,
        rope_theta=10_000.0,
        swiglu_mult=4.0,    # FFN expansion ratio Llama-like
        bias=False,
        tie_weights=True,
    )


def preset_sota_c():
    """Modelo C del PLAN_ENTRENAMIENTO_V2 — ~350M parámetros reales.

    Hardware:
      - RTX 2050 4GB: NO entra ni con todos los trucos.
      - Kaggle T4 16GB con gradient_checkpointing + batch 1: justo.
      - Kaggle P100 16GB: más cómodo.
      - Modal A10G 24GB / Lightning A10G: holgado.
    Tiempo training estimado (5 fases): ~70h en T4 o ~25h en A10G.

    El modelo principal de la tesis. Capacidad suficiente para almacenar
    patrones complejos de programación, refactorización y razonamiento
    iterativo (auto-crítica).
    """
    from ml.model.transformer_v2 import ModelConfigV2
    return ModelConfigV2(
        vocab_size=16000,
        block_size=2048,
        n_layer=22,        # 22 capas dan ~350M; 28 daban ~440M (oversize)
        n_head=16,
        n_kv_head=4,        # GQA factor 4
        n_embd=1024,
        dropout=0.0,
        rope_theta=10_000.0,
        swiglu_mult=4.0,
        bias=False,
        tie_weights=True,
    )


def preset_sota_d():
    """Modelo D del PLAN_ENTRENAMIENTO_V2 — ~700M-1B parámetros (OPCIONAL).

    Hardware:
      - Requiere A100 40GB+ o multi-GPU con DeepSpeed/FSDP.
      - Modal A100 con free credits: cabe (batch 1 + grad accum + GC).
    Tiempo training (5 fases): ~150h+.

    Sólo entrenar si los créditos cloud free alcanzan. La tesis principal
    son A+B+C; D es extensión académica.
    """
    from ml.model.transformer_v2 import ModelConfigV2
    return ModelConfigV2(
        vocab_size=16000,
        block_size=2048,
        n_layer=36,
        n_head=20,
        n_kv_head=4,        # GQA factor 5
        n_embd=1280,
        dropout=0.0,
        rope_theta=10_000.0,
        swiglu_mult=4.0,
        bias=False,
        tie_weights=True,
    )


PRESETS_V2 = {
    "sota_experto": preset_sota_experto,    # ~30M — debug rápido
    "sota_grande": preset_sota_grande,      # ~88M — preset intermedio
    "sota_b": preset_sota_b,                # Modelo B del plan: ~120M
    "sota_c": preset_sota_c,                # Modelo C del plan: ~350M
    "sota_d": preset_sota_d,                # Modelo D opcional: ~700M-1B
}


def guardar_config(ruta: Path, model_cfg: ModelConfig, train_cfg: TrainConfig | None = None) -> None:
    ruta.parent.mkdir(parents=True, exist_ok=True)
    payload = {"model": model_cfg.to_dict()}
    if train_cfg is not None:
        payload["train"] = train_cfg.to_dict()
    ruta.write_text(json.dumps(payload, indent=2, ensure_ascii=False), encoding="utf-8")


def resolver_device(preferencia: str = "auto") -> str:
    """Devuelve 'cuda' si hay GPU disponible (y se pidió), si no 'cpu'."""
    try:
        import torch
        if preferencia == "cuda":
            return "cuda" if torch.cuda.is_available() else "cpu"
        if preferencia == "cpu":
            return "cpu"
        return "cuda" if torch.cuda.is_available() else "cpu"
    except ImportError:
        return "cpu"
