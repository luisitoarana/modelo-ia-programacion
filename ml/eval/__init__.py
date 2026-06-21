"""Benchmark harness automático para evaluar modelos.

Este paquete evalúa cualquier checkpoint en métricas estándar:
    - HumanEval pass@1  (problemas Python con tests)
    - MBPP pass@1       (subset español de Mostly Basic Python Problems)
    - Perplexity en hold-out
    - Sample outputs cualitativos

Salida: tabla Markdown lista para el capítulo de Resultados de la tesis.

Uso:
    python -m ml.eval.run --checkpoint training/checkpoints/tesis_v2_best.pt \\
        --tokenizer ml/tokenizer/artefactos/tokenizer_tesis_v1.json \\
        --salida docs/EXPERIMENTOS/exp_tesis_v2.md
"""
