# Bitácora de Desarrollo

> Registro cronológico de las decisiones, implementaciones y eventos
> relevantes durante el desarrollo del proyecto. Sirve como historia
> técnica del proyecto y base para el sección de Metodología de la
> proyecto.

---

## Sesión de junio 2026 — Construcción del pipeline V2 completo

### Contexto inicial

Al inicio de esta sesión el proyecto ya disponía de:

- Backend FastAPI con autenticación, RBAC, audit log y base de datos
 Postgres operativa.
- Frontend web (Next.js + Tailwind) y aplicación de escritorio Flutter
 con paridad funcional.
- Modelo de lenguaje propio entrenado en la fase 1: Transformer
 decoder-only de aproximadamente 46 millones de parámetros, con
 arquitectura clásica (PositionalEncoding sinusoidal, Multi-Head
 Attention estándar, FeedForward con GeLU y LayerNorm), entrenado con
 un corpus de 187 000 ejemplos en español y código.
- Pipeline de entrenamiento basado en sentencepiece y un `Trainer`
 artesanal.
- Sistema RAG funcional con embeddings.
- ViT propio para procesamiento de imágenes, integrado con el LLM
 mediante un projector.
- Sistema MCP propio en el backend.
- Documentación inicial en `docs/`: hoja de ruta, plan de RLHF,
 análisis de mejoras nivel top, plan de visión, etc.

El objetivo de la sesión fue convertir esta base en un sistema completo
para construir un modelo de lenguaje educativo de 120 a 350 millones de
parámetros, mediante un currículum de cinco fases, manteniendo el
entrenamiento desde cero sin descargar modelos base externos, y
respetando la restricción de menos de 10 dólares estadounidenses en
presupuesto.

---

### Hito 1: Diseño del Dataset V2

**Decisión:** ampliar el schema de ejemplos pedagógicos del corpus para
capturar no solamente la dupla pregunta-respuesta, sino también el
proceso mental de un programador senior antes de escribir código.

**Inspiración:** análisis previo del problema identificó 12 niveles
cognitivos que un LLM educativo debería abordar (chain-of-thought,
decisiones, errores reales, refactorización, arquitectura, seguridad,
pedagógico multinivel, code review, testing, rendimiento, sistema de
puntuación y auto-crítica iterativa).

**Implementación:**

1. Extensión del `schema.py` con siete campos opcionales nuevos sin
 romper la compatibilidad con el formato anterior:
 - `pensamiento`: chain-of-thought con aclaraciones, restricciones
 implícitas, alternativas consideradas y criterios de decisión.
 - `explicacion_por_nivel`: explicación del mismo concepto en cuatro
 niveles (niño, principiante, intermedio, profesional).
 - `alternativas`: opciones evaluadas durante el diseño.
 - `errores_comunes`: errores típicos que un estudiante cometería.
 - `revision_codigo`: estructura para anti-patrones, con `problemas`,
 `por_que_funciona_pero_es_malo` y `problema_en_produccion`.
 - `puntuacion`: scores 0–10 por dimensión de calidad.
 - `version_evolutiva`: una de `v1_junior`, `v2_junior_plus`, `v3_mid`,
 `v4_senior`, `v5_staff` para el tipo `evolucion_codigo`.
2. Añadimos nueve tipos pedagógicos nuevos a los siete originales,
 alcanzando 17 tipos totales.
3. El método `to_dict` omite los campos opcionales no poblados, para
 mantener archivos JSONL pequeños y compatibles con consumidores V1.

**Verificación:** test end-to-end con cinco escenarios (ejemplo V1
válido, V2 con chain-of-thought válido, V2 mal formado con dos
alternativas elegidas, código Python con SyntaxError, roundtrip
`to_dict`/`from_dict`). Los cinco escenarios fueron rechazados o
aceptados según lo esperado.

---

### Hito 2: Validadores de calidad

**Decisión:** sin validación rigurosa, los proveedores LLM gratuitos
inundarían el corpus con respuestas malformadas, código que no compila,
chain-of-thought incompleto o placeholders sin desarrollar.

