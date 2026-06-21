# Arquitectura Técnica del Sistema

> Descripción técnica detallada de cada componente del sistema, sus
> dependencias internas, contratos de datos y flujo de información.
> Sirve como referencia para el sección de Implementación de el proyecto.

---

## 1. Vista de alto nivel

El sistema se organiza en cuatro capas funcionales:

```
┌─────────────────────────────────────────────────────────────┐
│ CAPA 1 — CONSTRUCCIÓN DEL CORPUS │
│ Fuentes: APIs gratuitas (Gemini, Groq, etc.) + HuggingFace │
│ Salida: data/dataset_v2.jsonl (~333 000 ejemplos) │
└────────────────────────┬────────────────────────────────────┘
 │
 ▼
┌─────────────────────────────────────────────────────────────┐
│ CAPA 2 — ETIQUETADO MULTI-CRITERIO │
│ Jueces: 6 dimensiones × 3 proveedores con mediana │
│ Salida: datasets/etiquetado/scores_v1.jsonl │
└────────────────────────┬────────────────────────────────────┘
 │
 ▼
┌─────────────────────────────────────────────────────────────┐
│ CAPA 3 — ENTRENAMIENTO DE MODELOS │
│ │
│ 3a — Reward Models (entrenar_rm.py + dataset etiquetado) │
│ 3b — Modelo LLM (run_fase.py + 5 fases × YAML) │
│ 3c — Alineación DPO (dpo_multi.py + reward models) │
└────────────────────────┬────────────────────────────────────┘
 │
 ▼
┌─────────────────────────────────────────────────────────────┐
│ CAPA 4 — INFERENCIA Y DESPLIEGUE │
│ Backend FastAPI con modelo cargado, sistema de │
│ regeneración por puntuación, exposición REST. │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. Capa 1: Construcción del corpus

### 2.1 Schema de un ejemplo

Implementado en `ml/data/schema.py`. La clase `EjemploEntrenamiento`
define el contrato canónico:

```python
@dataclass(slots=True)
class EjemploEntrenamiento:
 # Campos obligatorios (V1)
 instruccion: str
 salida: str
 entrada: str = ""
 nivel: str = "basico" # basico | intermedio | avanzado
 tema: str = "otro"
 tipo: str = "explicacion_codigo" # uno de 17 tipos válidos
 fuente: str = "semilla" # gemini | groq | deepseek |...
 metadata: dict = field(default_factory=dict)

 # Campos opcionales (V2, None significa "no aplica")
 pensamiento: dict | None = None
 explicacion_por_nivel: dict[str, str] | None = None
 alternativas: list[dict] | None = None
 errores_comunes: list[str] | None = None
 revision_codigo: dict | None = None
 puntuacion: dict[str, int] | None = None
 version_evolutiva: str | None = None
 tags: list[str] = field(default_factory=list)
