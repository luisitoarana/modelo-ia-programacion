"""Entrenamiento real del LLM educativo propio.

Consolida el corpus (semilla + ejemplos generados por APIs), entrena el
tokenizer y entrena el modelo con el preset elegido.

Uso típico:
    # 1) (opcional) generar datos con APIs
    python -m ml.data.generator --proveedor gemini --por-objetivo 10 \
        --salida datasets/raw/generado_gemini.jsonl

    # 2) entrenar el modelo con todo el corpus disponible
    python -m ml.train --preset pequeno --iters 4000 \
        --corpus datasets/raw/generado_gemini.jsonl
"""

from __future__ import annotations

import argparse
from pathlib import Path

from ml.config import DIR_TOKENIZER, PRESETS, TrainConfig
from ml.data.corpus import (
    cargar_jsonl,
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
    p = argparse.ArgumentParser(description="Entrena el LLM educativo propio.")
    p.add_argument("--preset", default="pequeno", choices=list(PRESETS.keys()))
    p.add_argument("--iters", type=int, default=4000)
    p.add_argument("--vocab", type=int, default=8000)
    p.add_argument("--batch", type=int, default=16)
    p.add_argument("--block", type=int, default=None, help="override de block_size")
    p.add_argument("--device", default="auto")
    p.add_argument("--experimento", default="exp01")
    p.add_argument(
        "--corpus", nargs="*", default=[],
        help="JSONL adicionales (generados por APIs) a unir con la semilla.",
    )
    p.add_argument("--sin-semilla", action="store_true", help="No incluir el corpus semilla.")
    p.add_argument(
        "--tokenizer-existente", default=None,
        help="Ruta a un tokenizer .json pre-entrenado. Si se pasa, se reutiliza en vez de re-entrenarlo.",
    )
    p.add_argument(
        "--solo-tokenizer", action="store_true",
        help="Entrena SOLO el tokenizer y sale. Útil para preparar artefactos reutilizables.",
    )
    p.add_argument(
        "--tokenizer-backend", default="sp", choices=["sp", "bpe"],
        help="Backend del tokenizer: 'sp' (sentencepiece C++, RÁPIDO) o 'bpe' (Python puro, lento).",
    )
    args = p.parse_args()

    # 1) Consolidar corpus
    ejemplos = [] if args.sin_semilla else construir_semilla()
    for ruta in args.corpus:
        ejemplos.extend(cargar_jsonl(ruta))
    ejemplos, descartados = filtrar_validos(ejemplos)
    ejemplos = deduplicar(ejemplos)
    if not ejemplos:
        raise SystemExit("Corpus vacío. Genera datos o usa la semilla.")

    guardar_jsonl(ejemplos, "datasets/processed/corpus_entrenamiento.jsonl")
    stats = estadisticas_corpus(ejemplos)
    print(f"[corpus] {stats['total']} ejemplos | descartados={len(descartados)}")
    print(f"[corpus] por_tema={stats['por_tema']}")

    # 2) Tokenizer (entrenar o reutilizar)
    # Selección del backend: sentencepiece (rápido, default) o BPE puro.
    if args.tokenizer_backend == "sp":
        from ml.tokenizer.sp_tokenizer import SPTokenizer as TokenizerClass
        print("[tokenizer] backend: sentencepiece (C++)")
    else:
        TokenizerClass = BPETokenizer
        print("[tokenizer] backend: BPE Python puro (lento)")

    if args.tokenizer_existente:
        tok_path = Path(args.tokenizer_existente)
        if not tok_path.exists():
            raise SystemExit(f"Tokenizer no encontrado: {tok_path}")
        print(f"[tokenizer] cargando pre-entrenado: {tok_path}")
        tokenizer = TokenizerClass.cargar(tok_path)
        print(f"[tokenizer] vocab={tokenizer.vocab_size}")
    else:
        print("[tokenizer] entrenando...")
        textos = construir_textos_tokenizer(ejemplos)
        tokenizer = TokenizerClass().entrenar(textos, vocab_size=args.vocab, verbose=True)
        tok_path = Path(DIR_TOKENIZER) / f"tokenizer_{args.experimento}.json"
        tokenizer.guardar(tok_path)
        print(f"[tokenizer] vocab={tokenizer.vocab_size} -> {tok_path}")

    if args.solo_tokenizer:
        print("[OK] Tokenizer listo. (--solo-tokenizer activo, no se entrena modelo)")
        return

    # 3) Datos
    data = empaquetar_tokens(ejemplos, tokenizer)
    train_data, val_data, test_data = split_datos(data, val_split=0.1, test_split=0.1)
    print(f"[datos] tokens: total={data.numel():,} train={train_data.numel():,} val={val_data.numel():,}")

    # 4) Modelo + entrenamiento
    model_cfg = PRESETS[args.preset]()
    model_cfg.vocab_size = tokenizer.vocab_size
    if args.block:
        model_cfg.block_size = args.block
    model_cfg.block_size = min(model_cfg.block_size, max(32, train_data.numel() // 4))

    train_cfg = TrainConfig(
        batch_size=args.batch,
        max_iters=args.iters,
        warmup_iters=max(50, args.iters // 20),
        eval_interval=max(100, args.iters // 20),
        device=args.device,
        nombre_experimento=args.experimento,
    )
    trainer = Trainer(model_cfg, train_cfg, train_data, val_data, tokenizer_path=str(tok_path))
    resultado = trainer.entrenar()
    print("\n[OK] Entrenamiento finalizado.")
    print(f"  experimento: {resultado['experimento']}")
    print(f"  checkpoint: {train_cfg.checkpoint_dir}\\{args.experimento}_best.pt")
    print(f"  prueba inferencia: python -m ml.generate --checkpoint training/checkpoints/{args.experimento}_best.pt")


if __name__ == "__main__":
    main()