**Implementación:** `validadores.py` con funciones especializadas por
campo y tipo, agregadas en un `validar_ejemplo` que aplica las reglas
correctas según el tipo del ejemplo:

- `validar_codigo_python`: compila el código con `ast.parse` (no
 ejecuta). Tolerante a fences de Markdown.
- `validar_pensamiento`: exige al menos dos alternativas, exactamente
 una elegida, al menos dos criterios de decisión.
- `validar_multinivel`: exige las cuatro explicaciones con longitudes
 mínimas (30 caracteres para `nino`, 80 para el resto) y detecta
 copia textual entre niveles.
- `validar_revision_codigo`: exige problemas identificados,
 `por_que_funciona_pero_es_malo` y `problema_en_produccion`.
- `validar_autocritica`: exige iteraciones con `version`, `codigo` que
 compile, `critica` con longitud mínima en cada iteración (excepto la
 última), versiones distintas en orden creciente.
- `validar_puntuacion`: las seis dimensiones presentes en rango [0, 10].
- `validar_salida_pedagogica`: detecta salidas demasiado cortas,
 abundancia de placeholders (`...`, `lorem ipsum`, `TODO`), y
 respuestas que son solo código sin explicación textual.

---

### Hito 3: Pool de generadores con tiers gratuitos

**Decisión:** maximizar el rendimiento dentro de los tiers gratuitos
mediante rotación inteligente entre múltiples proveedores.

**Proveedores integrados:**

| Proveedor | Modelo por defecto | RPM | RPD | Es 100 % gratis sin tarjeta |
|---|---|---|---|---|
| Gemini | `gemini-2.0-flash` | 15 | 1 500 | Sí |
| Groq | `llama-3.3-70b-versatile` | 30 | 14 400 | Sí |
| DeepSeek | `deepseek-chat` | 60 | 5 000 | Requiere registro (crédito gratis al iniciar) |
| Together AI | `meta-llama/Llama-3.3-70B-Instruct-Turbo` | 60 | 1 000 | Requiere tarjeta (crédito gratis al iniciar) |
| Mistral | `mistral-large-latest` | 30 | 1 000 | Requiere registro |
| OpenRouter | `meta-llama/llama-3.1-8b-instruct:free` | 20 | 200 | Sí |

**Implementación:** `pool_generadores.py` con cuatro componentes:

1. **Token-bucket rate limiter** (`RateLimit`): registra timestamps de
 las llamadas para respetar los límites RPM y RPD locales.
2. **Configuración por proveedor**: cada uno con su endpoint y formato
 (Gemini usa formato distinto, los demás son OpenAI-compatible).
3. **Pool con rotación por tarea**: prioridades distintas según tarea
 (`Tarea.COT` prioriza Gemini, `Tarea.CODIGO` prioriza DeepSeek,
 `Tarea.VOLUMEN` prioriza Groq por su alto RPD, etc.).
4. **Fallback con espera**: cuando todos los proveedores reportan 429,
 `esperar_si_rate_limited=True` activa una espera fija de 60
 segundos antes de reintentar (esto reemplazó una implementación
 inicial que acumulaba timestamps locales y producía esperas
 crecientes; ver [BUGS_Y_SOLUCIONES.md](./BUGS_Y_SOLUCIONES.md)).

**Extracción robusta de JSON**: dos funciones auxiliares
`extraer_json_objeto` y `extraer_json_array` que toleran respuestas
envueltas en bloques Markdown (`` ```json... ``` ``), strings con
saltos de línea literales (vía `strict=False`), y JSON parcialmente
truncado (mediante un balanceador de llaves que recupera objetos
individuales).

---

### Hito 4: Los 10 generadores de dataset

**Decisión arquitectónica:** cada tipo del dataset es un módulo
independiente, no una función dentro de un solo archivo. Esto facilita
mantener prompts específicos por tipo, evolucionar uno sin afectar los
demás, y orquestarlos en cualquier orden.

**Estructura común** (templado a partir de `generar_pensamiento.py`):

