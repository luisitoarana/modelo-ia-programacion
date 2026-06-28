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
