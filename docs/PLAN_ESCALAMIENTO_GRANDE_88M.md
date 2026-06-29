# Plan de Escalamiento Progresivo — Modelo Grande 88M

> Documentación del plan de continued pretraining incremental del modelo
> grande 88M, desde los 5000 pasos iniciales (loss 2.38, EduCodeEval
> 22.04) hasta los 40000 pasos objetivo.

---

## Visión general

El modelo grande 88M (sota_grande) fue entrenado en Kaggle el 2026-06-28
durante 5000 pasos sobre el corpus consolidado de 882K ejemplos. Loss
final: 2.38. EduCodeEval: 22.04 / 100.

Este documento describe el plan para continuar entrenando el mismo modelo
en escalones de 5000 pasos hasta alcanzar 40000 pasos totales, usando
checkpoints intermedios para sobrevivir al timeout de 12h de Kaggle.

## Por qué escalamiento progresivo (no un solo entrenamiento grande)

| Razón | Detalle |
|---|---|
| **Timeout Kaggle** | 12h por sesión. 40000 pasos = ~55h. Imposible en una sola corrida. |
| **Cuota semanal** | 30h GPU T4 x2 por semana. Permite ~4 escalones de 5K por semana. |
| **Validación intermedia** | Cada escalón se puede evaluar con EduCodeEval para ver progreso. |
| **Reversibilidad** | Si un escalón sale mal, volvemos al checkpoint anterior. |
| **Costo** | Total: $0 (todo dentro de la cuota gratis de Kaggle). |

## Tabla del plan

| Escalón | Config YAML | Pasos | Tiempo | LR pico | Loss esperada | EduCodeEval esperado |
|---|---|---|---|---|---|---|
| **5K** ✅ | `grande_sft_kaggle_5k.yaml` | 0-5000 | 8.7h | 3.0e-4 | **2.38** ✅ | **22.04** ✅ |
| **10K** | `grande_continued_10k.yaml` | 5001-10000 | ~7h | 1.5e-4 | ~2.0 | 25-28 |
| **15K** | `grande_continued_15k.yaml` | 10001-15000 | ~7h | 1.0e-4 | ~1.8 | 28-32 |
| **20K** | `grande_continued_20k.yaml` | 15001-20000 | ~7h | 8.0e-5 | ~1.6 | 32-36 |
| **25K** | `grande_continued_25k.yaml` | 20001-25000 | ~7h | 6.0e-5 | ~1.5 | 35-39 |
| **30K** | `grande_continued_30k.yaml` | 25001-30000 | ~7h | 5.0e-5 | ~1.4 | 38-42 |
| **35K** | `grande_continued_35k.yaml` | 30001-35000 | ~7h | 4.0e-5 | ~1.35 | 40-44 |
| **40K** | `grande_continued_40k.yaml` | 35001-40000 | ~7h | 3.0e-5 | **~1.3** | **42-48** |

**Tiempo total acumulado**: ~50 horas de cómputo restante (≈ 6-8 semanas
a 30h/semana de cuota Kaggle).

## Estrategia de Learning Rate decay manual

A diferencia del entrenamiento inicial (warmup + cosine decay automático),
en continued pretraining bajamos el LR manualmente con cada escalón.

```
5K:    LR pico 3.0e-4  (entrenamiento desde cero)
10K:   LR pico 1.5e-4  (50% del inicial)
15K:   LR pico 1.0e-4  (33% del inicial)
20K:   LR pico 8.0e-5  (27% del inicial)
25K:   LR pico 6.0e-5  (20% del inicial)
30K:   LR pico 5.0e-5  (17% del inicial)
35K:   LR pico 4.0e-5  (13% del inicial)
40K:   LR pico 3.0e-5  (10% del inicial)
```

**Justificación**: el modelo ya converge cerca del óptimo local. Reducir
LR evita oscilaciones y permite refinamiento fino.

## Cómo ejecutar cada escalón

### Pre-requisito en cada nuevo notebook de Kaggle

Subir el checkpoint del escalón anterior como Kaggle Dataset privado, o
re-ejecutar todo el pipeline desde cero (download + tokenizer + continued).

### Plantilla de notebook para cada escalón

