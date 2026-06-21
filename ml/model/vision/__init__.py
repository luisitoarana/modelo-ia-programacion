"""Modelo de visión propio — Vision Transformer (ViT) desde cero.

Componentes:
    - `patch_embedder.py` : corta la imagen en parches y los embebe.
    - `vit_encoder.py`    : Vision Transformer puro (encoder-only).
    - `projector.py`      : adapter MLP que mapea features visuales al
      espacio de embeddings del LLM (estilo LLaVA).

Ningún componente depende de modelos pre-entrenados externos. Todo se
entrena con el dataset propio en `ml/data/vision_dataset.py`.

Ver `docs/VISION_PROPIA.md` para la justificación arquitectónica.
"""

from ml.model.vision.patch_embedder import PatchEmbedder
from ml.model.vision.vit_encoder import VisionTransformer, ViTConfig
from ml.model.vision.projector import VisionProjector

__all__ = [
    "PatchEmbedder",
    "VisionTransformer",
    "ViTConfig",
    "VisionProjector",
]
