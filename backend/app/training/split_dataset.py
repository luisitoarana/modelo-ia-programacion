"""Divide un JSONL limpio en train / val / test para fine-tuning."""

from __future__ import annotations

import argparse
import json
import random
from pathlib import Path


def split(
    jsonl_entrada: Path,
    carpeta_salida: Path,
    *,
    proporciones: tuple[float, float, float] = (0.8, 0.1, 0.1),
    semilla: int = 42,
) -> dict[str, int]:
    if abs(sum(proporciones) - 1.0) > 1e-6:
        raise ValueError("Las proporciones deben sumar 1.0")

    registros = [
        json.loads(l)
        for l in jsonl_entrada.read_text(encoding="utf-8").splitlines()
        if l.strip()
    ]
    rng = random.Random(semilla)
    rng.shuffle(registros)

    n = len(registros)
    n_train = int(n * proporciones[0])
    n_val = int(n * proporciones[1])
    train = registros[:n_train]
    val = registros[n_train : n_train + n_val]
    test = registros[n_train + n_val :]

    carpeta_salida.mkdir(parents=True, exist_ok=True)
    for nombre, particion in (("train", train), ("val", val), ("test", test)):
        ruta = carpeta_salida / f"{nombre}.jsonl"
        with ruta.open("w", encoding="utf-8") as f:
            for reg in particion:
                f.write(json.dumps(reg, ensure_ascii=False) + "\n")

    return {"total": n, "train": len(train), "val": len(val), "test": len(test)}


def main() -> None:
    parser = argparse.ArgumentParser(description="Split de dataset para fine-tuning.")
    parser.add_argument("entrada", type=Path)
    parser.add_argument("salida_dir", type=Path)
    parser.add_argument("--train", type=float, default=0.8)
    parser.add_argument("--val", type=float, default=0.1)
    parser.add_argument("--test", type=float, default=0.1)
    parser.add_argument("--semilla", type=int, default=42)
    args = parser.parse_args()
    stats = split(
        args.entrada,
        args.salida_dir,
        proporciones=(args.train, args.val, args.test),
        semilla=args.semilla,
    )
    print(json.dumps(stats, indent=2))


if __name__ == "__main__":
    main()
