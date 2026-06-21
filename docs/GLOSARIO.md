# Glosario Técnico

> Definiciones de los términos técnicos usados a lo largo del proyecto.
> Cada término incluye la definición, su rol en el sistema, y cuando
> aplica, una referencia al archivo donde se implementa o a la decisión
> de diseño que lo justifica.
>
> El glosario está organizado por temas. del proyecto, se recomienda
> incluir una versión condensada como apéndice.

---

## A — Arquitectura de modelos

### Attention (atención)

Mecanismo que permite a un modelo Transformer ponderar la importancia
de cada token de la secuencia respecto a los demás. La fórmula clásica
es `softmax(Q · K^T / √d_k) · V`, donde `Q`, `K` y `V` son
proyecciones lineales del input (query, key, value). En este proyecto
se usa atención **causal** (con máscara triangular inferior) para
predicción autoregresiva.

### Autoregressive (autoregresivo)

Modo de generación donde el modelo predice un token a la vez,
usando los tokens previos como contexto. Cada predicción se concatena
al contexto y se itera hasta alcanzar un token de fin o un límite de
longitud. Ver `GPTEducativoV2.generar` en
`ml/model/transformer_v2.py`.

### Block size (bloque, contexto)

Longitud máxima de la secuencia que el modelo puede procesar en una
pasada. En el proyecto: 256 en V1, 1024–2048 en V2.

### Decoder-only

Variante del Transformer que usa solo bloques de atención causal
(sin encoder ni cross-attention). Es la arquitectura de GPT, Llama,
Qwen y de nuestro modelo. Apropiada para generación de texto.

### Embedding

Matriz de proyección que mapea cada ID de token (entero) a un vector
denso de dimensión `n_embd`. Ver `tok_emb` en `GPTEducativoV2`.

### FlashAttention v2

Implementación optimizada de atención en CUDA que NO materializa la
matriz `N × N` de atención en memoria. Reduce uso de VRAM y acelera
3–10×. En este proyecto se usa vía `F.scaled_dot_product_attention`
con `is_causal=True`. PyTorch selecciona automáticamente el kernel
óptimo. Ver [DD-15](./DECISIONES_DISENO.md).

### GQA (Grouped-Query Attention)

Variante de Multi-Head Attention donde varios heads de query
comparten las mismas matrices K y V. Reduce el KV-cache durante
inferencia. En este proyecto: `n_head = 12`, `n_kv_head = 4`, factor
de compresión 3×. Ver `GroupedQueryAttention` en
`transformer_v2.py`.

### Head dim (dimensión por cabeza)

Dimensión de cada cabeza de atención: `n_embd / n_head`. Por ejemplo,
`n_embd = 768`, `n_head = 12` → `head_dim = 64`.

### KV-cache

Memoria que guarda los keys y values calculados en pasos previos para
acelerar la generación autoregresiva. Con GQA, este cache es
`n_head / n_kv_head` veces más pequeño.

### LM head

Capa lineal final que mapea el estado oculto a logits sobre el
vocabulario. En este proyecto comparte pesos con el embedding (weight
tying) para reducir parámetros.

### Multi-Head Attention (MHA)

Atención clásica donde cada cabeza tiene sus propias matrices Q, K,
V. Reemplazada por GQA en V2 para reducir memoria de KV-cache. Era la
configuración del modelo V1.

### Pre-norm vs post-norm

Pre-norm aplica `RMSNorm` antes del bloque de atención y FFN
(`x = x + Attn(Norm(x))`). Es más estable durante el entrenamiento que
post-norm (`x = Norm(x + Attn(x))`). Llama, Mistral y nuestro V2 usan
pre-norm.

### RMSNorm (Root Mean Square LayerNorm)

Normalización por raíz cuadrada media: `y = x / √mean(x²) · g`. Más
simple y rápida que LayerNorm (no resta media, no añade bias).
Estándar en Llama, Mistral, Qwen. Ver `RMSNorm` en
`transformer_v2.py`.

### RoPE (Rotary Position Embeddings)

Codificación posicional que rota los vectores Q y K por un ángulo
dependiente de la posición. Permite extrapolar el contexto sin
reentrenar (por ejemplo, con YaRN). No requiere parámetros
entrenables. Ver `precomputar_rope` y `aplicar_rope` en
`transformer_v2.py`.

### SwiGLU

