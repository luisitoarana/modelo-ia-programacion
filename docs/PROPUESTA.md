# Propuesta de Investigación

> Documento de propuesta para el proyecto de investigación en Ciencias de la
> Computación. Sirve como base académica del trabajo. Estructura:
> Problema, justificación, objetivos, marco teórico, metodología,
> resultados esperados, cronograma, contribuciones.
>
> Este documento se actualiza con cada hito relevante del proyecto.

---

## 1. Título tentativo

**"Diseño, construcción y entrenamiento desde cero de un modelo de
lenguaje educativo especializado en programación, mediante currículum
pedagógico multi-fase y destilación de conocimiento de modelos de
lenguaje comerciales."**

---

## 2. Planteamiento del problema

### 2.1 Problema general

Los modelos de lenguaje (LLM) actuales para programación, como GitHub
Copilot, ChatGPT, Claude y Gemini, presentan limitaciones significativas
para uso educativo en hispanohablantes:

1. **Idioma**: la mayoría está optimizada en inglés; sus explicaciones
 en español son traducciones automatizadas con calidad variable.
2. **Enfoque generativo, no pedagógico**: optimizan para producir
 código que funciona, no para explicar el proceso de razonamiento
 detrás de él.
3. **Dependencia de servicios pagos**: requieren conexión constante a
 APIs comerciales, lo que excluye estudiantes en zonas con conectividad
 limitada o recursos económicos restringidos.
4. **Sin trazabilidad académica**: son cajas negras propietarias; no
 se puede estudiar su comportamiento ni publicar resultados sobre su
 funcionamiento interno.
5. **No discriminan calidad multi-criterio**: producen una sola respuesta
 sin evaluar simultáneamente seguridad, legibilidad, escalabilidad,
 arquitectura, rendimiento y mantenibilidad.

### 2.2 Problema específico

Construir, desde cero, un modelo de lenguaje educativo en español
especializado en programación que:
- Genere código *y* explique el proceso mental detrás del código.
- Razone en cuatro niveles pedagógicos (niño, principiante, intermedio,
 profesional).
- Auto-evalúe sus respuestas con un sistema multi-criterio de
 recompensa.
- Sea reproducible, auditable, y entrenado con recursos económicamente
 accesibles (hardware doméstico + tiers gratuitos de cloud).

---

## 3. Justificación

### 3.1 Académica

El proyecto constituye una contribución original en al menos cuatro
áreas:

1. **Arquitectura propia**: un Transformer decoder-only diseñado y
 construido desde cero, con mejoras del estado del arte 2024-2025
 (RoPE, GQA, SwiGLU, RMSNorm, FlashAttention v2), entrenable en
 hardware doméstico (RTX 2050 de 4 GB de VRAM).

2. **Currículum pedagógico de 5 fases**: una propuesta metodológica
 ordenada para el entrenamiento, inspirada en cómo aprende un
 estudiante de programación: lenguajes → documentación → razonamiento
 estructurado → destilación de expertos → revisión senior.

3. **Sistema multi-criterio de recompensa**: seis modelos de recompensa
 especializados (Seguridad, Legibilidad, Escalabilidad, Arquitectura,
 Rendimiento, Mantenibilidad) en lugar del único juez global usado
 en RLAIF tradicional.

4. **Dataset pedagógico V2**: un corpus de 333 000 ejemplos en 10 tipos
 distintos, incluyendo categorías inéditas como "chain-of-thought
 programador", "anti-patrón explicado", "evolución de código v1-v5"
 y "auto-crítica iterativa".

### 3.2 Social

- Acceso democrático a tutoría programática inteligente en español, sin
 dependencia de servicios pagos.
- Aplicable en universidades públicas, academias técnicas, escuelas
 rurales con conectividad limitada.

### 3.3 Tecnológica

- Demuestra que es viable construir un LLM funcional de 120-350 millones
 de parámetros desde cero, con un presupuesto inferior a 10 dólares
 estadounidenses, usando exclusivamente tiers gratuitos de servicios
 cloud.

---

## 4. Objetivos

### 4.1 Objetivo general

Diseñar, implementar, entrenar y evaluar un modelo de lenguaje
educativo especializado en programación, en español, entrenado desde
cero mediante un currículum de cinco fases y alineado con un sistema
multi-criterio de recompensas, demostrando su viabilidad metodológica y
técnica con recursos computacionales accesibles.

