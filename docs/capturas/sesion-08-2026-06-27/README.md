# Sesión 8 — Revisión del modelo B v1 + lanzamiento del v2

**Fecha**: 2026-06-27
**Días transcurridos desde la sesión 7**: 5
**Lugar**: Lightning AI Studio (a confirmar estado)

---

## Contexto al iniciar la sesión

La última vez que tocamos el proyecto (2026-06-22), había **tres
procesos corriendo en paralelo** en Lightning AI:

1. **Modelo B v1 (150M)** entrenando, PID 7961, ETA 15 horas.
2. **Dataset V2 escala media** generando, PID a confirmar, ETA 3-5 horas.
3. **Corpus ampliado** ya guardado en `/tmp/corpus_v2_ampliado.jsonl`.

Han pasado **5 días enteros** desde entonces. Esperamos que:

- Modelo B v1 **terminó hace tiempo** (sobrepasó 15h por ~105 horas).
- Dataset V2 media **debería haber terminado** o crasheado (sin
  recovery, ya estaría parado).
- Si Lightning suspendió el Studio por inactividad, los procesos
  murieron pero los archivos en disco persisten (excepto `/tmp/`).

---

## Plan de la sesión

### Bloque 1 — Diagnóstico (capturar todo)

1. **Captura 01**: estado del Studio al entrar (panel de Lightning,
   GPU activa o suspendida).
2. **Captura 02**: `ps aux | grep -E "(run_fase|construir_dataset)"`
   — ¿qué procesos siguen vivos?
3. **Captura 03**: `tail -50 entrenamiento_B.log` — ¿terminó el
   entrenamiento? ¿en qué loss?
4. **Captura 04**: `tail -50 dataset_v2_media.log` — ¿cuántos ejemplos
   generó el dataset V2?
5. **Captura 05**: `ls -la training/checkpoints/B_sft_5k/` —
   ¿checkpoint final guardado?
6. **Captura 06**: `cat training/checkpoints/B_sft_5k/metrics.jsonl
   | tail -20` — métricas finales.
7. **Captura 07**: `ls -la datasets/raw/` — estado del dataset V2.

### Bloque 2 — Inferencia del modelo B v1

8. **Captura 08**: comando de inferencia + primer respuesta del modelo.
9. **Captura 09**: 3-5 ejemplos de generación (instrucciones distintas).
10. **Captura 10**: observación de calidad (¿coherente? ¿en español?
    ¿genera código?).

### Bloque 3 — Decisión sobre el modelo B v2

11. **Captura 11**: si decide lanzar v2, el nuevo config YAML.
12. **Captura 12**: lanzamiento con `nohup` + PID.
13. **Captura 13**: primeros logs del v2 (modelo cargado, primer paso).

---

## Capturas tomadas en esta sesión

