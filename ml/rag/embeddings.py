"""Embedder — convierte texto en vectores para búsqueda semántica.

Estrategia escalonada (degrada elegantemente según lo instalado):

    1. sentence-transformers `all-MiniLM-L6-v2` (384 dims) — calidad SOTA
       para retrieval, 80MB, multilingüe razonable. Es la opción correcta.
    2. Fallback: hashing + TF-IDF puro Python (sin dependencias externas).
       Calidad menor pero el sistema sigue funcionando si no hay internet
       para descargar el modelo.

El embedder devuelve siempre vectores L2-normalizados → la similitud
coseno se calcula como un producto punto (más rápido).
"""

from __future__ import annotations

import hashlib
import re
from typing import Sequence

import numpy as np


class Embedder:
    """Embedder unificado con backend dinámico."""

    def __init__(self, modelo: str = "auto") -> None:
        self.modelo_nombre = modelo
        self._backend = None
        self._sbert = None
        self._dim = 0
        self._inicializar()

    # ─────────────── inicialización ───────────────

    def _inicializar(self) -> None:
        if self.modelo_nombre in ("auto", "sentence-transformers"):
            try:
                from sentence_transformers import SentenceTransformer  # type: ignore
                self._sbert = SentenceTransformer("all-MiniLM-L6-v2")
                self._dim = int(self._sbert.get_sentence_embedding_dimension())
                self._backend = "sentence-transformers"
                return
            except Exception:
                if self.modelo_nombre == "sentence-transformers":
                    raise
                # auto → fallback
        self._backend = "hashing"
        self._dim = 384

    @property
    def dim(self) -> int:
        return self._dim

    @property
    def backend(self) -> str:
        return self._backend or "none"

    # ─────────────── codificación ───────────────

    def codificar(self, textos: Sequence[str]) -> np.ndarray:
        """Devuelve matriz (N, dim) L2-normalizada."""
        if self._backend == "sentence-transformers":
            vecs = self._sbert.encode(
                list(textos), normalize_embeddings=True, show_progress_bar=False,
            )
            return np.asarray(vecs, dtype=np.float32)
        return self._codificar_hashing(textos)

    def _codificar_hashing(self, textos: Sequence[str]) -> np.ndarray:
        """Fallback: hashing trick + frecuencia normalizada.

        No es semántico (no entiende sinónimos) pero captura solapamiento
        léxico, suficiente para corpus pequeños y permite que el sistema
        funcione sin descargar nada.
        """
        salida = np.zeros((len(textos), self._dim), dtype=np.float32)
        for i, txt in enumerate(textos):
            tokens = re.findall(r"\w+", (txt or "").lower())
            if not tokens:
                continue
            for t in tokens:
                h = int.from_bytes(
                    hashlib.md5(t.encode("utf-8")).digest()[:4], "big",
                )
                salida[i, h % self._dim] += 1.0
            # L2 normalize
            n = np.linalg.norm(salida[i])
            if n > 0:
                salida[i] /= n
        return salida
