"""Datos de entrenamiento: esquema, corpus, generación y carga.

Las APIs externas se usan SOLO aquí (en generator.py) para producir datos
de entrenamiento. El resto del pipeline (tokenizer, modelo, training,
inference) es 100% propio.
"""

from ml.data.schema import EjemploEntrenamiento
from ml.data.corpus import (
    cargar_jsonl,
    construir_textos_tokenizer,
    deduplicar,
    estadisticas_corpus,
    guardar_jsonl,
)
from ml.data.loader import PackedDataset, empaquetar_tokens, get_batch, split_datos

__all__ = [
    "EjemploEntrenamiento",
    "PackedDataset",
    "cargar_jsonl",
    "construir_textos_tokenizer",
    "deduplicar",
    "empaquetar_tokens",
    "estadisticas_corpus",
    "get_batch",
    "guardar_jsonl",
    "split_datos",
]
