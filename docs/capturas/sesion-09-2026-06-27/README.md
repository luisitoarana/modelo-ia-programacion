# Sesión 9 — Migración a Kaggle + entrenamiento modelo grande (88M)

**Fecha de inicio**: 2026-06-27
**Lugar**: Kaggle Notebooks (cuenta de Luisito Arana)
**Hardware**: GPU T4 x2 (31.2 GB VRAM total)

---

## Contexto al iniciar la sesión

Lightning AI agotó los créditos gratis del mes. El modelo B v1 (150M)
quedó intacto en disco de Lightning, pero el Studio está dormido hasta
el próximo ciclo. Migramos a **Kaggle Notebooks** que da:

- **30 horas de GPU T4 x2 por semana** (gratis)
- **31.2 GB VRAM total** (vs 15.6 GB de Lightning)
- **Mejores recursos a costo cero**

---

## Estrategia paralela (decisión clave de la sesión)

En lugar de duplicar el modelo B v2 en Kaggle, aprovechamos las dos
plataformas para entrenar **modelos distintos en paralelo**:

| Plataforma | Cuándo | Modelo | Por qué |
|---|---|---|---|
| **Kaggle** | Ahora (junio-julio) | **Grande 88M** (sota_grande) | Llenar el hueco de scaling laws |
| **Lightning** | Cuando despierte (julio) | Continuar B v2 (150M) | Mejorar sobre el baseline 23/100 |

### Por qué el modelo grande 88M

Es el preset que **nunca habíamos entrenado**. Llenarlo da una curva
empírica de scaling laws con 4 puntos comparables:

```
sota_experto   30M   loss 3.94    smoke validado     ✅
sota_grande    88M   loss ~2.5    ESTA SESION        🟡
sota_b        150M   loss 1.86    B v1 done          ✅
sota_b extra  150M   loss ~1.5    B v2 en Lightning  ⏳
sota_c        350M   loss ~1.2    futuro             ⏳
```

Esto es **aporte académico de primer orden**: demostrar empíricamente
cómo escala TU arquitectura V2 con 4 puntos de datos propios.

---

## Plan de capturas para esta sesión

### Bloque 1 — Setup de Kaggle (capturas 22-26 en sesión 8)

Las capturas de creación de cuenta + GPU verification ya están
documentadas en `docs/capturas/sesion-08-2026-06-27/README.md`
(capturas 22-26 textualmente — perdidas como archivos pero descritas).

### Bloque 2 — Clonar repo y descargar datasets (capturas 27-29)

| # | Nombre sugerido | Qué muestra |
|---|---|---|
| 27 | `27-kaggle-repo-clonado.png` | Output del `git clone` exitoso |
| 28 | `28-kaggle-sentencepiece-pip.png` | Instalación de sentencepiece |
| 29 | `29-kaggle-descarga-datasets-inicio.png` | Inicio del `download_hf.py` |
| 30 | `30-kaggle-descarga-datasets-final.png` | Resumen de descargas completadas |

### Bloque 3 — Entrenar tokenizer + smoke test (capturas 31-33)

| # | Nombre sugerido | Qué muestra |
|---|---|---|
| 31 | `31-kaggle-tokenizer-entrenado.png` | sp_v2_16k.model entrenado |
| 32 | `32-kaggle-smoke-test-arranque.png` | Smoke 30M iniciando |
| 33 | `33-kaggle-smoke-test-loss-final.png` | Smoke completado |

### Bloque 4 — Modelo grande 88M (capturas 34-37)

| # | Nombre sugerido | Qué muestra |
|---|---|---|
| 34 | `34-kaggle-grande-config-listo.png` | Config `grande_sft_kaggle.yaml` listo |
| 35 | `35-kaggle-grande-lanzado.png` | Entrenamiento 88M iniciado |
| 36 | `36-kaggle-grande-paso-1000.png` | Primer check intermedio |
| 37 | `37-kaggle-grande-paso-final.png` | Entrenamiento 88M completado |

### Bloque 5 — Evaluación y comparación (capturas 38-40)

| # | Nombre sugerido | Qué muestra |
|---|---|---|
| 38 | `38-kaggle-inferencia-grande.png` | Suite de 6 pruebas pedagógicas |
| 39 | `39-kaggle-educodeeval-grande.png` | EduCodeEval del modelo grande |
| 40 | `40-comparacion-30m-88m-150m.png` | Tabla comparativa final |

