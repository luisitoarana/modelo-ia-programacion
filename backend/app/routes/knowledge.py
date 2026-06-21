"""Rutas para consultar la base de conocimiento."""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, status

from app.core.security import obtener_usuario_actual
from app.models.usuario import Usuario
from app.services.knowledge_service import KnowledgeService


router = APIRouter()


@router.get("/categorias", summary="Listar categorías de conocimiento")
async def categorias(
    _u: Annotated[Usuario, Depends(obtener_usuario_actual)],
) -> dict[str, list[str]]:
    return {"categorias": KnowledgeService().listar_categorias()}


@router.get("/categoria/{categoria}", summary="Listar temas de una categoría")
async def temas_categoria(
    categoria: str,
    _u: Annotated[Usuario, Depends(obtener_usuario_actual)],
) -> dict[str, list[dict[str, str]]]:
    servicio = KnowledgeService()
    temas = servicio.listar_temas(categoria)
    if not temas:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Categoría '{categoria}' no encontrada o vacía.",
        )
    return {
        "temas": [
            {"slug": t.slug, "titulo": t.titulo, "categoria": t.categoria}
            for t in temas
        ]
    }


@router.get("/tema/{categoria}/{slug}", summary="Obtener el contenido de un tema")
async def detalle_tema(
    categoria: str,
    slug: str,
    _u: Annotated[Usuario, Depends(obtener_usuario_actual)],
) -> dict[str, str]:
    servicio = KnowledgeService()
    for tema in servicio.listar_temas(categoria):
        if tema.slug == slug:
            return {
                "categoria": tema.categoria,
                "slug": tema.slug,
                "titulo": tema.titulo,
                "contenido": tema.contenido,
            }
    raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Tema no encontrado.")


@router.get("/buscar", summary="Buscar texto en la base de conocimiento")
async def buscar(
    q: Annotated[str, Query(min_length=2, max_length=200)],
    _u: Annotated[Usuario, Depends(obtener_usuario_actual)],
) -> dict[str, list[dict[str, str]]]:
    resultados = KnowledgeService().buscar(q)
    return {
        "resultados": [
            {"slug": r.slug, "categoria": r.categoria, "titulo": r.titulo}
            for r in resultados
        ]
    }
