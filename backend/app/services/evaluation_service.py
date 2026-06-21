"""Servicio de evaluación de aprendizaje."""

from __future__ import annotations

import re
import uuid

from sqlalchemy.ext.asyncio import AsyncSession

from app.models.dataset import DatasetEducativo
from app.models.evaluacion import Evaluacion


def _normalizar(texto: str) -> str:
    """Normalización tolerante para comparar respuestas en opción múltiple."""
    texto = texto.strip().lower()
    texto = re.sub(r"\s+", " ", texto)
    return texto.lstrip("abcd) ").strip()


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
        if not correcta:
            return 0.0, "No hay respuesta correcta registrada para esta actividad."

        if tipo == "opcion_multiple":
            if _normalizar(respuesta) == _normalizar(correcta):
                return 1.0, retro_esperada or "Respuesta correcta."
            return 0.0, retro_esperada or f"Respuesta esperada: {correcta}."

        if tipo == "completar_codigo":
            # Comparación robusta a espacios
            esperado = re.sub(r"\s+", "", correcta)
            obtenido = re.sub(r"\s+", "", respuesta)
            if esperado == obtenido:
                return 1.0, retro_esperada or "Código correcto."
            return 0.5 if esperado in obtenido or obtenido in esperado else 0.0, (
                retro_esperada or f"Solución esperada: {correcta}"
            )

        if tipo == "traza_logica":
            if _normalizar(respuesta) == _normalizar(correcta):
                return 1.0, retro_esperada or "Traza correcta."
            return 0.0, retro_esperada or f"Traza esperada: {correcta}"

        # Explicación libre: puntaje provisional 0.5 hasta revisión humana
        return 0.5, "Respuesta registrada. Pendiente de revisión cualitativa."
