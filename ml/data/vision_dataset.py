"""Dataset PyTorch para entrenamiento multimodal.

Lee el JSONL producido por `generar_imagenes_codigo.py` y devuelve, para
cada muestra:

    imagen: tensor (3, image_size, image_size) normalizado a [-1, 1]
    idx_texto: tensor (T,) con tokens del prompt + respuesta
    targets: tensor (P + T,) — -100 en posiciones visuales y de prompt,
             ids reales solo donde se predice la respuesta

Donde P = número de tokens visuales (num_visual_tokens del modelo).

Formato del texto:
    <usuario> {instrucción} <fin>
    <asistente> {respuesta} <fin>

Solo se calcula loss sobre la parte de respuesta (más <fin>).
"""

from __future__ import annotations

import json
import random
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

import torch
from PIL import Image
from torch.utils.data import Dataset

# Tokens especiales — usamos los strings, el tokenizer los convierte a ids.
TOKEN_USUARIO = "<usuario>"
TOKEN_ASISTENTE = "<asistente>"
TOKEN_FIN = "<fin>"
TOKEN_IMAGEN = "<imagen>"   # placeholder textual, no se tokeniza realmente


@dataclass(slots=True)
class ConfigDatasetVision:
    raiz: Path                    # carpeta con pares.jsonl + imagenes/
    image_size: int = 224
    block_size: int = 256          # tokens de texto máximo
    num_visual_tokens: int = 196   # debe coincidir con el modelo
    normalizacion: tuple[float, float] = (0.5, 0.5)  # mean, std → [-1, 1]


class VisionDataset(Dataset):
    """Dataset multimodal código-imagen → explicación.

    Args:
        cfg: configuración.
        codificar: función tokenizer (texto → list[int]).
        token_pad: id del token de padding.
        token_bos: id del token de inicio (opcional).
    """

    def __init__(
        self,
        cfg: ConfigDatasetVision,
        codificar: Callable[[str], list[int]],
        token_pad: int,
        token_bos: int | None = None,
    ) -> None:
        self.cfg = cfg
        self.codificar = codificar
        self.token_pad = token_pad
        self.token_bos = token_bos

        pares_path = cfg.raiz / "pares.jsonl"
        if not pares_path.exists():
            raise FileNotFoundError(
                f"No se encontró {pares_path}. "
                f"Genera el dataset primero con "
                f"`python -m ml.data.generar_imagenes_codigo`."
            )
        with pares_path.open(encoding="utf-8") as f:
            self.muestras = [json.loads(linea) for linea in f if linea.strip()]
        self.dir_imgs = cfg.raiz / "imagenes"

    def __len__(self) -> int:
        return len(self.muestras)

    # ─────────────── Helpers ───────────────

    def _cargar_imagen(self, nombre: str) -> torch.Tensor:
        img = Image.open(self.dir_imgs / nombre).convert("RGB")
        if img.size != (self.cfg.image_size, self.cfg.image_size):
            img = img.resize(
                (self.cfg.image_size, self.cfg.image_size),
                Image.Resampling.BILINEAR,
            )
        # (H, W, 3) → (3, H, W), [0, 255] → [-1, 1]
        arr = torch.frombuffer(img.tobytes(), dtype=torch.uint8).clone()
        arr = arr.view(self.cfg.image_size, self.cfg.image_size, 3)
        arr = arr.permute(2, 0, 1).float() / 255.0
        mean, std = self.cfg.normalizacion
        return (arr - mean) / std

    def _construir_secuencia(
        self, instruccion: str, respuesta: str,
    ) -> tuple[list[int], int]:
        """Devuelve (ids, longitud_prompt).

        Estructura: [BOS] <usuario> instr <fin> <asistente> resp <fin>

        longitud_prompt = posición desde donde empieza la respuesta
        (para enmascarar el loss en el prompt).
        """
        partes_prompt = f"{TOKEN_USUARIO} {instruccion} {TOKEN_FIN} {TOKEN_ASISTENTE} "
        partes_respuesta = f"{respuesta} {TOKEN_FIN}"

        ids_prompt = self.codificar(partes_prompt)
        if self.token_bos is not None:
            ids_prompt = [self.token_bos] + ids_prompt
        ids_respuesta = self.codificar(partes_respuesta)

        ids = ids_prompt + ids_respuesta
        return ids, len(ids_prompt)

    # ─────────────── __getitem__ ───────────────

    def __getitem__(self, idx: int) -> dict[str, torch.Tensor]:
        muestra = self.muestras[idx]
        imagen = self._cargar_imagen(muestra["imagen"])
        ids, n_prompt = self._construir_secuencia(
            muestra["instruccion"], muestra["respuesta"],
        )

        # Truncar/padear texto a block_size
        if len(ids) > self.cfg.block_size:
            ids = ids[: self.cfg.block_size]
            n_prompt = min(n_prompt, self.cfg.block_size)
        T_texto = len(ids)
        pad_n = self.cfg.block_size - T_texto
        ids_full = ids + [self.token_pad] * pad_n
        idx_texto = torch.tensor(ids_full, dtype=torch.long)

        # Construir targets de longitud P + block_size.
        # Posiciones visuales: -100 (no loss).
        # Prompt (incluido <asistente>): -100.
        # Respuesta + <fin>: ids reales.
        # Padding: -100.
        P = self.cfg.num_visual_tokens
        targets = torch.full(
            (P + self.cfg.block_size,), -100, dtype=torch.long,
        )
        # Para next-token prediction: target[i] = idx_texto[i+1] aprox.
        # En LLM causal estándar, target[i] = lo que predice la posición i.
        # Aquí, posición (P + i) predice el token (i+1) del texto. Para
        # mantenerlo simple, alineamos targets con la secuencia de input
        # (la pérdida estándar de language modeling shifteada).
        # Posiciones de respuesta en idx_texto: [n_prompt, T_texto)
        for i in range(n_prompt, T_texto - 1):
            # La posición (P + i) predice el siguiente token de texto.
            targets[P + i] = idx_texto[i + 1]
        # Última posición de respuesta: target = pad (cae en -100 ya).

        return {
            "imagen": imagen,
            "idx_texto": idx_texto,
            "targets": targets,
        }


def collate_multimodal(batch: list[dict[str, torch.Tensor]]) -> dict[str, torch.Tensor]:
    """Apila un batch. Todas las muestras ya tienen el mismo tamaño gracias
    al padding en __getitem__."""
    return {
        "imagen": torch.stack([b["imagen"] for b in batch], dim=0),
        "idx_texto": torch.stack([b["idx_texto"] for b in batch], dim=0),
        "targets": torch.stack([b["targets"] for b in batch], dim=0),
    }