```python
OBJETIVOS = ((tema, nivel),...) # 15–30 objetivos por generador
PROMPT_TEMPLATE = "..." # Plantilla con reglas estrictas de JSON
async def generar_objetivo(pool, tema, nivel, n, *, temperatura) -> list[Ejemplo]
async def generar_corpus(pool, salida, *, n_por_objetivo, temperatura) -> dict
def main() # CLI con argparse
```

**Generadores creados:**

| Tipo | Objetivos | Ejemplos por corrida | Tipo de salida |
|---|---|---|---|
| `pensamiento_programador` | 20 | 2 c/u | Chain-of-thought completo |
| `explicacion_multinivel` | 20 | 1 c/u × 4 niveles | Cuatro explicaciones distintas |
| `anti_patron` | 30 | 2 c/u | Código malo + refactorización |
| `bug_sutil` | 25 | 2 c/u | Bugs lógicos no obvios |
| `evolucion_codigo` | 15 | 5 versiones c/u | Cinco niveles de calidad |
| `decision_diseno` | 30 | 1 c/u | Comparativas tecnológicas |
| `arquitectura_sistema` | 25 | 1 c/u | Diseño end-to-end |
| `seguridad` | 25 | 2 c/u | OWASP + criptografía |
| `testing_complejidad` | 25 | 1 c/u | Tests + Big-O |
| `pensamiento_autocritico` | 20 | 1 c/u | Iteraciones A → B → C |

**Orquestador:** `construir_dataset_v2.py` ejecuta los 10 generadores
en serie, consolida en un único `dataset_v2.jsonl`, aplica auditoría
automática, soporta tres escalas (`mini`, `media`, `completa`),
reanudación entre fallos (`--skip`, archivo individual ya existente),
borrado limpio (`--reset`).

---

### Hito 5: Sistema multi-criterio de jueces

**Decisión:** en lugar de un único juez global (como hace el RLAIF
clásico), evaluar cada respuesta en seis dimensiones independientes
con tres jueces por dimensión, agregando con mediana.

**Dimensiones:**

1. SEG — Seguridad
2. LEG — Legibilidad
3. ESC — Escalabilidad
4. ARQ — Arquitectura
5. REN — Rendimiento
6. MAN — Mantenibilidad

**Implementación:** `jueces.py` con rúbricas escritas para cada
dimensión (definición + escala 0–10 con descriptores por rango), prompt
estructurado que pide una sola dimensión a la vez al juez LLM,
asignación de proveedores por dimensión (Gemini para SEG y LEG,
DeepSeek para ESC y REN, etc.), agregación por mediana entre los tres
jueces.

**Etiquetador:** `etiquetar_dataset.py` recorre un JSONL de respuestas
y produce un JSONL con scores agregados. Características clave:
reanudación automática mediante hash sha1 de prompt+respuesta,
concurrencia limitada con `asyncio.Semaphore`, progreso con velocidad y
ETA en tiempo real, manejo de excepciones por respuesta sin abortar el
batch.

---

### Hito 6: 6 Reward Models con encoder compartido

**Decisión arquitectónica:** seis reward models que comparten el mismo
encoder Transformer pero tienen cabezas de regresión independientes.

**Razones:**

- VRAM: un encoder más seis cabezas pequeñas usa drásticamente menos
 memoria que seis modelos completos.
- Generalización: el encoder ve todas las dimensiones simultáneamente,
 evitando overfit por dimensión.
- Inferencia rápida: un solo forward produce los seis scores.

**Implementación:** `reward_model.py` con:

- `RewardConfig`: hiperparámetros (vocab, contexto, capas, heads, etc.).
- `RewardEncoder`: usa `BloqueV2` del transformer principal (RoPE,
 GQA, SwiGLU, RMSNorm) sin LM head.
- Tres estrategias de pooling: `mean`, `last`, `attention` (con query
 aprendida).
- `RewardHead`: MLP opcional o lineal directa, salida con sigmoid * 10.
- `MultiCriteriaRewardModel`: orquesta encoder + pooling + 6 heads.
- Pérdidas: `loss_mse_multi` (regresión sobre scores absolutos),
 `loss_ranking_multi` (preferencia pairwise).
