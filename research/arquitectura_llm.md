# Arquitectura y metodología del LLM educativo propio

> Documento metodológico del proyecto. Describe el modelo construido desde
> cero, su entrenamiento y su evaluación.

## 1. Objetivo

Construir, desde cero, un modelo de lenguaje (LLM) decoder-only especializado
en la generación y explicación de código Python con fines educativos, evitando
depender de APIs externas en la respuesta final al estudiante.

## 2. Arquitectura del modelo

Transformer decoder (estilo GPT) implementado en PyTorch sin usar
`nn.Transformer` ni `nn.MultiheadAttention` (la atención se programa a mano):

```
Tokens ─► Embedding ─► + Positional Encoding (sinusoidal)
 ─► [ Bloque × N ]:
 x = x + MultiHeadSelfAttention(LayerNorm(x)) (atención causal)
 x = x + FeedForward(LayerNorm(x)) (MLP 4x + GELU)
 ─► LayerNorm final
 ─► LM Head (proyección a vocabulario, weight tying)
 ─► Cross-Entropy (entrenamiento autoregresivo)
```

Componentes (en `ml/model/transformer.py`):

- **Embedding de tokens** + **Positional Encoding sinusoidal** (sin parámetros).
- **Multi-Head Self-Attention causal**: Q, K, V proyectados, atención escalada
 `softmax(QKᵀ/√d)·V` con máscara triangular (no mirar el futuro).
- **Feed-Forward Network**: expansión 4×, GELU, dropout.
- **Pre-LN + residuales**: estabilidad de entrenamiento.
- **LM Head** con *weight tying* (comparte pesos con el embedding).
- **Generación**: muestreo con temperatura, top-k y top-p.

### Presets

| Preset | n_layer | n_head | n_embd | block | Parámetros | Uso |
|--------|---------|--------|--------|-------|------------|-----|
| nano | 4 | 4 | 128 | 128 | ~1-3 M | CPU / pruebas |
| pequeno | 6 | 6 | 384 | 256 | ~15-20 M | RTX 2050 (4 GB) |
| mediano | 8 | 8 | 512 | 384 | ~40-60 M | ≥ 8 GB VRAM |

## 3. Tokenizer propio

BPE byte-level en Python puro (`ml/tokenizer/bpe.py`):

- Base de 256 bytes ⇒ cualquier texto es representable (sin "unknown").
- Aprende fusiones de pares frecuentes hasta el tamaño de vocabulario.
- Tokens especiales que estructuran la tarea instrucción→respuesta:
 `<bos> <instr> … <inp> … <out> … <eos>`.
- Maneja simultáneamente español (tildes, ñ) y código Python (símbolos,
 identación, operadores).

## 4. Construcción del dataset (rol de las APIs)

Las APIs (Gemini/DeepSeek) se usan **solo** aquí (`ml/data/generator.py`) para
generar ejemplos en el formato:

```json
{"instruccion": "...", "entrada": "...", "salida": "...",
 "nivel": "basico", "tema": "funciones", "tipo": "explicacion_codigo"}
```

Pipeline de datos:
1. **Generación** dirigida por objetivos (tema × nivel).
2. **Validación** local (formato, longitud, no vacío).
3. **Deduplicación** y consolidación del corpus.
4. **Empaquetado** en tokens para entrenamiento autoregresivo.

Existe además un **corpus semilla** incorporado (`ml/data/seed.py`) que permite
entrenar y probar todo el pipeline sin gastar API.

## 5. Entrenamiento

Pipeline en `ml/training/trainer.py`:

- División train/val/test.
- Scheduler: warmup lineal + decaimiento cosenoidal.
- Acumulación de gradientes (batch efectivo mayor con poca VRAM).
- Gradient clipping.
- Autocast bf16/fp16 en GPU; float32 en CPU.
- Evaluación periódica (train/val) y **checkpoint de mejor val_loss**.
- **Registro de experimentos**: `config.json` + `metrics.jsonl` por experimento.

## 6. Inferencia

