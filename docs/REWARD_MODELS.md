# Sistema de Reward Models multi-criterio (RLAIF avanzado)

> El sistema actual (`ml/rlhf/preparar_pares.py`) usa UN juez global
> (Gemini) que decide A vs B con criterios mezclados. Esto funciona
> pero limita la capacidad de "controlar el estilo" del modelo.
>
> Este documento describe la evolución a **6 reward models
> especializados** — uno por dimensión de calidad — que permite:
> 1. Detectar y corregir debilidades específicas del modelo (ej. mal en
> seguridad pero bien en legibilidad).
> 2. Ajustar el "perfil" del modelo en tiempo de inferencia sin
> re-entrenar (más peso a "didáctico" para modo estudiante, más
> peso a "producción" para modo IDE).
> 3. Generar datasets DPO mucho más ricos (un par por dimensión, no uno
> global).
>
> Complementa [DATASET_V2.md](./DATASET_V2.md) y
> [RLHF_PLAN.md](./RLHF_PLAN.md).

---

## 1. Las 6 dimensiones de calidad

| ID | Dimensión | Qué mide |
|---|---|---|
| `SEG` | Seguridad | Vulnerabilidades, sanitización, gestión de secretos, OWASP |
| `LEG` | Legibilidad | Nombres claros, estructura, comentarios pertinentes, complejidad cognitiva |
| `ESC` | Escalabilidad | Complejidad algorítmica, uso de memoria, capacidad de crecer |
| `ARQ` | Arquitectura | Separación de responsabilidades, dependencias, patrones |
| `REN` | Rendimiento | Optimizaciones, ausencia de cómputo redundante, uso de stdlib |
| `MAN` | Mantenibilidad | Tests, error handling, documentación, configurabilidad |

Cada respuesta del modelo recibe **6 notas independientes 0-10**, no una
nota global.

**Por qué no más dimensiones**: 6 es el punto donde la varianza entre
jueces baja y la cobertura es suficiente. 10+ se vuelve ruidoso (los
jueces empiezan a discrepar en los matices).

**Por qué no menos**: con 3 dimensiones (correctness/clarity/style) se
pierde la capacidad de hacer trade-offs explícitos
(p.ej. legibilidad vs rendimiento).

---

## 2. Pipeline general

```
 Respuesta del modelo
 │
 ▼
 ┌────────────────────────┐
 │ 6 jueces LLM en paralelo│ (Fase A: bootstrap)
 │ Gemini · DeepSeek · │
 │ Llama 3.3 70B (Groq) │
 └────────────────────────┘
 │
 ▼
 {SEG: 8, LEG: 7, ESC: 9,
 ARQ: 6, REN: 8, MAN: 7}
 │
 ▼
 ┌────────────────────────┐
 │ Dataset (prompt, resp, │
 │ 6 scores) ~ 30k │
 └────────────────────────┘
 │
 ▼
 ┌────────────────────────┐
 │ Entrenar 6 reward │ (Fase B: internalizar)
 │ models small (~50M c/u) │
 │ con regresión MSE │
 └────────────────────────┘
 │
 ▼
 ┌────────────────────────┐
 │ Inferencia interna: │ (Fase C: producción)
 │ RM dan scores, NO LLM │
 └────────────────────────┘
 │
 ▼
 ┌────────────────────────┐
 │ DPO multi-criterio / │
 │ best-of-N sampling / │
 │ score-conditional gen │
 └────────────────────────┘
```

---

## 3. Fase A — Etiquetar dataset con LLMs como jueces

### 3.1 Prompt del juez por dimensión