- Tres presets: pequeño (8 millones), mediano (16 millones), grande
 (32 millones).

**Trainer dedicado:** `entrenar_rm.py` con `RMScoresDataset` que lee el
JSONL etiquetado, soporte para modo MSE y modo ranking, evaluación con
Pearson correlation por dimensión, resume support, AMP, gradient
accumulation, cosine LR con warmup.

---

### Hito 7: DPO multi-objetivo

**Decisión:** extender Direct Preference Optimization (Rafailov et al.,
2023) con pesos por dimensión. La pérdida final es una suma ponderada
de las pérdidas DPO por dimensión, lo que permite priorizar criterios
(por ejemplo, SEG > REN para un asistente educativo).

**Implementación:** `dpo_multi.py` con:

- `DPODataset`: soporta dos modos de carga, un archivo por dimensión
 (`por_dimension`) o un archivo único con campo `dim` por línea
 (`unico`). En modo `por_dimension` hace round-robin con shuffle entre
 archivos.
- Formato chat con tokens especiales (`<|user|>`, `<|assistant|>`,
 `<|end|>`) y máscara de prompt (labels = −100) para que la pérdida
 solo cuente sobre los tokens de la respuesta.
- `loss_dpo_multi`: computa el margen DPO por item, lo pondera por la
 dimensión asignada en el item, y devuelve métricas detalladas por
 dimensión (loss y accuracy).
- `DPOTrainer`: carga el modelo entrenable (de Fase 5a) y un modelo
 referencia congelado del mismo checkpoint, β configurable, gradient
 checkpointing obligatorio dado que cada step computa dos forwards
 del entrenable más uno del referencia.

---

### Hito 8: Arquitectura V2 del modelo principal

**Decisión:** mantener la arquitectura V2 existente (`transformer_v2.py`
ya tenía RoPE, GQA, SwiGLU, RMSNorm y FlashAttention v2 vía
`F.scaled_dot_product_attention`), y agregarle gradient checkpointing
para que el modelo B (150M parámetros) quepa en RTX 2050.

**Cambio:** método `gradient_checkpointing_enable` que activa
`torch.utils.checkpoint.checkpoint` con `use_reentrant=False` en el
forward del bucle de bloques. Reduce VRAM 2–3x a costa de 30 %
adicional de tiempo de training.

**Presets V2 definitivos:**

| Preset | Parámetros reales | Para |
|---|---|---|
| `sota_experto` | 30.7 M | Debug rápido |
| `sota_grande` | 87.8 M | Preset intermedio |
| `sota_b` | 150.7 M | Modelo B del plan |
| `sota_c` | 350.9 M | Modelo C del plan |
| `sota_d` | 869.9 M | Modelo D opcional |

---

### Hito 9: Runner por YAML para las cinco fases

**Decisión:** un único runner declarativo (`run_fase.py`) que lee un
YAML por fase. Esto desacopla la configuración del código y permite
versionar las configuraciones de los experimentos en el repositorio.

**Implementación:**

- `TrainerV2` orquesta todo el loop (autocast FP16/BF16 según GPU,
 gradient accumulation, gradient clipping, cosine LR con warmup,
 resume entre sesiones).
- Soporta dos modos de dataset: `pretrain` (lee archivos `.txt`,
 tokeniza al vuelo, chunks no-solapados de `block_size + 1`) y `sft`
 (lee JSONL del schema V2, aplica template `<|user|>... <|end|>
 <|assistant|>... <|end|>` con máscara de prompt).
- Chunking para Kaggle: parámetro `--tiempo-max-minutos 525` (8 h 45 min)
 para detener antes del límite de 9 horas y guardar estado.
- Captura `SIGINT` y `SIGTERM` para guardar antes de morir.
- Persiste `config_resuelta.json` en el directorio de salida para
 reproducibilidad.

**Seis configuraciones YAML creadas**, una por fase:

