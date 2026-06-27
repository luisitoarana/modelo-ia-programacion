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

(Esta lista se rellena al final de la sesión, con un punto por captura
realmente guardada.)

```
01-XXXX-XXXX.png            (descripción corta)
02-XXXX-XXXX.png            (descripción corta)
...
```

---

## Resultados clave

(A completar al final de la sesión.)

- Loss final modelo B v1:
- Ejemplos generados por dataset V2 media:
- Inferencia: coherente / parcial / basura:
- Modelo B v2: lanzado / pospuesto:

---

## Enlaces cruzados

- Cronología textual: `DIARIO_PROGRESO.md` → Sesión 8 (a crear al final).
- Experimentos: `EXPERIMENTOS.md` → EXP-LA-05 (modelo B v2 si se lanza).
- Bugs nuevos: si aparece alguno, `BUGS_Y_SOLUCIONES.md` → BUG-16, 17...
- Decisiones nuevas: si las hay, `DECISIONES_DISENO.md` → DD-27, 28...
