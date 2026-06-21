# Bitácora de investigación

> Registro cronológico de decisiones, hipótesis y observaciones del proyecto.
> Cada entrada debe poder ser citada en el cuerpo de el proyecto.

---

## 2026-05-29 — Inicio del desarrollo

**Decisiones tomadas:**

- Stack confirmado: FastAPI + PostgreSQL + Next.js + Gemini + DeepSeek.
- Se descarta entrenar un LLM desde cero en esta fase. La fase 1 cubre:
 plataforma funcional, dataset estructurado, preparación para fine-tuning.
- Se adopta JSON estricto contractual (`RespuestaIAEducativa`) como
 protocolo común para los proveedores IA. Justificación: garantiza
 estructura reproducible para análisis cuantitativo y para usar el
 dataset directamente en pipelines de SFT.
- Se implementa **auto-curación de JSON** con hasta 3 reintentos. Cada
 intento queda registrado en `Consulta.intentos_reparacion_json`. Esto
 permite medir empíricamente la confiabilidad de cada modelo respecto
 al cumplimiento del formato.

**Hipótesis preliminares:**

H1. Gemini 2.0 Flash producirá respuestas JSON-válidas en ≥ 95 % de las
 primeras pasadas para prompts educativos.

H2. La calidad pedagógica (validación humana del investigador) será mayor
 para DeepSeek en temas algorítmicos y para Gemini en temas conceptuales.

H3. El dataset validado de al menos 500 ejemplos permitirá observar mejoras
 medibles tras LoRA sobre un modelo base (DeepSeek-Coder).

**Próximos pasos:**

- Cargar conjunto inicial de prompts piloto (n ≈ 30) para validar el flujo.
- Definir rúbrica de evaluación pedagógica del investigador.
- Diseñar instrumento de evaluación para los estudiantes.

---

## 2026-05-29 — Realineación arquitectónica (auditoría científica)

**Contexto:** una auditoría de alineación detectó que el sistema operaba como
intermediario estudiante→API→respuesta, desviándose del objetivo: construir un
sistema educativo especializado que genere conocimiento propio reutilizable.

**Decisión:** reposicionar Gemini/DeepSeek como herramientas auxiliares para
*generar* conocimiento, y construir el núcleo propio:
1. **Currículo** (`domain/curriculo.py`) que dirige la generación.
2. **Generador de conocimiento** proactivo por currículo.
3. **Validador de calidad educativo automatizado** (rúbrica computable con AST).
4. **Base de conocimiento** consultable (`UnidadConocimiento`) que crece.
5. **Recuperación local** sin API.
6. **Motor educativo retrieval-first**: responde primero desde la base propia;
 solo usa la API si no hay conocimiento, y entonces lo valida y lo almacena.

**Evidencia generable:** nuevas métricas `tasa_independencia_api` y
`cobertura_curriculo` (endpoint `/knowledge-gen/estadisticas`).

**Impacto en la investigación:** la arquitectura ahora refleja el flujo
"API → conocimiento → dataset → validación → base → fine-tuning → modelo
especializado → estudiante". Ver [arquitectura_cientifica.md](arquitectura_cientifica.md).

**Próximos pasos:** generar conocimiento del currículo, validarlo, medir la
evolución de la independencia de APIs, y retomar el frontend del portal.

---

## 2026-05-30 — Construcción del LLM propio desde cero (decisión central)

**Contexto:** se redefinió el objetivo central de el proyecto. La meta NO es
consumir APIs para responder, sino **construir una IA propia desde cero**: un
LLM educativo (Transformer) entrenado con datos generados por APIs. Flujo final:
Usuario → Modelo propio → Respuesta. Las APIs quedan SOLO en la generación de
datos de entrenamiento.

**Hardware disponible:** NVIDIA RTX 2050 (4 GB VRAM), CUDA 13.2, 16 núcleos CPU,
PyTorch 2.10. Determina un modelo "mini-GPT" (~15-20M parámetros) suficiente
para demostrar el método.

