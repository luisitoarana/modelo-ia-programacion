"""PatchEmbedder — convierte una imagen en una secuencia de tokens.

Analogía con texto:
    - Tokenizer texto: "hola mundo" → [42, 851]            (cada palabra es un token)
    - Patch embedder: imagen 224×224 → 196 patches → 196 vectores
                       (cada patch de 16×16 píxeles es un "token visual")

Implementación:
    1. Imagen (B, 3, H, W) — RGB
    2. Conv2d con kernel=patch_size, stride=patch_size:
         (B, 3, 224, 224) → (B, embed_dim, 14, 14)
    3. Flatten + transpose:
         (B, embed_dim, 14, 14) → (B, 196, embed_dim)
    4. Añadir token [CLS] al inicio (opcional, para clasificación):
         (B, 196, embed_dim) → (B, 197, embed_dim)
    5. Sumar positional embeddings (los patches están en una grilla 2D
       pero los tratamos como secuencia 1D + embedding posicional).

Paper:
    Dosovitskiy et al., "An Image is Worth 16x16 Words: Transformers
    for Image Recognition at Scale", ICLR 2021.
"""

from __future__ import annotations

import math

import torch
import torch.nn as nn


class PatchEmbedder(nn.Module):
    """Convierte una imagen en una secuencia de embeddings de parches.

    Args:
        image_size: lado de la imagen cuadrada de entrada (px). 224 estándar.
        patch_size: lado de cada parche (px). 16 estándar.
        in_channels: canales de la imagen (3 para RGB).
        embed_dim: dimensión del embedding (debe coincidir con el ViT).
        use_cls_token: añadir token CLS aprendible al inicio (estándar en ViT).
    """

    def __init__(
        self,
        image_size: int = 224,
        patch_size: int = 16,
        in_channels: int = 3,
        embed_dim: int = 384,
        use_cls_token: bool = True,
    ) -> None:
        super().__init__()
        if image_size % patch_size != 0:
            raise ValueError(
                f"image_size ({image_size}) debe ser múltiplo de "
                f"patch_size ({patch_size})"
            )

        self.image_size = image_size
        self.patch_size = patch_size
        self.embed_dim = embed_dim
        self.use_cls_token = use_cls_token

        # Número de parches: (224/16)² = 14² = 196
        self.num_patches = (image_size // patch_size) ** 2
        # Secuencia final: 196 + 1 (CLS) = 197
        self.num_tokens = self.num_patches + (1 if use_cls_token else 0)

        # Conv2d con stride = patch_size hace el "corte" + proyección en un paso.
        # Cada parche de (3, 16, 16) → vector de (embed_dim,)
        self.proj = nn.Conv2d(
            in_channels, embed_dim,
            kernel_size=patch_size, stride=patch_size,
        )

        # Token CLS aprendible — vector que se prepende a la secuencia.
        # Sirve como "resumen" agregado de la imagen (útil para clasificación).
        if use_cls_token:
            self.cls_token = nn.Parameter(torch.zeros(1, 1, embed_dim))
            nn.init.trunc_normal_(self.cls_token, std=0.02)

        # Embeddings posicionales aprendibles para cada token.
        # Forma: (1, num_tokens, embed_dim). Se suma a la secuencia.
        self.pos_embed = nn.Parameter(torch.zeros(1, self.num_tokens, embed_dim))
        nn.init.trunc_normal_(self.pos_embed, std=0.02)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        """
        Args:
            x: tensor (B, C, H, W) — imagen RGB normalizada
        Returns:
            tensor (B, num_tokens, embed_dim)
        """
        B, _, H, W = x.shape
        if H != self.image_size or W != self.image_size:
            raise ValueError(
                f"Imagen debe ser {self.image_size}×{self.image_size}, "
                f"recibido {H}×{W}"
            )

        # 1. Conv2d aplica el corte + la proyección lineal por parche.
        # (B, 3, 224, 224) → (B, embed_dim, 14, 14)
        x = self.proj(x)

        # 2. Aplanar la grilla espacial a una secuencia:
        # (B, embed_dim, 14, 14) → (B, embed_dim, 196) → (B, 196, embed_dim)
        x = x.flatten(2).transpose(1, 2)

        # 3. Prepender token CLS si está habilitado.
        if self.use_cls_token:
            cls = self.cls_token.expand(B, -1, -1)        # (B, 1, embed_dim)
            x = torch.cat([cls, x], dim=1)                # (B, 197, embed_dim)

        # 4. Sumar embeddings posicionales.
        x = x + self.pos_embed

        return x