Variante de FeedForward Network: `hidden = silu(W_gate(x)) · W_up(x)`,
seguido de `W_down(hidden)`. Tres lineales en lugar de las dos
clásicas, con gating sigmoide. Mejora la calidad ~2-4 % sin
incrementar parámetros respecto a GeLU clásico. Ver `SwiGLU` en
`transformer_v2.py`.

### Token

Unidad atómica de texto que el modelo procesa. En este proyecto se
usan tokens BPE (Byte-Pair Encoding) producidos por sentencepiece.
Vocabulario: 8 000 en V1, 16 000 en V2.

### Vocab size (tamaño del vocabulario)

Número total de tokens distintos que el tokenizer puede producir.

### Weight tying

Compartir los pesos entre el embedding de tokens y el LM head.
Reduce parámetros aproximadamente en `vocab_size · n_embd`. En el
proyecto: activado por defecto en V1 y V2.

---

## B — Entrenamiento

### AMP (Automatic Mixed Precision)

Técnica que mezcla operaciones en FP32 y FP16 (o BF16) para acelerar
el entrenamiento sin perder estabilidad. En el proyecto se usa
`torch.autocast(dtype=...)` con `GradScaler` cuando es FP16.

### Batch size

Número de ejemplos procesados simultáneamente en un forward/backward.
En el proyecto: `per_device_batch_size = 1–4`, `grad_accum_steps = 8–32`
para conseguir batch efectivo de 16–32 con poca memoria.

### BF16 (bfloat16)

Formato de punto flotante con 8 bits de exponente (igual que FP32)
pero solo 7 bits de mantisa. Tiene el mismo rango dinámico que FP32
pero menos precisión. NO requiere loss scaling. Soportado en T4 a
medias, óptimo en A10G+.

### Catastrophic forgetting

Fenómeno donde un modelo olvida lo aprendido en una fase anterior al
entrenarse en una nueva. Se mitiga con replay buffer (mezclar 10 % de
los datos antiguos durante la nueva fase).

### Checkpoint

Estado serializado del entrenamiento: pesos del modelo, estado del
optimizador, estado del scaler, RNG, paso actual, mejor val_loss. En
el proyecto se guarda en `training/checkpoints/<nombre>/checkpoint_*.pt`.

### Cosine LR schedule

Programa de learning rate que sigue una curva coseno desde el valor
inicial hasta el mínimo. Combinado con warmup lineal al inicio. Ver
`_lr` en `TrainerV2`.

### CPT (Continued Pretraining)

Continuar el entrenamiento de un modelo preentrenado con corpus de
texto plano adicional. En este proyecto: se aplica entre fases
(modelo de Fase 1 → continuación con docs en Fase 2), siempre con
nuestros propios checkpoints. NO se hace continued pretraining sobre
un modelo base externo (ver [DD-01](./DECISIONES_DISENO.md)).

### DPO (Direct Preference Optimization)

Algoritmo de RLHF que evita PPO. La pérdida se computa directamente
de pares (chosen, rejected) usando los log-probs del modelo
entrenable y del modelo de referencia congelado. Ver [DD-08](./DECISIONES_DISENO.md).
Implementado en `ml/rlhf/dpo_multi.py`.

### Epoch (época)

Una pasada completa por el dataset de entrenamiento.

### FP16 (float16)

Formato de punto flotante de 16 bits. Más rápido y compacto que FP32
pero con rango dinámico limitado. Requiere `GradScaler` para evitar
underflow de gradientes.

### Grad accum (gradient accumulation)

Técnica para simular batches grandes acumulando gradientes a través
de varios mini-batches antes de hacer `optimizer.step()`. En el
proyecto se usa para conseguir batch efectivo grande con poca VRAM.

### Gradient checkpointing

Técnica que recomputa activaciones durante backward en lugar de
almacenarlas. Reduce VRAM 2–3× a costa de ~30 % más tiempo. Crítico
para entrenar modelos B+ en RTX 2050 / T4. Ver
`gradient_checkpointing_enable` en `GPTEducativoV2`.

### Gradient clipping

Limita la norma de los gradientes a un valor máximo para evitar
explosión durante backward. En el proyecto: `grad_clip = 1.0`.

### Learning rate (LR)

Tamaño del paso del optimizador. En el proyecto:
- Pretraining: 3e-4 → 3e-5 (cosine).
- SFT: 1e-4 → 1e-5.
- DPO: 5e-7 (muy bajo, alineamiento).

### Loss (pérdida)

Función que mide el error del modelo. En este proyecto:
- Pretraining y SFT: Cross-entropy de predicción del siguiente token.
- Reward models: MSE multi-dimensional o ranking pairwise.
- DPO: Margen DPO con sigmoide y log.

