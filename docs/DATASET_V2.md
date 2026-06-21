# Dataset V2 — Pipeline pedagógico multi-nivel + recursos gratuitos

> Extensión del dataset existente (`ml/data/`) para llegar al nivel de un
> modelo educativo "senior". Esta versión NO reemplaza lo que hay: lo
> amplía con tipos nuevos y un schema enriquecido. Mantiene compatibilidad
> con el corpus actual de 187k ejemplos.
>
> **Filosofía clave** (validada en investigación 2024-2025): la calidad
> del dataset domina sobre la cantidad de parámetros. 500k ejemplos de
> alta calidad superan a 100M de baja calidad. Por eso esta es la pieza
> crítica de el proyecto — más que el entrenamiento mismo.

---

## 1. Schema extendido (`ml/data/schema.py` v2)

El schema actual (instruccion/entrada/salida/nivel/tema/tipo) se mantiene
para retro-compatibilidad. Se agregan campos opcionales:

```python
@dataclass(slots=True)
class EjemploEntrenamiento:
 # === campos v1 (sin cambio) ===
 instruccion: str
 salida: str
 entrada: str = ""
 nivel: str = "basico"
 tema: str = "otro"
 tipo: str = "explicacion_codigo"
 fuente: str = "semilla"
 metadata: dict = field(default_factory=dict)

 # === campos v2 (nuevos, todos opcionales) ===
 pensamiento: str | None = None # chain-of-thought del programador
 explicacion_por_nivel: dict | None = None # {niño, principiante, intermedio, profesional}
 alternativas: list[dict] | None = None # otras soluciones consideradas y por qué se descartaron
 errores_comunes: list[str] | None = None # qué suele equivocarse un estudiante aquí
 revision_codigo: dict | None = None # crítica del código + versión mejorada
 puntuacion: dict | None = None # 6 criterios 0-10 (ver REWARD_MODELS.md)
 version_evolutiva: str | None = None # "v1_junior" | "v2_junior_plus" |... | "v5_staff"
 tags: list[str] = field(default_factory=list) # libres: "concurrencia", "seguridad", "async"
```

**Por qué opcionales**: cada tipo de dataset usa solo el subset que le
aplica. Un ejemplo "anti-patrón" usa `revision_codigo`. Un ejemplo
"chain-of-thought" usa `pensamiento`. Un ejemplo "evolución" usa
`version_evolutiva`. El trainer ignora campos `None`.

---

## 2. Los 9 tipos de dataset (lo que falta vs lo existente)

Los `TIPOS` actuales son 7. Se agregan estos para alcanzar el nivel
pedagógico del modelo. Cada tipo tiene su pipeline de generación.

### 2.1 `pensamiento_programador` (chain-of-thought)

Cada ejemplo NO solo tiene input/output. Captura el proceso mental:

```json
{
 "instruccion": "Crea una API REST para una tienda online",
 "pensamiento": {
 "aclaraciones": ["¿productos digitales o físicos?", "¿stock o catálogo abierto?"],
 "restricciones_implicitas": ["asumo CRUD básico", "asumo auth JWT", "asumo PostgreSQL"],
 "alternativas_consideradas": [
 {"opcion": "FastAPI", "elegida": true, "razon": "type hints + auto docs + async"},
 {"opcion": "Django REST", "elegida": false, "razon": "exceso para CRUD simple"},
 {"opcion": "Flask + Marshmallow", "elegida": false, "razon": "menos type safety"}
 ],
 "criterios_decision": ["mantenibilidad", "rapidez de desarrollo", "type safety"]
 },
 "salida": "...código + arquitectura + explicación..."
}
```

**Pipeline de generación** (`ml/data/generar_pensamiento.py`):
- Para cada prompt complejo del corpus, llamar a Gemini con prompt
 estructurado que pida explícitamente las 4 secciones del pensamiento.
- Validar que cada sección tenga al menos N items.
- Guardar.

**Por qué importa**: lo que diferencia a Claude/GPT-4/Gemini de los
modelos open de hace 2 años no es el tamaño, es que entrenaron con CoT.
Esto es el secreto público.

**Volumen objetivo**: 30k ejemplos.

### 2.2 `explicacion_multinivel`

Mismo concepto, 4 explicaciones distintas según audiencia:

