"""Servicio RAG — singleton del VectorStore con detección de utilidad.

Expone:
    obtener_store()        → VectorStore cargado en memoria
    debe_recuperar(texto)  → heurística: ¿conviene buscar antes de responder?
    formatear_contexto(...) → arma el bloque "FUENTES" para inyectar al LLM
"""

from __future__ import annotations

import re
import sys
import threading
from pathlib import Path

from app.config import settings
from app.utils.logger import obtener_logger


log = obtener_logger(__name__)

_RAIZ = Path(__file__).resolve().parents[3]
_INDICE_PATH = _RAIZ / "data" / "rag_index"

_lock = threading.Lock()
_store = None
_motivo: str | None = None


def _asegurar_path_ml() -> None:
    if str(_RAIZ) not in sys.path:
        sys.path.insert(0, str(_RAIZ))


def obtener_store():
    """Devuelve el VectorStore singleton (carga perezosa)."""
    global _store, _motivo
    with _lock:
        if _store is not None:
            return _store
        try:
            _asegurar_path_ml()
            from ml.rag.vector_store import VectorStore
            from ml.rag.embeddings import Embedder
            _store = VectorStore(_INDICE_PATH, Embedder())
            log.info(
                "[rag] Store cargado en %s (backend=%s, docs=%d, chunks=%d)",
                _INDICE_PATH, _store.embedder.backend,
                len(_store.documentos), len(_store.chunks),
            )
            return _store
        except Exception as exc:  # noqa: BLE001
            _motivo = f"No se pudo iniciar RAG: {exc}"
            log.warning("[rag] %s", _motivo)
            return None


def disponible() -> bool:
    return obtener_store() is not None


# ════════════════════════════════════════════════════════════════════
# Heurística: ¿la pregunta se beneficia de retrieval?
# ════════════════════════════════════════════════════════════════════

_PALABRAS_RECUPERAR = re.compile(
    r"\b(que dice|según|en el documento|en el archivo|en mi (proyecto|código|repo|nota)s?|"
    r"resumen de|qué contiene|busca en|encuentra|según mis (notas|documentos)|"
    r"explica el archivo|de mi corpus|de mi base)\b",
    re.IGNORECASE,
)


def debe_recuperar(texto: str) -> bool:
    """Decide si vale la pena consultar el índice antes de generar.

    Si hay documentos indexados y la pregunta contiene señales de
    referencia a contenido propio del usuario, devuelve True.
    """
    store = obtener_store()
    if store is None or not store.documentos:
        return False
    if _PALABRAS_RECUPERAR.search(texto or ""):
        return True
    # Si la pregunta es larga y específica, probar siempre.
    return len(texto.split()) >= 6


# ════════════════════════════════════════════════════════════════════
# Formato del contexto para el LLM
# ════════════════════════════════════════════════════════════════════

def recuperar_y_formatear(
    consulta: str, k: int = 4, umbral: float = 0.15,
    max_caracteres: int = 2000,
) -> tuple[str | None, list[dict]]:
    """Busca chunks relevantes y arma un bloque listo para inyectar al LLM.

    Returns:
        (texto_contexto | None, lista_de_fuentes_para_metadata)
    """
    store = obtener_store()
    if store is None:
        return None, []
    resultados = store.buscar(consulta, k=k, umbral_min=umbral)
    if not resultados:
        return None, []

    fragmentos: list[str] = []
    fuentes: list[dict] = []
    chars = 0
    for chunk, score in resultados:
        doc = store.documentos.get(chunk.doc_id)
        titulo = doc.titulo if doc else "(sin título)"
        bloque = f"[Fuente: {titulo}, score={score:.2f}]\n{chunk.texto.strip()}"
        if chars + len(bloque) > max_caracteres:
            break
        fragmentos.append(bloque)
        chars += len(bloque)
        fuentes.append({
            "doc_id": chunk.doc_id,
            "titulo": titulo,
            "score": round(score, 3),
            "chunk_id": chunk.id,
        })

    if not fragmentos:
        return None, []

    contexto = (
        "FUENTES DEL USUARIO (úsalas si son relevantes; cita el título "
        "entre paréntesis cuando hagas afirmaciones basadas en ellas):\n\n"
        + "\n\n---\n\n".join(fragmentos)
    )
    return contexto, fuentes