| # | Archivo | Qué muestra |
|---|---|---|
| 01 | `01-studio-git-pull.png` | Studio Lightning activo (GPU T4 visible). Salida de `git pull` trayendo el commit `eb24603` con la nueva estructura `docs/capturas/`. |
| 02 | `02-procesos-y-log-entrenamiento.png` | Resultado de `ps aux \| grep run_fase` (sin output = NO hay proceso corriendo). `tail -50 entrenamiento_B.log` mostrando pasos 3900-4600 con loss bajando 2.16 → 1.88. |
| 03 | `03-modelo-b-v1-terminado-checkpoint.png` | Logs finales del entrenamiento — `[done] paso=5000 checkpoint final: training/checkpoints/B_sft_5k/checkpoint_ultimo.pt`. Loss final: **1.8651**. `ls -lh` mostrando `checkpoint_ultimo.pt` de 1.7 GB. |
| 04 | `04-metricas-inicio-vs-final.png` | `metrics.jsonl` INICIO (paso 25 loss=8.65 → paso 125 loss=6.03) vs FINAL (paso 4775 loss=1.93 → paso 5000 loss=1.86). |
| 05 | `05-dataset-v2-atorado-rate-limit.png` | Generador V2 atorado en bucle de 429 (rate limit) de Groq. `ls` de `datasets/raw/` mostrando: pensamiento_v1.jsonl 71K, decision_v1.jsonl 19K, seguridad_v1.jsonl 15K, multinivel_v1.jsonl 6K, arquitectura_v1.jsonl 4.4K, antipatron_v1.jsonl 2.5K, bug_sutil_v1.jsonl 0 (vacío), evolucion_v1.jsonl 0 (vacío). |
| 06 | `06-buscar-script-inferencia.png` | `ls ml/ \| grep -iE "(infer\|generate\|chat)"` revelando que existen `ml/generate.py` (script V1) y la carpeta `ml/inference/` (engine V1). Confirma que NO había script de inferencia compatible con la arquitectura V2 — por eso se crea `ml/inferencia/generar_v2.py`. |
| 07 | `07-git-pull-pkill-pip.png` | Tres acciones en una línea: (1) `git pull` que trae los commits `eb24603..346c7c5` (sistema de capturas + scripts de automatización: 4 archivos, 509 líneas). (2) `pkill -9 -f construir_dataset_v2` que retorna sin matar nada porque el proceso V2 ya no estaba vivo (probablemente Lightning lo mató por inactividad días antes). (3) `pip install -q sentencepiece` exitoso. Terminal lista para ejecutar la inferencia. |
| 08 | `08-inferencia-setup-y-prueba-1.png` | Setup del modelo + Prueba 1. Modelo cargado: 150,725,376 params en 4.6s. Arquitectura: n_layer=16, n_embd=768, vocab=16000, block_size=1024. Tokenizer cargado. **Prueba 1 (promedio)**: el modelo NO genera función de promedio — escribe filter_list. Velocidad: 39.1 tok/s. |
| 09 | `09-inferencia-pruebas-2-y-3.png` | **Prueba 2 (list comprehension a niño)**: respuesta en inglés con regex sin sentido. **Prueba 3 (refactor)**: bucle de alucinación con `if len(result) == 0` repetido cuatro veces. |
| 10 | `10-inferencia-pruebas-3-y-4.png` | Continuación Prueba 3 + **Prueba 4 (bug detection)**: inventa función `twar(lista)`, no detecta el bug real. Velocidad consistente 43-45 tok/s. |
| 11 | `11-inferencia-pruebas-5-y-6.png` | **Prueba 5 (SQL injection)**: sugiere `pytz` y `subprocess`, cero detección de vulnerabilidad. **Prueba 6 (decorador en español)**: responde en INGLÉS sobre `find_find_find` — confirma que el modelo no aprendió español ni el concepto. |
| 12 | `12-dataset-v2-completar-lanzado.png` | `nohup python -m ml.data.construir_dataset_v2 --salida-dir datasets/raw --escala media > dataset_v2_completar.log 2>&1 &` — lanzado en background, PID 34704. Sin `--reset` para no borrar los generadores que ya tienen datos (pensamiento, decision, seguridad, etc.). |
| 13 | `13-educodeeval-inicio-y-primeras-tareas.png` | Setup EduCodeEval contra el checkpoint del modelo B v1. **30 tareas** iniciando. Primeras 2 tareas: `gen_01_fibonacci` FAIL (10.0), `gen_02_palindromo` FAIL (10.0). |
| 14 | `14-educodeeval-scores-tareas-detalle.png` | Detalle por tarea: seguridad (`seg_03_pickle_inseguro`, `seg_04_password_hashing`, `seg_05_jwt_alg_none`) todos con `obj=0.0 FAIL`. Refactorización: `ref_01_elif_chain_a_dict` **65.0 OK** (la única refactor aprobada). Enseñanza: `ens_01_variable_nino` **70.0 OK** y `ens_04_funcion_nino` **70.0 OK** (las dos OK son de "nivel niño"). |
| 15 | `15-educodeeval-resultado-global-23-78.png` | **RESULTADO GLOBAL del modelo B v1**: tareas aprobadas 3/30 (10.0%). Score por categoría: enseñanza 37.86, refactorización 35.00, explicación 33.20, generación 10.00, seguridad 0.80. **Score global: 23.78 / 100**. JSON guardado en `training/experiments/edu_modelo_b_v1.json`. |
| 16 | `16-git-pull-y-corpus-ampliado.png` | `git pull` trayendo el commit `abd6cc9` (3 archivos: EXPERIMENTOS.md +80, capturas README +303, b_sft_15k.yaml +69). Después `cat datasets/publicos/*.jsonl datasets/raw/*.jsonl > /tmp/corpus_v2_ampliado.jsonl`. Resultado: **882,961 ejemplos** consolidados (incluye los V2 generados), **2.0 GB**. |
| 17 | `17-modelo-b-v2-lanzado-nohup.png` | Lanzamiento del modelo B v2: `nohup python -m ml.training.run_fase --config ml/training/configs/b_sft_15k.yaml > entrenamiento_B_v2.log 2>&1 &`. PID asignado: **10064**. Archivo `entrenamiento_B_v2.log` creado en el directorio. |
| 18 | `18-modelo-b-v2-proceso-vivo-y-setup.png` | Confirmación: 2 procesos vivos (10064 bash wrapper, **10074 python real consumiendo 99.3% CPU y 18 GB RAM**). Setup del modelo cargado correctamente: `[train] modelo 150.7M params device=cuda dtype=bfloat16 amp=True gc=True` + `[train] total_pasos=15000 batch=2 grad_accum=8 lr=0.0002`. |

