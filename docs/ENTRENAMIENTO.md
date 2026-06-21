# Guía de Entrenamiento — Paso a Paso

> Esta guía describe exactamente cómo entrenar el modelo propio desde
> cero usando el pipeline en `ml/`. Está pensada para reproducir el
> experimento de el proyecto y como insumo del capítulo de metodología.

---

## 1. Hardware mínimo

| Componente | Mínimo | Recomendado | Usado en este experimento |
|---|---|---|---|
| GPU | RTX 2050 4GB | RTX 3090 24GB | **RTX 2050 4GB** |
| RAM | 16 GB | 32 GB | 16 GB |
| Disco | 20 GB libres | 100 GB | 50 GB |
| CPU | 6 cores | 12 cores | 8 cores |

El preset `experto` está calibrado para **RTX 2050 4 GB** — corre con
mixed precision FP16 y context length reducido (512) para caber en
VRAM. Si tienes más GPU, usa preset `grande` (~120M) o `xl` (~350M).

---

## 2. Stack de software

| Tool | Versión | Por qué |
|---|---|---|
| Python | 3.11 | Compatible con todas las libs ML actuales |
| PyTorch | 2.4+ CUDA 12.4 | Soporte completo RTX 2050 |
| sentencepiece | 0.2+ | BPE en C++ (Python BPE es 50× más lento) |
| HuggingFace datasets | 3.0+ | Descarga datasets oficiales |
| HuggingFace transformers | 4.45+ | Solo para tokenizadores de referencia |
| PEFT + bitsandbytes | last | LoRA / QLoRA para fine-tune (Fase 5) |

Instala todo en un venv aislado:

```powershell
cd C:\Users\tanyi\OneDrive\Escritorio\sistema-explicador-python-ia\ml
python -m venv.venv
.\.venv\Scripts\Activate
pip install -r requirements.txt
```

---

## 3. Pipeline completo

```
┌─────────────┐ ┌──────────────┐ ┌──────────────┐ ┌────────────┐
│ Descargar │ ──> │ Combinar + │ ──> │ Tokenizar │ ──> │ Entrenar │
│ datasets HF │ │ deduplicar │ │ sentencepiece │ │ Transformer│
└─────────────┘ └──────────────┘ └──────────────┘ └────────────┘
 download_hf.py combinar.py sp_tokenizer.py train.py
```

### Paso 1 — Descargar datasets

```powershell
cd ml
python data/download_hf.py --salida data/raw
```

Esto descarga:
- `sahil2801/CodeAlpaca-20k` (instrucciones de programación)
- `m-a-p/CodeFeedback-Filtered-Instruction` (pares pregunta-código)
- `bertin-project/alpaca-spanish` (instrucciones generales en español)
- `google-research-datasets/mbpp` (problemas Python con tests)

**Tiempo**: ~15 min con conexión 50 Mbps.
**Espacio**: ~3 GB en disco.

### Paso 2 — Combinar y normalizar

```powershell
python data/combinar.py --raw data/raw --salida data/dataset.jsonl
```

Output: `data/dataset.jsonl` con esquema unificado:
```json
{
 "instruccion": "Escribe una función que sume dos números",
 "entrada": "",
 "salida": "def sumar(a, b):\n return a + b",
 "nivel": "basico",
 "tema": "funciones",
 "tipo": "codigo",
 "origen": "codealpaca-es"
}
```

Hace dedup por hash de `instruccion`, split 95/5 train/val.

**Tamaño típico**: 187k ejemplos.

### Paso 3 — Entrenar tokenizador sentencepiece

```powershell
python tokenizer/sp_tokenizer.py train `
 --corpus data/dataset.jsonl `
 --salida tokenizer/sp_python.model `
 --vocab-size 8000
```

**Tiempo**: ~3 min.
**Por qué sentencepiece**: el BPE Python tarda **8+ horas** en 187k
ejemplos. Sentencepiece (C++) tarda **2 minutos**.

### Paso 4 — Entrenar el modelo

Preset `experto` (recomendado para RTX 2050):

```powershell
$env:PYTHONUNBUFFERED = "1"
python train.py `
 --preset experto `
 --tokenizer-backend sp `
 --tokenizer-existente tokenizer/sp_python.model `
 --dataset data/dataset.jsonl `
 --salida checkpoints/exp01 `
 --epocas 3 `
 --batch-size 4 `
 --grad-accum 8 `
 --lr 3e-4 `
 > logs/train_exp01.log 2>&1
