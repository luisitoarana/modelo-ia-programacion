"""Rutas REST para el Currículo de Aprendizaje y Banco de Retos de Python."""

from __future__ import annotations

from fastapi import APIRouter, HTTPException, status
from pydantic import BaseModel, Field

from app.services.curriculum_service import CurriculumService

router = APIRouter()


class SolicitudTutorLeccion(BaseModel):
    codigo: str = Field(..., min_length=1)
    duda: str | None = Field(default=None, max_length=1000)


@router.get("/modulos", summary="Listar los 3 módulos curriculares de Python")
async def listar_modulos():
    """Devuelve el catálogo de módulos (Principiante, Intermedio, Avanzado)."""
    return CurriculumService.listar_modulos()


@router.get("/modulos/{modulo_id}", summary="Detalles y lecciones de un módulo curricular")
async def obtener_modulo(modulo_id: str):
    """Devuelve las lecciones y retos del módulo especificado."""
    mod = CurriculumService.obtener_modulo(modulo_id)
    if not mod:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Módulo '{modulo_id}' no encontrado. Use 'principiante', 'intermedio' o 'avanzado'.",
        )
    return mod


@router.get("/leccion/{leccion_id}", summary="Obtener una lección o reto específico")
async def obtener_leccion(leccion_id: str):
    """Devuelve los detalles, código inicial, pistas y guía docente de una lección."""
    lec = CurriculumService.obtener_leccion(leccion_id)
    if not lec:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Lección '{leccion_id}' no encontrada.",
        )
    return {
        "id": lec.id,
        "modulo_id": lec.modulo_id,
        "modulo_titulo": lec.modulo_titulo,
        "numero": lec.numero,
        "titulo": lec.titulo,
        "concepto_clave": lec.concepto_clave,
        "palabras_reservadas": lec.palabras_reservadas,
        "descripcion_pedagogica": lec.descripcion_pedagogica,
        "codigo_inicial": lec.codigo_inicial,
        "guia_docente": lec.guia_docente,
        "pistas_andamiaje": lec.pistas_andamiaje,
        "pregunta_autoevaluacion": lec.pregunta_autoevaluacion,
        "codigo_solucion": lec.codigo_solucion,
    }


@router.post("/leccion/{leccion_id}/prompt-tutor", summary="Construir prompt de tutoría adaptado")
async def generar_prompt_tutor(leccion_id: str, datos: SolicitudTutorLeccion):
    """Construye el prompt pedagógico exacto para que el modelo IA asista al estudiante en esta lección."""
    lec = CurriculumService.obtener_leccion(leccion_id)
    if not lec:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Lección '{leccion_id}' no encontrada.",
        )
    prompt = CurriculumService.construir_prompt_tutor_leccion(
        lec,
        datos.codigo,
        datos.duda,
    )
    return {
        "leccion_id": lec.id,
        "modulo_id": lec.modulo_id,
        "prompt_tutor": prompt,
        "pistas_disponibles": lec.pistas_andamiaje,
        "pregunta_autoevaluacion": lec.pregunta_autoevaluacion,
    }
