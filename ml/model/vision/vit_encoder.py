"""Vision Transformer (ViT) — encoder visual desde cero.

Procesa la secuencia de tokens visuales del PatchEmbedder con bloques
Transformer (atención + FFN). El output es una secuencia de features
visuales contextualizados, lista para alimentar al LLM.

Diseño:
    - Pre-norm (LayerNorm antes de attention/FFN — más estable).
    - Atención no causal (las imágenes no tienen orden temporal).
    - SwiGLU en FFN (mismo estilo que el transformer_v2 del LLM).
    - Soporte para usar todos los tokens (no solo CLS) — necesario para
      LLaVA-style donde el LLM ve TODA la secuencia visual.

Paper: Dosovitskiy et al., "An Image is Worth 16x16 Words", ICLR 2021.
"""

from __future__ import annotations

from dataclasses import dataclass

import torch
import torch.nn as nn
import torch.nn.functional as F

from ml.model.vision.patch_embedder import PatchEmbedder


@dataclass(slots=True)
class ViTConfig:
    """Hiperparámetros del Vision Transformer."""

    image_size: int = 224
    patch_size: int = 16
    in_channels: int = 3

    # Arquitectura
    n_layer: int = 6          # bloques transformer
    n_head: int = 6           # cabezas de atención
    embed_dim: int = 384      # dimensión interna del ViT
    mlp_ratio: float = 4.0    # multiplicador del FFN hidden
    dropout: float = 0.0
    bias: bool = False

    use_cls_token: bool = True

    def __post_init__(self) -> None:
        if self.embed_dim % self.n_head != 0:
            raise ValueError(
                f"embed_dim ({self.embed_dim}) debe ser múltiplo de "
                f"n_head ({self.n_head})"
            )

    @property
    def head_dim(self) -> int:
        return self.embed_dim // self.n_head

    @property
    def num_patches(self) -> int:
        return (self.image_size // self.patch_size) ** 2

    @property
    def num_tokens(self) -> int:
        return self.num_patches + (1 if self.use_cls_token else 0)


# ════════════════════════════════════════════════════════════════════
# Bloques internos
# ════════════════════════════════════════════════════════════════════

class ViTAttention(nn.Module):
    """Multi-head self-attention NO causal (todos ven a todos)."""

    def __init__(self, cfg: ViTConfig) -> None:
        super().__init__()
        self.n_head = cfg.n_head
        self.head_dim = cfg.head_dim
        self.qkv = nn.Linear(cfg.embed_dim, 3 * cfg.embed_dim, bias=cfg.bias)
        self.proj = nn.Linear(cfg.embed_dim, cfg.embed_dim, bias=cfg.bias)
        self.dropout_p = cfg.dropout

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        B, T, C = x.shape
        qkv = self.qkv(x).reshape(B, T, 3, self.n_head, self.head_dim)
        qkv = qkv.permute(2, 0, 3, 1, 4)
        q, k, v = qkv.unbind(0)  # cada uno: (B, n_head, T, head_dim)

        # Atención bidireccional (sin máscara causal).
        # PyTorch SDPA usa FlashAttention si CUDA + bf16/fp16.
        y = F.scaled_dot_product_attention(
            q, k, v,
            attn_mask=None,
            dropout_p=self.dropout_p if self.training else 0.0,
            is_causal=False,  # ← clave: visión es no causal
        )
        y = y.transpose(1, 2).contiguous().reshape(B, T, C)
        return self.proj(y)


class ViTMLP(nn.Module):
    """FFN clásico con GeLU. Más simple que SwiGLU para el ViT.
    Si se requiere SwiGLU, reemplazar análogamente a transformer_v2."""

    def __init__(self, cfg: ViTConfig) -> None:
        super().__init__()
        hidden = int(cfg.embed_dim * cfg.mlp_ratio)
        self.fc1 = nn.Linear(cfg.embed_dim, hidden, bias=cfg.bias)
        self.act = nn.GELU()
        self.fc2 = nn.Linear(hidden, cfg.embed_dim, bias=cfg.bias)
        self.dropout = nn.Dropout(cfg.dropout)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return self.dropout(self.fc2(self.act(self.fc1(x))))


class ViTBlock(nn.Module):
    """Bloque pre-norm: norm → attn → residual → norm → mlp → residual."""

    def __init__(self, cfg: ViTConfig) -> None:
        super().__init__()
        self.norm1 = nn.LayerNorm(cfg.embed_dim, eps=1e-6)
        self.attn = ViTAttention(cfg)
        self.norm2 = nn.LayerNorm(cfg.embed_dim, eps=1e-6)
        self.mlp = ViTMLP(cfg)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        x = x + self.attn(self.norm1(x))
        x = x + self.mlp(self.norm2(x))
        return x


# ════════════════════════════════════════════════════════════════════
# Vision Transformer principal
# ════════════════════════════════════════════════════════════════════

class VisionTransformer(nn.Module):
    """ViT desde cero.

    Forward:
        imagen (B, 3, H, W)
            → PatchEmbedder → (B, num_tokens, embed_dim)
            → n bloques transformer
            → LayerNorm final
            → features (B, num_tokens, embed_dim)

    El consumidor decide qué hace con las features:
        - Clasificación: tomar features[:, 0] (token CLS).
        - LLaVA / multimodal: pasar TODOS los tokens (sin CLS) al
          projector que los mapea al espacio del LLM.
    """

    def __init__(self, cfg: ViTConfig) -> None:
        super().__init__()
        self.cfg = cfg

        # 1. Embedder de parches (con pos embedding + CLS opcional)
        self.patch_embed = PatchEmbedder(
            image_size=cfg.image_size,
            patch_size=cfg.patch_size,
            in_channels=cfg.in_channels,
            embed_dim=cfg.embed_dim,
            use_cls_token=cfg.use_cls_token,
        )

        # 2. Pila de bloques transformer
        self.blocks = nn.ModuleList(
            [ViTBlock(cfg) for _ in range(cfg.n_layer)]
        )

        # 3. LayerNorm final (estándar pre-norm ViT)
        self.norm = nn.LayerNorm(cfg.embed_dim, eps=1e-6)

        # Inicialización
        self.apply(self._init_pesos)

    @staticmethod
    def _init_pesos(modulo: nn.Module) -> None:
        if isinstance(modulo, nn.Linear):
            nn.init.trunc_normal_(modulo.weight, std=0.02)
            if modulo.bias is not None:
                nn.init.zeros_(modulo.bias)
        elif isinstance(modulo, nn.LayerNorm):
            nn.init.ones_(modulo.weight)
            nn.init.zeros_(modulo.bias)
        elif isinstance(modulo, nn.Conv2d):
            nn.init.trunc_normal_(modulo.weight, std=0.02)
            if modulo.bias is not None:
                nn.init.zeros_(modulo.bias)

    def num_parametros(self) -> int:
        return sum(p.numel() for p in self.parameters() if p.requires_grad)

    def forward(self, imagenes: torch.Tensor) -> torch.Tensor:
        """
        Args:
            imagenes: tensor (B, 3, H, W) normalizado a [0, 1] o [-1, 1].
        Returns:
            features: tensor (B, num_tokens, embed_dim)
        """
        x = self.patch_embed(imagenes)
        for block in self.blocks:
            x = block(x)
        x = self.norm(x)
        return x

    # ─────────────── helpers de inferencia ───────────────

    def features_cls(self, imagenes: torch.Tensor) -> torch.Tensor:
        """Devuelve solo el token CLS — útil para clasificación."""
        out = self.forward(imagenes)
        if not self.cfg.use_cls_token:
            raise RuntimeError("Este ViT se creó sin token CLS.")
        return out[:, 0]                # (B, embed_dim)

    def features_patches(self, imagenes: torch.Tensor) -> torch.Tensor:
        """Devuelve solo los patches (sin CLS) — útil para multimodal LLaVA."""
        out = self.forward(imagenes)
        if self.cfg.use_cls_token:
            return out[:, 1:]           # quita el CLS
        return out
