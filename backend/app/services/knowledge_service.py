"""Servicio de base de conocimiento.

Lee y expone el contenido educativo almacenado en `knowledge_base/`.
Sirve como contexto adicional para los LLMs y como contenido directo
para la UI (módulo conceptual).
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from app.utils.logger import obtener_logger


log = obtener_logger(__name__)


# Resolvemos la carpeta knowledge_base relativa a la raíz del proyecto.
# backend/app/services/knowledge_service.py -> raíz = parents[3]
_RAIZ_PROYECTO = Path(__file__).resolve().parents[3]
_RUTA_KB = _RAIZ_PROYECTO / "knowledge_base"

_CATEGORIAS = (
    "python_basics",
    "python_intermediate",
    "oop",
    "algorithms",
    "best_practices",
    "scientific_sources",
)


@dataclass(slots=True, frozen=True)
class TemaConocimiento:
    """Representa un archivo .md de la base de conocimiento."""

    categoria: str
    slug: str
    titulo: str
    contenido: str


class KnowledgeService:
    def __init__(self, ruta_base: Path | None = None) -> None:
        self.ruta_base = ruta_base or _RUTA_KB

    def listar_categorias(self) -> list[str]:
        return [c for c in _CATEGORIAS if (self.ruta_base / c).is_dir()]

    def listar_temas(self, categoria: str) -> list[TemaConocimiento]:
        carpeta = self.ruta_base / categoria
        if not carpeta.is_dir():
            return []
        temas: list[TemaConocimiento] = []
        for archivo in sorted(carpeta.glob("*.md")):
            temas.append(self._leer_tema(categoria, archivo))
        return temas

    def buscar(self, consulta: str) -> list[TemaConocimiento]:
        consulta_low = consulta.lower().strip()
        if not consulta_low:
            return []
        encontrados: list[TemaConocimiento] = []
        for categoria in self.listar_categorias():
            for tema in self.listar_temas(categoria):
                if (
                    consulta_low in tema.titulo.lower()
                    or consulta_low in tema.contenido.lower()
                ):
                    encontrados.append(tema)
        return encontrados

    def _leer_tema(self, categoria: str, archivo: Path) -> TemaConocimiento:
        try:
            texto = archivo.read_text(encoding="utf-8")
        except OSError as exc:
            log.warning("No se pudo leer %s: %s", archivo, exc)
            texto = ""
        titulo = archivo.stem.replace("_", " ").title()
        primera_linea = texto.splitlines()[0].strip() if texto else ""
        if primera_linea.startswith("#"):
            titulo = primera_linea.lstrip("#").strip() or titulo
        return TemaConocimiento(
            categoria=categoria,
            slug=archivo.stem,
            titulo=titulo,
            contenido=texto,
        )
