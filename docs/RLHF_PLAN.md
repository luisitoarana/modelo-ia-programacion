# Plan de RLHF — Aprendizaje por Refuerzo con Feedback Humano

> El sistema **mejora con uso**: cada 👍/👎 que un usuario da en el chat
> alimenta un dataset de preferencias que se usa para refinar el modelo
> propio mediante DPO (Direct Preference Optimization).

---

## 1. Qué es RLHF (en una frase)

> En lugar de decirle al modelo "esta es la respuesta correcta", le
> mostramos **dos respuestas** y le decimos cuál fue **preferida** por
> un humano. El modelo aprende a producir más como la preferida y menos
> como la rechazada.

Esto refleja exactamente lo que pide el usuario: "cuando el sistema
acierta se le da un punto positivo" — formalmente eso es **RLHF**, y la
"hormona positiva" es el gradiente que apunta hacia la respuesta
preferida.

---

## 2. Por qué DPO y no PPO

Hay tres métodos principales:

| Método | Necesita | Dificultad | Costo VRAM | Para nosotros |
|---|---|---|---|---|
| **PPO** (clásico OpenAI) | Modelo + reward model + value model | Alta | 3-4× el modelo base | ❌ No cabe en RTX 2050 |
| **DPO** (Direct Preference Optimization) | Solo el modelo + dataset de pares | Baja | 2× el modelo base | ✅ **El elegido** |
| **RLAIF** (AI as judge) | Un LLM externo como juez | Media | 2× el modelo base | ✅ Complementario |

**DPO en una fórmula**:

```
L_DPO = -E[(x, y_w, y_l) ~ D] [ log σ( β · log(π_θ(y_w|x) / π_ref(y_w|x))
 - β · log(π_θ(y_l|x) / π_ref(y_l|x)) )]
```

Donde:
- `y_w` = respuesta preferida (winner, el 👍)
- `y_l` = respuesta rechazada (loser, el 👎)
- `π_θ` = modelo que estamos entrenando
- `π_ref` = modelo de referencia congelado (la versión pre-DPO)
- `β` = controla qué tanto el modelo puede alejarse del ref (típico β=0.1)

**Por qué nos sirve**:
- No necesita reward model entrenado aparte
- No necesita rollouts (que son carísimos en RTX 2050)
- Funciona con datasets de pares pequeños (~5k pares ya da mejoras
 visibles)
- Implementación disponible en `trl` (HuggingFace) en ~50 líneas

---

## 3. Pipeline de recolección de feedback

```
┌──────────┐ ┌──────────┐ ┌─────────────┐ ┌──────────┐
│ Usuario │ -> │ Chat web │ -> │ Backend │ -> │ Postgres │
│ da 👍/👎 │ │ /desktop │ │ /feedback │ │ tabla │
└──────────┘ └──────────┘ └─────────────┘ │ feedback │
 └──────────┘
 │
 v
 ┌──────────────────────┐
 │ Exportador semanal: │
 │ dataset_rlhf.jsonl │
 │ con pares (yw, yl) │
 └──────────────────────┘
 │
 v
 ┌──────────────────────┐
 │ python rlhf/dpo.py │
 │ -> checkpoint nuevo │
 └──────────────────────┘
```

### Esquema de tabla `Feedback`

```sql
CREATE TABLE feedback (
 id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
 usuario_id UUID REFERENCES usuarios(id),
 mensaje_id UUID REFERENCES mensajes(id),
 conversacion_id UUID REFERENCES conversaciones(id),

 -- El feedback en sí
 voto SMALLINT NOT NULL, -- +1 (👍) o -1 (👎)
 comentario TEXT, -- opcional, hasta 500 chars
 razon VARCHAR(40), -- "preciso", "claro", "incorrecto", "alucina",...

 -- Contexto necesario para reconstruir el ejemplo
 prompt TEXT NOT NULL, -- la pregunta del usuario
 respuesta TEXT NOT NULL, -- la respuesta del asistente
 modelo VARCHAR(40), -- "gemini", "deepseek", "propio:exp02"
 nivel VARCHAR(20), -- "basico", "intermedio", "avanzado"

 fecha TIMESTAMP DEFAULT NOW(),
 procesado BOOLEAN DEFAULT FALSE -- true cuando ya entró al dataset RLHF
);

CREATE INDEX idx_feedback_voto ON feedback(voto);
CREATE INDEX idx_feedback_procesado ON feedback(procesado) WHERE procesado = FALSE;
```

### Endpoint REST

```
POST /api/feedback
Authorization: Bearer <jwt>
Content-Type: application/json

{
 "mensaje_id": "uuid-del-mensaje",
 "voto": 1, // +1 o -1
 "comentario": "Explicó muy bien la diferencia", // opcional
 "razon": "claro" // opcional
}

Response: 201 { "id": "feedback-uuid", "ok": true }
```

---

## 4. Generación automática de pares (RLAIF)

El problema del 👎 puro: si solo guardamos la respuesta rechazada,
**no tenemos** la respuesta preferida con la que compararla. Solución:

