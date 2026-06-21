"""Endpoints REST para el sistema RAG.

- POST   /api/v1/rag/subir         — subir documento por texto
- POST   /api/v1/rag/subir-archivo — subir documento como archivo (multipart)
- GET    /api/v1/rag/documentos    — listar documentos indexados
- DELETE /api/v1/rag/documentos/{id}
- POST   /api/v1/rag/buscar        — buscar chunks similares
- GET    /api/v1/rag/estado        — estado del índice

El RAG inyecta chunks relevantes al prompt del chat automáticamente
(ver `rag_service.recuperar_y_formatear` integrado en `chat_service`).
"""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile, status

from app.core.security import obtener_usuario_actual
from app.models.usuario import Usuario
from app.schemas.rag import (
    BuscarIn,
    BuscarOut,
    ChunkOut,
    DocumentoOut,
    EstadoRAG,
    SubirDocumentoTextoIn,
)
from app.services import rag_service


router = APIRouter(prefix="/rag", tags=["RAG"])


# ─────────────── Estado ───────────────

@router.get("/estado", response_model=EstadoRAG)
async def estado() -> EstadoRAG:
    store = rag_service.obtener_store()
    if store is None:
        return EstadoRAG(disponible=False, motivo=rag_service._motivo)
    e = store.estado()
    return EstadoRAG(disponible=True, **e)


# ─────────────── Documentos ───────────────

@router.post("/subir", response_model=DocumentoOut, status_code=201)
async def subir_texto(
    body: SubirDocumentoTextoIn,
    usuario: Annotated[Usuario, Depends(obtener_usuario_actual)],
) -> DocumentoOut:
    store = rag_service.obtener_store()
    if store is None:
        raise HTTPException(503, "Sistema RAG no disponible")
    try:
        doc = store.agregar_documento(
            titulo=body.titulo, fuente=body.fuente,
            texto=body.texto, tags=body.tags,
        )
    except ValueError as exc:
        raise HTTPException(400, str(exc)) from exc
    return DocumentoOut(**doc.__dict__)


@router.post("/subir-archivo", response_model=DocumentoOut, status_code=201)
async def subir_archivo(
    archivo: UploadFile = File(...),
    titulo: str | None = Form(None),
    tags: str = Form(""),
    usuario: Annotated[Usuario, Depends(obtener_usuario_actual)] = None,
) -> DocumentoOut:
    """Acepta .txt, .md, .py, .json y similares en texto plano."""
    store = rag_service.obtener_store()
    if store is None:
        raise HTTPException(503, "Sistema RAG no disponible")

    contenido = await archivo.read()
    if len(contenido) > 5_000_000:
        raise HTTPException(413, "Archivo demasiado grande (>5MB)")

    try:
        texto = contenido.decode("utf-8", errors="ignore")
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(415, f"No se pudo decodificar: {exc}") from exc

    nombre = titulo or archivo.filename or "documento"
    tags_lista = [t.strip() for t in tags.split(",") if t.strip()]
    try:
        doc = store.agregar_documento(
            titulo=nombre, fuente=f"archivo:{archivo.filename}",
            texto=texto, tags=tags_lista,
        )
    except ValueError as exc:
        raise HTTPException(400, str(exc)) from exc
    return DocumentoOut(**doc.__dict__)


@router.get("/documentos", response_model=list[DocumentoOut])
async def listar(
    usuario: Annotated[Usuario, Depends(obtener_usuario_actual)],
) -> list[DocumentoOut]:
    store = rag_service.obtener_store()
    if store is None:
        return []
    return [DocumentoOut(**d.__dict__) for d in store.listar_documentos()]


@router.delete("/documentos/{doc_id}", status_code=status.HTTP_200_OK)
async def eliminar(
    doc_id: str,
    usuario: Annotated[Usuario, Depends(obtener_usuario_actual)],
) -> dict:
    store = rag_service.obtener_store()
    if store is None:
        raise HTTPException(503, "Sistema RAG no disponible")
    if not store.eliminar_documento(doc_id):
        raise HTTPException(404, "Documento no encontrado")
    return {"eliminado": doc_id}


# ─────────────── Búsqueda ───────────────

@router.post("/buscar", response_model=BuscarOut)
async def buscar(
    body: BuscarIn,
    usuario: Annotated[Usuario, Depends(obtener_usuario_actual)],
) -> BuscarOut:
    store = rag_service.obtener_store()
    if store is None:
        raise HTTPException(503, "Sistema RAG no disponible")
    resultados = store.buscar(body.consulta, k=body.k)
    salida: list[ChunkOut] = []
    for chunk, score in resultados:
        doc = store.documentos.get(chunk.doc_id)
        salida.append(ChunkOut(
            chunk_id=chunk.id,
            doc_id=chunk.doc_id,
            doc_titulo=doc.titulo if doc else "(sin título)",
            score=round(float(score), 4),
            texto=chunk.texto,
        ))
    return BuscarOut(resultados=salida)
