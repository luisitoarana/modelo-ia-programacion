"""Servicio de evaluación de aprendizaje."""

from __future__ import annotations

import ast
import re
import uuid

from sqlalchemy.ext.asyncio import AsyncSession

from app.models.dataset import DatasetEducativo
from app.models.evaluacion import Evaluacion


def _normalizar(texto: str) -> str:
    """Normalización tolerante para comparar respuestas en opción múltiple."""
    texto = texto.strip().lower()
    texto = re.sub(r"\s+", " ", texto)
    # Quitar una etiqueta solo si después hay contenido. "A" y "B" son
    # respuestas distintas; lstrip("abcd) ") convertía ambas en "".
    sin_etiqueta = re.sub(r"^[a-d][).]\s*", "", texto)
    return sin_etiqueta if sin_etiqueta else texto


class EvaluationService:
    def __init__(self, sesion: AsyncSession) -> None:
        self.sesion = sesion

    async def registrar_respuesta(
        self,
        *,
        usuario_id: uuid.UUID,
        dataset_id: uuid.UUID,
        tipo_actividad: str,
        respuesta_estudiante: str,
    ) -> Evaluacion:
        dataset = await self.sesion.get(DatasetEducativo, dataset_id)
        if dataset is None:
            raise LookupError(f"Dataset {dataset_id} no existe")

        actividad = dataset.actividad_json or {}
        correcta = str(actividad.get("respuesta_correcta", "")).strip()
        retro = str(actividad.get("retroalimentacion_esperada", "")).strip()

        puntaje, observacion = self._evaluar(
            tipo_actividad, respuesta_estudiante, correcta, retro
        )

        evaluacion = Evaluacion(
            usuario_id=usuario_id,
            dataset_id=dataset_id,
            tipo_actividad=tipo_actividad,
            respuesta_estudiante=respuesta_estudiante,
            respuesta_correcta=correcta,
            puntaje=puntaje,
            retroalimentacion=observacion,
        )
        self.sesion.add(evaluacion)
        await self.sesion.flush()
        return evaluacion

    @staticmethod
    def _evaluar(
        tipo: str,
        respuesta: str,
        correcta: str,
        retro_esperada: str,
    ) -> tuple[float, str]:
        if tipo == "explicacion_libre":
            return 0.0, "Respuesta registrada. Pendiente de revisión docente; sin puntuación automática."

        if not correcta:
            return 0.0, "No hay respuesta correcta registrada para esta actividad."

        if tipo == "opcion_multiple":
            etiqueta_respuesta = re.fullmatch(r"\s*([a-d])\s*[).]?\s*", respuesta, re.I)
            etiqueta_correcta = re.match(r"\s*([a-d])(?:\s*[).]|\s*$)", correcta, re.I)
            coincide_etiqueta = (
                etiqueta_respuesta is not None
                and etiqueta_correcta is not None
                and etiqueta_respuesta.group(1).lower() == etiqueta_correcta.group(1).lower()
            )
            if coincide_etiqueta or _normalizar(respuesta) == _normalizar(correcta):
                return 1.0, retro_esperada or "Respuesta correcta."
            return 0.0, retro_esperada or f"Respuesta esperada: {correcta}."

        if tipo == "completar_codigo":
            # El AST ignora formato, pero conserva literales y operaciones.
            # Es equivalencia estructural, no una prueba de comportamiento.
            try:
                esperado = ast.dump(ast.parse(correcta), include_attributes=False)
                obtenido = ast.dump(ast.parse(respuesta), include_attributes=False)
            except SyntaxError:
                esperado = correcta.strip()
                obtenido = respuesta.strip()
            if obtenido and esperado == obtenido:
                return 1.0, retro_esperada or "Código correcto."
            return 0.0, retro_esperada or f"Revisa tu solución. Ejemplo esperado: {correcta}"

        if tipo == "traza_logica":
            if _normalizar(respuesta) == _normalizar(correcta):
                return 1.0, retro_esperada or "Traza correcta."
            return 0.0, retro_esperada or f"Traza esperada: {correcta}"

        raise ValueError(f"Tipo de actividad no soportado: {tipo}")
