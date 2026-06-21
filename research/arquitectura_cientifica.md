# Arquitectura científica: el rol de las APIs y el motor educativo propio

> Documento de alineación entre la implementación y el objetivo de la
> investigación. Responde a la auditoría de alineación científica.

## El problema detectado

Una primera versión del sistema funcionaba como **intermediario**: cada
consulta del estudiante disparaba una llamada a una API externa (Gemini /
DeepSeek). Esto desvía el objetivo de el proyecto, que **no** es construir un
proxy hacia proveedores de IA, sino un **sistema educativo especializado**
que genera conocimiento propio reutilizable.

## El rol CORRECTO de Gemini y DeepSeek

Las APIs son **herramientas auxiliares**, no el motor final. Se usan para:

1. Generar ejemplos educativos a partir del currículo.
2. Generar explicaciones, conceptos y actividades.
3. Construir el dataset educativo.
4. Comparar la calidad entre proveedores.
5. Generar el conocimiento inicial que poblará la base.

El conocimiento generado se **valida, almacena y reutiliza**, de modo que el
sistema dependa **cada vez menos** de las APIs.

## Flujo implementado

```
 CURRÍCULO (domain/curriculo.py)
 │ prompt semilla
 ▼
 API auxiliar (Gemini / DeepSeek) ← herramienta
 │ respuesta JSON estricta
 ▼
 Validador de calidad educativo (quality_service) ← rúbrica computable
 │ puntaje 0..12, aprobado?
 ▼
 Base de conocimiento (UnidadConocimiento) ← activo propio
 estado: candidato → validado (humano)
 │
 ▼
 Recuperación local (retrieval_service) ← SIN API
 ▲
 │ consulta del estudiante
 ┌───────────────────┴─────────────────────────────┐
 │ Motor educativo (educational_engine) │
 │ 1) busca en la base de conocimiento │
 │ 2) si hay match validado → responde sin API │
 │ 3) si no → usa API, valida, almacena, aprende │
 └──────────────────────────────────────────────────┘
 │
 ▼
 ESTUDIANTE
```

## Componentes del núcleo

| Componente | Archivo | Función |
|---|---|---|
| Currículo | `domain/curriculo.py` | Define qué conocimiento generar |
| Generador | `services/knowledge_generation_service.py` | Pobla la base usando las APIs |
| Validador de calidad | `services/quality_service.py` | Rúbrica automatizada (AST + heurísticas) |
| Base de conocimiento | `models/conocimiento.py` | Unidades validadas reutilizables |
| Recuperación | `services/retrieval_service.py` | Búsqueda local, sin API |
| Motor educativo | `services/educational_engine.py` | Estrategia recuperación-primero |

## Métrica clave de la investigación: independencia de las APIs

El endpoint `GET /api/v1/knowledge-gen/estadisticas` expone:

- `respondidas_desde_base` vs `respondidas_por_api`.
- `tasa_independencia_api` (% de respuestas servidas SIN llamar a una API).
- `reutilizaciones_totales` de las unidades de conocimiento.
- `cobertura_curriculo` (% del temario con conocimiento validado).

**Hipótesis medible:** conforme crece la base de conocimiento validada, la
`tasa_independencia_api` aumenta. Esta es evidencia directa de que el sistema
evoluciona desde "consumidor de APIs" hacia "sistema educativo autónomo",
preparado para la fase de fine-tuning de un modelo especializado.

## Preparación para el modelo especializado (fase futura)

La base de conocimiento validada se exporta a JSONL
(`app/training/export_jsonl.py`) como pares instrucción/respuesta. Ese corpus
curado es el insumo para entrenar el modelo propio desde cero (no LoRA sobre
modelo base externo). El validador de calidad garantiza que solo conocimiento de
alta calidad alimente el entrenamiento.

---

## 9. Sistema multi-criterio V2 (junio 2026)

La versión V2 del sistema extiende el motor educativo propio con un
**sistema de auto-evaluación multi-criterio** que permite al sistema
discriminar la calidad de sus propias respuestas en seis dimensiones
ortogonales.

### 9.1 Las seis dimensiones