`ml/inference/engine.py` carga el checkpoint y el tokenizer, construye el
prompt con la plantilla y genera la respuesta de forma autoregresiva, **sin
APIs**. Integrado en el backend vía `model_inference_service.py` y expuesto en
`POST /api/v1/ai/preguntar-modelo`.

## 7. Evaluación

- **Cuantitativa**: pérdida (cross-entropy) y perplejidad en validación/test;
 curvas de aprendizaje (panel de entrenamiento del portal).
- **Cualitativa**: rúbrica de calidad educativa (`quality_service`) y revisión
 humana de las respuestas generadas.
- **Comparativa**: calidad de los datos generados por Gemini vs DeepSeek.

## 8. Resultado verificado (prueba de concepto)

El pipeline completo se ejecutó end-to-end en la máquina de desarrollo (CPU):
modelo nano de ~895K parámetros, pérdida de entrenamiento 6.69 → 5.60 en 300
iteraciones (~30 s), con checkpoint e inferencia funcionales. Demuestra que la
maquinaria del LLM (tokenizer + Transformer + entrenamiento + inferencia)
opera correctamente. La coherencia del texto escala con el tamaño del corpus
(generado con APIs) y el número de iteraciones, idealmente sobre GPU.

## 9. Limitaciones

- Escala de cómputo (GPU de 4 GB) ⇒ modelo pequeño; no compite con LLMs
 comerciales en calidad.
- Dataset sintético: hereda sesgos y posibles errores de las APIs; de ahí la
 validación de calidad y la revisión humana.
- El aporte es la **metodología y el artefacto reproducible**, no un modelo de
 producción.

## 10. Trabajo futuro

- Ampliar el corpus (más temas, más ejemplos por objetivo).
- Entrenar presets mayores en GPU dedicada.
- Fine-tuning continuo con nuevas interacciones validadas.
- Métricas automáticas de comprensión y estudios con usuarios.
```

---

## 11. Arquitectura V2 (junio 2026) — Modernización del modelo propio

Este documento original describe el **Modelo A** de la fase 1 (~46 M
parámetros, prueba de concepto). En la fase de modelo propio escalable
(modelos B y C) se introduce la **Arquitectura V2**, que mantiene la
filosofía de construir el modelo desde cero pero incorpora cinco
técnicas del estado del arte 2024–2025 sin aumentar el número de
parámetros nominales.

### 11.1 Cambios introducidos

| Componente V1 | Componente V2 | Justificación |
|---|---|---|
| PositionalEncoding sinusoidal aditivo | **Rotary Position Embeddings (RoPE)** | Permite extrapolar el contexto sin reentrenar; usado por Llama, Mistral, Qwen. |
| Multi-Head Attention con n_head = n_kv_head | **Grouped-Query Attention (GQA)** con n_head > n_kv_head | KV-cache 4–8 × más pequeño, habilita contextos largos. |
| FeedForward MLP con GeLU (expansión 4×) | **SwiGLU** con expansión 8/3 (Llama) o 4 (Llama-large) | +2–4 % de calidad sin aumentar parámetros, mejor gradient flow. |
| LayerNorm | **RMSNorm** | ~7 % más rápida, sin pérdida de calidad. |
| Atención implementada a mano | **FlashAttention v2** vía `F.scaled_dot_product_attention` | 3–10× más rápida en GPU, NO materializa matriz N×N en memoria. |

### 11.2 Diagrama de un bloque V2

```
 Input x (B, T, n_embd)
 │
 ▼
 RMSNorm (ε=1e-6, en fp32 para estabilidad)
 │
 ▼
 GroupedQueryAttention:
 Q proj: (n_embd) → (n_head·head_dim)
 K, V proj: (n_embd) → (n_kv_head·head_dim)
 Aplicar RoPE a Q y K (no a V)
 Expandir K, V de n_kv_head a n_head con repeat_interleave
 F.scaled_dot_product_attention(causal=True)
 ↓ FlashAttention v2 si CUDA + dtype FP16/BF16
 + residual
 │
 ▼
 RMSNorm
 │
 ▼
 SwiGLU FFN:
 hidden = silu(W_gate(x)) * W_up(x)
 out = W_down(hidden)
 + residual
 │
 ▼
 Output (B, T, n_embd)
