# Catálogo de Archivos del Sistema

> Inventario completo de cada archivo creado o modificado durante el
> desarrollo. Listado por carpeta, con propósito de cada componente,
> dependencias internas, y a qué objetivo específico de la
> [propuesta de investigación](./PROPUESTA_INVESTIGACION.md) responde.
>
> Sirve como índice técnico para el sección de Implementación de la
> proyecto.

---

## 1. Estructura general del repositorio

```
sistema-explicador-python-ia/
├── backend/ Backend FastAPI + Postgres + JWT (fase 1, existente)
├── frontend/ Frontend Next.js + Tailwind (fase 1, existente)
├── app-desktop/ Aplicación de escritorio Flutter (fase 1, existente)
├── mcp_server/ Model Context Protocol server (fase 1, existente)
├── ml/ *** Núcleo de el proyecto: modelo, datos, RLHF, training ***
├── data/ Corpus crudo y procesado
├── datasets/ Datasets generados con APIs y públicos
├── training/ Checkpoints y experimentos
├── models/ Modelos serializados para inferencia
├── docs/ *** Documentación técnica completa ***
├── research/ Bitácora científica y artículos de investigación
├── docker/ Configuración de contenedores
├── scripts/ Scripts auxiliares
└── logs/ Salida de procesos largos
```

---

## 2. Módulo `ml/data/` — Pipeline de construcción de datasets

### 2.1 Existentes (antes de esta sesión)

| Archivo | Función |
|---|---|
| `corpus.py` | Funciones de carga, guardado, deduplicación y estadísticas de corpus JSONL. |
| `generator.py` | Generador original de dataset V1 con Gemini y DeepSeek (mantenido por compatibilidad). |
| `loader.py` | Cargador de tensores para el trainer V1. |
| `download_hf.py` | Descarga de datasets de HuggingFace. |
| `seed.py` | Corpus semilla local. |
| `combinar.py` | Combinación de archivos JSONL con deduplicación. |
| `vision_dataset.py` | Dataset para entrenamiento multimodal de visión. |
| `generar_imagenes_codigo.py` | Generación de imágenes de código para multimodal. |

### 2.2 Creados o modificados en esta sesión

| Archivo | Líneas | Propósito | Responde a |
|---|---|---|---|
| `schema.py` | ~150 | **Modificado**: extendido con 10 tipos pedagógicos V2 (`pensamiento_programador`, `explicacion_multinivel`, `anti_patron`, `bug_sutil`, `evolucion_codigo`, `decision_diseno`, `arquitectura_sistema`, `seguridad`, `testing_complejidad`, `pensamiento_autocritico`) y 7 campos opcionales (`pensamiento`, `explicacion_por_nivel`, `alternativas`, `errores_comunes`, `revision_codigo`, `puntuacion`, `version_evolutiva`). | OE1 |
| `validadores.py` | ~250 | **Nuevo**: validadores de calidad pedagógica. Funciones: `validar_codigo_python` (compila con AST), `validar_pensamiento` (chain-of-thought bien formado), `validar_multinivel` (4 niveles distintos), `validar_revision_codigo` (anti-patrón con problemas), `validar_autocritica` (iteraciones A→B→C), `validar_puntuacion` (6 dim en rango), `validar_salida_pedagogica` (longitud y placeholders), `validar_ejemplo` (validador agregado por tipo). | OE1 |
| `pool_generadores.py` | ~360 | **Nuevo**: abstracción común sobre 6 proveedores free (Gemini, DeepSeek, Groq, Together AI, Mistral, OpenRouter). Token-bucket rate limiter, rotación por prioridad de tarea (`Tarea.COT`, `Tarea.CODIGO`, `Tarea.EVALUACION`, `Tarea.VOLUMEN`, etc.), fallback automático, manejo de errores 429 con espera fija de 60 segundos, extractor robusto de JSON con balanceador de llaves (`_extraer_objetos_balanceados`). | OE1 |
| `audit.py` | ~250 | **Nuevo**: auditoría completa del corpus. Métricas: porcentaje de válidos, duplicados, distribución por tipo / nivel / tema / fuente, longitudes promedio y mediana, porcentaje de código que compila (AST), porcentaje con chain-of-thought poblado, idioma. Define umbrales mínimos en `OBJETIVOS` y reporta advertencias. | OE1 |
| `construir_dataset_v2.py` | ~270 | **Nuevo**: orquestador de los 10 generadores. Soporta 3 escalas (`mini`, `media`, `completa`), reanudación entre fallos (`--skip`, `--reset`), consolidación final con deduplicación, auditoría automática post-generación. | OE1 |
| `download_hf.py` | ~400 | **Modificado**: 7 datasets nuevos (Magicoder OSS-Instruct, Magicoder Evol, APPS, DS-1000, OpenCodeInterpreter, HumanEval+, MBPP+). 17 datasets totales registrados, mapeo V1→V2 con metadata, flag `--schema-v2`. | OE1 |
| `generar_pensamiento.py` | ~180 | **Nuevo**: generador de `pensamiento_programador` (chain-of-thought). 20 objetivos (tema × nivel). Template del resto de generadores. | OE1 |
| `generar_multinivel.py` | ~170 | **Nuevo**: generador de `explicacion_multinivel`. 20 conceptos, cada uno explicado en 4 niveles (niño / principiante / intermedio / profesional). | OE1 |
| `generar_antipatron.py` | ~180 | **Nuevo**: generador de `anti_patron`. 30 antipatrones canónicos con análisis y refactorización. | OE1 |
| `generar_bug_sutil.py` | ~175 | **Nuevo**: generador de `bug_sutil`. 25 categorías de bugs lógicos (off-by-one, mutable defaults, late binding, etc.) con diagnóstico y corrección. | OE1 |
| `generar_evolucion.py` | ~180 | **Nuevo**: generador de `evolucion_codigo`. 15 problemas × 5 versiones (junior → junior+ → mid → senior → staff). | OE1 |
| `generar_decision.py` | ~180 | **Nuevo**: generador de `decision_diseno`. 30 decisiones técnicas comparativas (PostgreSQL vs MongoDB, FastAPI vs Flask, etc.). | OE1 |
| `generar_arquitectura.py` | ~175 | **Nuevo**: generador de `arquitectura_sistema`. 25 sistemas con diseño end-to-end (red social 1M usuarios, plataforma streaming, etc.). | OE1 |
| `generar_seguridad.py` | ~190 | **Nuevo**: generador de `seguridad`. 25 categorías OWASP Top 10 + criptografía + secrets. | OE1 |
| `generar_testing.py` | ~180 | **Nuevo**: generador de `testing_complejidad`. 25 casos con unit tests + integration tests + análisis Big-O. | OE1 |
| `generar_autocritica.py` | ~175 | **Nuevo**: generador de `pensamiento_autocritico` (Nivel 12 de la visión). 20 problemas con iteraciones A → B → C, cada una con código y autocrítica. | OE1 |

