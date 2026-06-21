# Decisiones de Diseño

> Cada decisión técnica tomada en el proyecto, con su justificación,
> alternativas consideradas y razones del descarte. Esta sección es
> crítica para la presentación de el proyecto: el revisor preguntará "por qué
> elegiste X y no Y", y aquí está la respuesta documentada.

---

## DD-01: Modelo desde cero, no continued pretraining sobre un base externo

**Decisión:** entrenar el modelo de lenguaje desde cero (random
initialization), sin descargar ningún modelo base como Qwen, Llama o
SmolLM.

**Alternativas consideradas:**

1. Continued pretraining sobre `Qwen2.5-Coder-1.5B`.
2. Fine-tuning con LoRA sobre `SmolLM2-1.7B`.
3. Entrenamiento desde cero.

**Justificación de la elegida:**

- La visión del proyecto, articulada explícitamente por el autor, es
 "mi propio modelo, mi propia arquitectura, mis propios pesos, mi
 propio entrenamiento, mi propia especialización en programación".
- Académicamente, el aporte de el proyecto es la metodología de
 entrenamiento (currículum de cinco fases, sistema multi-criterio,
 dataset propio), no la calidad absoluta de los benchmarks. Esa
 metodología se demuestra mejor con un modelo construido desde cero.
- un proyecto que ajusta un modelo preentrenado externo no se diferencia
 de cualquier startup; un proyecto que construye desde cero con
 recursos limitados es publicable en un workshop de NLP educativo.

**Implicaciones:**

- Los tamaños objetivo deben ser realistas para hardware modesto:
 modelo A (46M, ya entrenado), modelo B (120M), modelo C (350M).
- Los benchmarks absolutos serán menores que los de modelos
 comerciales. Esto se compensa con análisis honesto de la
 contribución metodológica.

---

## DD-02: Schema V2 con campos opcionales en lugar de schema separado

**Decisión:** extender `EjemploEntrenamiento` con campos opcionales
(`pensamiento`, `explicacion_por_nivel`, etc.) en lugar de crear una
clase separada `EjemploEntrenamientoV2`.

**Alternativas consideradas:**

1. Schema V2 como clase separada con conversión.
2. Schema único con todos los campos siempre presentes (con None).
3. Schema único con campos opcionales no serializados cuando son None.

**Justificación de la elegida (opción 3):**

- Compatibilidad total con el corpus de 187 000 ejemplos V1 ya
 existente.
- Archivos JSONL más pequeños (los campos None no se escriben).
- El validador puede ramificar por tipo sin renombrar clases.
- Los consumidores V1 ignoran silenciosamente los campos extra.

---

## DD-03: Pool de seis proveedores con rotación por tarea

**Decisión:** integrar seis proveedores LLM gratuitos (Gemini, Groq,
DeepSeek, Together AI, Mistral, OpenRouter) en un pool con prioridades
distintas según el tipo de tarea.

**Alternativas consideradas:**

1. Un único proveedor (el más generoso).
2. Round-robin simple entre todos los proveedores configurados.
3. Pool con prioridades por tarea y fallback.

**Justificación de la elegida (opción 3):**

- Cada proveedor tiene fortalezas distintas: Gemini es excelente en
 chain-of-thought y razonamiento, DeepSeek genera mejor código (esa
 era su especialización), Groq es rapidísimo, Together AI tiene los
 modelos Llama más nuevos, Mistral aporta diversidad europea,
 OpenRouter sirve como fallback gratuito.
- Las prioridades por tarea aprovechan estas diferencias.
- El fallback automático protege contra caídas o saturación temporal
 de un proveedor.

**Tradeoffs aceptados:**

- Mayor complejidad del código del pool.
- Necesidad de mantener configuración de seis proveedores.
- Variabilidad en el estilo del corpus generado (mitigado con
 validadores estrictos y auditoría posterior).

---

## DD-04: Validadores estrictos en lugar de generar y limpiar después

**Decisión:** validar cada ejemplo inmediatamente al generarlo,
descartando los inválidos en lugar de aceptar todo y limpiar después.

**Alternativas consideradas:**

1. Aceptar todo y filtrar en un paso posterior.
2. Validar al generar y descartar al instante.
3. Validar al generar, descartar inválidos pero guardar muestra para
 análisis.

**Justificación de la elegida (opción 2 con elementos de la 3):**

- Los proveedores LLM gratuitos alucinan más que los de pago. Sin
 filtrado estricto, el corpus se llena de basura.
- Descartar al instante evita gastar espacio en disco con datos
 inservibles.