| YAML | Fase | Modo | Filtro de tipos |
|---|---|---|---|
| `fase1_pretrain_B.yaml` | 1 | pretrain | (txt files) |
| `fase2_docs_B.yaml` | 2 | pretrain | (txt files) |
| `fase3_cot_B.yaml` | 3 | sft | `pensamiento_programador`, `decision_diseno`, `arquitectura_sistema`, `pensamiento_autocritico` |
| `fase4_distillation_B.yaml` | 4 | sft | tipos clásicos V1 + `explicacion_multinivel` |
| `fase5a_senior_B.yaml` | 5a | sft | `anti_patron`, `bug_sutil`, `evolucion_codigo`, `seguridad`, `testing_complejidad` |
| `fase5b_dpo_B.yaml` | 5b | dpo | (pares por dimensión) |

---

### Hito 10: Tests reales con APIs

Durante el desarrollo se hicieron varios smoke tests con APIs reales.
Los principales hallazgos están documentados en
[BUGS_Y_SOLUCIONES.md](./BUGS_Y_SOLUCIONES.md):

- Smoke test con generador `pensamiento` solo: 28 ejemplos generados en
 4.7 minutos, 100 % válidos, 100 % de bloques de código que compilan.
- Mini full (los 10 generadores): tras varios ciclos de debug, el
 pipeline funciona end-to-end. La velocidad real depende del tier
 gratuito disponible.

Resultados detallados en [EXPERIMENTOS.md](./EXPERIMENTOS.md).

---

### Decisiones que se descartaron durante la sesión

| Decisión inicial | Razón del descarte | Reemplazo |
|---|---|---|
| Continued pretraining sobre `Qwen2.5-Coder-1.5B` | Contradice la visión del proyecto (modelo propio desde cero, no fine-tune de modelo externo). | Entrenamiento desde cero del modelo B (150M) con currículum de cinco fases. |
| Un único juez LLM global para RLAIF | Limita el control fino sobre el estilo del modelo. | Sistema multi-criterio de 6 dimensiones con ensemble de 3 jueces. |
| Acumular timestamps locales para forzar espera tras 429 del server | La espera crecía exponencialmente con cada 429, atascando el pipeline. | Espera fija de 60 segundos tras cada 429 con reintento. |
| Modelo Groq 70B para volumen | TPM de 6 000 lo hace muy lento. | Modelo Groq 8B (TPM 20 000) para masivo, modelo 70B solo para tareas críticas. |

---

### Estado al final de la sesión

- 17 archivos nuevos en `ml/data/`.
- 6 archivos nuevos en `ml/rlhf/`.
- 2 archivos nuevos en `ml/training/` (más 6 YAMLs).
- 1 archivo modificado en `ml/model/`.
- 1 archivo modificado en `ml/`.
- 7 documentos nuevos en `docs/`.
- 1 script auxiliar en `scripts/`.

Total aproximado: 5 000 líneas de código nuevo + 4 000 líneas de
documentación.

---

## Sesión 2026-06-22 — Primer entrenamiento real en Lightning AI

### Contexto

Tras finalizar la implementación del pipeline V2 (sesiones anteriores),
se ejecutó el primer entrenamiento end-to-end con GPU real en Lightning
AI Studio (T4 16 GB). Esta sesión es el **paso del código al modelo
real**.

### Hito 11: Smoke test del pipeline (modelo 30M)

Lanzamiento de `smoke_sft.yaml` con el modelo `sota_experto` (30M
params) sobre el corpus consolidado de 364K ejemplos. Mil pasos.

**Resultado**: bajada de loss **9.21 → 3.94** en 47 minutos.

Esto valida que el pipeline completo (corpus → tokenizer → modelo →
forward → backward → optimizer → checkpointing) funciona como se diseñó.

Bugs descubiertos y corregidos durante este hito:

- **BUG-12**: el config apuntaba al wrapper `.json` del tokenizer en
  lugar del archivo nativo `.model`. Fix de una línea, commit `161d339`.
