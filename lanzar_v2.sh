#!/bin/bash
# Wrapper portable que lanza el entrenamiento real.
# Logs en training_tesis_v2.log (append) — sobrevive desconexión.
export PYTHONUNBUFFERED=1
export PYTHONIOENCODING=utf-8
ml/.venv/Scripts/python.exe -u -m ml.train \
  --preset experto \
  --iters 30000 \
  --batch 8 \
  --experimento tesis_v2 \
  --vocab 16000 \
  --corpus datasets/processed/corpus_entrenamiento.jsonl \
  --tokenizer-backend sp \
  --tokenizer-existente ml/tokenizer/artefactos/tokenizer_tesis_v1.json \
  --sin-semilla \
  >> training_tesis_v2.log 2>&1