| Sigla | Dimensión | Ejemplo de criterio |
|---|---|---|
| SEG | Seguridad | Sin SQL injection, sin secrets hardcoded, sanitización adecuada. |
| LEG | Legibilidad | Nombres descriptivos, funciones pequeñas, type hints completos. |
| ESC | Escalabilidad | Complejidad algorítmica adecuada, paginación, streaming. |
| ARQ | Arquitectura | Capas limpias, dependency injection, separación de responsabilidades. |
| REN | Rendimiento | Uso apropiado de stdlib eficiente, ausencia de redundancia. |
| MAN | Mantenibilidad | Tests, manejo de errores específico, logs estructurados. |

### 9.2 Flujo del sistema V2

```
 Estudiante
 │
 ▼
 Motor educativo V2
 │
 │ 1) Generar respuesta candidata (modelo propio)
 │ 2) Evaluar con los 6 reward models propios
 │ 3) Si Σ scores < umbral configurable → regenerar
 │ (hasta 3 intentos, temperatura creciente)
 │ 4) Devolver mejor respuesta + scores 0–10 por dimensión
 ▼
 Frontend muestra la respuesta + scores como métricas visuales
 │
 ▼
 Estudiante (puede dar feedback 👍/👎 por dimensión)
 │
 ▼
 BD: feedback alimenta DPO incremental mensual
```

### 9.3 Cómo se construyen los reward models propios

1. **Fase A: Etiquetado del corpus** (ver `docs/REWARD_MODELS.md`
 sección 3). Para cada respuesta del corpus se consulta un ensemble
 de tres jueces LLM por dimensión y se agrega con mediana. Resultado:
 un dataset etiquetado con seis scores 0–10 por respuesta.

2. **Fase B: Destilación** (ver `docs/REWARD_MODELS.md` sección 4). Se
 entrenan seis reward models propios (Transformer V2 con encoder
 compartido, ~16 M parámetros totales) que aprenden a reproducir los
 scores agregados.

3. **Fase C: Uso en producción** (ver `docs/REWARD_MODELS.md` sección
 5). Los reward models propios evalúan localmente, sin API, las
 respuestas del modelo principal. El sistema regenera si los scores
 son insuficientes.

### 9.4 Métrica clave V2: independencia de jueces LLM en producción

Antes (fase 1): la métrica era *independencia de APIs en la respuesta
final al estudiante*.

Ahora (V2) se añade: *independencia de jueces LLM en la
auto-evaluación*. Los reward models propios reemplazan a los jueces
LLM en la inferencia, manteniendo el rol pedagógico de "auto-crítica
multi-criterio" sin dependencia externa.

### 9.5 Implicaciones del proyecto

- El motor educativo V2 NO es un proxy de APIs ni en respuesta ni en
 evaluación.
- Las APIs externas se usan exclusivamente para generación de dataset
 y para etiquetado durante entrenamiento (fase A) — nunca en
 inferencia.
- El sistema demuestra el cumplimiento del principio de soberanía
 tecnológica: una vez entrenados los modelos, el sistema puede
 operar 100 % en local.

### 9.6 Componentes V2 que materializan esta arquitectura

| Componente | Archivo | Función |
|---|---|---|
| Pool de generadores | `ml/data/pool_generadores.py` | Rotación de seis APIs gratuitas para Fase A. |
| Jueces LLM multi-criterio | `ml/rlhf/jueces.py` | Rúbricas y ensemble por dimensión. |
| Etiquetador | `ml/rlhf/etiquetar_dataset.py` | Aplica los jueces al corpus. |
| Reward models | `ml/rlhf/reward_model.py` | Arquitectura con encoder compartido. |
| Entrenador RM | `ml/rlhf/entrenar_rm.py` | Aprende a reproducir los scores de los jueces. |
| DPO multi-objetivo | `ml/rlhf/dpo_multi.py` | Alinea el modelo principal con preferencias multi-dim. |
| Modelo principal | `ml/model/transformer_v2.py` | Transformer V2 (RoPE + GQA + SwiGLU + RMSNorm). |
| Runner por YAML | `ml/training/run_fase.py` | Ejecuta cualquiera de las cinco fases. |