```

### 11.3 Presets V2 (`ml/config.py` función `PRESETS_V2`)

| Preset | Parámetros reales | n_layer | n_head | n_kv_head | n_embd | block_size | swiglu_mult |
|---|---|---|---|---|---|---|---|
| `sota_experto` | 30.7 M | 8 | 8 | 2 | 512 | 512 | 8/3 |
| `sota_grande` | 87.8 M | 12 | 12 | 4 | 768 | 1024 | 8/3 |
| `sota_b` | **150.7 M** | 16 | 12 | 4 | 768 | 1024 | 4.0 |
| `sota_c` | **350.9 M** | 22 | 16 | 4 | 1024 | 2048 | 4.0 |
| `sota_d` | 869.9 M (opcional) | 36 | 20 | 4 | 1280 | 2048 | 4.0 |

### 11.4 Gradient checkpointing

Para que el modelo B (~150 M) quepa en RTX 2050 (4 GB) o T4 (16 GB)
con seq_len 1024, se implementa gradient checkpointing en el bucle de
bloques:

```python
if self._gradient_checkpointing and self.training:
 for bloque in self.bloques:
 x = torch.utils.checkpoint.checkpoint(
 bloque, x, cos, sin, use_reentrant=False
 )
```

Activación dinámica con:

```python
modelo.gradient_checkpointing_enable()
modelo.gradient_checkpointing_disable()
```

Reduce VRAM 2–3× a costa de ~30 % de tiempo adicional.

### 11.5 Tokenizer V2

- Misma biblioteca: sentencepiece (Byte-Pair Encoding).
- Vocabulario: **16 000** (vs 8 000 del V1).
- Tokens especiales planificados:
 - Roles: `<|user|>`, `<|assistant|>`, `<|system|>`, `<|end|>`.
 - Estructura: `<think>`, `</think>`, `<code>`, `</code>`.
 - Control codes: `<NIVEL=basico>`, `<NIVEL=intermedio>`,
 `<NIVEL=avanzado>`.
 - Pesos: `<SEG=10>`, `<LEG=10>`, etc.

### 11.6 Interfaz compatible

`GPTEducativoV2` expone exactamente los mismos métodos públicos que
`GPTEducativo` (V1):

- `forward(idx, targets=None) → (logits, loss)`.
- `generar(idx, max_new_tokens, temperatura, top_k, top_p) → tensor`.
- `num_parametros(solo_entrenables=True) → int`.
- `configurar_optimizador(weight_decay, lr, betas) → Optimizer`.

Esto permite sustituir V1 ↔ V2 sin tocar el resto del pipeline
(`train.py`, `generate.py`, `model_inference_service.py`).

### 11.7 Pipeline de entrenamiento V2

El modelo V2 se entrena con un currículum de cinco fases descrito en
[`docs/PLAN_ENTRENAMIENTO_V2.md`](../docs/PLAN_ENTRENAMIENTO_V2.md).
Cada fase tiene su archivo YAML de configuración en
`ml/training/configs/`, y se ejecuta con
`python -m ml.training.run_fase --config <yaml>`.

### 11.8 Sistema de recompensa multi-criterio

Paralelamente al modelo principal, se entrenan **seis modelos de
recompensa** (uno por dimensión de calidad) con encoder Transformer V2
compartido. Estos modelos:

- Alimentan la pérdida DPO multi-objetivo de Fase 5b.
- Se usan en producción para regeneración por umbral.
- Detallados en [`docs/REWARD_MODELS.md`](../docs/REWARD_MODELS.md).

### 11.9 Referencias V2

- Su et al., **RoFormer: Enhanced Transformer with Rotary Position Embedding**, 2021.
- Ainslie et al., **GQA: Training Generalized Multi-Query Transformer Models**, 2023.
- Shazeer, **GLU Variants Improve Transformer**, 2020 (SwiGLU).
- Zhang & Sennrich, **Root Mean Square Layer Normalization**, 2019 (RMSNorm).
- Dao, **FlashAttention-2: Faster Attention with Better Parallelism**, 2023.
