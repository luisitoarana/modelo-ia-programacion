"""VectorStore — base vectorial persistente en disco.

Estructura en disco (carpeta `index_path/`):

    documentos.jsonl     ← metadatos de cada documento subido
    chunks.jsonl         ← cada chunk con su doc_id, posición, texto
    vectores.npy         ← matriz (N_chunks, dim) float32 normalizada
    config.json          ← dim, backend, fecha

Operaciones:
    - agregar_documento(titulo, fuente, texto)
    - buscar(consulta, k=5) → [(chunk, score), ...]
    - listar_documentos()
    - eliminar_documento(doc_id)
    - guardar() / cargar()

Es suficiente para tesis y proyectos de < 100k chunks (~50k páginas).
"""

from __future__ import annotations

import json
import re
import uuid
from dataclasses import dataclass, field, asdict
from datetime import datetime
from pathlib import Path

import numpy as np

from ml.rag.embeddings import Embedder


@dataclass(slots=True)
class Documento:
    id: str
    titulo: str
    fuente: str               # "subido", "web:url", "github:repo", etc.
    n_chunks: int
    fecha: str
    tags: list[str] = field(default_factory=list)


@dataclass(slots=True)
class Chunk:
    id: str
    doc_id: str
    pos: int                  # posición dentro del documento
    texto: str
    inicio_char: int = 0
    fin_char: int = 0


# ════════════════════════════════════════════════════════════════════
# Chunking
# ════════════════════════════════════════════════════════════════════

def trocear_texto(
    texto: str, tam_chunk: int = 500, solapamiento: int = 80,
) -> list[tuple[str, int, int]]:
    """Trocea texto en chunks de ~tam_chunk palabras con solapamiento.

    Returns:
        Lista de (texto_chunk, inicio_char, fin_char).
    """
    if not texto.strip():
        return []
    # Dividir por palabras manteniendo offsets en chars
    palabras = list(re.finditer(r"\S+", texto))
    if not palabras:
        return []

    chunks: list[tuple[str, int, int]] = []
    i = 0
    while i < len(palabras):
        j = min(i + tam_chunk, len(palabras))
        inicio = palabras[i].start()
        fin = palabras[j - 1].end()
        chunks.append((texto[inicio:fin], inicio, fin))
        if j >= len(palabras):
            break
        i = max(i + tam_chunk - solapamiento, i + 1)
    return chunks


# ════════════════════════════════════════════════════════════════════
# VectorStore
# ════════════════════════════════════════════════════════════════════

class VectorStore:
    def __init__(self, ruta: Path, embedder: Embedder | None = None) -> None:
        self.ruta = Path(ruta)
        self.ruta.mkdir(parents=True, exist_ok=True)
        self.embedder = embedder or Embedder()

        self.documentos: dict[str, Documento] = {}
        self.chunks: list[Chunk] = []
        self.vectores: np.ndarray = np.zeros((0, self.embedder.dim), dtype=np.float32)

        if (self.ruta / "config.json").exists():
            self.cargar()

    # ─────────────── persistencia ───────────────

    def guardar(self) -> None:
        with (self.ruta / "documentos.jsonl").open("w", encoding="utf-8") as f:
            for d in self.documentos.values():
                f.write(json.dumps(asdict(d), ensure_ascii=False) + "\n")
        with (self.ruta / "chunks.jsonl").open("w", encoding="utf-8") as f:
            for c in self.chunks:
                f.write(json.dumps(asdict(c), ensure_ascii=False) + "\n")
        np.save(self.ruta / "vectores.npy", self.vectores)
        config = {
            "dim": self.embedder.dim,
            "backend": self.embedder.backend,
            "n_docs": len(self.documentos),
            "n_chunks": len(self.chunks),
            "actualizado": datetime.utcnow().isoformat(),
        }
        (self.ruta / "config.json").write_text(
            json.dumps(config, indent=2), encoding="utf-8",
        )

    def cargar(self) -> None:
        docs_path = self.ruta / "documentos.jsonl"
        chunks_path = self.ruta / "chunks.jsonl"
        vec_path = self.ruta / "vectores.npy"

        if docs_path.exists():
            with docs_path.open(encoding="utf-8") as f:
                for linea in f:
                    if not linea.strip():
                        continue
                    d = json.loads(linea)
                    self.documentos[d["id"]] = Documento(**d)
        if chunks_path.exists():
            with chunks_path.open(encoding="utf-8") as f:
                self.chunks = [Chunk(**json.loads(l)) for l in f if l.strip()]
        if vec_path.exists():
            self.vectores = np.load(vec_path)
            if self.vectores.shape[1] != self.embedder.dim:
                # Backend cambió → re-indexar todo.
                self._reindexar()

    def _reindexar(self) -> None:
        if not self.chunks:
            self.vectores = np.zeros((0, self.embedder.dim), dtype=np.float32)
            return
        textos = [c.texto for c in self.chunks]
        self.vectores = self.embedder.codificar(textos)

    # ─────────────── operaciones públicas ───────────────

    def agregar_documento(
        self, titulo: str, fuente: str, texto: str,
        tags: list[str] | None = None,
        tam_chunk: int = 500, solapamiento: int = 80,
    ) -> Documento:
        """Trocea, embebe y persiste. Devuelve el documento creado."""
        doc_id = str(uuid.uuid4())
        trozos = trocear_texto(texto, tam_chunk, solapamiento)
        if not trozos:
            raise ValueError("Documento vacío tras trocear.")

        nuevos_chunks = [
            Chunk(
                id=f"{doc_id}:{i}", doc_id=doc_id, pos=i,
                texto=trozo, inicio_char=ini, fin_char=fin,
            )
            for i, (trozo, ini, fin) in enumerate(trozos)
        ]
        vecs = self.embedder.codificar([c.texto for c in nuevos_chunks])

        doc = Documento(
            id=doc_id, titulo=titulo, fuente=fuente,
            n_chunks=len(nuevos_chunks),
            fecha=datetime.utcnow().isoformat(),
            tags=tags or [],
        )
        self.documentos[doc_id] = doc
        self.chunks.extend(nuevos_chunks)
        self.vectores = np.vstack([self.vectores, vecs]) if self.vectores.size else vecs

        self.guardar()
        return doc

    def eliminar_documento(self, doc_id: str) -> bool:
        if doc_id not in self.documentos:
            return False
        mask = np.array(
            [c.doc_id != doc_id for c in self.chunks], dtype=bool,
        )
        self.chunks = [c for c, m in zip(self.chunks, mask) if m]
        self.vectores = self.vectores[mask]
        del self.documentos[doc_id]
        self.guardar()
        return True

    def listar_documentos(self) -> list[Documento]:
        return list(self.documentos.values())

    def buscar(
        self, consulta: str, k: int = 5,
        umbral_min: float = 0.0,
    ) -> list[tuple[Chunk, float]]:
        """Devuelve los k chunks más similares con su score [0, 1]."""
        if not self.chunks:
            return []
        q = self.embedder.codificar([consulta])[0]
        scores = self.vectores @ q
        if k >= len(scores):
            idx = np.argsort(-scores)
        else:
            idx = np.argpartition(-scores, k)[:k]
            idx = idx[np.argsort(-scores[idx])]

        salida: list[tuple[Chunk, float]] = []
        for i in idx[:k]:
            sc = float(scores[i])
            if sc < umbral_min:
                continue
            salida.append((self.chunks[i], sc))
        return salida

    def estado(self) -> dict:
        return {
            "n_documentos": len(self.documentos),
            "n_chunks": len(self.chunks),
            "dim": self.embedder.dim,
            "backend": self.embedder.backend,
        }