```

### 2.2 Tipos pedagógicos

| Tipo | Estructura | Campo V2 clave |
|---|---|---|
| `explicacion_codigo` | Texto pedagógico que explica un fragmento | (V1 puro) |
| `generacion_codigo` | Código a partir de descripción | (V1 puro) |
| `concepto` | Definición de concepto | (V1 puro) |
| `explicacion_linea` | Análisis línea por línea | (V1 puro) |
| `actividad` | Ejercicio para el estudiante | (V1 puro) |
| `correccion_error` | Detección y corrección | (V1 puro) |
| `comprension` | Pregunta de comprensión lectora | (V1 puro) |
| `pensamiento_programador` | Razonamiento previo al código | `pensamiento` |
| `explicacion_multinivel` | Mismo concepto, cuatro audiencias | `explicacion_por_nivel` |
| `anti_patron` | Código malo + refactorización | `revision_codigo` |
| `bug_sutil` | Bug lógico no obvio | `errores_comunes` |
| `evolucion_codigo` | Versión específica del problema | `version_evolutiva` |
| `decision_diseno` | Comparativa con justificación | `pensamiento` |
| `arquitectura_sistema` | Diseño end-to-end | `pensamiento` |
| `seguridad` | Vulnerabilidad + corrección | `tags` (OWASP) |
| `testing_complejidad` | Tests + análisis Big-O | (V1 puro) |
| `pensamiento_autocritico` | Iteraciones A → B → C | `pensamiento.iteraciones` |

### 2.3 Pool de generadores

`ml/data/pool_generadores.py` implementa el abstract sobre los seis
proveedores LLM gratuitos.

**Contrato de uso:**

```python
pool = Pool.desde_env() # lee.env automáticamente
texto, proveedor = await pool.generar(
 prompt="...",
 tarea=Tarea.COT, # determina prioridad
 temperatura=0.9,
 max_tokens=4096,
 esperar_si_rate_limited=True, # espera 60s si 429
)
```

**Tareas y prioridades:**

```python
PRIORIDADES[Tarea.COT] = [(gemini, 9), (deepseek, 8),...]
PRIORIDADES[Tarea.CODIGO] = [(deepseek, 9), (gemini, 8),...]
PRIORIDADES[Tarea.EXPLICACION] = [(gemini, 9), (mistral, 8),...]
PRIORIDADES[Tarea.EVALUACION] = [(gemini, 9), (groq, 8),...]
PRIORIDADES[Tarea.VOLUMEN] = [(groq, 9), (together, 8),...]
PRIORIDADES[Tarea.GENERICA] = [(gemini, 8), (deepseek, 8),...]
```

**Rate limiting:** cada proveedor tiene su token-bucket
(`RateLimit`) que registra timestamps de las llamadas. Cuando el server
devuelve 429, el pool espera 60 segundos fijos antes de reintentar (no
acumula timestamps locales para evitar el problema documentado en
[BUGS_Y_SOLUCIONES.md](./BUGS_Y_SOLUCIONES.md), sección sobre el bug
del rate limit con espera creciente).

**Extracción de JSON:** dos funciones públicas:

```python
extraer_json_objeto(texto) -> dict | None # un único objeto
extraer_json_array(texto) -> list | None # array, tolerante a truncamiento
```

Internamente, `extraer_json_array` intenta primero el parseo completo
del array con `strict=False`, y si falla cae al fallback
`_extraer_objetos_balanceados`, que recorre el texto carácter por
carácter contando llaves y extrae cada objeto que cierre balanceado.

### 2.4 Generadores

Cada generador es un módulo Python con la misma estructura:

```python
# Datos de configuración
OBJETIVOS = (("tema_1", "nivel_1"),...) # 15–30 entradas
PROMPT_TEMPLATE = "..." # f-string con reglas estrictas

# Funciones principales
async def generar_objetivo(pool, tema, nivel, n, *, temperatura)
async def generar_corpus(pool, salida, *, n_por_objetivo, temperatura)

# CLI
def main()
```

El template del prompt fuerza un formato estricto: solo array JSON, sin
texto explicativo, con todas las claves requeridas por el tipo. La
validación posterior descarta cualquier elemento que no cumpla.

### 2.5 Orquestador

`construir_dataset_v2.py` ejecuta los diez generadores en serie.

**Configuración por escala:**

```python
ESCALAS = {
 "mini": {pensamiento: {n: 2},...},
 "media": {pensamiento: {n: 4},...},
 "completa": {pensamiento: {n: 8},...},
}
```

**Pipeline ejecutado:**

1. Para cada generador en `GENERADORES`:
 1. Si el archivo de salida ya existe y no se pasó `--reset`, saltar.
 2. Si está en la lista `--skip`, saltar.
 3. Ejecutar el generador con los parámetros de la escala.
 4. Recolectar `stats_por_generador[nombre]`.
2. Consolidar todos los JSONL en `dataset_v2.jsonl`, deduplicando.
3. Ejecutar `audit.auditar` sobre el corpus consolidado.
4. Guardar `resumen_construccion.json` con todas las métricas.

### 2.6 Validadores

`validadores.py` expone una única función de uso típico:

```python
ok, motivo = validar_ejemplo(ejemplo)
```

Internamente, el validador agregado aplica:

1. Las validaciones del schema (`ejemplo.es_valido`).
2. `validar_salida_pedagogica` sobre el campo `salida`.
3. Si la `entrada` parece código Python (heurística por palabras clave),
 `validar_codigo_python`.
4. Para cada bloque de código en la `salida` (extraído con regex de
 fences Markdown), `validar_codigo_python`.
5. Validaciones específicas por tipo:
 - `pensamiento_programador` y `decision_diseno`: `validar_pensamiento`.
 - `explicacion_multinivel`: `validar_multinivel`.
 - `anti_patron`: `validar_revision_codigo`.
 - `evolucion_codigo`: verifica `version_evolutiva` válida.
 - `pensamiento_autocritico`: `validar_autocritica`.
6. Si tiene `puntuacion`, `validar_puntuacion`.

### 2.7 Auditoría

`audit.py` expone:

```python
reporte = auditar(lista_de_ejemplos)
```

Calcula y reporta:

- Total y porcentaje de válidos según `validar_ejemplo`.
- Duplicados según `clave_dedup`.
- Distribución por nivel / tema / tipo / fuente.
- Longitudes (promedio, mediana, máximo) de `instruccion` y `salida`.
- Bloques de código que compilan correctamente.
- Porcentaje de ejemplos con cada campo V2 poblado.
- Detección de idioma (heurística por marcadores españoles).
- Advertencias cuando alguna métrica está bajo el umbral en `OBJETIVOS`.

---

## 3. Capa 2: Etiquetado multi-criterio

### 3.1 Rúbricas

`ml/rlhf/jueces.py` define una `Rubrica` por dimensión:

```python
@dataclass(frozen=True, slots=True)
class Rubrica:
 nombre: str
 definicion: str
 rubrica: str # texto con descriptores 0-2, 3-4, 5-6, 7-8, 9-10