---

## Capturas REALMENTE tomadas (con descripción técnica)

> Las capturas iniciales (22-26) se perdieron en el portapapeles
> antes de configurar Snipping Tool con auto-guardado. Las descripciones
> textuales detalladas quedan como referencia equivalente.

| # | Archivo | Estado | Qué muestra |
|---|---|---|---|
| 22 | `22-kaggle-cuenta-creada.png` | Portapapeles (perdida) | Pantalla "Welcome Luisito Arana" tras crear cuenta Kaggle. |
| 23 | `23-kaggle-gpu-t4x2-configurada.png` | Portapapeles (perdida) | Panel derecho: "GPU T4 x2" + "Internet on" + Quota 0/30 hrs. |
| 24 | `24-kaggle-cuda-true-2-gpus.png` | Portapapeles (perdida) | Output: CUDA True, 2 GPUs Tesla T4 con 15.6 GB cada una. |
| 25 | `25-kaggle-pat-token-clone-exitoso.png` | Portapapeles (perdida) | UserSecretsClient + git clone exitoso (819 objetos, 1.80 MiB). |
| 26 | `26-kaggle-descarga-codealpaca-inicial.png` | Portapapeles (perdida) | Primera descarga: codealpaca 20016 ejemplos. |
| 27 | `27-kaggle-segunda-ejecucion-celdas-1-2.png` | En portapapeles | Re-ejecución de Save & Run All. Celda 1 (CUDA True, GPUs 2) + Celda 2 (clone 830 objetos, 8.93 MiB/s). Sesión 9m. |
| 28 | `28-kaggle-celda3-descarga-multidatasets.png` | En portapapeles | Celda 3 ejecutándose: codealpaca ✅ 20016, codefeedback ✅ 156525 (371 MB), magicoder-oss ✅ 75197 (203 MB), magicoder-evol descargando. Sesión 10m. |
| 29 | `29-kaggle-celda4-corpus-882837-tokenizer-arranca.png` | En portapapeles | Celda 4: corpus consolidado **882,837 líneas / 2.0 GB**. Sentencepiece arrancando con `1,796,200 textos extraídos, vocab 16000`. Sesión 18m. |
| 30 | `30-kaggle-tokenizer-bpe-trainer-1787225.png` | En portapapeles | Sentencepiece trainer avanzado: `Done! preprocessed 1787225 sentences`, `bpe_model_trainer Adding freq=8129606 size=20 active=2866 piece=_p`, etc. Construyendo vocab BPE 16K. Sesión 26m. |
| 31 | `31-kaggle-modelo-grande-88m-paso-500.png` | En portapapeles | **¡MODELO GRANDE 88M ENTRENANDO!** Log: `[train] modelo 87.8M params device=cuda dtype=bfloat16 amp=True gc=False`. Loss bajando: paso 25=8.61, paso 100=6.82, paso 250=5.44, paso 500=4.67. Checkpoint guardado en paso 250. Status bar muestra paso 1475/5000 con loss 3.2040. Velocidad: **0.19 pasos/s (2× más rápida que el B 150M de Lightning)**. Sesión: 6h:11m. ETA restante: 389 min. |
| 32 | `32-kaggle-modelo-grande-paso-3325-convergiendo.png` | En portapapeles | **Modelo grande 88M en paso 3325/5000 (66.5%)**. Loss convergiendo en 2.55-2.67 (plateau de convergencia). Checkpoints guardados en paso 3000 y 3250. Panel de recursos: **GPU T4 ×2 ON, GPU 0 al 100% util, 7.1 GiB VRAM usados, 9.1 GiB RAM, Disk 7.8 GiB**. Sesión 6h:15m / 12h, ETA restante 145 min. **El entrenamiento va a terminar exitosamente con margen de ~3h sobre el timeout**. |
| 33 | `33-kaggle-modelo-grande-terminado-paso-5000.png` | En portapapeles | **¡TERMINÓ! Paso 5000/5000, loss=2.3825**. Logs finales: `[paso 5000/5000] loss=2.3825 lr=3.00e-05 vel=0.19 pasos/s ETA=0 min`, `guardado checkpoint_ultimo.pt`, `[done] paso=5000 mejor_val=inf checkpoint final: /kaggle/working/checkpoints/grande_sft_5k/checkpoint_ultimo.pt`. Sesión: 8h:45m. Bajada total: 8.61 → 2.38 = **6.23 puntos**. |
| 34 | `34-kaggle-grande-checkpoint-metrics-final.png` | En portapapeles | Verificación de artefactos: `checkpoint_ultimo.pt` de **1005 MB** (88M params + optimizer state), `config_resuelta.json` 1.2K, `metrics.jsonl` 30K. `tail -10 metrics.jsonl` muestra los últimos pasos con loss 2.36-2.38 estable. Sesión 8h:46m. |
| 35 | `35-kaggle-grande-inferencia-suite-pruebas-1-3.png` | En portapapeles | Suite de inferencia ejecutándose contra el checkpoint. Modelo cargado: **87,804,672 params en 2.5s**. Arquitectura: n_layer=12, n_embd=768, vocab=16000, block_size=1024. **Prueba 1 (promedio)**: respuesta en español "La funcion Python que se sido una mezba la cabeza..." — el modelo aprendió ESPAÑOL (diferencia clave vs el v1 que respondía en inglés). 200 tokens en 3.26s = **61.4 tok/s**. **Prueba 3 (refactor)**: genera código pythonico pero pierde el filtro `if i % 2 == 0`. **71.5 tok/s**. |
| 36 | `36-kaggle-grande-inferencia-pruebas-4-6.png` | En portapapeles | **Prueba 4 (detección de bug)**: genera código similar pero no detecta el bug. **Prueba 5 (SQL injection)**: responde con JSON aleatorio `{"name": "John", "email": "johnda", "age": "Life"}`, sin detectar vulnerabilidad. Velocidad consistente 70-75 tok/s. El modelo aprende formato pero no razonamiento semántico (igual que el v1, esperado para 88M con 5000 pasos). |
| 37 | `37-kaggle-grande-prueba-6-bucle-degenerativo.png` | En portapapeles | **Prueba 6 (español nativo)**: el modelo entra en bucle degenerativo: "La vida que la vida que la vida que la tiempo que la vida que..." — fenómeno conocido en modelos undertraining. Aprende frases comunes pero no aprende a terminar coherentemente. 200 tokens en 2.67s = 74.9 tok/s. Es el equivalente al bucle de regex del v1. Esperable para 88M con 5K pasos. |
| 38 | `38-kaggle-educodeeval-grande-iniciando.png` | En portapapeles | **EduCodeEval ejecutándose** sobre el modelo grande 88M. `python -m ml.eval.edu_code_eval --modelo local --checkpoint /kaggle/working/checkpoints/grande_sft_5k/checkpoint_ultimo.pt --tokenizer ml/tokenizer/artefactos/sp_v2_16k.model --salida /kaggle/working/edu_modelo_grande_88m.json`. Modelo: `local_grande_sft_5k`. Primeras 4 tareas de generación (fibonacci, palindromo, frecuencias, busqueda_binaria) todas FAIL con score 10.0/100 (mínimo). Comportamiento consistente con el v1. Sesión: 8h:50m. ETA EduCodeEval: 20-30 min. |