**Implementado (paquete `ml/`):**
1. **Tokenizer BPE byte-level propio** en Python puro (español + código Python).
2. **Transformer decoder desde cero** en PyTorch: embeddings, positional
 encoding sinusoidal, multi-head self-attention causal (programada a mano),
 FFN, LayerNorm, residuales, LM head, cross-entropy, generación con
 temperatura/top-k/top-p.
3. **Dataset Generator** (`ml/data/generator.py`) — único uso de APIs.
4. **Corpus semilla** incorporado para entrenar sin gastar API.
5. **Pipeline de entrenamiento**: split, batches, warmup+cosine, grad accum,
 checkpoints, evaluación periódica, registro de experimentos.
6. **Motor de inferencia** device-agnostic.

**Evidencia (verificada):** el pipeline corre end-to-end en la máquina. Demo
nano: 895K parámetros, loss train 6.69→5.60 en 300 iteraciones (CPU, 30 s). El
texto aún es incoherente por el tamaño mínimo del corpus/iteraciones; la calidad
escala con datos e iteraciones.

**Limitación (del proyecto):** con 4 GB de VRAM y dataset sintético modesto, el
modelo demuestra la metodología pero no iguala a modelos comerciales. El aporte
es el artefacto completo y reproducible + el dataset curado. Ver `ml/README.md`.

**Próximos pasos:** generar dataset amplio con APIs, entrenar preset `pequeno`
en GPU, integrar el motor de inferencia en el backend (Usuario→Modelo propio),
y panel de entrenamiento en el frontend.

---

## 2026-06-20 — Construcción del pipeline V2 completo (sesión maratónica)

**Contexto:** punto de inflexión metodológico. Se construyó en una sola
sesión todo el aparato técnico que la propuesta del proyecto necesita:
dataset enriquecido, sistema multi-criterio de recompensas, arquitectura
del modelo modernizada, runner por YAML para las cinco fases, y dos
trainers especializados (reward models y DPO multi-objetivo).

**Decisión central:** confirmar entrenamiento desde cero (NO continued
pretraining sobre un modelo base externo como Qwen o Llama). El aporte
académico del proyecto es la metodología — currículum de cinco fases,
sistema multi-criterio, dataset propio — no la mera ejecución de un
fine-tuning sobre un base preentrenado. Esta decisión es no negociable
y queda documentada en `docs/DECISIONES_DISENO.md` (DD-01).

**Decisiones específicas tomadas (20 documentadas en
`docs/DECISIONES_DISENO.md`):**

1. Schema V2 con campos opcionales (extensión, no reemplazo) — DD-02.
2. Pool de 6 proveedores LLM gratuitos con rotación por tarea — DD-03.
3. Validadores estrictos al generar, no a posteriori — DD-04.
4. 6 dimensiones de calidad: SEG, LEG, ESC, ARQ, REN, MAN — DD-05.
5. Ensemble de 3 jueces por dimensión con agregación por mediana — DD-06.
6. Encoder compartido entre los 6 reward models — DD-07.
7. DPO (no PPO) para la fase 5b — DD-08.
8. Pesos por dimensión en la pérdida DPO — DD-09.
9. Tokenizer sentencepiece con vocab 16k (vs 8k del V1) — DD-10, DD-11.
10. Currículum por fases temáticas (no por dificultad ni mezcla
 uniforme) — DD-12.
11. Gradient checkpointing obligatorio en modelos B+ — DD-13.
12. AMP automático (BF16 cuando se puede, FP16 fallback) — DD-15.
13. Configuración por YAML, no argparse, para todo trainer — DD-17.

**Evidencia (artefactos creados):**

- 17 archivos nuevos en `ml/data/` (schema V2, validadores, pool,
 auditoría, 10 generadores, orquestador, download_hf extendido).
- 6 archivos nuevos en `ml/rlhf/` (jueces, etiquetador, reward_model,
 entrenar_rm, dpo_multi, config rm_v1.yaml).
