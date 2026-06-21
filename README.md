# Sistema Explicador Python IA

> Sistema educativo basado en un **modelo de lenguaje propio (LLM) entrenado
> desde cero** para la **generación y explicación automática de código Python**,
> orientado al **fortalecimiento de la comprensión algorítmica** en estudiantes
> de educación superior.

Proyecto de tesis (Ciencias de la Computación). El objetivo central es
**construir una IA propia**, no consumir APIs. Las APIs externas (Gemini,
DeepSeek) se usan **exclusivamente** para generar y validar datos de
entrenamiento. El flujo final es:

```
Usuario → Sistema educativo → Modelo propio (LLM) → Respuesta
```

---

## Componentes

| Componente | Tecnología | Estado |
|---|---|---|
| **LLM propio** (Transformer desde cero) | PyTorch | ✅ funcional |
| **Tokenizer propio** (BPE byte-level) | Python puro | ✅ |
| **Pipeline de entrenamiento** | PyTorch | ✅ |
| **Motor de inferencia** | PyTorch | ✅ |
| **Dataset Generator** (único uso de APIs) | httpx | ✅ |
| Backend (auth, base de conocimiento, panel) | FastAPI + PostgreSQL | ✅ |
| Frontend (portal, chat, panel de entrenamiento) | Next.js + Tailwind | ✅ build OK |

---

## Estructura del proyecto

```
sistema-explicador-python-ia/
├── ml/                       ★ LLM PROPIO (núcleo de la tesis)
│   ├── model/transformer.py     Transformer decoder desde cero
│   ├── tokenizer/bpe.py         Tokenizer BPE byte-level propio
│   ├── data/                    Dataset (semilla + generación con APIs)
│   ├── training/trainer.py      Pipeline de entrenamiento
│   ├── inference/engine.py      Motor de inferencia (sin APIs)
│   ├── train.py · generate.py · run_demo.py   CLIs
│   └── README.md                Guía del módulo ML
├── backend/                  FastAPI + base de conocimiento + integración del modelo
├── frontend/                 Portal Next.js (chat, dashboard, panel de entrenamiento)
├── datasets/                 Corpus crudo / procesado / validado
├── training/                 Checkpoints y experimentos
├── knowledge_base/           Conocimiento curado (Python/OOP/algoritmos)
├── research/                 Bitácora, metodología, arquitectura científica
├── docs/                     Documentación técnica
└── docker-compose.yml
```

---

## Inicio rápido del LLM propio (sin nada configurado)

```bash
pip install -r ml/requirements.txt
python -m ml.run_demo          # corpus → tokenizer → entrena → genera (CPU)
```

### Activar la GPU (RTX 2050)

```powershell
pip uninstall -y torch
pip install torch --index-url https://download.pytorch.org/whl/cu124
python -c "import torch; print('CUDA:', torch.cuda.is_available())"
```

### Entrenamiento real

```bash
# 1) Generar datos con las APIs (rol auxiliar). Pon las keys en .env
python -m ml.data.generator --proveedor gemini --por-objetivo 12 \
    --salida datasets/raw/generado_gemini.jsonl

# 2) Entrenar el modelo propio
python -m ml.train --preset pequeno --iters 4000 \
    --corpus datasets/raw/generado_gemini.jsonl --experimento exp01

# 3) Conversar con el modelo (sin APIs)
python -m ml.generate --checkpoint training/checkpoints/exp01_best.pt
```

Ver guía completa en [`ml/README.md`](ml/README.md).

---

## Backend + Frontend (portal web)

```bash
cp .env.example .env          # configurar keys y, si hay modelo, MODEL_ENABLED=true
docker compose up --build
```

- API + OpenAPI: http://localhost:8000/docs
- Portal: http://localhost:3000

> El portal incluye: chat con el modelo propio, generador/explicador
> estructurado, panel de entrenamiento con curva de pérdida, dataset y
> validación, base de conocimiento, reportes y mapa del proyecto, con
> **tema claro/oscuro**.

Para servir el modelo propio desde la web hay que tener un checkpoint
entrenado y ejecutar el backend en un entorno con PyTorch (ver `ml/README.md`).

---

## Endpoints clave del modelo propio

| Método | Ruta | Descripción |
|--------|------|-------------|
| GET | `/api/v1/ai/modelo-estado` | Estado del LLM propio |
| POST | `/api/v1/ai/preguntar-modelo` | **Usuario → Modelo propio → Respuesta** |
| GET | `/api/v1/ml/experimentos` | Métricas de entrenamiento (curva de loss) |
| POST | `/api/v1/knowledge-gen/generar-curriculo` | Generar dataset con APIs |
| GET | `/api/v1/knowledge-gen/estadisticas` | Independencia de APIs, cobertura |

---

## Documentación científica

- [Arquitectura del LLM y metodología](research/arquitectura_llm.md)
- [Arquitectura científica (rol de las APIs)](research/arquitectura_cientifica.md)
- [Bitácora de investigación](research/bitacora_investigacion.md)
- [Metodología de desarrollo](research/metodologia_desarrollo.md)
- [Guía del módulo ML](ml/README.md)

---

## Nota metodológica

El aporte científico es la **metodología completa y reproducible** de
construcción de un LLM educativo (tokenizer + Transformer + entrenamiento +
inferencia + integración), junto al **dataset curado** y la evaluación. La
calidad del texto depende de la escala de datos y cómputo; con una GPU de 4 GB
se demuestra el método y se obtiene un modelo funcional, no un modelo de
producción a la altura de los comerciales. Esto se documenta en la sección de
limitaciones (ver `research/`).