```json
{
 "instruccion": "Explica qué es una list comprehension",
 "explicacion_por_nivel": {
 "nino": "Imagina que tienes una caja de juguetes y quieres una nueva caja solo con los rojos. Eso es lo que hace.",
 "principiante": "Una list comprehension es una forma compacta de crear una lista nueva a partir de otra, en una sola línea. Por ejemplo: [x*2 for x in numeros]",
 "intermedio": "Sintaxis [expresión for variable in iterable if condición]. Equivale a un for-loop con.append(), pero el intérprete lo optimiza con una sola asignación de tamaño. ~2× más rápido en benchmarks.",
 "profesional": "Azúcar sintáctica para map+filter sobre iterables. Genera bytecode LIST_APPEND más eficiente que.append() en loop. Cuidado con NESTED — sobrepasar 2 niveles afecta legibilidad. Para datasets grandes preferir generator expression (paréntesis) por evaluación perezosa."
 }
}
```

**Por qué**: enseñar a estudiantes de distintos niveles desde un mismo
modelo. El backend ya tiene niveles (`nivel: basico/intermedio/avanzado`);
esto es la versión 4-niveles con foco didáctico.

**Volumen objetivo**: 8k conceptos × 4 niveles = 32k explicaciones.

### 2.3 `anti_patron_explicado`

Código que funciona pero es malo. Esto rara vez está en corpus open.

```json
{
 "instruccion": "Refactoriza este código de validación de usuarios",
 "entrada": "if user.role == 'admin':\n can_edit = True\nelif user.role == 'editor':\n can_edit = True\nelif user.role == 'viewer':\n can_edit = False\n#... 20 más",
 "salida": "PERMISOS = {'admin': True, 'editor': True, 'viewer': False,...}\ncan_edit = PERMISOS.get(user.role, False)",
 "revision_codigo": {
 "problemas": [
 "Cadena de elif que crece linealmente con cada rol",
 "Cambiar un permiso requiere modificar código en vez de configuración",
 "Difícil de testear: no se puede parametrizar"
 ],
 "por_que_funciona_pero_es_malo": "El cliente nunca verá un error. Pero al llegar a 50 roles tendrás 50 elif y bugs por copy-paste.",
 "problema_en_produccion": "Cuando legal pida un nuevo rol mañana, será otro deploy. Si se quisiera leer permisos de BD, hay que reescribir todo."
 },
 "tema": "refactorizacion",
 "nivel": "intermedio"
}
```

**Pipeline**: dataset semilla con 200 antipatrones canónicos
(condicionales en cadena, deep nesting, magic numbers, mutable default
args, bare except, etc.). Por cada uno, generar 50 variantes con Gemini.

**Volumen objetivo**: 10k ejemplos.

### 2.4 `bug_sutil` (lo que enseña ojo de senior)

NO errores de sintaxis. Bugs lógicos que un junior no ve.

```json
{
 "instruccion": "Revisa esta función. ¿Tiene algún problema?",
 "entrada": "def promedio(nums):\n return sum(nums) / len(nums)",
 "salida": "Sí, dos bugs sutiles:\n1. ZeroDivisionError si la lista está vacía.\n2. Inestabilidad numérica con listas muy grandes (sum acumula error fp).\n\nVersión robusta:\n\nfrom statistics import mean\ndef promedio(nums):\n if not nums:\n raise ValueError('lista vacía')\n return mean(nums)",
 "tema": "debugging",
 "nivel": "intermedio",
 "tags": ["bugs_sutiles", "numerica", "edge_cases"]
}
```

**Pipeline**: lista de 50 categorías de bugs canónicos
(off-by-one, integer overflow, race conditions, mutable defaults,
encoding bugs, timezone bugs, floating-point comparison, etc.). Por
cada categoría, generar variantes.

**Volumen objetivo**: 15k ejemplos.

### 2.5 `evolucion_codigo` (v1 → v5)

Mismo problema, 5 niveles de código:

```json
{
 "instruccion": "Endpoint para crear un usuario",
 "version_evolutiva": "v1_junior",
 "salida": "@app.post('/user')\ndef create_user(data):\n db.users.insert(data)\n return {'ok': True}"
}
```

Y luego v2, v3, v4, v5 del mismo prompt:
- **v1_junior**: funciona y ya.
- **v2_junior_plus**: con validación básica de input.
- **v3_mid**: + try/except + status codes + Pydantic.
- **v4_senior**: + dependency injection + repository pattern + tests.
- **v5_staff**: + idempotency key + rate limit + observability + retry strategy + auditoría.

**Por qué**: el modelo aprende qué significa "mejor código" como
gradiente, no como dicotomía bueno/malo.