---

## 3. Módulo `ml/rlhf/` — Sistema multi-criterio de recompensas

### 3.1 Existentes

| Archivo | Función |
|---|---|
| `dpo.py` | Implementación DPO clásica de la fase anterior (single-judge). |
| `preparar_pares.py` | Preparación de pares chosen/rejected con RLAIF (single-judge Gemini). |
| `exportar_dataset.py` | Exportador de dataset DPO a formato estándar. |

### 3.2 Creados en esta sesión

| Archivo | Líneas | Propósito | Responde a |
|---|---|---|---|
| `jueces.py` | ~250 | **Nuevo**: rúbricas multi-criterio para SEG / LEG / ESC / ARQ / REN / MAN. Función `calificar_respuesta` que llama 3 jueces por dimensión y agrega con mediana. Reduce sesgo de un solo juez. | OE4 |
| `etiquetar_dataset.py` | ~230 | **Nuevo**: pipeline que recorre un JSONL de respuestas y le agrega scores multi-criterio. Reanudación automática (hash sha1 de prompt+respuesta), concurrencia limitada con semáforo, progreso con velocidad y ETA. | OE4 |
| `reward_model.py` | ~330 | **Nuevo**: arquitectura `MultiCriteriaRewardModel` con encoder Transformer V2 compartido + 6 heads de regresión. 3 presets (pequeño 8M, mediano 16M, grande 32M). Soporte para pooling mean / last / attention. Funciones de pérdida MSE multi-dim y ranking pairwise. | OE4 |
| `entrenar_rm.py` | ~340 | **Nuevo**: trainer para los 6 reward models. Dataset `RMScoresDataset` que lee JSONL etiquetado. Evaluación con Pearson correlation por dimensión. Soporte para modo MSE y modo ranking. Resume automático. | OE4 |
| `dpo_multi.py` | ~410 | **Nuevo**: implementación de DPO multi-objetivo. Carga modelo entrenable (Fase 5a) y modelo referencia congelado. `DPODataset` que lee múltiples archivos (uno por dimensión) o uno solo con campo `dim`. Pérdida `loss_dpo_multi` con pesos por dimensión. Gradient checkpointing para que dos forwards + uno de referencia quepan en RTX 2050. | OE5 |
| `configs/rm_v1.yaml` | 50 | Configuración para entrenamiento RM (preset mediano, MSE loss, pesos por dimensión). | OE4 |