- El reporte de auditoría guarda el conteo por motivo de descarte
 (`descartados_por_motivo`), lo que sirve como análisis sin necesidad
 de guardar las muestras malas completas.

---

## DD-05: Seis dimensiones de calidad en lugar de tres o doce

**Decisión:** definir seis dimensiones ortogonales (SEG, LEG, ESC, ARQ,
REN, MAN).

**Alternativas consideradas:**

1. Tres dimensiones (correctness, clarity, style).
2. Seis dimensiones (la elegida).
3. Doce dimensiones (más granular).

**Justificación de la elegida (opción 2):**

- Con tres dimensiones se pierden trade-offs explícitos importantes
 (por ejemplo, legibilidad versus rendimiento).
- Con doce dimensiones los jueces LLM empiezan a discrepar en matices
 finos, aumentando la varianza.
- Seis dimensiones es el punto donde la cobertura es suficiente y la
 varianza entre jueces sigue siendo baja.

**Validación empírica esperada:** medir Pearson correlation entre los
jueces. Si Pearson > 0.7 por dimensión, las definiciones son lo
suficientemente claras.

---

## DD-06: Ensemble de tres jueces con mediana

**Decisión:** consultar tres proveedores LLM distintos por dimensión y
agregar con mediana.

**Alternativas consideradas:**

1. Un juez por dimensión (rápido, sesgo alto).
2. Tres jueces y promedio aritmético.
3. Tres jueces y mediana.
4. Cinco jueces y mediana.

**Justificación de la elegida (opción 3):**

- Un solo juez tiene sesgo conocido (Gemini es severo en legibilidad,
 DeepSeek indulgente en mantenibilidad, Llama tiende a sobrevalorar).
- Tres jueces ya promedian buena parte del sesgo individual.
- La mediana es robusta a un juez outlier (más que el promedio).
- Cinco jueces multiplica costos de API por 5/3 sin mejora proporcional.

---

## DD-07: Encoder compartido entre los seis reward models

**Decisión:** un único encoder Transformer V2 compartido por los seis
reward models, con cabezas (heads) de regresión independientes por
dimensión.

**Alternativas consideradas:**

1. Seis modelos independientes (encoder + head cada uno).
2. Encoder compartido + 6 heads.
3. Un único modelo con 6 outputs en su LM head.

**Justificación de la elegida (opción 2):**

- VRAM: opción 1 consume 6× la memoria de opción 2. Para los 16M
 parámetros del preset mediano, opción 1 sería 96M.
- Generalización: el encoder compartido ve todas las dimensiones, lo
 que ayuda a aprender representaciones más universales.
- Inferencia: opción 2 hace un solo forward por respuesta y obtiene
 los seis scores; opción 1 hace seis forwards.
- Comparado con opción 3: separar las heads facilita análisis (puedo
 ver cuánto pesa cada dimensión en el modelo aprendido).

---

## DD-08: DPO en lugar de PPO

**Decisión:** Direct Preference Optimization para la fase 5b.

**Alternativas consideradas:**

1. PPO clásico (OpenAI, InstructGPT).
2. DPO (Rafailov et al., 2023).
3. RLOO, ORPO o variantes más nuevas.

**Justificación de la elegida (opción 2):**

- PPO requiere modelo + reward model + value model + rollouts, lo que
 consume 3-4× la VRAM del modelo base. No cabe en RTX 2050 ni T4 para
 modelos de 150M+.
- DPO solo requiere el modelo entrenable + el modelo de referencia
 congelado, lo que consume 2× la memoria. Cabe con gradient
 checkpointing.
- DPO funciona con datasets de pares pequeños (5 000 ya da mejoras
 visibles según el paper).
- Su implementación es simple (~50 líneas para la pérdida core).

---

## DD-09: Pesos por dimensión en lugar de un único β

**Decisión:** la pérdida DPO multi-objetivo pondera las pérdidas
parciales por dimensión con pesos configurables:

```
loss_total = mean(loss_item × pesos_dim[dim_item] / mean(pesos_dim[dim_item]))
```

**Alternativas consideradas:**

1. Un único β para toda la pérdida.
2. Pesos fijos por dimensión.
3. Pesos aprendidos (treating los pesos como parámetros).

**Justificación de la elegida (opción 2):**

- Opción 1 trata todas las dimensiones como igual de importantes, lo
 que no se alinea con la naturaleza del asistente educativo
 (seguridad y arquitectura son prioritarias).
- Opción 3 incrementa la complejidad sin mejora demostrada en la
 literatura.
- Opción 2 permite control fino: ajustar pesos según el rol del modelo
 (educativo vs. producción) sin reentrenar.

**Pesos elegidos por defecto:**