### 4.2 Objetivos específicos

| # | Objetivo específico | Producto verificable |
|---|---|---|
| OE1 | Construir un corpus pedagógico de mínimo 300 000 ejemplos en español que cubra los 12 niveles cognitivos identificados (sintaxis, documentación, razonamiento, decisiones, errores, refactorización, arquitectura, seguridad, multinivel pedagógico, revisión, testing, rendimiento). | `data/dataset_v2.jsonl` + reporte de auditoría con métricas de calidad. |
| OE2 | Diseñar e implementar una arquitectura Transformer propia con técnicas de estado del arte (RoPE, GQA, SwiGLU, RMSNorm, FlashAttention v2) entrenable en hardware modesto. | `ml/model/transformer_v2.py` + 5 presets dimensionales (30M, 88M, 150M, 350M, 870M de parámetros). |
| OE3 | Implementar un currículum de 5 fases de entrenamiento con configuraciones reproducibles. | 6 archivos YAML de configuración (fase 1 a 5b) + runner `ml/training/run_fase.py`. |
| OE4 | Diseñar e implementar un sistema multi-criterio de 6 modelos de recompensa con encoder compartido. | `ml/rlhf/reward_model.py` + `entrenar_rm.py` + rúbricas multi-dimensionales (`jueces.py`). |
| OE5 | Implementar Direct Preference Optimization (DPO) multi-objetivo con pesos por dimensión de calidad. | `ml/rlhf/dpo_multi.py` + configuración `fase5b_dpo_B.yaml`. |
| OE6 | Evaluar el modelo resultante contra benchmarks estándar (HumanEval, MBPP+) y compararlo con baselines (modelo previo de 46M de la fase 1, modelos comerciales como Gemini en consultas educativas). | sección de Resultados con tablas comparativas y análisis estadístico. |
| OE7 | Documentar el proceso completo (decisiones, bugs, soluciones, resultados) para que sea reproducible por terceros. | 7 documentos técnicos en `docs/` + documentación final. |

---

## 5. Marco teórico

### 5.1 Modelos de lenguaje basados en Transformer

El proyecto se fundamenta en la arquitectura Transformer
(Vaswani et al., 2017), específicamente la variante decoder-only popularizada
por la familia GPT (Radford et al., 2018; Brown et al., 2020). Esta
arquitectura ha demostrado escalabilidad excepcional en tareas de
generación de lenguaje natural y de código.

### 5.2 Mejoras arquitectónicas modernas

Se incorporan cinco mejoras provenientes de modelos de estado del arte
(Llama, Mistral, Qwen, DeepSeek):

- **Rotary Position Embeddings (RoPE)** (Su et al., 2021): codificación
 posicional por rotación de vectores. Permite extrapolar contexto sin
 reentrenamiento mediante técnicas como YaRN.
- **Grouped-Query Attention (GQA)** (Ainslie et al., 2023): reducción
 del KV-cache por compartición de keys y values entre grupos de heads.
- **SwiGLU** (Shazeer, 2020): activación con gating sigmoide que
 reemplaza la combinación clásica GeLU + MLP de dos capas.
- **RMSNorm** (Zhang & Sennrich, 2019): normalización por raíz cuadrada
 media (sin sustracción de promedio), más rápida que LayerNorm.
- **FlashAttention v2** (Dao, 2023): kernel CUDA que evita materializar
 la matriz de atención N×N.

### 5.3 Preentrenamiento por currículum

El currículum learning (Bengio et al., 2009) propone presentar al modelo
ejemplos en orden de dificultad creciente para acelerar la convergencia
y mejorar la generalización. Esta propuesta adopta una variante por
*fases temáticas*: primero código puro, después documentación, después
razonamiento estructurado, después destilación de expertos, finalmente
revisión senior. Cada fase usa el checkpoint de la fase anterior como
inicialización.

### 5.4 Destilación de conocimiento desde LLM comerciales

Hsieh et al. (2023) y Magicoder (Wei et al., 2024) demostraron que
modelos pequeños pueden alcanzar desempeño competitivo entrenándose
sobre datos sintéticos generados por modelos más grandes. Este proyecto
extiende la idea: usa cinco proveedores en rotación (Gemini, Groq,
DeepSeek, Together AI, Mistral, OpenRouter) para construir un corpus
diverso y de alta calidad, aprovechando exclusivamente sus tiers gratuitos.

