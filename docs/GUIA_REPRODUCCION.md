# Guía de Reproducción

> Guía paso a paso para reproducir el sistema desde cero. Sirve como
> apéndice metodológico de el proyecto y para que un revisor académico
> pueda replicar los resultados.
>
> **Prerrequisito**: Python 3.11 o superior, Git, y al menos una clave
> API gratuita (Gemini o Groq).

---

## 1. Clonar el repositorio

```powershell
git clone <url-del-repo>
cd sistema-explicador-python-ia
```

---

## 2. Configurar el entorno

### 2.1 Crear entorno virtual

```powershell
python -m venv.venv
.\.venv\Scripts\Activate.ps1
```

### 2.2 Instalar dependencias

```powershell
pip install --upgrade pip
pip install -r ml/requirements.txt
pip install sentencepiece pyyaml httpx
```

Si se va a entrenar el modelo:

```powershell
pip install torch --index-url https://download.pytorch.org/whl/cu124
pip install -r ml/requirements-finetune.txt
```

### 2.3 Configurar `.env`

Copiar `.env.example` a `.env` y completar con las claves API:

```powershell
Copy-Item.env.example.env
notepad.env
```

Claves recomendadas (todas con tier gratis):

```
GEMINI_API_KEY=AIza... # https://aistudio.google.com/app/apikey
GROQ_API_KEY=gsk_... # https://console.groq.com/keys
GROQ_MODEL=llama-3.1-8b-instant # más rápido; usar 70b para mejor calidad
DEEPSEEK_API_KEY= # opcional
TOGETHER_API_KEY= # opcional
MISTRAL_API_KEY= # opcional
OPENROUTER_API_KEY= # opcional
```

Verificar que el pool detecta las claves:

```powershell
python -c "from ml.data.pool_generadores import Pool; print(Pool.desde_env().disponibles)"
```

Debe imprimir una lista no vacía: `['gemini']`, `['groq']`, etc.

---

## 3. Construir el corpus pedagógico V2

### 3.1 Smoke test (10–15 minutos)

```powershell
python -m ml.data.construir_dataset_v2 `
 --salida-dir datasets/raw `
 --escala mini
```

Esto produce ~200–500 ejemplos en `datasets/raw/dataset_v2.jsonl`.

### 3.2 Escala media (2–4 horas)

```powershell
python -m ml.data.construir_dataset_v2 `
 --salida-dir datasets/raw `
 --escala media `
 --reset
```

~3 000–5 000 ejemplos.

### 3.3 Escala completa (2–3 días)

```powershell
python -m ml.data.construir_dataset_v2 `
 --salida-dir datasets/raw `
 --escala completa `
 --reset
```

~50 000–100 000 ejemplos (objetivo: 333 000 con múltiples corridas y
proveedores).

### 3.4 Auditar el corpus

```powershell
python -m ml.data.audit --corpus datasets/raw/dataset_v2.jsonl
```

Reporta porcentaje de válidos, distribución por tipo/nivel/tema,
código que compila, ejemplos con CoT, etc.

### 3.5 Descargar datasets públicos en formato V2

```powershell
python -m ml.data.download_hf `
 --dataset codealpaca,magicoder-oss,magicoder-evol,apps,ds-1000 `
 --salida-dir datasets/raw `
 --schema-v2
```

---

## 4. Entrenar el tokenizer V2

```powershell
python ml/tokenizer/sp_tokenizer.py train `
 --corpus datasets/raw/dataset_v2.jsonl `
 --salida ml/tokenizer/artefactos/sp_v2_16k.model `
 --vocab-size 16000
```

Tarda ~2-3 minutos con sentencepiece.

---

## 5. Etiquetar el corpus con los jueces multi-criterio

```powershell
# Generar respuestas del modelo actual (Fase 5a o modelo V1 si no hay V2 aún)
# y volcarlas a un JSONL con campos prompt y respuesta.

python -m ml.rlhf.etiquetar_dataset `
 --entrada datasets/raw/respuestas_modelo.jsonl `
 --salida datasets/etiquetado/scores_v1.jsonl `
 --concurrencia 4