```

Las seis dimensiones están en `RUBRICAS`. Por ejemplo, `RUBRICAS["SEG"]`
contiene:

- `nombre`: "Seguridad"
- `definicion`: "Ausencia de vulnerabilidades, manejo correcto de
 inputs, gestión segura de credenciales, OWASP, defense-in-depth."
- `rubrica`: descripciones por rango (0-2 con SQL injection, 3-4 con
 edge cases obvios,..., 9-10 defensive coding completo).

### 3.2 Asignación de jueces

```python
JUECES_POR_DIMENSION = {
 "SEG": ("gemini", "deepseek", "groq"),
 "LEG": ("gemini", "mistral", "groq"),
 "ESC": ("deepseek", "gemini", "groq"),
 "ARQ": ("gemini", "deepseek", "mistral"),
 "REN": ("deepseek", "groq", "together"),
 "MAN": ("gemini", "deepseek", "mistral"),
}
```

Cada dimensión usa tres proveedores distintos (de la lista de
disponibles); si menos están configurados, el ensemble se reduce
automáticamente al subset disponible.

### 3.3 Funciones públicas

```python
score, detalle = await calificar_dimension(pool, pregunta, respuesta, dim)
resultado = await calificar_respuesta(pool, pregunta, respuesta)
# resultado = {"scores": {SEG: 8, LEG: 7,...}, "detalle": {SEG: [...]}}
```

`calificar_dimension` consulta los tres jueces de la dimensión en
paralelo (`asyncio.gather`), parsea `{"score": int, "razon": str}` con
`extraer_json_objeto`, y devuelve la mediana de los scores válidos.

### 3.4 Etiquetador

`etiquetar_dataset.py` orquesta el etiquetado sobre un JSONL entero:

- Lee el archivo de entrada.
- Detecta lo ya etiquetado en la salida (resume con hash sha1 de
 prompt+respuesta).
- Lanza tareas en paralelo con `asyncio.Semaphore(concurrencia)`.
- Escribe cada resultado a la salida inmediatamente (apertura en modo
 `"a"` para resilience a interrupciones).
- Reporta progreso cada 10 items con velocidad y ETA.

---

## 4. Capa 3: Entrenamiento

### 4.1 Modelo principal

`ml/model/transformer_v2.py` implementa el `GPTEducativoV2`:

```
Input idx (B, T)
 │
 ▼
Embedding (vocab, n_embd)
 │
 ▼
Drop(p=dropout)
 │
 ▼ ┌──────────── × n_layer ────────────┐
 │ │ │
 │ │ RMSNorm │
 │ │ GroupedQueryAttention │
 │ │ Q proj: (n_embd) → (n_head·hd)│
 │ │ K, V proj: (n_embd) → (n_kv_head·hd)
 │ │ Aplicar RoPE a Q y K │
 │ │ Expandir K, V a n_head │
 │ │ F.scaled_dot_product_attention│
 │ │ + residual │
 │ │ │
 │ │ RMSNorm │
 │ │ SwiGLU FFN │
 │ │ Hidden = ⌈n_embd · mult / 64⌉ · 64
 │ │ out = w_down(silu(w_gate(x)) * w_up(x))
 │ │ + residual │
 │ │ │
 │ └────────────────────────────────────┘
 │
 ▼
RMSNorm final
 │
 ▼
LM Head (n_embd → vocab) (weight-tied con embedding)
 │
 ▼