### 5.5 RLHF y RLAIF

Reinforcement Learning from Human Feedback (RLHF) introducido por
Christiano et al. (2017) y popularizado por InstructGPT
(Ouyang et al., 2022) alinea modelos con preferencias humanas. RLAIF
(Lee et al., 2023) reemplaza el feedback humano por feedback de un
modelo juez LLM, lo que permite escalar.

Esta propuesta innova al introducir **6 modelos de recompensa
especializados** en lugar de uno solo, alineados con dimensiones
distintas de calidad de código. Adicionalmente, Direct Preference
Optimization (DPO) (Rafailov et al., 2023) reemplaza el ciclo PPO
clásico por una pérdida cerrada, más eficiente y estable, que cabe en
hardware modesto.

### 5.6 Sistema multi-criterio (contribución original)

Se introduce una taxonomía de calidad de código en seis dimensiones
ortogonales:

1. **SEG** — Seguridad (OWASP, gestión de secretos, sanitización).
2. **LEG** — Legibilidad (nombres, estructura, formato).
3. **ESC** — Escalabilidad (complejidad algorítmica, memoria).
4. **ARQ** — Arquitectura (separación, dependencias, patrones).
5. **REN** — Rendimiento (optimizaciones, ausencia de redundancia).
6. **MAN** — Mantenibilidad (tests, error handling, documentación).

Esta granularidad permite, en producción, ajustar el "perfil" del
modelo en tiempo de inferencia mediante pesos configurables sin
reentrenar.

---

## 6. Metodología

### 6.1 Tipo de investigación

**Aplicada, experimental y de desarrollo.** Se diseña, construye y
evalúa un artefacto tecnológico (el modelo de lenguaje educativo) con
metodología reproducible y experimentos controlados.

### 6.2 Diseño metodológico

El proyecto adopta una metodología de desarrollo iterativo en tres
fases temporales:

#### Mes 1 — Construcción del dataset
- Implementación de 10 generadores de dataset, cada uno enfocado en un
 tipo pedagógico específico.
- Validadores automáticos de calidad (sintaxis, estructura, longitud,
 presencia de chain-of-thought, escapado de control characters).
- Auditoría con umbrales mínimos antes de aceptar el corpus para
 entrenamiento.
- Etiquetado del corpus con seis jueces LLM (uno por dimensión de
 calidad), almacenando *scores* numéricos por dimensión.

#### Mes 2 — Entrenamiento de los modelos
- **Fase 1** (Pretraining puro de código): un modelo de 120 millones de
 parámetros recibe corpus crudo de Python, JavaScript, SQL, HTML, CSS
 y Java para aprender sintaxis y patrones léxicos.
- **Fase 2** (Continued pretraining sobre documentación): el checkpoint
 de Fase 1 se especializa con documentación oficial scrappeada (Python
 Docs, MDN, PEPs, PostgreSQL Docs, Docker, manuales de Linux).
- **Fase 3** (SFT con chain-of-thought): entrenamiento supervisado con
 el subset del corpus que contiene razonamiento estructurado explícito
 (tipos `pensamiento_programador`, `decision_diseno`,
 `arquitectura_sistema`, `pensamiento_autocritico`).
- **Fase 4** (SFT con corpus destilado): entrenamiento supervisado con
 el resto del corpus pedagógico (explicaciones, generación,
 conceptos, multinivel).
- **Entrenamiento de los 6 reward models**: el dataset etiquetado por
 los jueces LLM se usa para entrenar seis modelos de recompensa con
 encoder compartido (~16 millones de parámetros totales).

#### Mes 3 — Alineación y evaluación
- **Fase 5a** (SFT senior): entrenamiento con los tipos enfocados en
 revisión (`anti_patron`, `bug_sutil`, `evolucion_codigo`, `seguridad`,
 `testing_complejidad`).
- **Fase 5b** (DPO multi-objetivo): el modelo se alinea con
 preferencias generadas a partir de los reward models, ponderadas por
 dimensión de calidad.
- Evaluación final: HumanEval pass@1, MBPP+ pass@1, comparativa con el
 modelo de 46M previo, análisis cualitativo con 100 prompts educativos.
- Redacción del documentación y presentación.

