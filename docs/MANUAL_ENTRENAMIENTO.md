# Manual de Entrenamiento — Cómo se entrena el modelo paso a paso

> Este documento es el manual reproducible de CÓMO se entrena cada modelo
> del proyecto. Sirve para la propuesta de investigación (metodología) y
> para la tesis (desarrollo). Cualquier persona puede seguir estos pasos
> y reproducir el entrenamiento.

---

## Glosario rápido (conceptos clave)

| Término | Qué significa |
|---|---|
| **M (parámetros)** | Millones. 88M = 88 millones de parámetros = "tamaño del cerebro" del modelo. 150M = 150 millones. Más parámetros = más capacidad, pero más lento de entrenar. |
| **K (pasos)** | Miles de pasos de entrenamiento. 8K = 8000 pasos. 40K = 40000 pasos. Cada paso el modelo "estudia" un lote de datos y mejora un poquito. Más pasos = mejor entrenado (hasta cierto límite). |
| **loss** | Error del modelo. Empieza alto (~8) y baja con el entrenamiento (~2 o menos). Menor loss = modelo mejor. |
| **checkpoint** | Archivo `.pt` con los pesos del modelo en un momento dado. Es el modelo mismo, guardado en disco. |
| **continued pretraining** | Cargar un checkpoint ya entrenado y seguir entrenándolo más pasos. Así se sube 5K → 8K → 15K sin empezar de cero. |
| **EduCodeEval** | Benchmark propio que mide qué tan bueno es el modelo (0-100) en 5 categorías pedagógicas. |
| **Save & Run All (Commit)** | Modo de Kaggle que ejecuta el notebook EN LA NUBE (sin PC encendida). Es la ÚNICA forma segura de que no se pierda el resultado. |
| **Sesión interactiva** | Cuando trabajás en el notebook con la pestaña abierta. Muere a las 12h y PIERDE TODO. NO usar para entrenamientos largos. |

---

## Modelos del proyecto (estado a 2026-07-09)

| Modelo | Params | Plataforma | Pasos | Loss | EduCodeEval |
|---|---|---|---|---|---|
| Smoke | 30M | Lightning | 1K | 3.94 | (no medido) |
| **Grande** | **88M** | **Kaggle** | 5K → 8K (en curso) | 2.38 → ~2.1 | 22.04 |
| **B v1** | **150M** | **Lightning** | 5K | 1.86 | 23.07 |
| **B v2** | **150M** | **Lightning** | 15K (en curso) | ~1.5 esperado | ~35 esperado |

**Objetivo final**: llegar al modelo más avanzado posible (grande hasta 40K,
o modelo C de 350M), refinarlo con DPO, y que sea 100% funcional sin
alucinaciones en programación y explicación de código.

---

## RECETA A — Entrenar en KAGGLE (modelo grande 88M)

### Requisitos previos (una sola vez)
- Cuenta Kaggle con teléfono verificado (GPU gratis)
- Token de GitHub guardado en Kaggle Secrets como `GITHUB_TOKEN`
- El checkpoint anterior subido como Kaggle Dataset privado
  (ej: `modelo-grande-88m-5k-pasos`)

### Pasos

**1.** Crear notebook nuevo → panel derecho:
   - Accelerator = **GPU T4 x2**
   - Internet = **ON**
   - Add Input → Your Work → atachar el dataset del checkpoint anterior

**2.** Celda 1 (clonar repo):
```python
from kaggle_secrets import UserSecretsClient
github_token = UserSecretsClient().get_secret("GITHUB_TOKEN")
!git clone https://luisitoarana:{github_token}@github.com/luisitoarana/modelo-ia-programacion.git
%cd /kaggle/working/modelo-ia-programacion
!pip install sentencepiece -q
```