---

## Salida textual completa de la suite

(Para análisis detallado — el output del comando se guarda integro como referencia.)

```
[device] cuda
[cuda] Tesla T4 — 15.6 GB total
[cargando] training/checkpoints/B_sft_5k/checkpoint_ultimo.pt
[modelo] 150,725,376 params en 4.6s
[arquitectura] n_layer=16 n_embd=768 vocab=16000 block_size=1024
[cargando] ml/tokenizer/artefactos/sp_v2_16k.model
[tokenizer] vocab=16000

======================================================================
  SUITE DE PRUEBAS PEDAGOGICAS — modelo B v1
======================================================================

[Prueba 1/6] Generacion basica
PROMPT: Escribe una funcion Python que reciba una lista de numeros y
devuelva el promedio.
RESPUESTA:
The following Python script will output a list of all possible lists
of lists.

```python
# Function to filter out the lists
def filter_list(lst):
    return [x for x in lst if x != 0]

print(filter_list([]))
```

When you run this script, it will output:

```python
[3, 3, 5, 7, 9]
```

(200 tokens en 5.11s = 39.1 tok/s)

──────────────────────────────────────────────────────────────────────

[Prueba 2/6] Explicacion pedagogica
PROMPT: Explicame que es una list comprehension en Python, como si
tuviera 12 anos.
RESPUESTA:
Sure, here is a simple Python script that uses the `re` module to
achieve the desired result.

```python
import re

def get_pattern(text):
    pattern = r'\d{3,}?\d{2,}?\d{2,}?\d{3,}\d{2,}?\d{3,}?\d{3,}?\d{3,}?
    \d{3,}?\d{3,}?\d{3,}?\d{3,}?\d{3,}?\d{3,}?\d{3,}?\d{3,}?\d{3,}?
    [...repite indefinidamente...]
```

(200 tokens en 4.37s = 45.8 tok/s)

──────────────────────────────────────────────────────────────────────

[Prueba 3/6] Refactor
PROMPT: Refactoriza este codigo para que sea mas pythonico:

resultado = []
for i in range(10):
    if i % 2 == 0:
        resultado.append(i * i)

RESPUESTA:
Here is a Python solution for your problem:

```python
def process_result(result):
    # Check if the result is a list
    if not result:
        return []

    # Check if the list has only one element
    if len(result) == 0:
        return []

    # Check if the list has at least one element
    if len(result) == 0:
        return []

    # Check if the list has at least one element
    if not is_prime(result):
        return []

    # Check if the list has at least one element
    if len(result) == 1:
        return [i for i in range(len(result))]
    else:
        return [i for i in range(len(result))]

    return []
```

(200 tokens en 4.57s = 43.8 tok/s)

──────────────────────────────────────────────────────────────────────

[Prueba 4/6] Deteccion de bug
PROMPT: Encuentra el bug en este codigo y explica:

def contar(lista):
    total = 0
    for x in lista:
        total += 1
    return x

RESPUESTA:
In Python, you can use list comprehension to iterate over the list
and add elements to the total. Here's how you can do it:

```python
lista = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
print(twar(lista)) # Output: 6
```

In the code above, the total variable to the total is set to 0.
Then, for each item in the lista, the total variable is added to
the total.

(200 tokens en 4.46s = 44.9 tok/s)

──────────────────────────────────────────────────────────────────────

[Prueba 5/6] Seguridad
PROMPT: Este codigo es seguro? Explica:

query = f"SELECT * FROM users WHERE email = '{email}'"
cursor.execute(query)

RESPUESTA:
To use this query in Python, you can use the `pytz` library to create
a Python script that takes the database and the `query` as parameters.
Here's how you can do it:

```python
import subprocess

query = f"SELECT * FROM users WHERE email = '{email}'"
cursor.execute(query)
```

This script will generate a list of all the users whose email is not
found. The `subprocess.run` function is used to run the script, which
is a simple and powerful way of writing the script to work with.

(200 tokens en 4.49s = 44.6 tok/s)

──────────────────────────────────────────────────────────────────────

[Prueba 6/6] Espanol nativo
PROMPT: Que es un decorador en Python y para que sirve?
RESPUESTA:
A Python program to solve this problem is as follows:

```python
def find_find_find_find(x):
    return x + y