---

## 4. Módulo `ml/model/` — Arquitectura del modelo

### 4.1 Existentes

| Archivo | Función |
|---|---|
| `transformer.py` | Arquitectura V1 (GPTEducativo, ~46M de la fase 1, PosEnc sinusoidal + MHA + GeLU + LayerNorm). |
| `multimodal_model.py` | Modelo multimodal con ViT propio + projector + LLM (fase de visión). |
| `vision/` | Submódulo del Vision Transformer propio. |

### 4.2 Creados o modificados

| Archivo | Líneas | Propósito | Responde a |
|---|---|---|---|
| `transformer_v2.py` | ~450 | **Modificado**: agregado `gradient_checkpointing_enable` / `disable` para reducir uso de VRAM en backward (clave para entrenar modelo B en RTX 2050). El resto ya existía: arquitectura V2 con RoPE (rotary position embeddings), GQA (grouped-query attention), SwiGLU, RMSNorm, FlashAttention v2 vía `F.scaled_dot_product_attention`. Interfaz compatible con V1 para sustitución sin tocar el resto. | OE2 |

---

## 5. Módulo `ml/training/` — Pipeline de entrenamiento del LLM

### 5.1 Existentes

| Archivo | Función |
|---|---|
| `trainer.py` | Trainer original para modelo V1 (fase 1, existente). |

### 5.2 Creados en esta sesión

| Archivo | Líneas | Propósito | Responde a |
|---|---|---|---|
| `run_fase.py` | ~400 | **Nuevo**: runner por YAML para las fases de entrenamiento del modelo B. `_Tokenizer` (wrapper sentencepiece), `PretrainDataset` (lee `.txt`), `SFTDataset` (lee JSONL con schema V2 y aplica template chat con masking de prompt), `TrainerV2` (loop con autocast FP16/BF16, gradient accumulation, gradient clipping, gradient checkpointing opcional, cosine LR con warmup, resume entre sesiones, chunking Kaggle 9 horas, métricas a `metrics.jsonl`, captura de SIGINT). | OE3 |
| `configs/fase1_pretrain_B.yaml` | 60 | Fase 1: pretraining puro en código Python, JavaScript, SQL, HTML, CSS, Java. Preset `sota_b` (150M params). | OE3 |
| `configs/fase2_docs_B.yaml` | 50 | Fase 2: continued pretraining sobre documentación oficial. | OE3 |
| `configs/fase3_cot_B.yaml` | 50 | Fase 3: SFT con chain-of-thought (subset del corpus con `pensamiento_programador`, `decision_diseno`, `arquitectura_sistema`, `pensamiento_autocritico`). | OE3 |
| `configs/fase4_distillation_B.yaml` | 50 | Fase 4: SFT con corpus destilado de LLMs comerciales. | OE3 |
| `configs/fase5a_senior_B.yaml` | 50 | Fase 5a: SFT con foco en revisión y refactorización (`anti_patron`, `bug_sutil`, `evolucion_codigo`, `seguridad`, `testing_complejidad`). | OE3 |
| `configs/fase5b_dpo_B.yaml` | 60 | Fase 5b: DPO multi-criterio sobre el checkpoint de Fase 5a. Pesos por dimensión. | OE5 |

---

## 6. Módulo `ml/config.py`

| Archivo | Líneas modificadas | Propósito |
|---|---|---|
| `config.py` | +60 | **Modificado**: agregadas las clases y funciones para los presets V2. `PRESETS_V2` con 5 entradas: `sota_experto` (30M), `sota_grande` (88M), `sota_b` (150M, modelo B del plan), `sota_c` (350M, modelo C del plan), `sota_d` (870M, modelo D opcional). |

---

## 7. Documentación en `docs/`

### 7.1 Existentes

| Archivo | Función |
|---|---|
| `AGENTE.md`, `MCP_PLAN.md` | Plan de capacidades agénticas. |
| `HOJA_DE_RUTA.md` | Roadmap del proyecto. |
| `ENTRENAMIENTO.md` | Guía de entrenamiento del modelo V1 (46M). |
| `RLHF_PLAN.md` | Plan original de RLHF (single-judge). |
| `VISION_PLAN.md`, `VISION_PROPIA.md` | Plan multimodal. |
| `MEJORAS_NIVEL_TOP.md` | Análisis de gaps vs estado del arte. |
| `MODELO_V2.md`, `CAMBIOS_RECIENTES.md` | Notas técnicas. |
| `api_documentation.md`, `arquitectura.md`, `documentacion_tecnica.md`, `instalacion.md`, `INSTALACION_JURADO.md`, `manual_administrador.md`, `manual_usuario.md` | Documentación de la fase 1. |
| `RAG.md` | Sistema RAG. |