Logits (B, T, vocab)
```

**Métodos públicos:**

```python
modelo.gradient_checkpointing_enable()
modelo.gradient_checkpointing_disable()
logits, loss = modelo.forward(idx, targets=None)
salida = modelo.generar(idx, max_new_tokens, temperatura, top_k, top_p)
opt = modelo.configurar_optimizador(weight_decay, lr, betas)
```

### 4.2 Tokenizer

Sentencepiece con vocabulario de 16 000 (V2). El runner usa un wrapper
mínimo `_Tokenizer`:

```python
class _Tokenizer:
 def __init__(self, modelo_path: Path):
 import sentencepiece as spm
 self.sp = spm.SentencePieceProcessor()
 self.sp.Load(str(modelo_path))
 self.vocab_size = self.sp.get_piece_size()

 def codificar(self, texto: str) -> list[int]
 def decodificar(self, ids: list[int]) -> str
```

Tokens especiales que se planifican (a entrenar con el sp):
`<|user|>`, `<|assistant|>`, `<|system|>`, `<|end|>`, `<think>`,
`</think>`, `<code>`, `</code>`, `<NIVEL=...>`, `<SEG=...>` etc.

### 4.3 Dataset para pretrain

`PretrainDataset(IterableDataset)`:

- Lee todos los archivos `.txt` en orden mezclado (RNG con semilla).
- Tokeniza cada archivo entero al vuelo.
- Emite chunks no-solapados de tamaño `block_size + 1` (x = chunk[:-1],
 y = chunk[1:]).
- Itera infinitamente (cuando termina los archivos, vuelve a mezclar y
 reanuda).

### 4.4 Dataset para SFT

`SFTDataset(IterableDataset)`:

- Lee el JSONL en bloque, mezcla, itera.
- Formatea cada ejemplo con el template:
 ```
 <|user|>{instruccion}\n{entrada}<|end|><|assistant|>{salida}<|end|>
 ```
- Computa `labels`: `-100` para todos los tokens del prompt (no se
 contabilizan en la pérdida) y los IDs reales para los tokens de la
 respuesta.
- Trunca por el inicio si el ejemplo excede `block_size` (preserva la
 respuesta).
- Padding con `0` y `labels = -100`.

### 4.5 Trainer

`TrainerV2`:

```
┌────────────────────────────────────────────────────────────┐
│ Loop principal │
│ │
│ while paso < max_pasos and not abortar: │
│ opt.zero_grad() │
│ for _ in range(grad_accum): │
│ x, y = next(train_iter) │
│ with autocast(dtype): │
│ _, loss = modelo(x, y) │
│ loss = loss / grad_accum │
│ if fp16: scaler.scale(loss).backward() │
│ else: loss.backward() │
│ │
│ if fp16: scaler.unscale_(opt) │
│ clip_grad_norm_(modelo.parameters(), grad_clip) │
│ if fp16: scaler.step(opt); scaler.update() │
│ else: opt.step() │
│ │
│ set_lr(cosine_with_warmup(paso, max_pasos)) │
│ paso += 1 │
│ │
│ if paso % log_cada == 0: log_metricas() │
│ if paso % eval_cada == 0: evaluar(); save best │
│ if paso % save_cada == 0: save ultimo │
│ if tiempo_agotado: break │
│ │
│ save_checkpoint("ultimo") │
└────────────────────────────────────────────────────────────┘
```

**Estado serializable** para resume:

```python
@dataclass
class _RunState:
 paso: int = 0
 epoca: int = 0
 mejor_val_loss: float = float("inf")
 rng_seed_actual: int = 42
 tiempo_total_segundos: float = 0.0
```

Se persiste junto al `model_state`, `opt_state`, `scaler_state` y la
configuración resuelta del modelo en cada checkpoint.

### 4.6 Reward models

`MultiCriteriaRewardModel` (en `reward_model.py`):

```
Input idx (B, T) + attention_mask (B, T)
 │
 ▼
RewardEncoder
 │
 ▼
Hidden (B, T, n_embd)
 │
 ▼
Pooling (mean | last | attention)
 │
 ▼
Pooled (B, n_embd)
 │
 ├─► Head SEG → score_SEG (B,) en [0, 10]
 ├─► Head LEG → score_LEG (B,)
 ├─► Head ESC → score_ESC (B,)
 ├─► Head ARQ → score_ARQ (B,)
 ├─► Head REN → score_REN (B,)
 └─► Head MAN → score_MAN (B,)