```python
{SEG: 1.5, ARQ: 1.2, MAN: 1.0, LEG: 1.0, ESC: 0.8, REN: 0.8}
```

Esto refleja una decisión pedagógica: un asistente para estudiantes
prioriza enseñar código seguro y bien arquitectado por encima de
optimizado al máximo.

---

## DD-10: Sentencepiece BPE en lugar de BPE en Python puro

**Decisión:** usar la biblioteca `sentencepiece` en lugar del BPE en
Python puro de `ml/tokenizer/bpe.py`.

**Alternativas consideradas:**

1. BPE puro Python (`ml/tokenizer/bpe.py`, ya existente).
2. Sentencepiece.
3. tokenizers (HuggingFace).

**Justificación de la elegida (opción 2):**

- BPE puro Python sobre 187 000 ejemplos toma más de 8 horas.
 Sentencepiece (escrita en C++) toma 2 minutos sobre el mismo
 corpus.
- Sentencepiece es estándar en Llama, Mistral, Qwen.
- Es trivial de instalar (`pip install sentencepiece`).
- Mantenemos el BPE puro como referencia académica para el documentación
 (capítulo de Tokenización), pero usamos sentencepiece en producción.

---

## DD-11: Vocabulario de 16 000 tokens

**Decisión:** vocab de 16 000 para el tokenizer V2 (vs 8 000 del
tokenizer original).

**Alternativas consideradas:**

1. 4 000 (mínimo).
2. 8 000 (V1).
3. 16 000 (V2 elegido).
4. 32 000 (Llama-like).

**Justificación de la elegida (opción 3):**

- Con 8 000 tokens, palabras técnicas en español y código se
 fragmentan demasiado (`function` queda en `func` + `tion`,
 `escalabilidad` en `escala` + `bili` + `dad`).
- Con 32 000, el embedding consume mucho más espacio sin mejora
 proporcional en cobertura.
- 16 000 es el sweet spot: cobertura del 98 % del corpus mixto
 español + código según pruebas en sentencepiece.
- Es compatible con los tokens especiales pedagógicos
 (`<|user|>`, `<think>`, `<NIVEL=...>`, etc.).

---

## DD-12: Currículum por fases temáticas en lugar de mezcla uniforme

**Decisión:** entrenar el modelo en cinco fases temáticas secuenciales
(lenguajes → docs → CoT → destilación → senior), no en una única fase
con todos los datos mezclados.

**Alternativas consideradas:**

1. Mezcla uniforme: todos los datos juntos desde el inicio.
2. Currículum por dificultad: ordenar por longitud o complejidad
 creciente.
3. Currículum por fases temáticas (la elegida).

**Justificación de la elegida (opción 3):**

- Mezcla uniforme funciona pero converge más lento y es difícil de
 diagnosticar (¿por qué está bajando o subiendo el loss? hay muchos
 factores mezclados).
- Currículum por dificultad estricta (Bengio et al., 2009) requiere
 estimar dificultad de cada ejemplo, lo que es costoso y subjetivo.
- Currículum por fases temáticas:
 - Es defendible pedagógicamente (refleja cómo aprende un humano).
 - Cada fase tiene un objetivo claro (sintaxis, razonamiento,
 estilo, revisión).
 - Permite diagnosticar problemas por fase.
 - Cada fase se puede pausar, ajustar y reanudar.
- Estrategia de "replay buffer": cada fase mezcla 10 % de las
 anteriores para evitar catastrophic forgetting.

---

## DD-13: Gradient checkpointing obligatorio en modelos B+

**Decisión:** activar gradient checkpointing por defecto en los
configs de entrenamiento del modelo B (150M) y C (350M).

**Alternativas consideradas:**

1. Sin gradient checkpointing, batch_size mayor.
2. Gradient checkpointing siempre, batch_size 1-2 con grad_accum
 grande.

**Justificación de la elegida (opción 2):**

- Sin gradient checkpointing, el modelo B no cabe en RTX 2050 (4 GB
 VRAM) ni en T4 (16 GB) con seq_len 1024.
- El costo es ~30 % más tiempo de entrenamiento.
- Permite usar batch_size 1 con grad_accum 16-32, lo que da batch
 efectivo de 16-32 sin problemas de memoria.

---

## DD-14: Tokens especiales como caracteres en el sentencepiece

**Decisión:** los tokens especiales (`<|user|>`, `<think>`, `<NIVEL=...>`,
etc.) se entrenan como `user_defined_symbols` en sentencepiece, en
lugar de pre-tokenizar el corpus.

**Alternativas consideradas:**

1. Pre-tokenizar el corpus separando los tokens especiales antes de
 entrenar el sentencepiece.