```

El etiquetador es resumible: si se interrumpe, al relanzar continúa
donde quedó.

Objetivo: 30 000+ respuestas etiquetadas.

---

## 6. Entrenar los 6 reward models propios

```powershell
python -m ml.rlhf.entrenar_rm `
 --config ml/rlhf/configs/rm_v1.yaml
```

Configuración recomendada (preset mediano, ~16 M parámetros). Tiempo
estimado en RTX 2050: ~3 horas.

Verificar al final que los Pearson correlation contra los jueces LLM
son ≥ 0.7 en cada dimensión.

---

## 7. Entrenar el modelo B (150 M parámetros) en 5 fases

Cada fase es un comando independiente, reanudable.

### 7.1 Fase 1 — Pretraining código

```powershell
python -m ml.training.run_fase `
 --config ml/training/configs/fase1_pretrain_B.yaml
```

Tiempo estimado en Kaggle T4: ~25 horas (en chunks de 9 horas).
Para chunking:

```powershell
python -m ml.training.run_fase `
 --config ml/training/configs/fase1_pretrain_B.yaml `
 --tiempo-max-minutos 525
```

Tras 8 h 45 min guarda checkpoint y termina cleanly. Para reanudar:

```powershell
python -m ml.training.run_fase `
 --config ml/training/configs/fase1_pretrain_B.yaml `
 --resume training/checkpoints/B_fase1/checkpoint_ultimo.pt `
 --tiempo-max-minutos 525
```

### 7.2 Fase 2 — Documentación oficial

```powershell
python -m ml.training.run_fase --config ml/training/configs/fase2_docs_B.yaml
```

### 7.3 Fase 3 — Chain-of-thought

```powershell
python -m ml.training.run_fase --config ml/training/configs/fase3_cot_B.yaml
```

### 7.4 Fase 4 — Destilación

```powershell
python -m ml.training.run_fase --config ml/training/configs/fase4_distillation_B.yaml
```

### 7.5 Fase 5a — Senior (revisión)

```powershell
python -m ml.training.run_fase --config ml/training/configs/fase5a_senior_B.yaml
```

### 7.6 Fase 5b — DPO multi-criterio

```powershell
python -m ml.rlhf.dpo_multi --config ml/training/configs/fase5b_dpo_B.yaml
```

---

## 8. Repetir para modelo C (350 M parámetros)

Editar cada YAML cambiando:

```yaml
modelo:
 preset: sota_c # antes era sota_b
```

Y ajustar `salida:` a `training/checkpoints/C_faseN/`.

Tiempo proyectado total: ~70 horas en Kaggle T4 (vs. ~30 para B).

---

## 9. Cargar el modelo final en el backend

Copiar el checkpoint a la carpeta de servicio:

```powershell
New-Item -ItemType Directory -Path backend/app/services/modelo_propio -Force
Copy-Item training/checkpoints/B_fase5b_dpo/checkpoint_best.pt `
 backend/app/services/modelo_propio/prod_v2.0_2026-09.pt

Copy-Item ml/tokenizer/artefactos/sp_v2_16k.model `
 backend/app/services/modelo_propio/
```

Actualizar `.env`:

```
MODEL_ENABLED=true
MODEL_CHECKPOINT_PATH=backend/app/services/modelo_propio/prod_v2.0_2026-09.pt
MODEL_TOKENIZER_PATH=backend/app/services/modelo_propio/sp_v2_16k.model
```

Reiniciar el backend.

---

## 10. Ejecutar evaluación final

```powershell
# Benchmarks automáticos
python -m ml.eval.run --modelo backend/app/services/modelo_propio/prod_v2.0_2026-09.pt

# Comparativa cualitativa con 100 prompts canónicos
python -m ml.eval.benchmarks --prompts ml/eval/prompts_canonicos.txt
```

Resultados van a `training/experiments/eval_v2_<timestamp>/`.

---

## 11. Verificar reproducibilidad

Para confirmar que cualquier paso es reproducible:

