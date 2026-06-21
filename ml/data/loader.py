"""Carga de datos para entrenamiento autoregresivo.

Estrategia de empaquetado (estilo nanoGPT):
    1. Cada ejemplo se serializa con la plantilla del tokenizer:
       <bos><instr>...<inp>...<out>...<eos>
    2. Se concatenan todos los flujos de tokens en un único tensor 1-D.
    3. El entrenamiento muestrea ventanas contiguas de longitud block_size,
       donde el objetivo es predecir el siguiente token (desplazamiento de 1).
"""

from __future__ import annotations

import random

import torch
from torch.utils.data import Dataset

from ml.data.schema import EjemploEntrenamiento
from ml.tokenizer.bpe import BPETokenizer


def empaquetar_tokens(
    ejemplos: list[EjemploEntrenamiento],
    tokenizer: BPETokenizer,
) -> torch.Tensor:
    """Serializa y concatena todos los ejemplos en un tensor 1-D de tokens."""
    ids: list[int] = []
    for ej in ejemplos:
        ids.extend(
            tokenizer.encode_plantilla(
                instruccion=ej.instruccion,
                entrada=ej.entrada,
                salida=ej.salida,
            )
        )
    if not ids:
        return torch.zeros(0, dtype=torch.long)
    return torch.tensor(ids, dtype=torch.long)


def split_datos(
    data: torch.Tensor,
    *,
    val_split: float = 0.1,
    test_split: float = 0.1,
) -> tuple[torch.Tensor, torch.Tensor, torch.Tensor]:
    """Divide el flujo de tokens en train/val/test de forma contigua."""
    n = data.numel()
    n_test = int(n * test_split)
    n_val = int(n * val_split)
    n_train = n - n_val - n_test
    train = data[:n_train]
    val = data[n_train : n_train + n_val]
    test = data[n_train + n_val :]
    return train, val, test


def get_batch(
    data: torch.Tensor,
    *,
    batch_size: int,
    block_size: int,
    device: str = "cpu",
    generador: random.Random | None = None,
) -> tuple[torch.Tensor, torch.Tensor]:
    """Muestrea un lote (x, y) de ventanas contiguas.

    x: (B, block_size)   y: (B, block_size) desplazado una posición.
    """
    rng = generador or random
    n = data.numel()
    if n <= block_size + 1:
        raise ValueError(
            f"Datos insuficientes ({n} tokens) para block_size={block_size}. "
            "Genera o agrega más ejemplos al corpus."
        )
    maximo = n - block_size - 1
    offsets = [rng.randint(0, maximo) for _ in range(batch_size)]
    x = torch.stack([data[i : i + block_size] for i in offsets])
    y = torch.stack([data[i + 1 : i + 1 + block_size] for i in offsets])
    if device == "cuda":
        x = x.pin_memory().to(device, non_blocking=True)
        y = y.pin_memory().to(device, non_blocking=True)
    else:
        x = x.to(device)
        y = y.to(device)
    return x, y


class PackedDataset(Dataset):
    """Dataset map-style sobre ventanas no solapadas (para DataLoader)."""

    def __init__(self, data: torch.Tensor, block_size: int) -> None:
        self.data = data
        self.block_size = block_size
        self.n_ventanas = max(0, (data.numel() - 1) // block_size)

    def __len__(self) -> int:
        return self.n_ventanas

    def __getitem__(self, idx: int) -> tuple[torch.Tensor, torch.Tensor]:
        inicio = idx * self.block_size
        x = self.data[inicio : inicio + self.block_size]
        y = self.data[inicio + 1 : inicio + 1 + self.block_size]
        return x, y