**Volumen objetivo**: 5k problemas × 5 versiones = 25k ejemplos.

### 2.6 `decision_diseno`

```json
{
 "instruccion": "¿Por qué usar PostgreSQL y no MongoDB para una API de e-commerce?",
 "salida": "...",
 "pensamiento": {
 "criterios_decision": ["transacciones ACID", "modelo relacional natural", "queries complejas", "escalabilidad", "ecosistema"],
 "alternativas_consideradas": [
 {"opcion": "PostgreSQL", "elegida": true, "razon": "transacciones, JOINs, JSONB para flex"},
 {"opcion": "MongoDB", "elegida": false, "razon": "transacciones limitadas, JOINs costosos, schema drift"},
 {"opcion": "SQLite", "elegida": false, "razon": "no escala concurrencia escritura"}
 ]
 }
}
```

**Pipeline**: 200 decisiones canónicas (BD, framework web, ORM,
auth, queue, cache, deploy target, lenguaje del backend, etc.) por 30
variantes de pregunta.

**Volumen objetivo**: 6k ejemplos.

### 2.7 `arquitectura_sistema`

```json
{
 "instruccion": "Red social para 1 millón de usuarios. Diseña la arquitectura.",
 "salida": "{diagrama textual + componentes + flujo + tradeoffs}",
 "pensamiento": {
 "restricciones_implicitas": ["latencia < 200ms", "99.9% uptime", "costo razonable"],
 "alternativas_consideradas": [...],
 "criterios_decision": ["escalabilidad", "consistencia", "costo", "complejidad operativa"]
 }
}
```

**Volumen objetivo**: 3k ejemplos (caro de generar bien).

### 2.8 `seguridad` (OWASP enfocado)

```json
{
 "instruccion": "Revisa este endpoint",
 "entrada": "query = f\"SELECT * FROM users WHERE id={id}\"\ncursor.execute(query)",
 "salida": "SQL Injection — un input id=`1 OR 1=1` lee toda la tabla.\n\nVersión segura:\ncursor.execute(\"SELECT * FROM users WHERE id=%s\", (id,))",
 "tags": ["owasp_a03", "sql_injection"],
 "tema": "seguridad"
}
```

Cubrir las 10 categorías OWASP + criptografía + auth + secrets + supply
chain.

**Volumen objetivo**: 15k ejemplos.

### 2.9 `testing_y_complejidad`

```json
{
 "instruccion": "Escribe tests para esta función + analiza complejidad",
 "entrada": "def buscar(lista, x):...",
 "salida": "{unit tests + integration test + edge cases + análisis O(n) + benchmark}"
}
```

**Volumen objetivo**: 10k ejemplos.

---

## 3. Mezcla del corpus final

Para llegar al nivel "modelo senior":

| Tipo | Volumen objetivo | Origen |
|---|---|---|
| Tipos v1 actuales (instrucción → respuesta) | 187k existentes | corpus actual |
| `pensamiento_programador` | 30k | Gemini + DeepSeek |
| `explicacion_multinivel` | 32k | Gemini |
| `anti_patron_explicado` | 10k | semilla + Gemini |
| `bug_sutil` | 15k | semilla + Gemini |
| `evolucion_codigo` | 25k | Gemini structurado |
| `decision_diseno` | 6k | Gemini + DeepSeek |
| `arquitectura_sistema` | 3k | Gemini (cuidadoso) |
| `seguridad` | 15k | semilla OWASP + Gemini |
| `testing_y_complejidad` | 10k | semilla + Gemini |
| **TOTAL nuevo** | **~146k** | |
| **CORPUS TOTAL final** | **~333k** | |

Distribución en entrenamiento (peso al samplear):

```
25% código + explicación (v1 actual)
20% pensamiento_programador
15% seguridad + bugs_sutiles
10% anti_patron + evolucion
10% explicacion_multinivel
10% decision + arquitectura
5% testing
5% misc
```

---

## 4. Pipeline de generación con APIs gratuitas

### 4.1 Tiers gratuitos identificados

| Proveedor | Free tier | Útil para |
|---|---|---|
| **Google Gemini** | 15 req/min, 1500 req/día, 1M token/min `gemini-2.0-flash` | Generación masiva CoT, RLAIF juez |
| **DeepSeek** | $5 USD crédito al registrar (~10M tokens) | Generación de código (mejor que Gemini en code) |
| **Together AI** | $25 USD crédito gratis | Llama 3.3 70B, modelos open |
| **Groq** | 30 req/min Llama 3.3 70B | Generación rápida |
| **Mistral La Plateforme** | tier free | Mistral Large |
| **OpenRouter** | algunos modelos free (Llama 3.1 8B, Gemma) | Fallback |
| **HuggingFace Inference API** | rate-limited free | Cualquier modelo open |