```python
# === Celda 1: Verificar GPU ===
import torch
print("CUDA:", torch.cuda.is_available())

# === Celda 2: Clonar repo ===
from kaggle_secrets import UserSecretsClient
github_token = UserSecretsClient().get_secret("GITHUB_TOKEN")
!git clone https://luisitoarana:{github_token}@github.com/luisitoarana/modelo-ia-programacion.git
%cd modelo-ia-programacion
!pip install sentencepiece -q

# === Celda 3: Descargar datasets ===
# (mismo comando que la primera corrida)

# === Celda 4: Consolidar corpus + tokenizer ===
# (mismo comando que la primera corrida)

# === Celda 5: Cargar checkpoint del escalón anterior ===
# OPCION A: si subiste como Kaggle Dataset privado
# !cp /kaggle/input/<nombre-dataset>/modelo_grande_88m_5k.pt /kaggle/working/checkpoints/grande_sft_5k/
# OPCION B: si re-entrenas desde cero en cada notebook (más lento)
# (no hace falta, el continued lo carga automáticamente desde el path en el config)

# === Celda 6: Entrenar continued ===
!python -m ml.training.run_fase --config ml/training/configs/grande_continued_10k.yaml
# (cambiar el config en cada escalón: continued_10k, _15k, _20k, _25k, _30k, _35k, _40k)
```

### Save & Run All en cada escalón

Para cada escalón, hacer **Save Version → Save & Run All (Commit)** con
nombre descriptivo (ej: `grande-88m-continued-10k`). Tarda ~7-9h en cloud
sin necesidad de PC encendida.

## Cronograma de 6-8 semanas

```
Semana 1   (días 1-3):     5K → 10K  (commit en cloud, 7h)
Semana 1-2 (días 4-7):     10K → 15K (commit en cloud, 7h)
Semana 2   (días 8-10):    15K → 20K (commit en cloud, 7h)
Semana 3   (días 11-14):   evaluar progreso con EduCodeEval del 20K
Semana 4   (días 15-17):   20K → 25K
Semana 4   (días 18-21):   25K → 30K
Semana 5   (días 22-24):   30K → 35K
Semana 6   (días 25-28):   35K → 40K
Semana 7-8 (días 29-42):   evaluación final, comparativa, escribir
                           sección del informe
```

## Evaluación entre escalones

Después de cada escalón **importante** (cada 2 escalones, es decir,
en 10K, 20K, 30K, 40K), ejecutar:

```bash
python -m ml.eval.edu_code_eval \
  --modelo local \
  --checkpoint /kaggle/working/checkpoints/grande_continued_XXk/checkpoint_ultimo.pt \
  --tokenizer ml/tokenizer/artefactos/sp_v2_16k.model \
  --salida /kaggle/working/edu_grande_XXk.json
```

Y comparar con el escalón anterior:

| Métrica | 10K vs 5K | 20K vs 10K | 30K vs 20K | 40K vs 30K |
|---|---|---|---|---|
| Mejora esperada loss | -0.4 | -0.4 | -0.2 | -0.1 |
| Mejora esperada EduCodeEval | +3-5 puntos | +5-8 puntos | +5-7 puntos | +3-5 puntos |

Si la mejora se estanca, **detener el escalamiento** y pasar a Reward
Models + DPO.

## Resultado esperado al finalizar (40K pasos)

| Métrica | Valor proyectado |
|---|---|
| Loss final | ~1.30 |
| EduCodeEval global | **42-48 / 100** |
| Tareas aprobadas | 6-9 de 30 |
| Comparable a | Mejor que B v1 (23.07), competitivo con baselines comerciales pequeños |

## Después del 40K

Cuando el modelo grande alcance 40K pasos, las opciones son:

1. **Reward Models + DPO**: refinar el modelo con preferencias.
2. **Modelo C (350M)**: escalar a un tamaño mayor.
3. **Modelo grande v2**: re-entrenar desde cero con dataset mejorado.
4. **Multimodalidad**: integrar el ViT + Projector ya implementado.

La decisión se tomará en base a:
- EduCodeEval del 40K
- Recursos restantes (Kaggle gratis + Lightning gratis)
- Prioridad del proyecto

## Backup de checkpoints

Cada checkpoint que termine exitosamente debe **descargarse del Kaggle
notebook** y guardarse en:

```
C:\Users\tanyi\OneDrive\Escritorio\sistema-explicador-python-ia\models\
├── modelo_grande_88m_5k.pt    ✅ (descargado 2026-06-29)
├── modelo_grande_88m_10k.pt   (pendiente)
├── modelo_grande_88m_15k.pt   (pendiente)
├── ...
└── modelo_grande_88m_40k.pt   (pendiente)
```

Opcionalmente subir a HuggingFace Hub como modelo privado para tener
backup eterno.