2. Entrenar el sentencepiece con `user_defined_symbols`.
3. Tokens especiales fuera del vocab con IDs reservados.

**Justificación de la elegida (opción 2):**

- Es la práctica estándar en sentencepiece para tokens especiales.
- No requiere pre-procesamiento manual del corpus.
- Los tokens aparecen como unidades atómicas en el tokenizer.
- Compatible con el SFTDataset que aplica el template chat.

---

## DD-15: AMP con FP16 en T4 y BF16 en hardware más nuevo

**Decisión:** el runner detecta automáticamente la GPU y usa BF16 si
está soportado, FP16 en caso contrario.

**Alternativas consideradas:**

1. FP32 puro (más estable, más memoria).
2. FP16 siempre (problemas en GPUs sin BF16 a veces).
3. BF16 cuando se puede, FP16 como fallback.

**Justificación de la elegida (opción 3):**

- FP32 dobla el uso de memoria sin necesidad.
- BF16 tiene mismo rango dinámico que FP32 (no necesita loss scaling).
- FP16 funciona en T4 y RTX 2050 pero requiere `torch.amp.GradScaler`.
- La detección automática (`torch.cuda.is_bf16_supported()`) ya está
 en la implementación.

---

## DD-16: Datasets HuggingFace en schema V2 con metadata

**Decisión:** el script `download_hf.py --schema-v2` emite los
datasets públicos en el formato V2 con `fuente: "publico_hf"` y
`metadata.hf_dataset: <nombre>`.

**Alternativas consideradas:**

1. Mantener formato V1 (instrucción/input/response).
2. Schema V2 directo.
3. Schema V2 con metadata de origen.

**Justificación de la elegida (opción 3):**

- Permite consolidar el corpus V1 (datasets públicos) con el V2
 (generado) en un único `dataset_v2.jsonl` sin distinción ad-hoc.
- La metadata permite analizar contribución por dataset durante
 auditoría y debug.
- No rompe consumidores V1 (los demás campos opcionales quedan None).

---

## DD-17: Configuración por YAML en lugar de argparse

**Decisión:** los runners de entrenamiento (`run_fase.py`,
`entrenar_rm.py`, `dpo_multi.py`) leen configuración desde archivos
YAML pasados por `--config`.

**Alternativas consideradas:**

1. Todo por argparse (banderas y valores en línea de comandos).
2. YAML por archivo.
3. JSON por archivo.
4. Pydantic Settings +.env.

**Justificación de la elegida (opción 2):**

- Argparse con 30+ flags se vuelve ilegible.
- YAML soporta comentarios (crítico para documentar decisiones de
 hiperparámetros).
- Es más legible que JSON.
- Versionable en Git (los.env no se deben commitear).
- Reproducibilidad: cada experimento queda con su YAML en el repo.

---

## DD-18: Tres escalas del orquestador en lugar de parámetros libres

**Decisión:** `construir_dataset_v2.py --escala {mini|media|completa}`
en lugar de exponer `--n-por-objetivo`, `--repeticiones`, etc.

**Alternativas consideradas:**

1. Solo parámetros libres (cualquier combinación).
2. Escalas preconfiguradas.
3. Ambas (escala como default, parámetros como override).

**Justificación de la elegida (opción 2 con cierta opción 3):**

- Las escalas dan smoke test rápido (`mini`) y producción
 (`completa`) sin pensar en parámetros.
- Reduce errores de configuración (cada escala fue probada).
- Si alguien quiere variar, lo hace en el código mismo de
 `ESCALAS` o llamando a un generador individual.

---

## DD-19: Documentación exhaustiva en `docs/`

**Decisión:** documentar EXHAUSTIVAMENTE cada componente, decisión,
bug y experimento en el directorio `docs/`.

**Justificación:**

- el proyecto se redactará desde esta documentación. Sin ella, hay que
 reconstruir el razonamiento meses después.
- La propuesta de investigación necesita decir qué se va a hacer y por
 qué; los documentos sirven como insumo directo.
- Reproducibilidad: un tercero debe poder reconstruir el sistema solo
 leyendo `docs/`.
- presentación: el revisor preguntará "por qué X y no Y", y aquí está la
 respuesta argumentada.

---

## DD-20: Sin emojis ni iconografía en la documentación

**Decisión:** la documentación de `docs/` evita emojis y caracteres
decorativos.

**Justificación:**

- Tono académico apropiado del proyecto.
- Compatible con compiladores LaTeX que pueden no manejar bien
 emojis.
- Búsqueda de texto más fiable.
- Profesionalismo en publicaciones derivadas (artículo de workshop,
 blog técnico, etc.).
