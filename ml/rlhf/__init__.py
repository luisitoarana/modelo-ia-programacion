"""Aprendizaje por refuerzo con feedback humano (RLHF) — implementación
educativa desde cero.

Estructura:
    - `exportar_dataset.py` : exporta votos de la BD a JSONL de pares.
    - `preparar_pares.py`   : genera/limpia pares (chosen, rejected).
    - `dpo.py`              : entrenamiento DPO desde cero.

Ver `docs/RLHF_PLAN.md` para el plan completo y `docs/DPO_TECNICO.md`
para la justificación matemática de la implementación.
"""
