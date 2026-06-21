# Metodología de desarrollo

## Enfoque

Investigación aplicada de tipo **diseño y desarrollo de software educativo**
(Design Science Research adaptada). Se construye un artefacto (sistema)
y se evalúa empíricamente su utilidad para fortalecer la comprensión
algorítmica.

## Fases

### Fase 1 — Análisis de necesidades

- Revisión bibliográfica sobre enseñanza de Python y LLMs educativos.
- Caracterización del estudiante de educación superior.
- Identificación de brechas en herramientas existentes.

### Fase 2 — Diseño del sistema

- Definición del contrato JSON pedagógico (`RespuestaIAEducativa`).
- Arquitectura limpia + servicios desacoplados de proveedores IA.
- Diseño del esquema relacional + JSONB en PostgreSQL.

### Fase 3 — Implementación (esta fase)

- Backend FastAPI funcional.
- Frontend Next.js con vista dividida código/explicación.
- Integración Gemini + DeepSeek con auto-curación de JSON.
- Construcción automática del dataset educativo.

### Fase 4 — Validación

- Validación pedagógica de N registros del dataset por investigador.
- Pruebas funcionales (rutas + casos límite).
- Pruebas con usuarios estudiantes (instrumento en
 [instrumentos_evaluacion.md](instrumentos_evaluacion.md)).

### Fase 5 — Análisis y reporte

- Cálculo de métricas en `/research/reporte-general`.
- Análisis cualitativo de respuestas estudiantiles.
- Documentación de resultados en [resultados.md](resultados.md).

### Fase 6 — Modelo propio desde cero (V1, 46 M parámetros)

- Diseño de arquitectura Transformer decoder-only clásica
 (PositionalEncoding sinusoidal, Multi-Head Attention, GeLU + LayerNorm).
- Entrenamiento de un tokenizer sentencepiece (vocab 8 000).
- Construcción del corpus combinando datasets públicos + generación con
 Gemini y DeepSeek.
- Entrenamiento en RTX 2050 (4 GB de VRAM) con preset `experto`.
- Resultado: el modelo de 46 millones de parámetros se ejecuta como
 prueba de concepto metodológica; demuestra que el pipeline completo
 (tokenizer + arquitectura + entrenamiento + inferencia) funciona
 desde cero. Se mantiene como contribución académica del documentación,
 bajo el rótulo *Modelo A — prueba de concepto*.

### Fase 7 — Dataset V2 pedagógico enriquecido (junio 2026)

- Extensión del schema con siete campos opcionales nuevos
 (`pensamiento`, `explicacion_por_nivel`, `revision_codigo`,
 `puntuacion`, `version_evolutiva`, `errores_comunes`, `alternativas`).
- Diez tipos pedagógicos cubriendo los doce niveles cognitivos
 identificados en el análisis de necesidades.
- Pipeline de generación con seis proveedores LLM gratuitos (Gemini,
 Groq, DeepSeek, Together AI, Mistral, OpenRouter) en rotación por
 tarea.
- Validadores estrictos por tipo de ejemplo: AST de Python, longitud,
 estructura, ausencia de placeholders, escapado de caracteres de
 control.
- Auditoría automática con umbrales mínimos
 (válidos ≥ 98 %, duplicados ≤ 1 %, código compila ≥ 95 %, CoT
 poblado ≥ 30 %).
- Volumen objetivo: 333 000 ejemplos validados.

Ver [`docs/DATASET_V2.md`](../docs/DATASET_V2.md).

### Fase 8 — Sistema multi-criterio de recompensas

- Definición de seis dimensiones ortogonales de calidad: Seguridad
 (SEG), Legibilidad (LEG), Escalabilidad (ESC), Arquitectura (ARQ),
 Rendimiento (REN), Mantenibilidad (MAN).
- Etiquetado del corpus con ensemble de tres jueces LLM por dimensión,
 agregación con mediana.
- Entrenamiento de seis modelos de recompensa con encoder Transformer
 V2 compartido (~16 M de parámetros total) y cabezas de regresión
 independientes.
- Pérdidas implementadas: MSE multi-dimensional y ranking pairwise.

Ver [`docs/REWARD_MODELS.md`](../docs/REWARD_MODELS.md).

### Fase 9 — Currículum de cinco fases para el modelo B (150 M parámetros)

- Arquitectura modernizada: Transformer V2 con RoPE (rotary position
 embeddings), GQA (grouped-query attention), SwiGLU FFN, RMSNorm y
 FlashAttention v2 vía `F.scaled_dot_product_attention`.
- Cinco fases secuenciales:
 - **Fase 1**: pretraining puro de código (Python, JavaScript, SQL,
 HTML, CSS, Java).
 - **Fase 2**: continued pretraining sobre documentación oficial.
 - **Fase 3**: SFT con chain-of-thought.
 - **Fase 4**: SFT con corpus destilado.
 - **Fase 5a**: SFT con foco en revisión y refactorización.
 - **Fase 5b**: DPO multi-objetivo con pesos por dimensión.
- Cada fase tiene configuración YAML reproducible.
- Hardware: RTX 2050 local + tiers gratuitos de cloud
 (Kaggle T4 16 GB, Modal $30/mes en créditos, Lightning $15/mes).
- Cero presupuesto pago. Costo total proyectado < 10 USD.

Ver [`docs/PLAN_ENTRENAMIENTO_V2.md`](../docs/PLAN_ENTRENAMIENTO_V2.md).

### Fase 10 — Escalado a modelo C (350 M parámetros) y evaluación final

- Repetir el currículum de cinco fases sobre la arquitectura más grande.
- Evaluación contra benchmarks: HumanEval pass@1, MBPP+ pass@1.
- Comparativa cualitativa con 100 prompts educativos juzgados por Gemini.
- Análisis por dimensión usando los reward models propios.
- Redacción del documentación final.

## Trazabilidad

Cada módulo del sistema responde a un objetivo específico (OE1–OE7)
declarado en [`docs/PROPUESTA_INVESTIGACION.md`](../docs/PROPUESTA_INVESTIGACION.md)
y mapeado a archivos concretos en
[`docs/CATALOGO_ARCHIVOS.md`](../docs/CATALOGO_ARCHIVOS.md).
