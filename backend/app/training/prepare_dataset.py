"""Normalización y limpieza previa al fine-tuning.

Operaciones:
- Elimina registros con campos vacíos críticos.
- Normaliza espacios en blanco.
- Asegura que el JSON anidado sea serializable.
- Genera estadísticas por tema/nivel.
"""

from __future__ import annotations

import json
from collections import Counter
from pathlib import Path
from typing import Any


CAMPOS_REQUERIDOS_OUTPUT = (
    "nivel",
    "tema",
    "pregunta",
    "codigo",
    "explicacion_general",
)


def _output_valido(output_raw: str) -> dict[str, Any] | None:
    try:
        data = json.loads(output_raw)
    except json.JSONDecodeError:
        return None
    for campo in CAMPOS_REQUERIDOS_OUTPUT:
        if not data.get(campo):
            return None
    return data


def preparar(jsonl_entrada: Path, jsonl_salida: Path) -> dict[str, int]:
    """Procesa un JSONL crudo y produce uno limpio. Devuelve estadísticas."""
    jsonl_salida.parent.mkdir(parents=True, exist_ok=True)
    total = 0
    descartados = 0
    por_tema: Counter[str] = Counter()
    por_nivel: Counter[str] = Counter()

    with (
        jsonl_entrada.open("r", encoding="utf-8") as f_in,
        jsonl_salida.open("w", encoding="utf-8") as f_out,
    ):
        for linea in f_in:
            linea = linea.strip()
            if not linea:
                continue
            total += 1
            try:
                registro = json.loads(linea)
            except json.JSONDecodeError:
                descartados += 1
                continue

            output_data = _output_valido(registro.get("output", ""))
            if output_data is None:
                descartados += 1
                continue

            por_tema[output_data.get("tema", "otro")] += 1
            por_nivel[output_data.get("nivel", "basico")] += 1

            registro["instruction"] = " ".join(registro.get("instruction", "").split())
            registro["input"] = " ".join(registro.get("input", "").split())
            f_out.write(json.dumps(registro, ensure_ascii=False) + "\n")

    return {
        "total_leidos": total,
        "descartados": descartados,
        "escritos": total - descartados,
        **{f"tema_{k}": v for k, v in por_tema.items()},
        **{f"nivel_{k}": v for k, v in por_nivel.items()},
    }


def main() -> None:
    import argparse

    parser = argparse.ArgumentParser(description="Limpia JSONL de fine-tuning.")
    parser.add_argument("entrada", type=Path)
    parser.add_argument("salida", type=Path)
    args = parser.parse_args()
    stats = preparar(args.entrada, args.salida)
    print(json.dumps(stats, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