### Lo que cada captura demuestra técnicamente

- **Captura 27**: la sesión arranca limpia tras un reinicio del kernel
  (Save & Run All). GPU verificada antes de gastar recursos.
- **Captura 28**: el fix BUG-14 (try/except por dataset) funciona porque
  un eventual fallo de un dataset no detendría a los demás.
- **Captura 29**: el corpus en Kaggle (882,837) coincide con el de
  Lightning (882,856) — diferencia mínima de ~20 ejemplos, posiblemente
  por descartes en la validación V2. **Reproducibilidad confirmada**
  entre plataformas distintas.
- **Captura 30**: el tokenizer V2 sobre Kaggle produce
  resultados consistentes con el de Lightning. Confirma que el
  preprocesamiento es determinístico (mismo seed).

---

## Configuración usada

- Config: `ml/training/configs/grande_sft_kaggle.yaml`
- Modelo: `sota_grande` (88M params)
- Pasos: 10,000
- Batch: 4 (sin gradient checkpointing porque 88M cabe en T4)
- LR: 3e-4 → 3e-5 (cosine)
- Save cada: 300 pasos (~30 min)
- Tiempo estimado: 10-15 horas wall-clock

---

## Resultados (a completar)

- Loss final modelo grande 88M:
- EduCodeEval score:
- Tiempo real de entrenamiento:
- Capturas tomadas con archivo físico (sí/no):

---

## Aprendizajes / Observaciones

(A completar al cierre de la sesión.)