- 1 archivo nuevo + 6 configs YAML en `ml/training/` (run_fase.py +
 fases 1, 2, 3, 4, 5a, 5b).
- 1 archivo modificado en `ml/model/` (transformer_v2.py con gradient
 checkpointing).
- 1 archivo modificado en `ml/config.py` (presets V2: sota_b 150M,
 sota_c 350M, sota_d 870M).
- 10 documentos nuevos en `docs/`: PROPUESTA_INVESTIGACION,
 CATALOGO_ARCHIVOS, BITACORA_DESARROLLO, ARQUITECTURA_TECNICA,
 DECISIONES_DISENO, BUGS_Y_SOLUCIONES, EXPERIMENTOS, DATASET_V2,
 REWARD_MODELS, PLAN_ENTRENAMIENTO_V2 (reescrito).
- Aproximadamente 5 000 líneas de código + 4 000 de documentación.

**Bugs documentados durante el desarrollo (11 en
`docs/BUGS_Y_SOLUCIONES.md`):** problemas con parser de fences
internos en respuestas JSON con bloques de código, JSON con saltos de
línea literales (`strict=False`), modelo Groq 8B con JSON malformado
(extractor robusto con balanceo de llaves), pool abandonaba ante 429
(reemplazado por espera fija 60s), clave Gemini formato OAuth
incompatible con el endpoint. Cada bug con análisis de causa raíz y
lección aprendida.

**Smoke tests ejecutados (resumen en `docs/EXPERIMENTOS.md`):**

- Arquitectura V2: 5 presets validados, gradient checkpointing
 funcional, RoPE extrapola correctamente.
- Reward models: 3 presets (8M / 16M / 32M params reales), MSE loss +
 ranking loss + backward verificados.
- Pipeline de generación con Groq: 28 ejemplos válidos del generador
 `pensamiento` en 4.7 min, 100 % código compila, 100 % CoT poblado.
- Pipeline completo en background: progresando linealmente con
 modelo Groq 8B (~10 min para `pensamiento`, ~5 min para
 `multinivel`).
- 7 configuraciones YAML parsean correctamente.

**Impacto en la investigación:**

- La propuesta del proyecto (documento en `docs/PROPUESTA_INVESTIGACION.md`)
 ahora describe exactamente lo que se va a hacer, con respaldo de
 arquitectura técnica ya implementada. El revisor puede revisar el
 código.
- Los 7 objetivos específicos (OE1 a OE7) están mapeados a archivos
 concretos en `docs/CATALOGO_ARCHIVOS.md`. Cada uno tiene producto
 verificable.
- sección de la documentación que ya tienen insumo casi completo:
 Metodología, Implementación, Decisiones de diseño, Desarrollo
 (bitácora), Bugs y soluciones, Resultados parciales.
- Capítulos que faltan: Resultados completos del modelo entrenado,
 Análisis cualitativo, Conclusiones, presentación.

**Próximos pasos:**

1. Cuando el usuario tenga acceso a una API que permita entrenamiento
 en la nube, ejecutar las fases 1 a 5b según las configuraciones
 YAML ya preparadas.
2. Generar el corpus completo (escala "completa" del orquestador) con
 más proveedores LLM activos para acelerar.
3. Etiquetar el corpus completo con los 6 jueces multi-criterio.
4. Entrenar los 6 reward models.
5. Ejecutar las 5 fases del modelo B (150M).
6. Repetir para modelo C (350M).
7. Evaluar contra benchmarks (HumanEval, MBPP+) y completar la tabla
 principal del sección de Resultados.
8. Redactar el documentación final extrayendo contenido de los 10
 documentos de `docs/`.

---

## Plantilla para nuevas entradas

```
## YYYY-MM-DD — Título corto

**Contexto:**
**Decisión / observación:**
**Evidencia:**
**Impacto en la investigación:**
**Próximos pasos:**
```