### 6.3 Hardware y recursos

| Recurso | Uso |
|---|---|
| RTX 2050 de 4 GB (local) | Prototipado rápido, validación de pipelines, ejecución del modelo de 46M. |
| Kaggle Notebooks (30 horas semanales GPU T4 16 GB gratuitas) | Entrenamiento de las fases del modelo de 120 M. |
| Modal Labs ($30 USD/mes en créditos gratis) | Ejecuciones largas que excedan el límite de Kaggle. |
| Lightning AI Studios ($15 USD/mes en créditos gratis) | Backup y experimentos paralelos. |
| Tiers gratuitos de APIs (Gemini, Groq, Together, DeepSeek, Mistral, OpenRouter) | Generación del corpus mediante destilación. |

**Costo total proyectado: menos de 10 dólares estadounidenses** (solo
electricidad).

### 6.4 Variables e indicadores

| Variable | Indicador | Instrumento |
|---|---|---|
| Calidad técnica del modelo | Loss validación al final de cada fase | Curvas de entrenamiento (`metrics.jsonl`). |
| Capacidad de generación de código | HumanEval pass@1, MBPP+ pass@1 | Benchmark automatizado. |
| Capacidad pedagógica | Score subjetivo en 100 prompts educativos | Rúbrica humana + juez Gemini. |
| Calidad multi-criterio | Win rate del modelo final vs. baseline en cada dimensión | Test pareado contra modelo de 46M. |
| Eficiencia económica | Costo total en USD | Bitácora de gastos. |
| Eficiencia temporal | Horas-GPU usadas por fase | Logs de Kaggle/Modal. |

### 6.5 Reproducibilidad

Todo el código fuente, datasets generados, configuraciones YAML,
checkpoints y métricas se publicarán en un repositorio público al
finalizar el proyecto, con instrucciones paso a paso para reproducir
cada fase del entrenamiento.

---

## 7. Resultados esperados

### 7.1 Cuantitativos

| Métrica | Baseline (46M actual) | Modelo B (120M) | Modelo C (350M) |
|---|---|---|---|
| Loss validación final | < 4.5 | < 3.0 | < 2.5 |
| HumanEval pass@1 | ~5% | 15–20% | 30–35% |
| MBPP+ pass@1 | ~8% | ~20% | ~35% |
| Win rate vs. baseline (juez Gemini) | — | > 70% | > 85% |
| Score pedagógico (1–10) | ~5 | ~7 | ~8 |
| Porcentaje de respuestas con chain-of-thought visible | 0% | > 50% | > 70% |

### 7.2 Cualitativos

- Las respuestas presentarán análisis previo al código, justificación
 de la solución elegida, alternativas descartadas con razones.
- La explicación pedagógica se adaptará al nivel solicitado (niño,
 principiante, intermedio, profesional) en consultas que lo requieran.
- El modelo detectará anti-patrones y propondrá refactorización
 argumentada.
- Generará tests unitarios y análisis de complejidad cuando se le
 solicite implementar un algoritmo.

### 7.3 Productos de investigación

1. Artefacto software: el modelo entrenado en sus tres tamaños (46M
 existente, 120M y 350M nuevos) más sistema de inferencia local.
2. Dataset pedagógico: 333 000 ejemplos en 10 tipos pedagógicos,
 publicable como recurso open para la comunidad académica.
3. Sistema multi-criterio: 6 reward models entrenados, exportables como
 herramienta independiente para evaluación de código en otros
 sistemas.
4. Documentación: documento del proyecto con metodología, experimentos y
 resultados.
5. Documentación técnica: 8 documentos en el directorio `docs/` con
 detalle exhaustivo del proceso.

---

## 8. Cronograma

| Mes | Semana | Actividad |
|---|---|---|
| 1 | 1 | Implementación de schema V2, validadores, pool de generadores. |
| 1 | 2 | Implementación de los 10 generadores de dataset. |
| 1 | 3 | Generación del corpus completo (333 000 ejemplos). |
| 1 | 4 | Etiquetado con los 6 jueces LLM, auditoría de calidad. |
| 2 | 5 | Entrenamiento Fase 1 (modelo B, pretraining de código). |
| 2 | 6 | Entrenamiento Fase 2 (continued pretraining sobre documentación). |
| 2 | 7 | Entrenamiento Fase 3 (SFT con chain-of-thought). |
| 2 | 8 | Entrenamiento de los 6 reward models. |
| 3 | 9 | Entrenamiento Fase 4 (SFT destilación) y 5a (SFT senior). |
| 3 | 10 | Entrenamiento Fase 5b (DPO multi-criterio). |
| 3 | 11 | Evaluación final, benchmarks, análisis cualitativo. |
| 3 | 12 | Redacción del documentación, preparación de presentación. |

