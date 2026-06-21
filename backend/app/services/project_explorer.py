"""Explorador de proyecto: capacidad agéntica de acceso a archivos (segura).

Permite al sistema RECORRER el proyecto real (árbol de carpetas) y LEER el
contenido de archivos, para luego explicarlos. Es una capacidad de ingeniería
pura: no necesita un "cerebro" para navegar; el modelo (propio, cuando esté
entrenado) se usa solo para EXPLICAR lo que aquí se lee.

Seguridad (importante):
  - Todo acceso queda CONFINADO a una raíz (`raiz`). Se bloquea cualquier
    intento de salir de ella (path traversal con '..').
  - Solo LECTURA. No escribe, no borra, no ejecuta nada.
  - Excluye carpetas/archivos sensibles o pesados (.git, node_modules, .env…).
  - Límite de tamaño al leer archivos.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from app.config import settings


# Carpetas/archivos que nunca se exponen (sensibles o ruido).
_EXCLUIR_NOMBRES = {
    ".git", ".github", "node_modules", ".next", "out", "dist", "build",
    "__pycache__", ".venv", "venv", "env", ".mypy_cache", ".ruff_cache",
    ".pytest_cache", ".idea", ".vscode", ".dart_tool", "checkpoints",
}
_EXCLUIR_SUFIJOS = {".pt", ".ckpt", ".pyc", ".pyo", ".so", ".dll", ".bin"}
_EXCLUIR_ARCHIVOS = {".env", ".env.local"}

# Extensiones consideradas "texto legible".
_TEXTO_SUFIJOS = {
    ".py", ".ts", ".tsx", ".js", ".jsx", ".dart", ".java", ".go", ".rs",
    ".c", ".cpp", ".h", ".css", ".scss", ".html", ".json", ".yaml", ".yml",
    ".md", ".txt", ".toml", ".ini", ".cfg", ".sql", ".sh", ".dockerfile",
    ".gitignore", ".env.example",
}

_MAX_BYTES_ARCHIVO = 200_000  # 200 KB


def _resolver_raiz() -> Path:
    """Raíz del proyecto a explorar. En Docker se monta en /proyecto."""
    candidato = Path(settings.proyecto_root)
    if candidato.exists():
        return candidato.resolve()
    # Fallback local: raíz del repo (backend/app/services/este.py -> parents[3]).
    return Path(__file__).resolve().parents[3]


@dataclass(slots=True)
class NodoArchivo:
    nombre: str
    ruta: str          # relativa a la raíz
    tipo: str          # "carpeta" | "archivo"
    tamano: int = 0
    es_texto: bool = False


class ExploradorProyecto:
    def __init__(self) -> None:
        self.raiz = _resolver_raiz()

    # ------------------------------------------------------------------
    def _resolver_seguro(self, ruta_relativa: str) -> Path:
        """Resuelve una ruta relativa garantizando que queda dentro de la raíz."""
        relativa = (ruta_relativa or "").strip().lstrip("/\\")
        destino = (self.raiz / relativa).resolve()
        # Confinamiento: destino debe estar dentro de la raíz.
        if self.raiz != destino and self.raiz not in destino.parents:
            raise PermissionError("Acceso fuera del proyecto no permitido.")
        return destino

    @staticmethod
    def _excluido(p: Path) -> bool:
        if p.name in _EXCLUIR_NOMBRES or p.name in _EXCLUIR_ARCHIVOS:
            return True
        if p.suffix.lower() in _EXCLUIR_SUFIJOS:
            return True
        return False

    @classmethod
    def _es_texto(cls, p: Path) -> bool:
        return (
            p.suffix.lower() in _TEXTO_SUFIJOS
            or p.name in {"Dockerfile", "README", ".gitignore", ".env.example"}
        )

    # ------------------------------------------------------------------
    def listar(self, ruta_relativa: str = "") -> list[NodoArchivo]:
        """Lista los hijos directos de una carpeta (carpetas primero)."""
        destino = self._resolver_seguro(ruta_relativa)
        if not destino.is_dir():
            raise NotADirectoryError(f"No es una carpeta: {ruta_relativa}")

        nodos: list[NodoArchivo] = []
        for hijo in destino.iterdir():
            if self._excluido(hijo):
                continue
            rel = hijo.relative_to(self.raiz).as_posix()
            if hijo.is_dir():
                nodos.append(NodoArchivo(nombre=hijo.name, ruta=rel, tipo="carpeta"))
            else:
                try:
                    tam = hijo.stat().st_size
                except OSError:
                    tam = 0
                nodos.append(
                    NodoArchivo(
                        nombre=hijo.name,
                        ruta=rel,
                        tipo="archivo",
                        tamano=tam,
                        es_texto=self._es_texto(hijo),
                    )
                )
        nodos.sort(key=lambda n: (n.tipo != "carpeta", n.nombre.lower()))
        return nodos

    def leer(self, ruta_relativa: str) -> dict[str, object]:
        """Lee el contenido (texto) de un archivo dentro del proyecto."""
        destino = self._resolver_seguro(ruta_relativa)
        if not destino.is_file():
            raise FileNotFoundError(f"No es un archivo: {ruta_relativa}")
        if self._excluido(destino):
            raise PermissionError("Archivo no accesible.")

        tam = destino.stat().st_size
        truncado = tam > _MAX_BYTES_ARCHIVO
        try:
            with destino.open("rb") as f:
                data = f.read(_MAX_BYTES_ARCHIVO)
            contenido = data.decode("utf-8", errors="replace")
        except OSError as exc:
            raise FileNotFoundError(f"No se pudo leer: {exc}") from exc

        return {
            "ruta": destino.relative_to(self.raiz).as_posix(),
            "nombre": destino.name,
            "lenguaje": destino.suffix.lstrip(".") or "texto",
            "tamano": tam,
            "truncado": truncado,
            "contenido": contenido,
        }

    def buscar(self, termino: str, *, limite: int = 40) -> list[NodoArchivo]:
        """Busca archivos por nombre dentro del proyecto (recorrido acotado)."""
        termino = (termino or "").strip().lower()
        if not termino:
            return []
        resultados: list[NodoArchivo] = []
        for p in self._recorrer(self.raiz):
            if termino in p.name.lower():
                rel = p.relative_to(self.raiz).as_posix()
                resultados.append(
                    NodoArchivo(
                        nombre=p.name, ruta=rel, tipo="archivo",
                        es_texto=self._es_texto(p),
                    )
                )
                if len(resultados) >= limite:
                    break
        return resultados

    def _recorrer(self, base: Path, profundidad: int = 6):
        """Generador de archivos, excluyendo carpetas pesadas/sensibles."""
        if profundidad < 0:
            return
        try:
            hijos = list(base.iterdir())
        except OSError:
            return
        for hijo in hijos:
            if self._excluido(hijo):
                continue
            if hijo.is_dir():
                yield from self._recorrer(hijo, profundidad - 1)
            else:
                yield hijo
