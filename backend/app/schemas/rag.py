"""Schemas Pydantic para los endpoints RAG."""

from __future__ import annotations

from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field


class SubirDocumentoTextoIn(BaseModel):
    titulo: str = Field(..., min_length=1, max_length=200)
    fuente: str = Field("subido", max_length=120)
    texto: str = Field(..., min_length=10)
    tags: list[str] = Field(default_factory=list)


class DocumentoOut(BaseModel):
    id: str
    titulo: str
    fuente: str
    n_chunks: int
    fecha: str
    tags: list[str] = Field(default_factory=list)


class EstadoRAG(BaseModel):
    disponible: bool
    n_documentos: int = 0
    n_chunks: int = 0
    dim: int = 0
    backend: str = "none"
    motivo: Optional[str] = None


class BuscarIn(BaseModel):
    consulta: str = Field(..., min_length=1)
    k: int = Field(5, ge=1, le=20)


class ChunkOut(BaseModel):
    chunk_id: str
    doc_id: str
    doc_titulo: str
    score: float
    texto: str


class BuscarOut(BaseModel):
    resultados: list[ChunkOut]
