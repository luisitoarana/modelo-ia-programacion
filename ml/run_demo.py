"""Demostración end-to-end del LLM propio (sin APIs).

Ejecuta TODO el pipeline en modo reducido para verificar que funciona en
esta máquina:
    1. Construye el corpus semilla.
    2. Entrena el tokenizer propio.
    3. Entrena el Transformer (preset nano, pocas iteraciones).
    4. Carga el checkpoint y genera una respuesta.

Uso:
    python -m ml.run_demo
    python -m ml.run_demo --iters 500 --preset pequeno
"""

from __future__ import annotations

import argparse
from pathlib import Path

from ml.config import DIR_TOKENIZER, PRESETS, TrainConfig
from ml.data.corpus import (
    construir_textos_tokenizer,
    deduplicar,
    estadisticas_corpus,
    filtrar_validos,
    guardar_jsonl,
)
from ml.data.loader import empaquetar_tokens, split_datos
from ml.data.seed import construir_semilla
from ml.tokenizer.bpe import BPETokenizer
from ml.training.trainer import Trainer


def main() -> None:
    parser = argparse.ArgumentParser(description="Demo end-to-end del LLM propio.")
    parser.add_argument("--preset", default="nano", choices=list(PRESETS.keys()))
    parser.add_argument("--iters", type=int, default=300)
    parser.add_argument("--vocab", type=int, default=1000)
    parser.add_argument("--batch", type=int, default=8)
    parser.add_argument("--device", default="auto")
    args = parser.parse_args()

    print("=" * 60)
    print("DEMO LLM EDUCATIVO PROPIO — pipeline end-to-end")
    print("=" * 60)

    # 1) Corpus
    ejemplos = construir_semilla()
    ejemplos, _ = filtrar_validos(ejemplos)
    ejemplos = deduplicar(ejemplos)
    print(f"\n[1] Corpus semilla: {len(ejemplos)} ejemplos")
    stats = estadisticas_corpus(ejemplos)
    print(f"    temas: {stats['por_tema']}")
    guardar_jsonl(ejemplos, "datasets/processed/corpus_demo.jsonl")

    # 2) Tokenizer
    print("\n[2] Entrenando tokenizer propio...")
    textos = construir_textos_tokenizer(ejemplos)
    tokenizer = BPETokenizer().entrenar(textos, vocab_size=args.vocab, verbose=False)
    tok_path = Path(DIR_TOKENIZER) / "tokenizer_demo.json"
    tokenizer.guardar(tok_path)
    print(f"    vocab_size={tokenizer.vocab_size}  -> {tok_path}")

    # 3) Datos empaquetados
    data = empaquetar_tokens(ejemplos, tokenizer)
    train_data, val_data, _ = split_datos(data, val_split=0.15, test_split=0.05)
    print(f"\n[3] Tokens: total={data.numel()} train={train_data.numel()} val={val_data.numel()}")

    # 4) Modelo + entrenamiento
    model_cfg = PRESETS[args.preset]()
    model_cfg.vocab_size = tokenizer.vocab_size
    model_cfg.block_size = min(model_cfg.block_size, max(32, train_data.numel() // 4))

    train_cfg = TrainConfig(
        batch_size=args.batch,
        grad_accum_steps=1,
        max_iters=args.iters,
        warmup_iters=max(10, args.iters // 20),
        eval_interval=max(50, args.iters // 5),
        eval_iters=20,
        log_interval=max(20, args.iters // 10),
        device=args.device,
        nombre_experimento="demo",
    )
    print(f"\n[4] Entrenando modelo (preset={args.preset}, block_size={model_cfg.block_size})...")
    trainer = Trainer(
        model_cfg, train_cfg, train_data, val_data, tokenizer_path=str(tok_path)
    )
    resultado = trainer.entrenar()

    # 5) Inferencia
    print("\n[5] Generando una respuesta con el modelo entrenado...")
    from ml.inference.engine import InferenceEngine

    ckpt = Path(train_cfg.checkpoint_dir) / "demo_best.pt"
    if not ckpt.exists():
        ckpt = Path(train_cfg.checkpoint_dir) / "demo_final.pt"
    engine = InferenceEngine(ckpt, tokenizer_path=str(tok_path), device=args.device)
    r = engine.responder(
        "Explica qué es una función en Python",
        max_nuevos_tokens=80,
        temperatura=0.8,
    )
    print(f"\n  >>> Respuesta del modelo propio ({r.tokens_generados} tokens, {r.latencia_segundos}s):")
    print(f"  {r.texto!r}")

    print("\n" + "=" * 60)
    print("DEMO COMPLETADA. El pipeline LLM propio funciona end-to-end.")
    print(f"Mejor val_loss: {resultado['mejor_val_loss']:.4f}")
    print("Nota: con corpus pequeño y pocas iteraciones el texto aún es")
    print("incoherente; la calidad sube con más datos (APIs) e iteraciones.")
    print("=" * 60)


if __name__ == "__main__":
    main()