### Optimizer (AdamW)

Algoritmo que ajusta los pesos basándose en los gradientes. En el
proyecto se usa AdamW con weight decay selectivo (decay solo en
matrices, no en bias ni normas).

### Replay buffer

Mezcla de datos de fases anteriores durante el entrenamiento de la
nueva fase, para evitar catastrophic forgetting. Típicamente 10 %.

### RLAIF (Reinforcement Learning from AI Feedback)

Variante de RLHF donde el juez no es humano sino otro LLM. En este
proyecto: los seis jueces LLM (Gemini, Groq, etc.) etiquetan el
corpus y alimentan el entrenamiento de los reward models propios.

### RLHF (Reinforcement Learning from Human Feedback)

Familia de técnicas para alinear modelos con preferencias humanas.
Incluye PPO clásico, DPO, ORPO, etc. En el proyecto se usa DPO
multi-objetivo.

### Scheduler

Componente que ajusta dinámicamente el learning rate durante el
entrenamiento. En el proyecto: warmup lineal + cosine decay.

### SFT (Supervised Fine-Tuning)

Entrenamiento supervisado del modelo con pares (instrucción,
respuesta) en formato chat. La pérdida solo se computa sobre los
tokens de la respuesta (no del prompt). En el proyecto: Fases 3, 4 y
5a.

### Warmup

Período inicial del entrenamiento donde el learning rate sube
linealmente desde 0 hasta el valor inicial. Estabiliza los primeros
pasos.

### Weight decay

Regularización L2 que tira los pesos hacia cero. Se aplica
selectivamente a matrices, no a bias ni normas.

---

## C — Datos y dataset

### Auditoría

Análisis automático del corpus completo para validar métricas de
calidad antes del entrenamiento. Ver `ml/data/audit.py`.

### Chain-of-thought (CoT)

Estructura donde el modelo razona paso a paso antes de dar la
respuesta final. En el proyecto se materializa en el tipo
`pensamiento_programador` con campo `pensamiento` estructurado.

### Curriculum learning

Estrategia que presenta al modelo los datos en un orden definido
(por dificultad o por tema). En el proyecto se usan **fases
temáticas**: lenguajes → docs → CoT → distilation → senior.

### Dataset

Colección de ejemplos para entrenamiento. En este proyecto: JSONL con
el schema V2.

### Destilación

Técnica donde un modelo más grande (profesor) genera ejemplos que
entrenan a un modelo más pequeño (estudiante). En el proyecto: los
LLMs comerciales gratuitos actúan como profesores generando el corpus.

### JSONL

Formato de archivo donde cada línea es un objeto JSON independiente.
Ideal para datasets de millones de ejemplos.

### Schema (esquema)

Estructura formal de un ejemplo del dataset. Ver
`EjemploEntrenamiento` en `ml/data/schema.py`.

### Tipo (de ejemplo pedagógico)

Etiqueta que indica qué clase de razonamiento se enseña en el
ejemplo. En V2 hay 17 tipos (7 V1 + 10 V2 nuevos).

### Validador

Función que decide si un ejemplo cumple con los requisitos para
formar parte del corpus. Ver `validar_ejemplo` en
`ml/data/validadores.py`.

---

## D — Sistema multi-criterio

### Dimensión de calidad

Eje ortogonal de evaluación: SEG, LEG, ESC, ARQ, REN, MAN.

### Ensemble de jueces

Conjunto de tres jueces LLM (de proveedores distintos) que evalúan
una misma respuesta en una misma dimensión. La nota final es la
mediana.

### Juez LLM

Modelo de lenguaje (Gemini, Groq, DeepSeek, etc.) que califica una
respuesta en una dimensión específica con escala 0–10. Ver
`ml/rlhf/jueces.py`.

### Pearson correlation

Métrica que mide la correlación lineal entre dos series. En el
proyecto: validación de los reward models propios contra los jueces
LLM. Objetivo: r ≥ 0.7 por dimensión.

### Pesos por dimensión

Coeficientes que ponderan cada dimensión en la pérdida combinada.
Por defecto: SEG = 1.5, ARQ = 1.2, MAN = 1.0, LEG = 1.0, ESC = 0.8,
REN = 0.8.

### Reward model (RM)

Modelo que asigna un score numérico a una respuesta. En el proyecto:
seis RM con encoder compartido, uno por dimensión.

### Score multi-criterio