```python
# ml/rlhf/jueces.py
PROMPT_JUEZ_TEMPLATE = """Eres un revisor experto evaluando código y
explicaciones técnicas. Tu única tarea es calificar la siguiente
respuesta en UNA dimensión: **{dimension_nombre}**.

DEFINICIÓN de la dimensión:
{dimension_definicion}

CRITERIOS de calificación (escala 0-10):
{rubrica}

Pregunta original:
{pregunta}

Respuesta a evaluar:
{respuesta}

Devuelve EXACTAMENTE un JSON sin markdown:
{{"score": <int 0-10>, "razon": "<una frase>"}}
"""

RUBRICAS = {
 "SEG": {
 "nombre": "Seguridad",
 "definicion": "Ausencia de vulnerabilidades, manejo correcto de inputs, "
 "gestión segura de credenciales, conformidad con OWASP.",
 "rubrica": """
0-2: tiene SQL injection / XSS / inyección de comandos / hardcoded secret
3-4: vulnerable a edge cases obvios (timing attack, eval, etc.)
5-6: básicamente seguro pero con omisiones notables
7-8: aplica buenas prácticas conocidas
9-10: defensive coding completo, considera amenazas no triviales"""
 },
 "LEG": {... }, # similar para cada dimensión
 "ESC": {... },
 "ARQ": {... },
 "REN": {... },
 "MAN": {... },
}
```

### 3.2 Ensemble de jueces (para reducir sesgo)

UN solo LLM-juez tiene sesgo (Gemini es severo en LEG, DeepSeek es
indulgente en MAN, etc.). Solución: **3 jueces por dimensión** y la
nota final es **mediana**.

```python
JUECES_POR_DIMENSION = {
 "SEG": ["gemini-2.0-flash", "deepseek-chat", "groq-llama-3.3-70b"],
 "LEG": ["gemini-2.0-flash", "mistral-large", "groq-llama-3.3-70b"],
 #...
}

async def calificar_respuesta(pregunta, respuesta) -> dict[str, int]:
 """Devuelve {"SEG": 8, "LEG": 7,...} con mediana de 3 jueces."""
 tareas = []
 for dim, jueces in JUECES_POR_DIMENSION.items():
 for juez in jueces:
 tareas.append(_consultar_juez(juez, dim, pregunta, respuesta))
 resultados = await asyncio.gather(*tareas)
 # agrupar por dimensión y tomar mediana
 return _agregar_mediana(resultados)
```

**Costo en free tier**: cada respuesta consume 18 llamadas (6 dim × 3
jueces). Con los rate limits de §4.1 de DATASET_V2: ~2k respuestas
calificadas/día sin pagar. En 2 semanas: 30k respuestas etiquetadas.

### 3.3 Dataset resultante

```jsonl
{"prompt": "Crea endpoint login", "respuesta": "...", "scores": {"SEG":8,"LEG":7,"ESC":6,"ARQ":7,"REN":8,"MAN":6}, "fuente": "modelo_v1"}
{"prompt": "...", "respuesta": "...", "scores": {...}, "fuente": "humano_alta_calidad"}
```

Mezcla:
- 60% respuestas del modelo propio (varias temperaturas)
- 25% respuestas de modelos públicos (DeepSeek/Llama vía API)
- 15% respuestas humanas "premium" (Stack Overflow top, libros)

Esto cubre todo el rango 0-10 en cada dimensión.

---

## 4. Fase B — Entrenar 6 reward models propios

### 4.1 Arquitectura

Cada RM es un modelo pequeño (~50M params) con un **regression head**:

```python
class RewardModel(nn.Module):
 def __init__(self, base_transformer, dim_nombre: str):
 super().__init__()
 self.encoder = base_transformer # comparte arquitectura con el modelo principal
 self.regression_head = nn.Linear(self.encoder.d_model, 1)
 self.dim_nombre = dim_nombre # "SEG", "LEG", etc.

 def forward(self, input_ids):
 h = self.encoder(input_ids)
 # promediar sobre tokens (o tomar el último)
 pooled = h.mean(dim=1)
 score = torch.sigmoid(self.regression_head(pooled)) * 10 # 0-10
 return score.squeeze(-1)
```

**Base compartida**: los 6 RM comparten el mismo encoder (congelado o
con LoRA fino) y solo difieren en la head. Esto:
- Ahorra VRAM: 1 encoder + 6 heads pequeñas en lugar de 6 modelos completos.
- Reduce overfit por dimensión.
- Permite generación rápida en inferencia (un forward, 6 outputs).

### 4.2 Pérdida

```python
loss = F.mse_loss(score_predicho, score_real_del_juez_ensemble)
```

