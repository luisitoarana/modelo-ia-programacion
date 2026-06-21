# Módulo ML — LLM educativo propio (desde cero)

Este paquete construye, entrena y sirve un **modelo de lenguaje propio**
(Transformer decoder) especializado en Python educativo. Las APIs externas
**solo** se usan para generar datos de entrenamiento (`ml/data/generator.py`).
El modelo final responde **sin APIs**.

## Estructura

```
ml/
├── config.py            Configuración de modelo y entrenamiento + presets
├── tokenizer/
│   └── bpe.py           Tokenizer BPE byte-level propio (Python puro)
├── model/
│   └── transformer.py   Transformer decoder desde cero (PyTorch)
├── data/
│   ├── schema.py        Formato del ejemplo de entrenamiento
│   ├── seed.py          Corpus semilla incorporado (sin APIs)
│   ├── generator.py     Dataset Generator (Gemini/DeepSeek) — ÚNICO uso de APIs
│   ├── corpus.py        Cargar / deduplicar / validar / estadísticas
│   └── loader.py        Empaquetado de tokens y batches para entrenamiento
├── training/
│   └── trainer.py       Pipeline: scheduler, checkpoints, métricas, experimentos
├── inference/
│   └── engine.py        Motor de inferencia (carga checkpoint y genera)
├── run_demo.py          Demo end-to-end (corpus→tokenizer→train→inferencia)
├── train.py             Entrenamiento real (CLI)
└── generate.py          Inferencia interactiva (CLI)
```

## Requisitos

```bash
pip install -r ml/requirements.txt
```

### ⚡ Activar la GPU (RTX 2050)

Por defecto PyTorch puede instalarse como `+cpu`. Para usar tu GPU instala el
build CUDA (CUDA 12.x es compatible con tu driver):

```powershell
pip uninstall -y torch
pip install torch --index-url https://download.pytorch.org/whl/cu124
python -c "import torch; print('CUDA:', torch.cuda.is_available())"
```

Debe imprimir `CUDA: True`. Si imprime `False`, seguirá entrenando en CPU
(más lento, pero funciona).

## Flujo de trabajo

### 0) Probar que todo funciona (rápido, sin APIs)

```bash
python -m ml.run_demo --preset nano --iters 300
```

### 1) Generar dataset con las APIs (rol auxiliar)

Configura `GEMINI_API_KEY` o `DEEPSEEK_API_KEY` en `.env`, luego:

```bash
python -m ml.data.generator --proveedor gemini --por-objetivo 12 \
    --salida datasets/raw/generado_gemini.jsonl
python -m ml.data.generator --proveedor deepseek --por-objetivo 12 \
    --salida datasets/raw/generado_deepseek.jsonl
```

### 2) Entrenar el modelo propio

```bash
python -m ml.train --preset pequeno --iters 4000 \
    --corpus datasets/raw/generado_gemini.jsonl datasets/raw/generado_deepseek.jsonl \
    --experimento exp01
```

### 3) Conversar con el modelo entrenado (sin APIs)

```bash
python -m ml.generate --checkpoint training/checkpoints/exp01_best.pt
```

## Presets de modelo

| Preset | Parámetros aprox. | Recomendado para |
|--------|-------------------|------------------|
| `nano` | ~1-3 M | Pruebas en CPU |
| `pequeno` | ~15-20 M | RTX 2050 (4 GB) |
| `mediano` | ~40-60 M | ≥ 8 GB VRAM |

## Nota metodológica (tesis)

El aporte científico es la **metodología completa de construcción** de un LLM
educativo: tokenizer + arquitectura Transformer desde cero + pipeline de
entrenamiento + inferencia + integración. La **calidad** del texto generado
depende de la escala del dataset y del cómputo disponible; con una GPU de 4 GB
se demuestra el método y se obtiene un modelo funcional, no un modelo de
producción a la altura de Gemini/DeepSeek. Esto se documenta en la sección de
limitaciones de la tesis (ver `research/`).
```
