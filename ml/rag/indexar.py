"""CLI para indexar carpetas completas en el RAG.

Uso:
    python -m ml.rag.indexar --carpeta docs --indice data/rag_index
    python -m ml.rag.indexar --carpeta . --extensiones .md .py .txt

Recorre la carpeta, lee cada archivo como texto plano y lo añade al
índice. Útil para subir documentación de la tesis, libros, código del
proyecto, etc. de una sola vez.
"""

from __future__ import annotations

import argparse
from pathlib import Path

from ml.rag.embeddings import Embedder
from ml.rag.vector_store import VectorStore


_EXTS_DEFAULT = {".md", ".txt", ".py", ".rst", ".json", ".yml", ".yaml"}
_IGNORAR = {".git", ".venv", "node_modules", "__pycache__", "runs", "data"}


def indexar_carpeta(
    carpeta: Path, indice: Path, extensiones: set[str],
    max_archivos: int | None = None,
) -> dict:
    store = VectorStore(indice, Embedder())
    n_ok = n_skip = n_err = 0
    procesados: list[Path] = []

    for ruta in sorted(carpeta.rglob("*")):
        if not ruta.is_file():
            continue
        if any(p in _IGNORAR for p in ruta.parts):
            n_skip += 1
            continue
        if ruta.suffix.lower() not in extensiones:
            n_skip += 1
            continue
        if max_archivos and n_ok >= max_archivos:
            break
        try:
            texto = ruta.read_text(encoding="utf-8", errors="ignore")
            if len(texto.strip()) < 30:
                n_skip += 1
                continue
            store.agregar_documento(
                titulo=str(ruta.relative_to(carpeta)),
                fuente=f"local:{ruta}",
                texto=texto,
            )
            n_ok += 1
            procesados.append(ruta)
            if n_ok % 25 == 0:
                print(f"  ... {n_ok} archivos indexados")
        except Exception as exc:  # noqa: BLE001
            print(f"  [X] {ruta.name}: {exc}")
            n_err += 1

    return {
        "indexados": n_ok, "saltados": n_skip, "errores": n_err,
        "indice_path": str(indice),
        **store.estado(),
    }


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--carpeta", type=Path, required=True,
                   help="Carpeta raíz a indexar (recursivo).")
    p.add_argument("--indice", type=Path, default=Path("data/rag_index"),
                   help="Carpeta donde se persiste el índice.")
    p.add_argument("--extensiones", nargs="*", default=list(_EXTS_DEFAULT),
                   help="Extensiones a incluir (con el punto).")
    p.add_argument("--max", type=int, default=None,
                   help="Máximo de archivos a indexar.")
    args = p.parse_args()

    extensiones = {e.lower() if e.startswith(".") else "." + e.lower()
                   for e in args.extensiones}

    print(f"[indexar] Carpeta: {args.carpeta.resolve()}")
    print(f"[indexar] Índice : {args.indice.resolve()}")
    print(f"[indexar] Exts   : {sorted(extensiones)}")
    stats = indexar_carpeta(args.carpeta, args.indice, extensiones, args.max)
    print("\n[OK] Resultado:")
    for k, v in stats.items():
        print(f"  {k}: {v}")


if __name__ == "__main__":
    main()