- **BUG-13**: el corpus `/tmp/corpus_tokenizer.jsonl` se perdió tras
  reanudar el Studio (Lightning no preserva `/tmp`). Workaround:
  reconstruir con `cat datasets/publicos/*.jsonl ...`.

### Hito 12: Modelo B v1 (150M) en marcha

Lanzamiento del primer entrenamiento serio del modelo B con
`b_sft_5k.yaml` (commit `c4872c3`):

- 150.7M parámetros, arquitectura V2 (RoPE+GQA+SwiGLU+RMSNorm).
- 5,000 pasos sobre el mismo corpus de 364K ejemplos.
- Batch efectivo 16 (batch=2 × grad_accum=8).
- Gradient checkpointing ON (obligatorio en T4 para 150M).
- bfloat16 mixed precision.

ETA total: **~15 horas**. Throughput: **0.09 pasos/segundo** (12× más
lento que el smoke por tamaño + GC).

Lanzado con `nohup` para sobrevivir cierres de navegador (DD-23):

```bash
nohup python -m ml.training.run_fase \
  --config ml/training/configs/b_sft_5k.yaml \
  > entrenamiento_B.log 2>&1 &
```

Loss bajando linealmente durante el warmup:
- Paso 25: 8.65
- Paso 150: 5.73
- Proyección final: 2.8 - 3.2

### Hito 13: Ampliación del corpus de 364K → 882K ejemplos

En paralelo al entrenamiento, se descargaron 6 datasets adicionales con
`--max-items 200000`:

| Dataset | Estado | Aporte |
|---|---|---|
| codeparrot-py | ✅ 683 MB | Python real de GitHub |
| openhermes | ✅ 331 MB | Conversaciones de calidad |
| alpaca-es | ✅ 30 MB | Español (diferenciador clave) |
| open-code-interp | ✅ 164 MB | Código con feedback de ejecución |
| cot | ❌ HF deprecado | (skip) |
| python-edu | ❌ HF deprecado | (skip) |

**BUG-14**: HF deprecó dataset scripts → `cot` y `python-edu` fallan.
Hay que migrar a alternativas modernas (Open-Orca, cosmopedia) — tarea
pendiente.

Corpus consolidado nuevo: `/tmp/corpus_v2_ampliado.jsonl` (882,856
ejemplos, 2.0 GB). Listo para el modelo B v2.

### Hito 14: Generación del dataset V2 escala media en paralelo

Tercera terminal lanzada en paralelo:

```bash
nohup python -m ml.data.construir_dataset_v2 \
  --salida-dir datasets/raw \
  --escala media \
  --reset > dataset_v2_media.log 2>&1 &
```

Target: 5000-8000 ejemplos pedagógicos para Fase 4 (DPO) y Fase 5
(EduCodeEval). ETA: 3-5 horas.

Esto valida la decisión DD-26 (pipeline de tres terminales paralelas).

### Estado al final de la sesión

**Procesos corriendo simultáneamente en Lightning**:

1. Terminal 1: modelo B v1 (150M) entrenando, PID 7961, ETA 15h.
2. Terminal 2: descarga de datasets completada (882K ejemplos en disco).
3. Terminal 3: generación de dataset V2 escala media, ETA 3-5h.

**Archivos creados**:

- `ml/training/configs/b_sft_5k.yaml` (commit `c4872c3`).
- `training/checkpoints/smoke_test_30M/` (369 MB checkpoint + métricas).
- `training/checkpoints/B_sft_5k/` (creciendo: checkpoints cada 500
  pasos).
- `/tmp/corpus_v2_ampliado.jsonl` (2.0 GB, 882,856 líneas).
- `datasets/publicos/{codeparrot-py,openhermes,alpaca-es,open-code-interp}.jsonl`
  (+1.2 GB de datos nuevos).

**Bugs documentados**: BUG-12, BUG-13, BUG-14, BUG-15.

**Decisiones registradas**: DD-21 a DD-26.

**Próxima sesión**: verificar resultado del modelo B v1 al terminar
(loss final + inferencia), decidir si lanzar modelo B v2 con el corpus
ampliado.