---

## 9. Aportes y contribuciones esperadas

### 9.1 Contribuciones científicas originales

1. **Metodología de currículum por fases temáticas** para entrenamiento
 de LLM educativos desde cero con recursos limitados.
2. **Sistema multi-criterio de recompensa** (6 dimensiones) para RLAIF
 en código.
3. **Dataset pedagógico V2** con 10 tipos enfocados en razonamiento
 estructurado y no solo generación.
4. **Demostración de viabilidad económica**: proyecto completa de LLM con
 menos de 10 USD de presupuesto.

### 9.2 Productos publicables

- documentación del proyecto.
- Artículo en workshop de NLP educativo (e.g. ACL Workshop on Educational
 Applications, EMNLP).
- Repositorio público con código y datasets.

---

## 10. Documentos técnicos relacionados

Esta propuesta es la portada académica del proyecto. La metodología
detallada, decisiones de diseño y registro de implementación están en:

- [`docs/ARQUITECTURA_TECNICA.md`](./ARQUITECTURA_TECNICA.md): descripción
 exhaustiva de cada componente.
- [`docs/CATALOGO_ARCHIVOS.md`](./CATALOGO_ARCHIVOS.md): inventario de
 todos los archivos del proyecto.
- [`docs/BITACORA_DESARROLLO.md`](./BITACORA_DESARROLLO.md): registro
 cronológico de desarrollo.
- [`docs/DECISIONES_DISENO.md`](./DECISIONES_DISENO.md): cada decisión
 técnica con su justificación.
- [`docs/BUGS_Y_SOLUCIONES.md`](./BUGS_Y_SOLUCIONES.md): incidentes
 encontrados y resueltos.
- [`docs/EXPERIMENTOS.md`](./EXPERIMENTOS.md): resultados de cada
 prueba.
- [`docs/DATASET_V2.md`](./DATASET_V2.md): especificación del corpus
 pedagógico.
- [`docs/REWARD_MODELS.md`](./REWARD_MODELS.md): especificación del
 sistema multi-criterio.
- [`docs/PLAN_ENTRENAMIENTO_V2.md`](./PLAN_ENTRENAMIENTO_V2.md): plan
 técnico de entrenamiento.

---

## 11. Referencias bibliográficas seleccionadas

1. Vaswani, A. et al. (2017). *Attention Is All You Need*. NeurIPS.
2. Brown, T. et al. (2020). *Language Models are Few-Shot Learners*. NeurIPS (GPT-3).
3. Bengio, Y. et al. (2009). *Curriculum learning*. ICML.
4. Su, J. et al. (2021). *RoFormer: Enhanced Transformer with Rotary Position Embedding*.
5. Ainslie, J. et al. (2023). *GQA: Training Generalized Multi-Query Transformer Models from Multi-Head Checkpoints*.
6. Shazeer, N. (2020). *GLU Variants Improve Transformer*.
7. Zhang, B. & Sennrich, R. (2019). *Root Mean Square Layer Normalization*.
8. Dao, T. (2023). *FlashAttention-2: Faster Attention with Better Parallelism*.
9. Ouyang, L. et al. (2022). *Training language models to follow instructions with human feedback* (InstructGPT).
10. Christiano, P. et al. (2017). *Deep Reinforcement Learning from Human Preferences*.
11. Lee, H. et al. (2023). *RLAIF: Scaling Reinforcement Learning from Human Feedback with AI Feedback*.
12. Rafailov, R. et al. (2023). *Direct Preference Optimization: Your Language Model is Secretly a Reward Model*. NeurIPS.
13. Wei, X. et al. (2024). *Magicoder: Source Code Is All You Need*.
14. Hsieh, C.-Y. et al. (2023). *Distilling Step-by-Step!*. ACL.
15. Wei, J. et al. (2022). *Chain-of-Thought Prompting Elicits Reasoning in Large Language Models*. NeurIPS.