**3.** Celda 2 (datos + tokenizer + checkpoint + entrenar + preservar):
```python
# Datasets
!python -m ml.data.download_hf \
    --dataset codealpaca,codefeedback,magicoder-oss,magicoder-evol,humaneval,ds-1000,humaneval-plus,mbpp-plus,codeparrot-py,openhermes,alpaca-es,open-code-interp \
    --salida-dir datasets/publicos --schema-v2 --max-items 200000

# Corpus + tokenizer
!cat datasets/publicos/*.jsonl > /kaggle/working/corpus_v2.jsonl
!mkdir -p ml/tokenizer/artefactos
!python -m ml.tokenizer.sp_tokenizer train \
    --corpus /kaggle/working/corpus_v2.jsonl \
    --salida ml/tokenizer/artefactos/sp_v2_16k.model --vocab-size 16000

# Checkpoint anterior (ajustar path/nombre del dataset)
!mkdir -p /kaggle/working/checkpoints/grande_sft_5k/
!cp /kaggle/input/datasets/luisitoarana/modelo-grande-88m-5k-pasos/modelo_grande_88m_5k.pt \
    /kaggle/working/checkpoints/grande_sft_5k/checkpoint_ultimo.pt

# ENTRENAR (cambiar config segun escalon: 8k, 15k, 20k...)
!python -m ml.training.run_fase --config ml/training/configs/grande_continued_8k.yaml

# PRESERVAR el resultado (clave para que no se pierda)
!cp /kaggle/working/checkpoints/grande_continued_8k/checkpoint_ultimo.pt /kaggle/working/modelo_grande_88m_8k.pt
!ls -lh /kaggle/working/*.pt
```

**4.** Save Version → **Save & Run All (Commit)** → nombre descriptivo → Save

**5.** CERRAR TODO. Corre en la nube ~8h. Email al terminar.

**6.** Al terminar: descargar `modelo_grande_88m_8k.pt` desde la pestaña
   Output de la versión → subirlo como nuevo Dataset (`modelo-grande-88m-8k`)
   → usarlo como base del próximo escalón.

### REGLA DE ORO KAGGLE
- El continued de **5000 pasos tarda ~13h → NO cabe en 12h**.
- El continued de **3000 pasos (config 8k) tarda ~8h → SÍ cabe**.
- Por eso subimos de a 3000 pasos por sesión: 5K → 8K → 11K → 14K...

---

## RECETA B — Entrenar en LIGHTNING (modelo B v2, 150M)

### Pasos

**1.** Entrar a Lightning AI Studio, activar GPU T4.

**2.** En la terminal:
```bash
cd modelo-ia-programacion && git pull
cat datasets/publicos/*.jsonl datasets/raw/*.jsonl > /tmp/corpus_v2_ampliado.jsonl
nohup python -m ml.training.run_fase --config ml/training/configs/b_sft_15k.yaml > entrenamiento_B_v2.log 2>&1 &
```

**3.** Verificar (esperar ~9 min por el primer log):
```bash
tail -30 entrenamiento_B_v2.log
```

**4.** `nohup` mantiene el proceso vivo aunque cierres el navegador.
   Volver cada tanto y correr `tail -30 entrenamiento_B_v2.log` para ver
   el progreso.

**5.** Al terminar (~45h): descargar el checkpoint final de
   `training/checkpoints/B_sft_15k/checkpoint_ultimo.pt`.

### DIFERENCIA LIGHTNING vs KAGGLE
- Lightning usa `nohup` (proceso en background que sobrevive al cierre).
- Kaggle usa "Save & Run All" (ejecución en la nube).
- Ambos permiten cerrar la PC sin perder el entrenamiento.

---

## Documentación obligatoria en cada sesión

1. **Capturas**: guardar screenshot de cada paso importante (comando +
   resultado). Windows: `Win+Shift+S` con auto-guardado activado, o
   `Win+PrtScn`. Las capturas se guardan en
   `C:\Users\tanyi\OneDrive\Imágenes\Screenshots\`.

2. **Mover capturas al repo**: las capturas se copian a
   `docs/capturas/sesion-NN-YYYY-MM-DD/` y se suben a GitHub. Así
   sobreviven al reset de la PC (quedan en la nube de GitHub).

3. **Actualizar** `docs/DIARIO_PROGRESO.md` y `docs/EXPERIMENTOS.md` con
   los resultados de cada entrenamiento (loss final, EduCodeEval, tiempo).

---

## Por qué documentar todo

- **Propuesta de investigación**: es el "manual" de qué se va a hacer y cómo.
- **Tesis**: es el desarrollo real — modelo entrenado, cómo avanzó, hasta
  dónde se llegó.
- El objetivo es un modelo especializado en programación y explicación de
  código, funcional al máximo, sin alucinaciones, con explicación pedagógica
  perfecta — superior a modelos generales en ese nicho específico.