```

Cada head es un MLP opcional (`head_hidden=256` por defecto) seguido de
`sigmoid * score_max`.

### 4.7 DPO multi-objetivo

Pérdida con pesos por dimensión:

```
margen = β · ((log π_θ(y_w|x) - log π_ref(y_w|x))
 - (log π_θ(y_l|x) - log π_ref(y_l|x)))

loss_item = -log σ(margen) shape (B,)
peso_item = pesos_dim[dim_idx_item] shape (B,)
loss = mean(loss_item * peso_item / mean(peso_item))
```

`_log_prob_secuencia` extrae los log-probs de los tokens en `labels`
distintos de `-100` (los tokens de la respuesta, no del prompt).

---

## 5. Capa 4: Inferencia y despliegue

### 5.1 Sistema de regeneración por puntuación

Mencionado en [PLAN_ENTRENAMIENTO_V2.md](./PLAN_ENTRENAMIENTO_V2.md)
sección 6, este será un middleware en el backend FastAPI:

```python
def responder_con_threshold(prompt, max_intentos=3, score_minimo=55):
 for intento in range(max_intentos):
 respuesta = modelo_propio.generar(prompt, temperatura=0.6 + 0.1*intento)
 scores = reward_models.evaluar(prompt, respuesta) # 6 dim, 0-10 c/u
 if sum(scores.values()) >= score_minimo:
 return respuesta, scores
 return mejor_respuesta_vista, mejores_scores
```

### 5.2 Modos de uso en producción

- **Modo estudiante**: pesos altos en LEG y MAN, respuestas didácticas.
- **Modo profesional**: pesos altos en SEG y ARQ, respuestas
 production-grade.
- **Modo competencia**: pesos altos en REN y ESC, optimización.

Los pesos se inyectan en el prompt como control codes (planeados en
sección 8 de PLAN_ENTRENAMIENTO_V2.md), interpretados por el modelo
mediante tokens especiales del tokenizer.

---

## 6. Flujo end-to-end de un ejemplo

```
[1] Usuario envía pregunta al frontend
 ↓
[2] Frontend → POST /api/v1/chat → backend FastAPI
 ↓
[3] Backend resuelve prompt con system message + control codes
 ↓
[4] Backend invoca modelo local (checkpoint Fase 5b cargado)
 ↓
[5] Modelo genera respuesta (con CoT si pidió razonamiento)
 ↓
[6] Backend evalúa con los 6 reward models
 ↓
[7] Si suma de scores < umbral: regenerar con T más alta (max 3 intentos)
 ↓
[8] Backend devuelve respuesta + scores al frontend
 ↓
[9] Frontend renderiza con los scores como métricas visuales
 ↓
[10] (opcional) Usuario marca 👍/👎 → feedback va a BD
 ↓
[11] (mensual) Feedback acumulado alimenta DPO incremental
```

---

## 7. Dependencias entre archivos

```
schema.py
 ↑
 ├── validadores.py
 ├── corpus.py
 └── pool_generadores.py
 ↑
 ├── jueces.py
 │ ↑
 │ └── etiquetar_dataset.py
 │
 └── 10 generadores (generar_*.py)
 ↑
 └── construir_dataset_v2.py
 ↑
 └── audit.py

transformer_v2.py
 ↑
 ├── reward_model.py
 │ ↑
 │ └── entrenar_rm.py
 │
 ├── dpo_multi.py
 │
 └── run_fase.py

config.py (PRESETS_V2)
 ↑
 ├── run_fase.py
 ├── dpo_multi.py
 └── reward_model.py
```

---

## 8. Convenciones de código

- **Idioma**: nombres de funciones y variables en español
 (`generar_corpus`, `validar_ejemplo`, `pool`, etc.) salvo cuando
 coinciden con términos técnicos en inglés universalmente adoptados
 (`tokenizer`, `forward`, `backward`, `dropout`, `attention`, etc.).
- **Type hints**: completos en signatures de funciones públicas.
- **Docstrings**: español, formato libre pero indicando propósito,
 parámetros y retorno cuando no son obvios.
- **Async**: las interacciones con APIs externas siempre asíncronas
 (`httpx.AsyncClient`, `asyncio.gather`).
- **Imports**: ordenados por sección (stdlib, terceros, locales),
 separados por línea en blanco.
- **No emojis** en código ni en documentación (`docs/`), salvo
 excepción justificada.