Variante más robusta: **ranking loss** entre pares mejor/peor:

```python
loss = -F.logsigmoid(score_chosen - score_rejected).mean()
```

Esta es preferible cuando los scores absolutos del juez son ruidosos
pero el ordering es confiable.

### 4.3 Hyperparams

| Param | Valor |
|---|---|
| Base encoder | Transformer v2 (RoPE + GQA) con `n_layer=6, d_model=512` |
| Params totales por RM | ~50M (compartiendo encoder) |
| Batch size | 16 (cabe en RTX 2050) |
| LR | 1e-5 (mucho más bajo que pretraining) |
| Epochs | 3 |
| Datos | 30k ejemplos del Fase A, split 90/10 train/val |
| Tiempo entrenamiento | ~3h por RM en RTX 2050 → ~18h total (cabe en una semana) |

---

## 5. Fase C — Usos del sistema en producción

### 5.1 DPO multi-criterio

En lugar de una sola lista de pares `(chosen, rejected)`, generamos
**6 listas** — una por dimensión:

```
data/dpo_v2_SEG.jsonl (pares donde chosen >> rejected en SEG)
data/dpo_v2_LEG.jsonl
data/dpo_v2_ESC.jsonl
data/dpo_v2_ARQ.jsonl
data/dpo_v2_REN.jsonl
data/dpo_v2_MAN.jsonl
```

Entrenamiento DPO en 6 pases (uno por dimensión) o en 1 pase con
**multi-objective DPO** (suma ponderada de loss). Recomendado: pase
único con pesos:

```python
W = {"SEG": 1.5, "ARQ": 1.2, "MAN": 1.0, "LEG": 1.0, "ESC": 0.8, "REN": 0.8}
loss = sum(W[dim] * loss_dpo[dim] for dim in dimensiones)
```

Los pesos altos en `SEG` y `ARQ` son decisión pedagógica: un asistente
educativo prioriza enseñar código seguro y bien arquitectado por encima
de optimizado al máximo.

### 5.2 Best-of-N sampling con RM en inferencia

Para queries críticas, generar N respuestas (N=4) y elegir la de mayor
score combinado:

```python
async def responder_critica(prompt, n=4):
 candidatas = [modelo.generar(prompt, temperature=0.8) for _ in range(n)]
 scores = [rm_combinado(prompt, c) for c in candidatas]
 return candidatas[max(range(n), key=lambda i: scores[i])]
```

Usar solo cuando el endpoint lo solicita (modo "alta calidad"); por
defecto N=1 por costo.

### 5.3 Score-conditional generation

Estilo "control codes": inyectar al inicio del prompt qué scores
queremos:

```
<NIVEL=profesional><SEG=10><LEG=8><ESC=9> Cómo implementar JWT...
```

El modelo aprende a calibrar el output al perfil pedido. Útil para:
- Estudiante junior → `<LEG=10><MAN=10>` (didáctico, legible)
- Senior profesional → `<SEG=10><ARQ=10>` (production-grade)
- Concurso de código → `<REN=10><ESC=10>` (eficiencia)

Esto se entrena agregando las anotaciones a un % del corpus durante SFT.

### 5.4 Self-critique loop en inference

Antes de devolver al usuario:

```python
respuesta = modelo.generar(prompt)
scores = rm_combinado(prompt, respuesta)
if min(scores.values()) < 5: # alguna dimensión flaquea
 critica = f"Tu respuesta falló en {peor_dimension}. Mejora."
 respuesta = modelo.generar(prompt + respuesta + critica)
return respuesta
```

Limitar a 1 retry (más es caro).

### 5.5 Filtro de respuestas en endpoint

El backend ya tiene `quality_service`. Reemplazar/aumentar con RM:

```python
# backend/app/services/quality_service.py
def evaluar_respuesta(prompt: str, respuesta: str) -> dict:
 scores = rm_inference(prompt, respuesta) # llamada local
 return {
 "scores": scores,
 "ok_para_responder": all(s >= 4 for s in scores.values()),
 "razones_rechazo": [d for d, s in scores.items() if s < 4],
 }
```