### Opción A — Pedir al usuario que regenere

Cuando da 👎, mostrar botón "Regenerar" → la nueva respuesta es la
**candidata preferida**. Si la acepta (👍), guardamos el par
`(y_old=👎, y_new=👍)`.

### Opción B — Juez LLM (Gemini)

Cuando solo hay 👎 sin alternativa, pedirle a **Gemini** que genere una
mejor respuesta para esa misma pregunta. Usamos esa como `y_w`.

```python
# rlhf/generar_pares.py
async def generar_par_desde_negativo(feedback):
 prompt_juez = f"""
La siguiente respuesta a una consulta de un estudiante de Python fue
calificada como deficiente. Por favor genera una respuesta mejorada,
manteniendo el mismo nivel pedagógico que el sistema usa.

Consulta del estudiante:
{feedback.prompt}

Respuesta deficiente:
{feedback.respuesta}

Razón del rechazo: {feedback.razon or "no especificada"}

Respuesta mejorada (estructura: qué hace / por qué / ejemplo / ejercicio):
"""
 mejor = await gemini.generar(prompt_juez)
 return {
 "prompt": feedback.prompt,
 "y_w": mejor,
 "y_l": feedback.respuesta
 }
```

### Opción C — Pares sintéticos desde respuestas premium

Tomar las respuestas con 👍 alto y compararlas con respuestas
**aleatorias** del corpus para esa misma pregunta. Útil para bootstrap
cuando hay poco feedback real.

---

## 5. Formato del dataset DPO

```jsonl
{"prompt": "Explica qué es una list comprehension", "chosen": "Una list comprehension es...", "rejected": "list comp es loop con [..]", "source": "human_feedback"}
{"prompt": "...", "chosen": "...", "rejected": "...", "source": "rlaif_gemini"}
```

Comando para exportar:

```powershell
python rlhf/exportar_dataset.py --salida data/dpo_v1.jsonl --min-pares 100
```

---

## 6. Entrenamiento DPO

```python
# rlhf/dpo.py — esqueleto
from trl import DPOTrainer, DPOConfig
from transformers import AutoModelForCausalLM, AutoTokenizer

config = DPOConfig(
 output_dir="checkpoints/dpo_v1",
 per_device_train_batch_size=2,
 gradient_accumulation_steps=8,
 learning_rate=5e-7, # mucho más bajo que pretraining
 beta=0.1, # ver fórmula DPO
 num_train_epochs=3,
 fp16=True,
)

model = AutoModelForCausalLM.from_pretrained("checkpoints/exp02/best.pt")
model_ref = AutoModelForCausalLM.from_pretrained("checkpoints/exp02/best.pt")
model_ref.eval() # ¡importantísimo!

trainer = DPOTrainer(
 model=model,
 ref_model=model_ref,
 args=config,
 train_dataset=cargar_dataset("data/dpo_v1.jsonl"),
 tokenizer=tokenizer,
)
trainer.train()
```

**Tiempo estimado**: 1-3 horas para 5k pares en RTX 2050.

---

## 7. Métricas a trackear

### Durante entrenamiento DPO
- `loss_dpo` (debe bajar)
- `rewards/chosen` (debe subir)
- `rewards/rejected` (debe bajar)
- `rewards/margins` = chosen - rejected (debe subir)
- `rewards/accuracies` (% de veces que chosen > rejected)

### Post-entrenamiento
- **Win rate** vs modelo base: pasar 100 prompts al modelo base y al
 modelo DPO, pedir a Gemini que elija → calcular % de wins.
- **👍/👎 rate en producción** comparando semanas antes/después del
 deploy.

---

## 8. Timeline realista (proyecto)

| Semana | Hito |
|---|---|
| 1 | Modelo base entrenado (exp02) |
| 2-4 | Recolección de feedback (objetivo: 500+ votos) |
| 5 | Implementar exportador + dataset_rlhf v1 |
| 6 | Primer entrenamiento DPO (dpo_v1) |
| 7 | Evaluación win rate vs exp02 |
| 8 | Iteración: limpiar dataset, re-entrenar (dpo_v2) |
| 9 | Capítulo de RLHF en el documentación del proyecto |

---

## 9. Consideraciones éticas

- **Consentimiento informado**: el usuario sabe que su feedback se usa
 para mejorar el modelo (mostrar aviso al primer 👍/👎).
- **Anonimización**: no asociar feedback con email/nombre — solo
 `usuario_id` UUID.
- **Filtros de contenido**: descartar feedback con prompts ofensivos o
 consultas no-Python.
- **Sesgos**: si solo entrenamos con feedback de estudiantes
 hispanohablantes, el modelo se sesga. Documentar la composición
 demográfica del corpus.

---

## 10. Referencias

- Rafailov et al., **Direct Preference Optimization**, NeurIPS 2023
- Lee et al., **RLAIF: Scaling RL from Human Feedback with AI
 Feedback**, 2023
- HuggingFace `trl` documentation
- AnthropicAI **Constitutional AI** (alternativa con AI judge)