### 7.2 Creados o modificados en esta sesión

| Archivo | Líneas | Propósito |
|---|---|---|
| `DATASET_V2.md` | ~500 | Especificación completa del corpus pedagógico V2: schema extendido, 10 tipos de dataset, mezcla objetivo (333k ejemplos), pipeline de generación con APIs gratuitas, datasets públicos a integrar, plan de actualización continua. |
| `REWARD_MODELS.md` | ~400 | Sistema de 6 reward models multi-criterio: 6 dimensiones de calidad, pipeline en 3 fases (etiquetado con jueces LLM → entrenamiento RM propios → uso en producción), arquitectura técnica, configuración del ensemble de jueces, métricas de validación. |
| `PLAN_ENTRENAMIENTO_V2.md` | ~600 | **Reescrito**: plan técnico de entrenamiento desde cero (sin descargar modelos base externos). 5 fases del currículum, hardware realista, configuraciones por fase, sistema de regeneración por puntuación, auto-crítica, estructura de archivos. |
| `PROPUESTA_INVESTIGACION.md` | ~450 | **Nuevo**: propuesta académica formal. Problema, justificación, objetivos general y específicos, marco teórico, metodología, resultados esperados, cronograma, contribuciones, referencias. Base para el documento de propuesta del proyecto. |
| `CATALOGO_ARCHIVOS.md` | (este) | Inventario completo de archivos creados o modificados. |
| `BITACORA_DESARROLLO.md` | ~400 | Registro cronológico del desarrollo de esta sesión: qué se hizo en cada paso, en qué orden, qué decisiones se tomaron. |
| `ARQUITECTURA_TECNICA.md` | ~500 | Descripción técnica detallada de cada componente (data flow, dependencias, contratos). |
| `DECISIONES_DISENO.md` | ~400 | Cada decisión técnica con justificación y alternativas consideradas. |
| `BUGS_Y_SOLUCIONES.md` | ~300 | Incidentes encontrados durante implementación, causa raíz, solución, lecciones aprendidas. |
| `EXPERIMENTOS.md` | ~250 | Registro de smoke tests, configuraciones probadas, métricas obtenidas. |

---

## 8. Investigación en `research/`

| Archivo | Modificado en esta sesión |
|---|---|
| `bitacora_investigacion.md` | Sí — agregada entrada del trabajo de esta sesión. |
| `arquitectura_llm.md` | No — describe arquitectura V1; pendiente actualizar con V2. |
| `arquitectura_cientifica.md` | No — pendiente actualizar con los aportes nuevos. |
| `capacidades_ia_avanzada.md`, `instrumentos_evaluacion.md`, `metodologia_desarrollo.md`, `plan_pruebas.md`, `resultados.md`, `validacion_dataset.md` | No tocados, pendientes revisión. |

---

## 9. Scripts auxiliares

| Archivo | Propósito |
|---|---|
| `scripts/debug_parser.py` | **Nuevo**: utilidad de debug end-to-end del pipeline pool → parser → validador. Usado para identificar los bugs reportados en [BUGS_Y_SOLUCIONES.md](./BUGS_Y_SOLUCIONES.md). |

---

## 10. Tabla resumen — cobertura de objetivos específicos

| OE | Archivos clave responsables |
|---|---|
| **OE1** — Corpus pedagógico de 300 000+ ejemplos | `schema.py`, `validadores.py`, `pool_generadores.py`, `audit.py`, `construir_dataset_v2.py`, 10 generadores, `download_hf.py` |
| **OE2** — Arquitectura propia con técnicas SOTA | `transformer_v2.py`, `config.py` (presets V2) |
| **OE3** — Currículum de 5 fases con configs reproducibles | `run_fase.py`, 6 YAMLs en `ml/training/configs/` |
| **OE4** — Sistema multi-criterio de 6 reward models | `jueces.py`, `etiquetar_dataset.py`, `reward_model.py`, `entrenar_rm.py`, `rm_v1.yaml` |
| **OE5** — DPO multi-objetivo con pesos por dimensión | `dpo_multi.py`, `fase5b_dpo_B.yaml` |
| **OE6** — Evaluación contra benchmarks | Pendiente — script de evaluación en mes 3 |
| **OE7** — Documentación reproducible | 10 documentos en `docs/` |