Si `ok_para_responder == False` → regenerar o caer a Gemini.

---

## 6. Ventajas vs el juez único actual

| Aspecto | Juez único actual | 6 RM multi-criterio |
|---|---|---|
| Costo en inferencia | $0.0001/query (API) | $0 (RM local) |
| Latencia | ~2s por juez | ~50ms (RM local pequeño) |
| Privacidad | Manda data a Google | Todo on-prem |
| Granularidad de feedback | "respuesta B es mejor" | "B es mejor en SEG y ESC, peor en LEG" |
| Control del estilo | Solo via prompt engineering | Via control codes + pesos DPO |
| Aporte a el proyecto | RLAIF estándar | Sistema multi-criterio = contribución original |

---

## 7. Validación de los RM

Antes de usarlos para DPO, validar que dan scores razonables:

```bash
python -m ml.rlhf.validar_rm \
 --benchmark data/rm_test_set.jsonl \
 --modelos rm/SEG.pt rm/LEG.pt...
```

Métricas:
- **Pearson correlation** RM vs jueces LLM (objetivo > 0.7)
- **Kendall tau** sobre ordering (objetivo > 0.6)
- **Calibración**: que score=8 signifique algo consistente
- **Robustez a perturbaciones**: agregar comentarios cambia LEG pero NO
 cambia SEG (test de validez convergente)

---

## 8. Estructura de archivos a crear

```
ml/rlhf/
├── jueces.py ← rubrics + ensemble de LLM jueces
├── etiquetar_dataset.py ← Fase A: corre jueces sobre dataset
├── reward_model.py ← arquitectura del RM
├── entrenar_rm.py ← Fase B: training de los 6 RM
├── validar_rm.py ← métricas de los RM entrenados
├── preparar_pares.py ← (existente) extender con --criterio
├── dpo.py ← (existente) extender con multi-objetivo
└── inferencia_rm.py ← API local para servir los RM
```

---

## 9. Plan de ejecución (mes 2)

| Semana | Trabajo |
|---|---|
| 5 | `jueces.py` + rúbricas; `etiquetar_dataset.py` corriendo con ensemble |
| 5-6 | Etiquetar 30k respuestas (consume 2 semanas de free tier) |
| 7 | `reward_model.py` + `entrenar_rm.py`; entrenar 6 RM |
| 7 | `validar_rm.py`; iterar hasta Pearson > 0.7 en todas las dim |
| 8 | Generar `dpo_v2_<dim>.jsonl` para cada dimensión |
| 8 | Entrenar DPO multi-objetivo sobre checkpoint base; comparar vs DPO single-judge |

**Entregable**: 6 RM cargados en `backend/app/services/reward_models/`,
DPO mejorado, métricas comparativas en `docs/EXPERIMENTOS/`.

---

## 10. del proyecto

Esta sección es una contribución original publicable. El estado del arte
en 2024-2025 hace ensemble de jueces pero raramente entrena RM
multi-dimensionales especializados para enseñanza. Anthropic Constitutional
AI usa principios pero no granularidad dimensional. Una sección de
documentación puede titularse:

> *"Sistema de recompensa multi-criterio destilado para RLAIF en
> modelos educativos de programación"*

Comparativas a reportar:
1. **Win rate DPO** vs base: single-judge DPO vs multi-criterio DPO.
2. **Trade-offs explícitos**: qué pasa cuando subes peso de SEG (sube
 código seguro, baja velocidad de respuesta — interesante del proyecto).
3. **Score-conditional**: demostrar que el modelo cambia estilo según
 control codes.
4. **Pearson de RM vs juez LLM** como validación de la destilación.

---

## 11. Referencias

- Anthropic, **Constitutional AI**, 2022 — base de RLAIF
- OpenAI, **Summarization with Human Feedback**, 2020 — origen de los RM
- Lee et al., **RLAIF**, 2023 — escalar feedback con IA juez
- Wu et al., **Fine-Grained RLHF**, 2023 — feedback multi-dimensional
- Rame et al., **Rewarded Soups**, 2023 — combinar reward functions