```

**Hiperparámetros del preset `experto`**:

| Param | Valor | Justificación |
|---|---|---|
| n_capas | 8 | Suficiente para reasoning básico, cabe en VRAM |
| n_heads | 8 | Multi-head con 64 dim por head |
| d_modelo | 512 | Sweet spot entre capacidad y velocidad |
| d_ff | 2048 | 4× d_modelo (estándar Transformer) |
| max_seq_len | 512 | Reduce VRAM 4× vs 2048 |
| vocab_size | 8000 | Cobertura ~98% del corpus español+código |
| dropout | 0.1 | Regularización conservadora |
| **params totales** | **~46M** | Comparable a GPT-2 small |

**Tiempo estimado**: ~10-14 horas para 3 épocas (187k ejemplos × 3 =
561k pasos efectivos con batch 32).

### Paso 5 — Servir el modelo

Una vez termine, copiar a `backend/app/services/modelo_propio/`:

```powershell
mkdir -Force..\backend\app\services\modelo_propio
Copy-Item checkpoints\exp01\best.pt..\backend\app\services\modelo_propio\
Copy-Item tokenizer\sp_python.model..\backend\app\services\modelo_propio\
```

El backend lo detecta automáticamente vía
`/api/modelo/estado` y empieza a routear consultas a él cuando hay
suficiente calidad.

---

## 4. Monitoreo durante el entrenamiento

El script imprime cada 100 iters:
```
[iter 1200/100k] loss_train=5.82 loss_val=6.11 lr=2.4e-4 tok/s=4870
```

**Cómo saber que va bien**:

- Loss train **bajando** monotónicamente (sin spikes)
- Loss val **bajando** y **siguiendo** al train (gap < 0.5)
- tok/s **estable** (no debería caer — síntoma de OOM swap)

**Cómo saber que va mal** (y qué hacer):

| Síntoma | Causa probable | Solución |
|---|---|---|
| Loss train baja, val sube | Overfit | Reducir épocas, subir dropout a 0.2 |
| Loss val no baja del 6 | LR muy alto / bajo | Probar 1e-4 o 5e-4 |
| Loss explota a inf | LR muy alto | Bajar a 1e-4, warmup más largo |
| tok/s cae con tiempo | Memory leak | `del` tensores explícitamente |
| OOM | Batch muy grande | Bajar `--batch-size 2` o `--max-seq-len 384` |

---

## 5. Evaluación post-entrenamiento

### Métricas automáticas

```powershell
python eval/run.py --modelo checkpoints/exp01/best.pt
```

Reporta:
- **Loss val final**
- **Perplexity** en hold-out
- **HumanEval pass@1** (problemas Python con tests automatizados)
- **MBPP exact match** (subset español)
- **BLEU** contra respuestas de referencia

### Métricas cualitativas

Pasar 20 prompts manuales y medir:
- ¿La respuesta es coherente?
- ¿El código compila?
- ¿La explicación es pedagógica?
- ¿Inventa funciones que no existen? (hallucinations)

Documentar en `docs/EXPERIMENTOS.md` con tabla de resultados.

---

## 6. Reproducibilidad

Para que el proyecto sea reproducible:

```powershell
# Fijar seeds
python train.py --seed 42...

# Guardar config exacta
Copy-Item checkpoints/exp01/config.json docs/experimentos/exp01.json

# Versionar el dataset (hash)
python data/combinar.py --hash > docs/experimentos/exp01.hash
```

El hash del dataset queda como evidencia de que el experimento usó
exactamente el mismo corpus.

---

## 7. Próximos experimentos planeados

1. **exp02**: misma config, 5 épocas (verificar si más época mejora)
2. **exp03**: preset `grande` (~120M) en cloud (Colab Pro / Vast.ai)
3. **exp04**: fine-tune con QLoRA sobre Qwen2.5-Coder-1.5B (baseline
 externo para comparar)
4. **exp05**: DPO sobre exp02 con dataset de preferencias humanas
5. **exp06**: Multi-task — añadir traducción inglés→español como
 tarea auxiliar

---

## 8. Costo estimado de entrenamiento

| Recurso | Costo unitario | Volumen | Total |
|---|---|---|---|
| Electricidad RTX 2050 (250W × 14h) | 0.15 USD/kWh | 3.5 kWh | $0.50 |
| Disco (datasets + checkpoints) | — | 50 GB | $0 (local) |
| Total experimento local | | | **~$0.50** |

Comparativa: Entrenar GPT-3 (~$4.6M). Nuestro modelo, **un experimento
educativo válido**, sale por menos de **un dólar** en electricidad.

Para escalar al preset `xl` (~350M):
- Colab Pro A100 40GB: $10/mes
- Vast.ai RTX 4090: ~$0.40/h × ~24h = ~$10

---

## 9. Citación del proyecto

```bibtex
@misc{explicador-py-ia-2026,
 title = {Sistema Explicador Python IA: un LLM educativo en español
 entrenado desde cero},
 author = {Panezo, Luis},
 year = {2026},
 note = {proyecto de investigación, Ciencias de la Computación},
 url = {https://github.com/.../sistema-explicador-python-ia}
}
```
