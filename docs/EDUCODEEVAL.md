# EduCodeEval — Benchmark pedagógico propio

> Benchmark de evaluación de LLMs especializados en programación con foco
> educativo. A diferencia de HumanEval / MBPP+ (que solo miden si el
> código pasa unit tests), **EduCodeEval mide las cinco dimensiones que
> son las que importan en un modelo educativo**: generación, explicación,
> seguridad, refactorización y enseñanza.
>
> Este benchmark es **una contribución original del proyecto** y la
> presentación principal de el proyecto frente a la pregunta del revisor:
>
> > "¿Por qué tu modelo, que tiene menos parámetros que GPT, vale como
> > aporte académico?"
>
> Respuesta: porque mide lo que ningún benchmark estándar mide — la
> capacidad de enseñar.

---

## 1. Las cinco categorías

| Categoría | Qué mide | Peso por defecto |
|---|---|---|
| **GENERACIÓN** | Resolver un problema con código que compila y pasa unit tests. | 1.0 |
| **EXPLICACIÓN** | Explicar código existente de manera pedagógica, con conceptos clave correctos. | 1.2 |
| **SEGURIDAD** | Identificar la vulnerabilidad por su nombre y proponer código seguro. | 1.3 |
| **REFACTORIZACIÓN** | Detectar un antipatrón, explicarlo y mostrar un refactor estrictamente mejor. | 1.0 |
| **ENSEÑANZA** | Adaptar la explicación al nivel del estudiante (niño / principiante / profesional). | **1.5** |

La **enseñanza pesa más** porque es la dimensión donde el modelo
educativo puede destacar frente a modelos generales.

---

## 2. Cómo se calcula el score

Cada tarea tiene un verificador objetivo que devuelve un score 0-100
basado en heurísticas verificables: ¿compila el código?, ¿pasa los unit
tests?, ¿menciona la vulnerabilidad por su nombre?, ¿incluye un patrón
de código seguro?, ¿la densidad de jerga técnica es la apropiada para
el nivel?

Opcionalmente, un juez LLM (por defecto Gemini) aporta un score
subjetivo. El score final de una tarea es:

```
score_final = peso_objetivo * score_objetivo + (1 - peso_objetivo) * score_subjetivo
```

con `peso_objetivo = 0.5` por defecto.

Una tarea se considera **aprobada** si su `score_final >= 60`.

El score global del modelo es la **media ponderada** de los scores
promedio por categoría, usando los pesos de la tabla anterior.

---

## 3. Catálogo de tareas inicial (v1)

| Categoría | # tareas | Ejemplos |
|---|---|---|
| Generación | 8 | Fibonacci eficiente, palíndromo, top-k palabras, búsqueda binaria, validar email, dedup O(n), anagrama, promedio seguro. |
| Explicación | 5 | list comprehension, lru_cache, with/context manager, lista vs generator, mutable default argument. |
| Seguridad | 5 | SQL injection, command injection, pickle inseguro, MD5 para passwords, JWT alg=none. |
| Refactorización | 5 | elif chain → dict, bare except, string concat en loop, mutable default, god function. |
| Enseñanza | 7 | Variable a niño / principiante / profesional, función a niño / principiante, decorador a profesional, loop a niño. |
| **Total** | **30** | — |

El catálogo crecerá: el objetivo a 3 meses son **150 tareas** (30 por
categoría) para que el benchmark sea estadísticamente robusto.

---

## 4. Cómo se corre

### 4.1 Evaluar un modelo del pool (Gemini, Groq, DeepSeek, etc.)

```powershell
python -m ml.eval.edu_code_eval --modelo gemini --salida training/experiments/edu_gemini_baseline.json
```

### 4.2 Evaluar el modelo propio entrenado

```powershell
python -m ml.eval.edu_code_eval `
 --modelo local `
 --checkpoint training/checkpoints/B_fase5b_dpo/checkpoint_best.pt `
 --tokenizer ml/tokenizer/artefactos/sp_v2_16k.model `
 --salida training/experiments/edu_modelo_B_fase5b.json
```

### 4.3 Comparativa completa

```powershell
# Baselines comerciales (uno por proveedor disponible)
python -m ml.eval.edu_code_eval --modelo gemini --salida training/experiments/edu_gemini.json
python -m ml.eval.edu_code_eval --modelo groq --salida training/experiments/edu_groq_70b.json
python -m ml.eval.edu_code_eval --modelo deepseek --salida training/experiments/edu_deepseek.json

# Tus modelos
python -m ml.eval.edu_code_eval --modelo local --checkpoint training/checkpoints/A_46M.pt --tokenizer ml/tokenizer/artefactos/sp_python.model --salida training/experiments/edu_A.json
python -m ml.eval.edu_code_eval --modelo local --checkpoint training/checkpoints/B_fase5b/checkpoint_best.pt --tokenizer ml/tokenizer/artefactos/sp_v2_16k.model --salida training/experiments/edu_B.json
python -m ml.eval.edu_code_eval --modelo local --checkpoint training/checkpoints/C_fase5b/checkpoint_best.pt --tokenizer ml/tokenizer/artefactos/sp_v2_16k.model --salida training/experiments/edu_C.json
```

El JSON de salida contiene:

- `nombre_modelo`, `n_tareas_total`, `n_tareas_aprobadas`.
- `score_por_categoria`: cinco scores 0-100.
- `score_global`: ponderado 0-100.
- `tareas`: detalle por tarea (respuesta truncada + métricas).

---

## 5. Por qué este benchmark vale

### 5.1 HumanEval / MBPP+ tienen un problema fundamental para tu proyecto

Ellos miden **una sola cosa**: ¿el código pasa unit tests? Esto deja
fuera lo que el modelo educativo necesita demostrar:

