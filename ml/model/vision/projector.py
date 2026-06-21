"""VisionProjector — MLP que mapea features del ViT al espacio del LLM.

Idea (LLaVA, Liu et al. 2023):
    El ViT produce vectores en su propio espacio (embed_dim_vit, ej 384).
    El LLM espera tokens en SU espacio (n_embd del transformer_v2, ej 512).
    El projector es un MLP pequeño que aprende esa traducción:

        ViT features  →  [Linear → GELU → Linear]  →  tokens visuales para el LLM
        (B, P, 384)                                    (B, P, 512)

    Luego el LLM los recibe como si fueran tokens normales en su secuencia,
    intercalados con los embeddings de texto antes del `<imagen>` placeholder.

Por qué un MLP y no algo más complejo:
    LLaVA original usa Linear simple, LLaVA-1.5 usa MLP 2 capas. Los Q-Former
    (BLIP-2) son más capaces pero requieren mucho más entreno. Para nuestro
    sistema y dataset propio, MLP 2 capas es el equilibrio correcto.
"""

from __future__ import annotations

import torch
import torch.nn as nn


class VisionProjector(nn.Module):
    """Adapter MLP 2 capas con GELU.

    Args:
        in_dim:  dimensión de salida del ViT (cfg.embed_dim del ViTConfig).
        out_dim: dimensión de embeddings del LLM (cfg.n_embd del TransformerV2).
        hidden_dim: dimensión intermedia. Por defecto = out_dim.
        bias: si añadir bias a las capas Linear.
    """

    def __init__(
        self,
        in_dim: int,
        out_dim: int,
        hidden_dim: int | None = None,
        bias: bool = True,
    ) -> None:
        super().__init__()
        hidden = hidden_dim or out_dim
        self.fc1 = nn.Linear(in_dim, hidden, bias=bias)
        self.act = nn.GELU()
        self.fc2 = nn.Linear(hidden, out_dim, bias=bias)

        # Init razonable para que al inicio el LLM no se desestabilice.
        self._init_pesos()

    def _init_pesos(self) -> None:
        for capa in (self.fc1, self.fc2):
            nn.init.trunc_normal_(capa.weight, std=0.02)
            if capa.bias is not None:
                nn.init.zeros_(capa.bias)

    def forward(self, features_visuales: torch.Tensor) -> torch.Tensor:
        """
        Args:
            features_visuales: tensor (B, P, in_dim) — output del ViT.
                P = num parches (sin CLS si así fue elegido).
        Returns:
            tokens_visuales: tensor (B, P, out_dim) listos para el LLM.
        """
        x = self.fc1(features_visuales)
        x = self.act(x)
        x = self.fc2(x)
        return x

    def num_parametros(self) -> int:
        return sum(p.numel() for p in self.parameters() if p.requires_grad)