Vector de seis números 0–10, uno por dimensión.

---

## E — Infraestructura del sistema

### Backend

Servicio FastAPI que expone el API REST del sistema. Implementado en
`backend/`.

### Cloud free tier

Cuota gratuita de un servicio cloud. En el proyecto se usan:
- Kaggle Notebooks: 30 horas/semana de T4 16GB.
- Modal Labs: 30 USD/mes en créditos.
- Lightning AI: 15 USD/mes en créditos.

### Frontend

Aplicación web (Next.js) que consume el backend. Implementado en
`frontend/`.

### MCP (Model Context Protocol)

Protocolo de Anthropic para que LLMs invoquen herramientas
estructuradas. El servidor MCP del proyecto está en `mcp_server/` y
expone tools como leer archivo, ejecutar Python, buscar en web.

### Pool de generadores

Componente que gestiona múltiples proveedores LLM con rotación,
rate limiting y fallback. Ver `ml/data/pool_generadores.py`.

### Rate limit

Límite máximo de llamadas que un proveedor permite por minuto o por
día. En el proyecto se respetan localmente con token-bucket y se
manejan con espera de 60 segundos ante 429.

---

## F — Términos académicos

### Currículum (en aprendizaje automático)

Orden estructurado en el que se presentan los datos al modelo durante
el entrenamiento. Inspirado en cómo aprende un humano.

### Hipótesis (en investigación)

Predicción sobre lo que el modelo logrará. En el proyecto: ver
[`research/bitacora_investigacion.md`](../research/bitacora_investigacion.md).

### Objetivo específico (OE)

Subobjetivo medible que contribuye al objetivo general. En el
proyecto: OE1 a OE7, declarados en
[`docs/PROPUESTA_INVESTIGACION.md`](./PROPUESTA_INVESTIGACION.md) §4.

### OWASP

Open Web Application Security Project. Provee el "Top 10" de
vulnerabilidades web. Usado en el tipo `seguridad` del dataset V2.

### Pretrining (preentrenamiento)

Fase inicial de entrenamiento de un LLM con corpus grande y diverso
(predicción de siguiente token). En el proyecto: Fases 1 y 2.

### Reproducibilidad

Capacidad de un tercero para reproducir los resultados con el mismo
código, datos y configuración. En el proyecto se asegura con: semilla
fija, configuración YAML versionada, dataset hasheado, métricas en
`metrics.jsonl`.

### Proyecto (de pregrado)

Trabajo final del estudiante para obtener el grado de Ingeniero/Lic.
en Ciencias de la Computación. El presente proyecto es la base
técnica para esa proyecto.

---

## G — Siglas usadas en el proyecto

| Sigla | Significado |
|---|---|
| AMP | Automatic Mixed Precision |
| AST | Abstract Syntax Tree |
| BPE | Byte-Pair Encoding |
| CoT | Chain of Thought |
| CPT | Continued Pretraining |
| DD | Decisión de Diseño |
| DPO | Direct Preference Optimization |
| FFN | Feed-Forward Network |
| GC | Gradient Checkpointing |
| GQA | Grouped-Query Attention |
| LLM | Large Language Model |
| LM | Language Model |
| LoRA | Low-Rank Adaptation |
| MHA | Multi-Head Attention |
| MCP | Model Context Protocol |
| MSE | Mean Squared Error |
| OE | Objetivo Específico |
| OWASP | Open Web Application Security Project |
| PEP | Python Enhancement Proposal |
| PPL | Perplejidad |
| PPO | Proximal Policy Optimization |
| QLoRA | Quantized LoRA |
| RAG | Retrieval-Augmented Generation |
| RLHF | Reinforcement Learning from Human Feedback |
| RLAIF | Reinforcement Learning from AI Feedback |
| RM | Reward Model |
| RPM | Requests Per Minute |
| RPD | Requests Per Day |
| SDPA | Scaled Dot-Product Attention |
| SFT | Supervised Fine-Tuning |
| ToS | Terms of Service |
| TPM | Tokens Per Minute |
| TPS | Tokens Per Second |
| ViT | Vision Transformer |
| VRAM | Video RAM (memoria GPU) |
| YAML | YAML Ain't Markup Language |

---

## H — Siglas del sistema multi-criterio

| Sigla | Dimensión |
|---|---|
| SEG | Seguridad |
| LEG | Legibilidad |
| ESC | Escalabilidad |
| ARQ | Arquitectura |
| REN | Rendimiento |
| MAN | Mantenibilidad |
