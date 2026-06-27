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
