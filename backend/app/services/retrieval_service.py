"""Recuperación local de conocimiento (retrieval-first), sin API externa.

Este servicio es lo que hace que el sistema dependa CADA VEZ MENOS de las
APIs: antes de llamar a Gemini/DeepSeek, busca en la base de conocimiento
(`UnidadConocimiento`) una unidad validada que ya responda la consulta del
estudiante.

Estrategia (100% local, determinista, sin dependencias pesadas):
- Normaliza y tokeniza la consulta y el texto de cada unidad.
- Calcula similitud por solapamiento ponderado (Jaccard + cobertura de
  términos de la consulta).
- Bonifica coincidencia de tema y nivel.
- Devuelve los mejores candidatos por encima de un umbral.

La arquitectura queda preparada para sustituir el scorer léxico por
embeddings locales (sentence-transformers) sin cambiar la interfaz.
"""

from __future__ import annotations

import re
import unicodedata
from dataclasses import dataclass

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.conocimiento import EstadoConocimiento, UnidadConocimiento


UMBRAL_REUTILIZACION_DEFECTO = 0.62   # score 0..1 mínimo para responder sin API

_STOPWORDS = {
    "de", "la", "el", "en", "y", "a", "los", "las", "un", "una", "que", "con",
    "por", "para", "del", "se", "su", "al", "lo", "como", "mas", "más", "o",
    "es", "me", "mi", "tu", "le", "explicame", "explícame", "genera", "crea",
    "haz", "hazme", "dame", "quiero", "necesito", "python", "codigo", "código",
    "programa", "ejemplo", "funcion", "función", "sobre", "the", "of", "to",
}

_RE_TOKEN = re.compile(r"[a-záéíóúñü0-9_]+", re.IGNORECASE)


def _normalizar(texto: str) -> str:
    texto = texto.lower().strip()
    texto = "".join(
        c for c in unicodedata.normalize("NFD", texto)
        if unicodedata.category(c) != "Mn"
    )
    return texto


def tokenizar(texto: str) -> set[str]:
    """Tokeniza eliminando acentos, stopwords y tokens muy cortos."""
    base = _normalizar(texto)
    tokens = _RE_TOKEN.findall(base)
    return {
        t for t in tokens
        if len(t) > 2 and _normalizar_stop(t) not in _STOPWORDS
    }


def _normalizar_stop(t: str) -> str:
    return "".join(
        c for c in unicodedata.normalize("NFD", t) if unicodedata.category(c) != "Mn"
    )


def construir_indice_texto(
    *, pregunta: str, tema: str, nivel: str,
    conceptos: list[str] | None = None, objetivo: str | None = None,
) -> tuple[str, str]:
    """Genera (texto_busqueda, keywords) para almacenar en UnidadConocimiento."""
    partes = [pregunta, tema, nivel, objetivo or ""]
    if conceptos:
        partes.extend(conceptos)
    texto_busqueda = " ".join(p for p in partes if p)
    keywords = " ".join(sorted(tokenizar(texto_busqueda)))
    return texto_busqueda, keywords


@dataclass(slots=True)
class Candidato:
    unidad: UnidadConocimiento
    score: float


class RetrievalService:
    """Búsqueda de unidades de conocimiento reutilizables."""

    def __init__(
        self,
        sesion: AsyncSession,
        *,
        umbral: float = UMBRAL_REUTILIZACION_DEFECTO,
    ) -> None:
        self.sesion = sesion
        self.umbral = umbral

    async def buscar(
        self,
        consulta: str,
        *,
        tema: str | None = None,
        nivel: str | None = None,
        solo_validadas: bool = True,
        top_k: int = 5,
    ) -> list[Candidato]:
        tokens_consulta = tokenizar(consulta)
        if not tokens_consulta:
            return []

        stmt = select(UnidadConocimiento)
        if solo_validadas:
            stmt = stmt.where(UnidadConocimiento.estado == EstadoConocimiento.VALIDADO)
        unidades = list((await self.sesion.scalars(stmt)).all())

        candidatos: list[Candidato] = []
        for u in unidades:
            score = self._score(
                tokens_consulta=tokens_consulta,
                unidad=u,
                tema=tema,
                nivel=nivel,
            )
            if score > 0:
                candidatos.append(Candidato(unidad=u, score=round(score, 4)))

        candidatos.sort(key=lambda c: c.score, reverse=True)
        return candidatos[:top_k]

    async def mejor_match(
        self,
        consulta: str,
        *,
        tema: str | None = None,
        nivel: str | None = None,
    ) -> Candidato | None:
        """Devuelve el mejor candidato SOLO si supera el umbral de reutilización."""
        candidatos = await self.buscar(
            consulta, tema=tema, nivel=nivel, top_k=1
        )
        if candidatos and candidatos[0].score >= self.umbral:
            return candidatos[0]
        return None

    def _score(
        self,
        *,
        tokens_consulta: set[str],
        unidad: UnidadConocimiento,
        tema: str | None,
        nivel: str | None,
    ) -> float:
        tokens_unidad = set((unidad.keywords or "").split())
        if not tokens_unidad:
            tokens_unidad = tokenizar(unidad.texto_busqueda or unidad.pregunta_canonica)
        if not tokens_unidad:
            return 0.0

        interseccion = tokens_consulta & tokens_unidad
        if not interseccion:
            return 0.0

        union = tokens_consulta | tokens_unidad
        jaccard = len(interseccion) / len(union)
        cobertura = len(interseccion) / len(tokens_consulta)

        # Mezcla: prioriza cubrir los términos de la consulta.
        score = 0.45 * jaccard + 0.55 * cobertura

        # Bonificaciones por coincidencia de metadatos.
        if tema and unidad.tema.value == tema:
            score += 0.08
        if nivel and unidad.nivel.value == nivel:
            score += 0.05

        # Pequeño refuerzo por calidad (conocimiento mejor curado pesa más).
        score += min(unidad.puntaje_calidad / 12.0, 1.0) * 0.05

        return min(score, 1.0)
