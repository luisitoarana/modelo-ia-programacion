"""Inferencia interactiva con el LLM propio (sin APIs).

Uso:
    python -m ml.generate --checkpoint training/checkpoints/exp01_best.pt
    python -m ml.generate --checkpoint ... --instruccion "Explica los bucles for"
"""

from __future__ import annotations

import argparse

from ml.inference.engine import InferenceEngine


def main() -> None:
    p = argparse.ArgumentParser(description="Genera respuestas con el modelo propio.")
    p.add_argument("--checkpoint", required=True)
    p.add_argument("--tokenizer", default=None)
    p.add_argument("--instruccion", default=None)
    p.add_argument("--entrada", default="")
    p.add_argument("--max-tokens", type=int, default=200)
    p.add_argument("--temperatura", type=float, default=0.8)
    p.add_argument("--top-k", type=int, default=40)
    p.add_argument("--device", default="auto")
    args = p.parse_args()

    engine = InferenceEngine(
        args.checkpoint, tokenizer_path=args.tokenizer, device=args.device
    )
    print(f"[modelo] {engine.num_parametros:,} parámetros en {engine.device}\n")

    if args.instruccion:
        r = engine.responder(
            args.instruccion,
            entrada=args.entrada,
            max_nuevos_tokens=args.max_tokens,
            temperatura=args.temperatura,
            top_k=args.top_k,
        )
        print(f">>> {r.texto}\n")
        print(f"({r.tokens_generados} tokens, {r.latencia_segundos}s, {r.device})")
        return

    print("Modo interactivo. Escribe una instrucción (vacío para salir).\n")
    while True:
        try:
            instr = input("instruccion> ").strip()
        except (EOFError, KeyboardInterrupt):
            break
        if not instr:
            break
        r = engine.responder(
            instr,
            max_nuevos_tokens=args.max_tokens,
            temperatura=args.temperatura,
            top_k=args.top_k,
        )
        print(f"\n>>> {r.texto}\n({r.tokens_generados} tokens, {r.latencia_segundos}s)\n")


if __name__ == "__main__":
    main()
