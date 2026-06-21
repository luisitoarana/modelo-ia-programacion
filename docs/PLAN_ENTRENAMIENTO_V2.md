# Plan de Entrenamiento V2 — Modelo propio FROM SCRATCH

> **Decisión fundamental, NO negociable**: el modelo se entrena DESDE CERO.
> Sin descargar Qwen, Llama, SmolLM ni nada. Nuestra arquitectura, nuestros
> pesos, nuestro tokenizer, nuestro corpus. Las APIs externas se usan
> ÚNICAMENTE como profesores para generar el dataset, NUNCA como cerebro.
>
> Este documento reemplaza completamente versiones previas que sugerían
> continued pretraining sobre modelos abiertos — eso era contrario a la
> visión del proyecto y se descarta.
>
> Complementa [ENTRENAMIENTO.md](./ENTRENAMIENTO.md) (modelo 46M ya
> entrenado), [DATASET_V2.md](./DATASET_V2.md) (corpus pedagógico) y
> [REWARD_MODELS.md](./REWARD_MODELS.md) (sistema de puntuación).

---

## 1. Filosofía del proyecto

Citando textualmente la visión:

> *"Mi propio modelo, mi propia arquitectura, mis propios pesos, mi
> propio entrenamiento, mi propia especialización en programación."*

> *"Las APIs pueden servir como profesores, no como cerebro."*

> *"Lo que buscas no se logra principalmente con entrenamiento. Se logra
> con datasets. 1 millón de ejemplos excelentes vence a 100 millones de
> ejemplos malos. 80% del tiempo en construir datasets, no en entrenar."*

Esto define todo lo que sigue. **El aporte del proyecto no es construir un
asistente; es construir el modelo y la metodología de entrenamiento desde
cero**, con datasets curados que enseñen a *pensar* sobre código, no
solo a *generarlo*.

---

## 2. Las 5 fases de entrenamiento (currículum)

Calcadas del documento de visión:

### Fase 1 — Aprender lenguajes
Solo código, sin documentación todavía. Predicción de siguiente token.

