"""Paquete del LLM educativo propio (construido desde cero en PyTorch).

Subpaquetes:
    tokenizer/  — Tokenizer BPE byte-level propio.
    model/      — Transformer decoder implementado desde cero.
    data/       — Generación de dataset, corpus y datasets de entrenamiento.
    training/   — Pipeline de entrenamiento, checkpoints y experimentos.
    inference/  — Motor de inferencia y respuesta educativa.

Las APIs externas (Gemini/DeepSeek) se usan EXCLUSIVAMENTE en data/ para
generar y validar datos de entrenamiento. El modelo final responde sin APIs.
"""

__version__ = "0.1.0"