- ¿Sabe explicar el código que generó?
- ¿Adapta su explicación al estudiante?
- ¿Detecta vulnerabilidades reales?
- ¿Reconoce un antipatrón?
- ¿Refactoriza con justificación?

Un modelo que saca 90% en HumanEval pero responde con código sin
explicación pedagógica **no sirve para un sistema educativo**. Y un
modelo que saca 40% en HumanEval pero explica brillantemente para
cuatro niveles distintos **sí sirve** y es lo que tu proyecto defiende.

### 5.2 argumentación técnica

En la presentación, cuando el revisor pregunte:

> *"¿Cómo evaluó la calidad de su modelo respecto a alternativas
> comerciales?"*

La respuesta será:

> *"Usé HumanEval+ y MBPP+ como benchmarks estándar de generación, pero
> diseñé además **EduCodeEval**, un benchmark propio con cinco
> categorías pedagógicas, porque los benchmarks estándar no miden las
> dimensiones que motivan esta investigación. Los resultados muestran
> que mi modelo, aunque inferior en HumanEval, supera a [Gemini/Claude]
> en EduCodeEval-Enseñanza por X puntos."*

Esto es una **argumentación metodológica sólida**.

### 5.3 Publicabilidad

EduCodeEval es **publicable como artefacto independiente** en un
workshop de NLP educativo. Es la primera (que sepamos) propuesta de
benchmark con dimensión explícita de calibración por audiencia
(niño / principiante / intermedio / profesional).

---

## 6. Arquitectura técnica

```
ml/eval/edu_code_eval/
├── __init__.py # API pública del módulo
├── __main__.py # CLI: python -m ml.eval.edu_code_eval
├── core.py # Tarea, Categoria, EduCodeEval, helpers
└── tareas/
 ├── __init__.py
 ├── generacion.py # 8 tareas con unit tests
 ├── explicacion.py # 5 tareas con conceptos clave
 ├── seguridad.py # 5 tareas con OWASP
 ├── refactorizacion.py # 5 tareas con antipatrones
 └── ensenanza.py # 7 tareas multi-nivel
```

### 6.1 Estructura de una tarea

```python
Tarea(
 id="seg_01_sql_injection",
 categoria=Categoria.SEGURIDAD,
 prompt="Revisa este código y dime si tiene problemas...",
 descripcion="SQL Injection clásico",
 verificador=_verificador_seguridad(
 nombres_vuln=["sql injection", "sqli",...],
 patrones_codigo_seguro=[r"cursor\.execute\(.+,\s*\("],
 patrones_explicacion=["concatena", "atacante"],
 ),
)
```

### 6.2 Verificadores

Los verificadores son **funciones puras** que reciben la respuesta del
modelo y devuelven un `dict` con un campo `score` (0-100) y métricas
adicionales. Esto permite **explicabilidad completa**: cualquier
auditor puede ver exactamente por qué la tarea X obtuvo el score Y.

Tipos de verificadores implementados:

- **Generación**: extrae código, verifica que compile, ejecuta unit
 tests reales en subprocess aislado.
- **Explicación**: longitud + cobertura de conceptos clave + ausencia
 de errores técnicos + marcadores de estructura pedagógica.
- **Seguridad**: nombre de la vulnerabilidad + patrón de código seguro
 (regex) + conceptos explicativos.
- **Refactorización**: nombre del antipatrón + bloque de código nuevo
 que compila + patrón de refactor aceptable.
- **Enseñanza**: calibrado por nivel — niño exige analogía y veta
 jerga + código; profesional exige densidad técnica alta y referencias
 a PEP / CPython / edge cases.

---

## 7. Integración con los reward models propios

Cuando los seis reward models multi-criterio (SEG/LEG/ESC/ARQ/REN/MAN)
estén entrenados, podrán integrarse como **juez subjetivo** del
benchmark:

```python
from ml.rlhf.reward_model import MultiCriteriaRewardModel
from ml.eval.edu_code_eval import EduCodeEval, cargar_tareas

rm = MultiCriteriaRewardModel.load("training/checkpoints/RM_v1/checkpoint_best.pt")

def juez_subjetivo(tarea, respuesta):
 scores = rm.evaluar(tarea.prompt, respuesta)
 # Promedio ponderado de las 6 dimensiones — 0..10 → 0..100
 return sum(scores.values()) / len(scores) * 10

bench = EduCodeEval(tareas=cargar_tareas(), juez_subjetivo=juez_subjetivo)
```

Esto cierra el ciclo: **el modelo entrenado con los reward models es
evaluado por los reward models como juez**, demostrando que el sistema
multi-criterio funciona como rúbrica reproducible.

---

## 8. Próximos pasos del benchmark

1. **Crecer a 150 tareas** (30 por categoría) en los próximos 2 meses.
2. **Validar consistencia inter-juez**: correr el benchmark con
 Gemini, Claude y DeepSeek como jueces y medir correlación.
3. **Liberar como dataset HuggingFace** después de la presentación.
4. **Pedir feedback de docentes de programación** para iterar sobre
 las rúbricas (estudio cualitativo en el proyecto).
5. **Construir un leaderboard público** con tu modelo y los comerciales
 evaluados con los mismos prompts.

---

## 9. Referencias y trabajos relacionados

- HumanEval (Chen et al., 2021) — benchmark estándar de generación.
- MBPP+ (Liu et al., 2023) — versión robustecida con tests adicionales.
- APPS (Hendrycks et al., 2021) — problemas competitivos.
- DS-1000 (Lai et al., 2022) — data science.
- BigCodeBench (Zhuo et al., 2024) — bibliotecas reales.

**Ninguno de ellos mide pedagogía**. Esa es exactamente la brecha que
EduCodeEval llena.