### 4.2 Estrategia de uso (rotación)

`ml/data/pool_generadores.py` (nuevo módulo):

```python
GENERADORES_FREE = [
 {"nombre": "gemini-flash", "rpm": 15, "rpd": 1500, "calidad_cot": 9, "calidad_code": 8},
 {"nombre": "deepseek-chat", "rpm": 60, "rpd": 5000, "calidad_cot": 8, "calidad_code": 9},
 {"nombre": "groq-llama-3.3-70b", "rpm": 30, "rpd": 14400, "calidad_cot": 8, "calidad_code": 7},
 {"nombre": "together-llama-3.3-70b", "rpm": 60, "rpd": 1000, "calidad_cot": 8, "calidad_code": 8},
 {"nombre": "mistral-large", "rpm": 30, "rpd": 1000, "calidad_cot": 8, "calidad_code": 7},
]
```

El generador rota proveedores según rate limit, prioriza calidad por
tarea. Para `pensamiento_programador` usa Gemini (mejor CoT). Para
`evolucion_codigo` usa DeepSeek (mejor code). Para volumen masivo usa
Groq (límites altos).

**Capacidad real estimada**: con 5 proveedores en paralelo y rotación
inteligente → 50k-100k ejemplos/semana sin pagar nada.

### 4.3 Validación automática (crítico)

Cada ejemplo generado pasa por validadores:

```python
# ml/data/validadores.py
def validar_codigo(salida: str) -> tuple[bool, str]:
 """Que el código compile (ast.parse), que tenga structure mínima."""
def validar_tests(salida: str) -> tuple[bool, str]:
 """Que los tests generados PASEN al ejecutarse en sandbox."""
def validar_cot(pensamiento: dict) -> tuple[bool, str]:
 """Que tenga las 4 secciones, que tengan contenido > N chars."""
def validar_decision(salida: str) -> tuple[bool, str]:
 """Que mencione al menos 2 alternativas con razón."""
```

Sin esto, el dataset se llena de basura de los LLMs free (más
alucinaciones que los pagos).

---

## 5. Datos públicos que NO podemos perdernos

Además de generación con APIs, integrar estos corpus open:

| Dataset | Tamaño | Por qué |
|---|---|---|
| **The Stack v2** (BigCode) | 800GB de código | Pretraining real |
| **CodeAlpaca-20k-es** | 20k | Ya incluido |
| **CodeFeedback-Filtered** | 156k | Ya incluido |
| **MBPP / MBPP+** | 1k | Ya incluido (HumanEval) |
| **HumanEval / HumanEvalPlus** | 164 problemas | Para benchmark |
| **BigCodeBench** | 1k tests reales | Benchmark más serio |
| **Magicoder OSS-Instruct** | 75k | High quality code instructions |
| **DS-1000** | 1k problemas data science Python | Especialización |
| **APPS** | 10k problemas competitivos | Para razonamiento difícil |
| **WizardCoder evol** | 78k | Instruction evolution |
| **OpenCodeInterpreter** | 68k | Code + execution feedback |
| **Python-Doc-instruct** (custom) | scraping de docs.python.org | Conocimiento puro |

Script `ml/data/descargar_publicos.py` (extender `download_hf.py`):

```python
DATASETS_OBJETIVO = [
 ("bigcode/the-stack-v2", "python", "sample_1pct"), # 8GB Python only
 ("ise-uiuc/Magicoder-OSS-Instruct-75K", None, None),
 ("ise-uiuc/Magicoder-Evol-Instruct-110K", None, None),
 ("HuggingFaceH4/MATH-500", None, None), # razonamiento numérico
 ("codeparrot/apps", "all", None),
 ("nuprl/MultiPL-E", "python", None), # eval cross-lingual
]
```

---

## 6. Actualización continua (lo que pediste explícitamente)

El sistema debe mantenerse al día. Esquema:

### 6.1 Crawler de documentación oficial

`ml/data/crawler_docs.py` (cron mensual):