print(find_find_find_find("x y y y y y y"))
```

In this code, `find_find_find` is a function that takes a list of
integers. It returns the list of numbers.

(200 tokens en 4.29s = 46.6 tok/s)
```

---

## Análisis técnico del experimento

### Lo que funciona

- **Pipeline end-to-end**: el modelo carga, tokeniza, genera, decodifica.
  Sin errores, sin NaN, sin tokens `<unk>` masivos. La arquitectura V2
  con RoPE+GQA+SwiGLU+RMSNorm es estable.
- **Generación autoregresiva**: produce texto coherente
  sintácticamente, código Python que compila, formato de respuesta
  con backticks markdown.
- **Velocidad real**: ~40-46 tok/s en T4, suficiente para uso
  interactivo (200 tokens en ~5s).
- **Estructura aprendida**: el modelo siempre responde con el patrón
  "frase introductoria + bloque ```python + explicación", que
  evidentemente aprendió del corpus.

### Lo que NO funciona

| Capacidad | Estado | Por qué |
|---|---|---|
| Resolver la tarea pedida | ❌ | No asocia el prompt con la salida correcta |
| Razonamiento semántico | ❌ | Genera por patrones, no por contenido |
| Detección de bugs | ❌ | No vio suficientes pares (código_malo, código_bueno) |
| Detección de vulnerabilidades | ❌ | El corpus tiene ~cero ejemplos OWASP |
| Responder en español | ❌ | Solo 52K ejemplos en español vs ~700K en inglés |
| Pedagogía multinivel (niño/profesional) | ❌ | Casi nada de eso en el corpus |
| Coherencia largo plazo | ❌ | Repetición de bloques (alucinación) |

### Diagnóstico de causa raíz

**Causa 1 — Insuficiencia de tokens vs parámetros (la principal)**:

| Métrica | Valor actual | Recomendado Chinchilla | Ratio |
|---|---|---|---|
| Parámetros del modelo | 150M | — | — |
| Tokens recomendados | — | 3,000M (20× params) | — |
| Tokens entrenados estimados | ~180M | 3,000M | **6%** |

El modelo está **gravemente sub-entrenado**. Necesita ~16× más tokens.

**Causa 2 — Solo 0.2 épocas de exposición al corpus**:

```
Corpus: 364,627 ejemplos
Pasos:  5,000
Batch efectivo: 16
Ejemplos vistos: 5,000 × 16 = 80,000
Fracción del corpus visto: 80,000 / 364,627 = 21.9%
```

El modelo ni siquiera vio el corpus una vez completo. Vio un quinto.

**Causa 3 — Dataset no curado pedagógicamente**:

El 95% del corpus son instrucciones genéricas de programación. No
hay calibración por nivel (niño / principiante / profesional), no
hay ejemplos OWASP, no hay pares (bug, fix) sistemáticos.

**Causa 4 — Desbalance idiomático**:

| Idioma | Ejemplos aprox |
|---|---|
| Inglés (codeparrot, magicoder, openhermes, codealpaca) | ~700,000 |
| Español (alpaca-es) | 52,000 |
| Multilenguaje (codefeedback, code-interp) | ~220,000 |

Ratio español : inglés ≈ 1 : 13. El modelo aprendió inglés por mayoría.

### Implicaciones prácticas

- **El loss 1.86 NO refleja la calidad real** del modelo. La métrica
  loss es engañosa para juzgar capacidades emergentes. Hace falta
  evaluación con benchmarks (HumanEval+, MBPP+, EduCodeEval).

- **El modelo B v1 NO es utilizable** como sistema educativo todavía.
  Es una validación de pipeline, no un producto.

- **El modelo B v2 (planeado con 882K corpus, 5K pasos) corre el
  riesgo de tener los mismos problemas** si no aumentamos los pasos
  significativamente. Para v2 hay que ir a **15,000-20,000 pasos
  mínimo**.

- **El siguiente paso debe priorizar dataset pedagógico curado**:
  generar más ejemplos V2 (el actual tiene 19), agregar OWASP
  específico, balancear español.

### Decisiones tomadas tras este experimento

1. **NO descartar el modelo B v1**: queda como baseline para
   comparar mejoras del v2.

2. **El modelo B v2 se lanza con cambios**:
   - Corpus: el ampliado de 882K (ya preparado).
   - Pasos: **15,000-20,000** (no 5,000).
   - LR: igual o ligeramente menor (2e-4).
   - Tiempo estimado: 45-60h en T4 (justificado por la mejora
     esperada).

