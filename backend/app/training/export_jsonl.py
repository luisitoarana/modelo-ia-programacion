"""CLI auxiliar para exportar el dataset validado a JSONL.

Uso:
    python -m app.training.export_jsonl --salida datasets/processed/finetune.jsonl

Genera pares instruction/input/output en el formato esperado por la mayoría
de pipelines de fine-tuning supervisado (Alpaca-like).
"""

from __future__ import annotations

import argparse
import asyncio
from pathlib import Path

from app.database import SessionLocal
from app.services.dataset_service import DatasetService
from app.utils.logger import obtener_logger


log = obtener_logger(__name__)


async def _ejecutar(ruta: Path, solo_validados: bool) -> None:
    async with SessionLocal() as sesion:
        servicio = DatasetService(sesion)
        cantidad, destino = await servicio.exportar_jsonl(
            ruta, solo_validados=solo_validados
        )
        await sesion.commit()
        log.info("OK exportados %s registros a %s", cantidad, destino)
        print(f"OK exportados {cantidad} registros a {destino}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Exporta dataset educativo a JSONL.")
    parser.add_argument(
        "--salida",
        type=Path,
        default=Path("datasets/processed/finetune.jsonl"),
        help="Ruta del archivo JSONL de salida.",
    )
    parser.add_argument(
        "--todos",
        action="store_true",
        help="Incluye registros NO validados (por defecto solo valida).",
    )
    args = parser.parse_args()
    asyncio.run(_ejecutar(args.salida, solo_validados=not args.todos))


if __name__ == "__main__":
    main()
