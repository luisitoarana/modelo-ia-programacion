"""Arquitectura del modelo (Transformer decoder desde cero).

Hay dos versiones disponibles:
    - v1 (`GPTEducativo`)   : PositionalEncoding + MHA + GeLU + LayerNorm.
                               Más fiel al GPT original (Vaswani 2017).
    - v2 (`GPTEducativoV2`) : RoPE + GQA + SwiGLU + RMSNorm + FlashAttention.
                               Arquitectura SOTA 2024-2025 (Llama/Mistral-like).

Ambas exponen la misma API pública (`forward`, `generar`, `num_parametros`,
`configurar_optimizador`), por lo que se intercambian sin modificar el
resto del pipeline (train.py, generate.py, model_inference_service.py).

Ver `docs/MODELO_V2.md` para una explicación detallada de cada técnica.
"""

# v1 (clásico)
from ml.model.transformer import (
    Bloque,
    CausalSelfAttention,
    FeedForward,
    GPTEducativo,
    PositionalEncoding,
)

# v2 (SOTA)
from ml.model.transformer_v2 import (
    BloqueV2,
    GPTEducativoV2,
    GroupedQueryAttention,
    ModelConfigV2,
    RMSNorm,
    SwiGLU,
    aplicar_rope,
    precomputar_rope,
)

__all__ = [
    # v1
    "Bloque",
    "CausalSelfAttention",
    "FeedForward",
    "GPTEducativo",
    "PositionalEncoding",
    # v2
    "BloqueV2",
    "GPTEducativoV2",
    "GroupedQueryAttention",
    "ModelConfigV2",
    "RMSNorm",
    "SwiGLU",
    "aplicar_rope",
    "precomputar_rope",
]