```powershell
# Re-correr el smoke test del dataset
python -m ml.data.construir_dataset_v2 --salida-dir datasets/raw --escala mini --reset

# Re-correr un entrenamiento con la misma semilla
python -m ml.training.run_fase --config ml/training/configs/fase1_pretrain_B.yaml

# Comparar los metrics.jsonl (deben ser bit-idénticos hasta tolerancia FP)
diff training/checkpoints/B_fase1/metrics.jsonl reference/B_fase1_metrics.jsonl
```

---

## 12. Estructura de archivos generados

Al final del proceso se tiene:

```
datasets/
├── raw/
│ ├── dataset_v2.jsonl # Corpus consolidado
│ ├── pensamiento_v1.jsonl # Por tipo
│ ├──...
│ └── resumen_construccion.json # Stats del orquestador
├── etiquetado/
│ └── scores_v1.jsonl # Corpus + scores 6 dim
└── publicos/ # Datasets HF descargados
 ├── codealpaca.jsonl
 └──...

ml/tokenizer/artefactos/
└── sp_v2_16k.model # Tokenizer V2

training/checkpoints/
├── RM_v1/
│ ├── checkpoint_best.pt
│ ├── checkpoint_ultimo.pt
│ ├── config_resuelta.json
│ └── metrics.jsonl
├── B_fase1/... B_fase5b_dpo/
└── C_fase1/... C_fase5b_dpo/

backend/app/services/modelo_propio/
├── prod_v2.0_2026-09.pt
└── sp_v2_16k.model
```

---

## 13. Tiempos totales proyectados (hardware mínimo)

| Etapa | Hardware | Tiempo |
|---|---|---|
| Configuración del entorno | local | 30 min |
| Dataset mini | Cualquiera + Gemini/Groq | 15 min |
| Dataset media | Cualquiera + Gemini/Groq | 3 h |
| Dataset completo | Cualquiera + 6 APIs | 2–3 días |
| Etiquetado (30k respuestas) | Cualquiera + 6 APIs | 1–2 días |
| Tokenizer V2 | local | 5 min |
| Entrenamiento 6 RM | RTX 2050 (preset pequeño) | 6–12 h |
| Modelo B Fases 1-5b | Kaggle T4 (chunks de 9 h) | ~50 h |
| Modelo C Fases 1-5b | Kaggle T4 / Modal A10G | ~80 h |
| Evaluación final | local | 4 h |
| **Total proyectado** | — | **~3 meses calendario** |

---

## 14. Solución de problemas comunes

### El pool dice "No hay proveedores configurados"

Verificar que `.env` está en la raíz del proyecto y que tiene al
menos una clave válida sin espacios alrededor del `=`.

### El parser de JSON falla

Verificar que se está usando el modelo Groq 70B o Gemini para CoT. El
modelo 8b a veces produce JSON malformado; el extractor robusto lo
maneja pero la calidad baja.

### CUDA out of memory

Activar gradient checkpointing en el YAML:

```yaml
training:
 gradient_checkpointing: true
 per_device_batch_size: 1
 grad_accum_steps: 32
```

Y reducir `max_seq_len` si es necesario.

### El entrenamiento es muy lento

- Verificar que `dtype: auto` selecciona FP16 o BF16 (no FP32).
- Confirmar GPU detectada: `python -c "import torch; print(torch.cuda.is_available())"`.
- En CPU el entrenamiento de modelos B+ no es viable.

### Rate limit de Groq

Reducir frecuencia o cambiar a Gemini con TPM mucho mayor (1 M).
Verificar que `esperar_si_rate_limited=True` está activo en los
generadores.

---

## 15. Referencias adicionales

- [`README.md`](./README.md) del directorio `docs/` para el orden de
 lectura recomendado.
- [`PROPUESTA_INVESTIGACION.md`](./PROPUESTA_INVESTIGACION.md) para el
 marco académico.
- [`DECISIONES_DISENO.md`](./DECISIONES_DISENO.md) para entender el
 porqué de cada decisión.
- [`BUGS_Y_SOLUCIONES.md`](./BUGS_Y_SOLUCIONES.md) para problemas
 encontrados durante el desarrollo y sus soluciones.