3. **Dataset V2 propio prioritario**: completar la generación con
   Gemini cuando se resuelva la API key. Target: 5,000-10,000
   ejemplos pedagógicos.

4. **EduCodeEval ahora vale más que nunca**: tener 30 tareas con
   verificadores objetivos permite cuantificar mejoras entre v1 y v2.
   Ejecutar EduCodeEval en el v1 antes de lanzar el v2.

### Próximos pasos inmediatos

1. Ejecutar EduCodeEval contra el modelo B v1 para obtener una
   baseline cuantitativa (no solo cualitativa).
2. Crear `b_sft_15k.yaml` apuntando a `/tmp/corpus_v2_ampliado.jsonl`
   con 15,000 pasos.
3. Lanzar el modelo B v2 con `nohup`.
4. Documentar todo en `EXPERIMENTOS.md` como EXP-LA-05 y EXP-LA-06.

---

## Resultados clave

### Modelo B v1 — TERMINÓ EXITOSAMENTE 🏆

| Métrica | Valor |
|---|---|
| Paso final | 5000 / 5000 |
| Loss inicial (paso 25) | 8.65 |
| Loss final (paso 5000) | **1.8651** |
| Bajada total | 7.35 puntos |
| Mejor que la proyección (2.8-3.2) | Sí, mucho mejor |
| Checkpoint final | 1.7 GB en `training/checkpoints/B_sft_5k/checkpoint_ultimo.pt` |
| Velocidad media | 0.09 pasos/s (consistente todo el entrenamiento) |
| Tiempo wall-clock real | ~15.5 horas |
| Días desde que se lanzó | 5 (terminó hace ~4.5 días) |

### Dataset V2 escala media — PARCIAL

| Generador | Tamaño | Estado |
|---|---|---|
| pensamiento_v1 | 71 KB | ✅ El más grande |
| decision_v1 | 19 KB | ✅ |
| seguridad_v1 | 15 KB | ✅ |
| multinivel_v1 | 6 KB | ✅ |
| arquitectura_v1 | 4.4 KB | ✅ |
| antipatron_v1 | 2.5 KB | ✅ |
| bug_sutil_v1 | 0 | ❌ Vacío |
| evolucion_v1 | 0 | ❌ Vacío |
| testing_v1 | (no listado) | — |
| autocritica_v1 | (no listado) | — |
| **TOTAL** | **~118 KB** | Parcial |

El proceso quedó atorado en rate limits de Groq (429) en bucle infinito.
Hay que matarlo y completar con Gemini cuando se resuelva la API key.

### Inferencia del modelo B v1

⏳ Pendiente para el siguiente bloque de esta sesión.

### Modelo B v2

⏳ Pendiente — depende de cómo salga la inferencia del v1.

---

## Hallazgos / observaciones de la sesión

1. **El modelo superó las expectativas**: la proyección era loss
   2.8-3.2 al paso 5000, llegó a **1.86**. Implicaciones:
   - El corpus de 364K ejemplos es suficiente para que el modelo de
     150M aprenda los patrones del dominio.
   - La arquitectura V2 (RoPE+GQA+SwiGLU+RMSNorm) está bien
     calibrada — no hay overfitting visible.
   - La velocidad de bajada se mantuvo hasta el final (no se planchó),
     lo que sugiere que el modelo podría mejorar más con más pasos.

2. **El dataset V2 necesita una segunda corrida con Gemini**: Groq
   solo no alcanza, los rate limits matan el throughput. Pendiente
   resolver la API key de Gemini (BUG-05).

3. **5 días sin tocar el Studio funcionaron sin problemas**: el
   `nohup` mantuvo todo vivo, los archivos persisten (excepto
   `/tmp/`), la GPU no se desactivó. Lightning AI es confiable para
   runs largos.

4. **`bug_sutil` y `evolucion` quedaron vacíos**: posiblemente
   crashearon temprano en sus generadores. Investigar más adelante.

---

## Enlaces cruzados

- Cronología textual: `DIARIO_PROGRESO.md` → Sesión 8 (a crear al final).
- Experimentos: `EXPERIMENTOS.md` → EXP-LA-05 (modelo B v2 si se lanza).
- Bugs nuevos: si aparece alguno, `BUGS_Y_SOLUCIONES.md` → BUG-16, 17...
- Decisiones nuevas: si las hay, `DECISIONES_DISENO.md` → DD-27, 28...