- Python · JavaScript · TypeScript · Java · SQL · HTML · CSS
- Corpus: The Stack v2 filtrado por lenguaje + lo público de
 [DATASET_V2.md §5](./DATASET_V2.md#5-datos-públicos-que-no-podemos-perdernos)
- **Objetivo**: que el modelo aprenda sintaxis y patrones léxicos. Como
 un estudiante de primer semestre que aún no entiende el "por qué".

### Fase 2 — Aprender documentación oficial
Después del léxico, los conceptos. Solo fuentes canónicas.

- Python Docs · MDN · PEPs · PostgreSQL Docs · Docker Docs · Linux man pages
- Corpus: crawler de docs ([DATASET_V2.md §6.1](./DATASET_V2.md#61-crawler-de-documentación-oficial))
- **Objetivo**: que el modelo empiece a razonar — *qué hace · por qué
 existe · cuándo usarlo*.

### Fase 3 — Profesor IA (pensamiento estructurado)
Aquí el diferenciador. NO entrenar `pregunta → código`, sino
`pregunta → análisis → arquitectura → código → explicación`.

- Corpus: el tipo `pensamiento_programador` del [DATASET_V2.md](./DATASET_V2.md#21-pensamiento_programador-chain-of-thought)
 + `decision_diseno` + `arquitectura_sistema`.
- **Objetivo**: que el modelo razone ANTES de programar.

### Fase 4 — Aprender de GPT/Claude/Gemini como profesores
Distillation pura: las APIs generan ejemplos, el modelo aprende.

- Corpus: los 9 generadores ya implementados
 ([construir_dataset_v2.py](../ml/data/construir_dataset_v2.py)).
- **Objetivo**: capturar el estilo y patrones de los modelos comerciales
 para reproducirlos en local.

### Fase 5 — Programador Senior (revisión y refactorización)
La diferencia enorme. NO entrenar para generar, entrenar para revisar.

- Corpus: `anti_patron` + `bug_sutil` + `evolucion_codigo` v1→v5
 + `seguridad` + `testing_complejidad`.
- DPO multi-criterio con los 6 reward models
 ([REWARD_MODELS.md](./REWARD_MODELS.md)).
- **Objetivo**: que el modelo dé respuestas como un senior dando code
 review, no como un autocompletado.

---

## 3. Realidad de hardware sin descargar modelos

### Lo que cabe en RTX 2050 (4 GB VRAM) **entrenando desde cero**

| Tamaño | Con qué tricks | Cabe |
|---|---|---|
| 25-50M | FP16 + gradient checkpointing | Sí, cómodo |
| 100M | FP16 + GC + batch size 2 + gradient accumulation | Sí, justo |
| 200M | FP16 + GC + batch 1 + grad accum + max_seq 512 | Apretado |
| 300M+ | No realista local | No |

**Ya tenemos** el modelo de 46M entrenado as PoC. La RTX 2050 sirve para:
- Iterar prototipos rápidos (cambios de arquitectura, debug)
- Validar pipelines de datos
- Entrenar el modelo de 50-100M completo

### Lo que cabe en tiers gratuitos cloud (sin pagar nada)

| Recurso | GPU | Cuota gratis | From-scratch hasta |
|---|---|---|---|
| Kaggle Notebooks | T4 16GB / P100 16GB | 30 h/sem | ~500M con tricks, ~250M cómodo |
| Modal Labs | A10G 24GB / A100 40GB | $30 free credits/mes | ~1B con A10G |
| Lightning AI Studios | T4/A10G | $15 free credits + 22h GPU studios | ~500M |
| Google Colab Free | T4 15GB (variable) | ~3-5 h/día | ~500M con tricks |
| Vast.ai / RunPod welcome | RTX 4090 24GB | $5-10 inicial | ~500M-1B según horas |

**Suma realista mensual**: 120h-GPU/mes en gama T4/A10G **sin pagar**.

### Target de tamaño realista del proyecto

| Modelo | Params | Hardware mínimo | Tiempo training | Estado |
|---|---|---|---|---|
| **A — nano** | ~46M | RTX 2050 local | ~14h | **YA EXISTE** (PoC metodológica) |
| **B — pequeño** | ~120M | RTX 2050 + Kaggle T4 | ~30h | Próximo paso |
| **C — mediano** | ~350M | Kaggle T4 + Modal credits | ~70h | Modelo principal del proyecto |
| **D — grande** | ~700M-1B | Modal A100 + créditos varios | ~150h | Opcional, post-proyecto |

el proyecto presenta los modelos **A + B + C** como progresión documentada.
La progresión MISMA es contribución científica ("cómo escalar un LLM
educativo from-scratch con recursos limitados"). Si los créditos alcanzan,
**D** entra como extensión.

---

## 4. Arquitectura modernizada (cambios al `ml/model/transformer.py`)

El modelo actual es GPT clásico (PosEnc sinusoidal · MHA · GELU FFN ·
LayerNorm). Para el modelo B/C/D incorporar mejoras de SOTA SIN agregar
parámetros — solo mejor uso de los que ya tenemos:

| Cambio | Beneficio | Esfuerzo |
|---|---|---|
| **RoPE** en lugar de PosEnc sinusoidal | Extiende contexto sin re-entrenar (técnica YaRN), estándar Llama/Qwen | 1-2 días |
| **GQA** (Grouped-Query Attention) en lugar de MHA | KV cache 4-8× menor, contexto largo cabe en VRAM | 2-3 días |
| **SwiGLU** en lugar de GeLU FFN | +2-4% accuracy con mismos params | 0.5 días |
| **RMSNorm** en lugar de LayerNorm | 7% más rápido | 0.3 días |
| **FlashAttention v2** | 3-10× más rápido, contexto largo sin OOM | 1 día |
| **Tokenizer sentencepiece** | Ya existe (`ml/tokenizer/sp_tokenizer.py`) | hecho |

Estas mejoras YA están detalladas en
[MEJORAS_NIVEL_TOP.md §1](./MEJORAS_NIVEL_TOP.md#-área-1--modernizar-la-arquitectura-del-modelo-propio).
Se aplican como parte del modelo B/C — no hace falta replicarlas aquí.

---

## 5. Pipeline de entrenamiento por fase (técnico)

### Fase 1 — Pretraining puro en código

```
Corpus: The Stack v2 filtrado Python + JS + SQL + HTML + CSS + Java
 ~5-10 GB texto
Tokens: ~2B-3B (con sentencepiece 16k vocab)
Modelo: B (120M) o C (350M)
Objetivo: Cross-entropy sobre predicción de siguiente token
Hardware: Kaggle T4 (chunks de 9h, resume entre sesiones)
Tiempo: B → ~25h; C → ~60h
Métrica: PPL en hold-out, debe bajar de ~10 a ~3-4
```

Comando (config YAML):

```yaml
# ml/training/configs/fase1_pretrain_B.yaml
fase: 1
modelo_arquitectura: gpt_v2 # con RoPE + GQA + SwiGLU + RMSNorm
modelo_params:
 n_layers: 12
 n_heads: 12 # 4 KV heads (GQA 3:1)
 d_model: 768
 d_ff: 2048 # SwiGLU intermedio
 vocab_size: 16000
 max_seq_len: 1024
 # ≈ 120M params

corpus:
 archivos:
 - data/the_stack_v2_python.txt
 - data/the_stack_v2_js.txt
 - data/the_stack_v2_sql.txt
 #... etc.

training:
 per_device_batch_size: 4
 grad_accum: 16 # batch efectivo 64
 epochs: 1 # pretraining 1 epoch
 lr: 3e-4
 warmup_ratio: 0.02
 lr_scheduler: cosine
 fp16: true
 gradient_checkpointing: true
 optim: adamw_torch
 save_every: 1000
```

### Fase 2 — Continued pretraining en docs oficiales

Sobre checkpoint Fase 1.

```yaml
fase: 2
modelo_base: checkpoints/fase1_B_final.pt # nuestro propio checkpoint
corpus:
 archivos:
 - data/python_docs.txt
 - data/mdn_es.txt
 - data/peps_index.txt
 #...
training:
 epochs: 1
 lr: 5e-5 # más bajo: refinamiento, no aprendizaje base
 # resto igual
```

### Fase 3 — SFT con CoT pedagógico

Sobre checkpoint Fase 2.

```yaml
fase: 3
modelo_base: checkpoints/fase2_B_final.pt
corpus: data/dataset_v2_pensamiento_estructurado.jsonl
filtro_tipos: ["pensamiento_programador", "decision_diseno", "arquitectura_sistema"]
formato: |
 <|user|>{instruccion}<|end|>
 <|assistant|><think>
 {pensamiento}
 </think>
 {salida}<|end|>
training:
 epochs: 3
 lr: 1e-4
 max_seq_len: 2048 # CoT necesita más contexto
```

### Fase 4 — SFT con dataset destilado

Sobre checkpoint Fase 3.

```yaml
fase: 4
modelo_base: checkpoints/fase3_B_final.pt
corpus: data/dataset_v2.jsonl
filtro_tipos: [
 "explicacion_codigo", "generacion_codigo", "concepto",
 "explicacion_multinivel", "explicacion_linea", "actividad",
 "correccion_error", "comprension"
]
training:
 epochs: 2
 lr: 1e-4
```

### Fase 5 — SFT senior + DPO multi-criterio

Sobre checkpoint Fase 4.

```yaml
# Sub-fase 5a — SFT con foco en revisión
fase: 5a
modelo_base: checkpoints/fase4_B_final.pt
corpus: data/dataset_v2.jsonl
filtro_tipos: ["anti_patron", "bug_sutil", "evolucion_codigo", "seguridad", "testing_complejidad"]
training:
 epochs: 3
 lr: 5e-5

# Sub-fase 5b — DPO multi-criterio
fase: 5b
modelo_base: checkpoints/fase5a_B_final.pt
modelo_ref: checkpoints/fase5a_B_final.pt
corpus_pares: data/dpo_v2_multi.jsonl # con scores por dimensión
pesos_dimension: {SEG: 1.5, ARQ: 1.2, MAN: 1.0, LEG: 1.0, ESC: 0.8, REN: 0.8}
training:
 epochs: 3
 lr: 5e-7
 beta: 0.1
```

Total Fase 5: ~20h Kaggle T4 para modelo B.

---

## 6. Sistema de regeneración por puntuación (Nivel 11 del usuario)

Citando: *"Si la respuesta no llega a cierto nivel: regenerar."*

Implementación en producción (`backend/app/services/`):

```python
def responder_con_threshold(prompt, max_intentos=3, score_minimo=55):
 for intento in range(max_intentos):
 respuesta = modelo_propio.generar(prompt, temperatura=0.6 + 0.1*intento)
 scores = reward_models.evaluar(prompt, respuesta) # 6 dim, 0-10 c/u
 total = sum(scores.values()) # max 60
 if total >= score_minimo:
 return respuesta, scores
 # Si tras 3 intentos no llega, devolver la mejor:
 return mejor_respuesta_vista, mejores_scores
```

Esto cierra el ciclo: el modelo se auto-mejora en inferencia usando su
propia rúbrica.

---

## 7. Auto-crítica (Nivel 12 del usuario)

Citando: *"Genera Solución A → ¿Qué errores tiene? → Mejora la solución → Vuelve a evaluarla."*

Esto se implementa como **un tipo nuevo de dataset** que se agregará a
los 9 actuales:

### Tipo 10 — `pensamiento_autocritico`

```json
{
 "instruccion": "Implementa un parser de CSV robusto",
 "tipo": "pensamiento_autocritico",
 "salida": "{Solucion final mejorada + explicacion}",
 "pensamiento": {
 "iteraciones": [
 {
 "version": "A",
 "codigo": "<codigo inicial>",
 "critica": "<3 problemas que identifico en mi propia version A>",
 },
 {
 "version": "B",
 "codigo": "<version mejorada basada en la critica>",
 "critica": "<2 problemas restantes>",
 },
 {
 "version": "C_final",
 "codigo": "<version final>",
 "critica": "Sin problemas significativos."
 }
 ]
 }
}
```

Generador: `ml/data/generar_autocritica.py` (mismo patrón que los otros 9).
Se agregará en próxima iteración del corpus.

**En inferencia**: el modelo aprende a generar A→B→C internamente, incluso
sin que el usuario lo pida. La forma `<think>...</think>` envuelve este
razonamiento.

---

## 8. Tokenizer propio extendido

El sentencepiece actual (`ml/tokenizer/sp_tokenizer.py`) sirve. Cambios
para V2:

- **Vocab size**: subir de 8000 a 16000 — más cobertura sin disparar
 tamaño de embedding mucho.
- **Tokens especiales pedagógicos** (control codes):

```
<|user|> <|assistant|> <|system|> <|end|>
<think> </think> <code> </code>
<NIVEL=basico> <NIVEL=intermedio> <NIVEL=avanzado>
<SEG=10> <LEG=10> <ESC=10> <ARQ=10> <REN=10> <MAN=10>
```

Estos permiten:
- Distinguir roles en conversación.
- Encapsular chain-of-thought.
- Score-conditional generation (modo "respuesta production-grade"
 vs "respuesta didáctica").

Re-entrenar tokenizer con corpus completo V2 (~2 min con sentencepiece).

---

## 9. Plan de ejecución (3 meses, NADA descargado)

| Mes | Foco | Entregable |
|---|---|---|
| **Mes 1** | Construcción del dataset V2 (~333k ejemplos) | `data/dataset_v2.jsonl` + tokenizer 16k + reward models etiquetando ya activos |
| **Mes 2** | Modelo B (120M) — Fases 1-5 from-scratch | `checkpoints/B_fase5_final.pt` + benchmarks (HumanEval, MBPP+) |
| **Mes 3** | Modelo C (350M) — escalar arquitectura + métricas finales + documentación | `checkpoints/C_fase5_final.pt` + capítulo Metodología + Resultados |

Si los créditos alcanzan en mes 3: intentar **D (700M-1B)** como
extensión opcional.

---

## 10. Tabla de modelos de el proyecto (qué presenta el documentación)

| Modelo | Params | Status | Aporte académico |
|---|---|---|---|
| **A** | 46M | Ya entrenado | Prueba metodológica: pipeline completo desde cero funciona |
| **B** | 120M | A entrenar Mes 2 | Demuestra escalabilidad de la metodología con arquitectura SOTA |
| **C** | 350M | A entrenar Mes 3 | Modelo principal del proyecto — competitivo en HumanEval/MBPP en español |
| **D** | 700M-1B | Opcional | Extensión: límites de la metodología con recursos gratuitos |

Más:
- Dataset V2 (333k ejemplos) — **contribución open**.
- Sistema de 6 reward models multi-criterio — **contribución metodológica**.
- Pipeline de actualización continua — **contribución de sostenibilidad**.

---

## 11. Métricas objetivo por modelo

| Métrica | A (actual) | B (objetivo) | C (objetivo) |
|---|---|---|---|
| Loss val final | <4.5 | <3.0 | <2.5 |
| HumanEval pass@1 | ~5% | ~15-20% | ~30-35% |
| MBPP+ pass@1 | ~8% | ~20% | ~35% |
| Win rate vs A (Gemini juzga) | — | >70% | >85% |
| Win rate vs B | — | — | >65% |
| Score subjetivo es-PY (1-10) | ~5 | ~7 | ~8 |
| % respuestas con CoT visible | 0% | >50% | >70% |
| Tamaño on-disk (FP16) | ~90 MB | ~240 MB | ~700 MB |
| Tamaño on-disk (INT4) | ~25 MB | ~70 MB | ~200 MB |

del proyecto, lo importante es la **progresión**, no el valor absoluto.

---

## 12. Costos REALES (sin descargar nada, sin entrenar sobre nada externo)

| Item | Costo |
|---|---|
| Tiers gratuitos cloud (Kaggle + Colab + Lightning + Modal credits) | $0 |
| Tiers gratis de APIs (Gemini + DeepSeek + Groq + Together + Mistral) | $0 |
| Electricidad RTX 2050 (250W × ~50h experimentos locales) | <$2 USD |
| Storage (HuggingFace privado para checkpoints + datasets) | $0 |
| GitHub privado | $0 |
| **TOTAL toda el proyecto** | **<$10 USD** |

un proyecto de LLM **desde cero** por menos de $10. Eso, por sí solo, es
publicable como caso de estudio.

---

## 13. Riesgos y mitigaciones

| Riesgo | Probabilidad | Impacto | Mitigación |
|---|---|---|---|
| 120M from-scratch no llega a calidad útil | Media | Alto | Inversión 80% en dataset (la calidad de datos compensa params chicos) |
| Kaggle no da GPU disponible | Baja | Medio | Fallback Colab + Modal credits |
| Free tier de APIs se agota mid-week | Media | Bajo | 5 proveedores en rotación (pool ya implementado) |
| El modelo no aprende es-PY (corpus Stack v2 es mayoría inglés) | Media | Alto | Filtrar es en docs oficiales + comentarios; mezcla 70/30 código/explicación-es |
| 350M no cabe en T4 con seq len objetivo | Media | Medio | Gradient checkpointing agresivo + seq len 768 en pretraining → 2048 solo en SFT |
| Catastrophic forgetting entre fases | Media | Medio | Replay buffer 10% de fases anteriores |
| Quiero probar 1B y créditos no alcanzan | Alta | Bajo | D es opcional; B+C son el proyecto |

---

## 14. Comparación honesta vs alternativas

| Estrategia | Pro | Contra |
|---|---|---|
| **Esta (from-scratch puro)** | Modelo realmente propio, contribución metodológica clara, costo $0 | Resultados absolutos menores que modelos comerciales |
| Continued pretraining sobre Qwen | Resultados absolutos mejores en HumanEval | Discutible si es "modelo propio"; baja contribución metodológica |
| Solo SFT sobre Qwen-Coder | Más rápido | Es básicamente lo que hace cualquier startup; sin aporte académico |

Esta estrategia es **académicamente más fuerte** aunque los números
absolutos sean menores. un proyecto no se evalúa por benchmarks crudos,
sino por contribución original y rigor metodológico.

---

## 15. Lo que NO hacemos (importante para el norte)

- ❌ NO descargamos Qwen, Llama, SmolLM, Mistral, Phi, ni cualquier
 modelo base externo para usarlo como inicialización.
- ❌ NO hacemos LoRA/QLoRA sobre modelos abiertos.
- ❌ NO usamos APIs externas para responder al usuario final en producción.
- ✅ SÍ usamos APIs externas como **profesores** para generar dataset
 (lo único que cabe acá).
- ✅ SÍ usamos modelos abiertos como **jueces** para etiquetar nuestro
 dataset durante entrenamiento (Fase A del sistema RM en
 [REWARD_MODELS.md](./REWARD_MODELS.md)).
- ✅ SÍ usamos checkpoints de modelos abiertos COMO EVALUADORES (Gemini
 como juez en evaluación final), nunca como inferencia productiva.

---

## 16. Estructura de archivos a crear/modificar

```
ml/model/
├── transformer.py ← existente: arquitectura clásica
├── transformer_v2.py ← NUEVO: con RoPE + GQA + SwiGLU + RMSNorm + FlashAttn
└──...

ml/training/
├── trainer.py ← existente (refactor mínimo para soportar fases)
├── run_fase.py ← NUEVO: ejecuta una fase desde YAML
└── configs/
 ├── fase1_pretrain_A.yaml ← (el modelo de 46M ya entrenado, doc retrospectivo)
 ├── fase1_pretrain_B.yaml
 ├── fase2_docs_B.yaml
 ├── fase3_cot_B.yaml
 ├── fase4_distilled_B.yaml
 ├── fase5a_senior_B.yaml
 ├── fase5b_dpo_B.yaml
 ├── fase1_pretrain_C.yaml
 └──...

ml/training/kaggle/
├── notebook_fase1.ipynb ← template Kaggle con chunking 9h
├── notebook_fase3.ipynb
└──...

ml/rlhf/
├── reward_model.py ← NUEVO: arquitectura RM compartiendo encoder
├── entrenar_rm.py ← NUEVO: entrena los 6 RM
└── dpo_multi.py ← NUEVO: DPO multi-objetivo

checkpoints/
├── A_46M_final.pt ← YA EXISTE
├── B_120M_fase1.pt
├── B_120M_fase2.pt
├──...
└── C_350M_fase5_final.pt ← entregable del proyecto
```

---

## 17. del proyecto (resumen ejecutivo)

> **Construir, desde cero, un LLM educativo especializado en programación
> en español, sin depender de modelos preentrenados externos.**
>
> Contribuciones originales:
> 1. **Arquitectura propia** (decoder-only modernizado: RoPE + GQA +
> SwiGLU + RMSNorm + FlashAttention).
> 2. **Pipeline de currículum** en 5 fases (lenguajes → docs →
> pensamiento estructurado → destilación → revisión senior).
> 3. **Dataset V2** (~333k ejemplos en 10 tipos pedagógicos incluyendo
> chain-of-thought, antipatrones explicados, bugs sutiles, evolución
> de código v1-v5).
> 4. **Sistema multi-criterio de 6 reward models** (SEG/LEG/ESC/ARQ/REN/MAN)
> para RLAIF y self-correction en inferencia.
> 5. **Progresión de modelos A→B→C** (46M → 120M → 350M) documentada como
> metodología reproducible.
> 6. **Costo total < $10** — viable para investigación académica con
> recursos limitados.
>
> Eso es publicable en un workshop de NLP educativo o de sistemas de
> tutoría inteligente.

---

## 18. Referencias clave

- **Documento de visión de el proyecto** (los 12 niveles de dataset + las 5
 fases de entrenamiento + el sistema de puntuación, citado a lo largo
 de este documento).
- Su et al., **RoPE: Rotary Position Embedding**, 2021
- Ainslie et al., **GQA**, 2023
- Shazeer, **GLU Variants Improve Transformer**, 2020 (SwiGLU)
- Zhang & Sennrich, **Root Mean Square Layer Normalization**, 2019
- Dao, **FlashAttention-2**, 2023
- Rafailov et al., **Direct Preference Optimization**, NeurIPS 2023
- Lee et al., **RLAIF**, 2023
- Wei et al., **Chain-of-Thought Prompting**, NeurIPS 2022