```python
FUENTES_DOC = {
 "python_docs": "https://docs.python.org/3/",
 "fastapi": "https://fastapi.tiangolo.com/",
 "django": "https://docs.djangoproject.com/en/stable/",
 "postgres": "https://www.postgresql.org/docs/current/",
 "react": "https://react.dev/reference/react",
 "pep_index": "https://peps.python.org/api/peps.json",
 "mdn": "https://developer.mozilla.org/en-US/docs/Web/",
}
```

Cada mes corre, detecta páginas nuevas/modificadas (diff vs hash
anterior), las indexa al RAG, y selecciona las top 100 más relevantes
para generar dataset incremental con Gemini.

### 6.2 Crawler de novedades

- **GitHub Trending Python** (semanal): top 20 repos, README, ejemplos
- **Hacker News programación**: artículos top con keyword python/js/go
- **PEPs nuevas**: cada PEP "Final" o "Accepted" → dataset de explicación
- **Release notes** de Python (3.13 → 3.14, etc.) → dataset de "qué cambió"

### 6.3 Re-entrenamiento incremental

No se re-entrena desde cero cada mes. Esquema:
- Continued pretraining sobre el checkpoint más reciente con el
 delta-corpus del mes (~5k-10k ejemplos nuevos).
- LoRA específico para la actualización (se puede merge o servir como
 adapter).
- Mensual.

---

## 7. Métricas de calidad del dataset

Antes de entrenar, validar:

```bash
python -m ml.data.audit --corpus data/dataset_v2.jsonl
```

Reporta:

| Métrica | Objetivo | Por qué |
|---|---|---|
| % ejemplos válidos (`es_valido()`) | > 98% | Si no, hay leak de basura |
| Duplicados | < 1% | Dedup por hash de prompt |
| Distribución de tipos | Como tabla §3 | Sin sobrerepresentación |
| Distribución de niveles | Aprox. 40/40/20 (basico/intermedio/avanzado) | Currículo balanceado |
| Distribución de temas | Sin tema > 25% | Sin sesgo |
| Longitud promedio de salida | 200-1500 tokens | Ni truncado ni verboso |
| % con `pensamiento` poblado | > 30% del corpus final | CoT es el diferenciador |
| % código que compila (`ast.parse` OK) | > 95% | Validación de calidad técnica |
| % bilingüismo es/en | 90% es, 10% en | Proyecto es en español pero el código suele ser en inglés |

---

## 8. Plan de ejecución (mes 1)

| Semana | Trabajo |
|---|---|
| 1 | Extender `schema.py` v2; implementar validadores (`ml/data/validadores.py`); crear `pool_generadores.py` |
| 1 | Descargar todos los corpus públicos (§5) |
| 2 | Pipeline `generar_pensamiento.py` + `generar_multinivel.py`; generar 10k de cada |
| 2 | Pipeline `generar_antipatron.py` + `generar_bug_sutil.py`; seed manual de 200 + 50 categorías |
| 3 | Pipeline `generar_evolucion.py` + `generar_decision.py`; generar volúmenes objetivo |
| 3 | Pipeline `generar_seguridad.py` (OWASP) + `generar_arquitectura.py` |
| 4 | Auditoría completa (`ml.data.audit`); rebalance; export `data/dataset_v2.jsonl` |
| 4 | Re-entrenar tokenizer sentencepiece sobre corpus v2; benchmark coverage |

**Salida del mes 1**: `data/dataset_v2.jsonl` (~333k ejemplos validados)
+ `data/dpo_pares_v2.jsonl` (~30k pares) + tokenizer actualizado.

---

## 9. Integración con lo que ya existe

- **`ml/data/schema.py`**: extender (no romper). Campos nuevos opcionales.
- **`ml/data/generator.py`**: refactorizar para usar `pool_generadores.py`.
- **`ml/data/combinar.py`**: ya hace dedup, extender para v2.
- **`ml/rlhf/preparar_pares.py`**: agregar `--criterio` para separar
 pares por dimensión (seguridad, legibilidad, etc.). Ver
 [REWARD_MODELS.md](./REWARD_MODELS.md).
- **`docs/ENTRENAMIENTO.md`**: actualizar §3 cuando cambie el pipeline.

---

## 10. Referencias

- Wang et al., **Self-Instruct**, 2023 — base de generación con LLM
- Luo et al., **WizardCoder**, 2023 — evolución de instrucciones
- Wei et al., **Chain-of-Thought Prompting**, NeurIPS 2022 — base del CoT
- Lee et al., **RLAIF: Scaling RL from Human Feedback with AI Feedback**, 2023
- Wei et al., **Magicoder: Source Code Is All You Need**, 2024 — OSS-Instruct
