"""RAG — Retrieval-Augmented Generation.

Componentes:
    - `embeddings.py`  : convertir texto en vectores
    - `vector_store.py`: guardar/buscar vectores en disco
    - `indexar.py`     : CLI para procesar carpetas de documentos

Diseño minimalista (sin dependencias de FAISS/Chroma): un JSON + numpy
basta para corpus < 100k chunks, que es lo que necesita una tesis.
"""

from ml.rag.embeddings import Embedder
from ml.rag.vector_store import VectorStore, Documento, Chunk

__all__ = ["Embedder", "VectorStore", "Documento", "Chunk"]
