# Instrumentos de evaluación

## 1. Rúbrica de validación pedagógica del dataset

Aplicada por el investigador a cada `DatasetEducativo` antes de marcarlo
como `validado=true`.

| Dimensión | 0 | 1 | 2 |
|-----------|---|---|---|
| Corrección del código | Incorrecto / no ejecuta | Ejecuta con observaciones | Correcto |
| Coherencia explicación-código | Inconsistente | Mayormente coherente | Totalmente coherente |
| Calidad pedagógica de la explicación | Mecánica / opaca | Aceptable | Clara y conecta el "por qué" |
| Conceptos clave identificados | Faltan o sobran | Mayormente correctos | Completos y precisos |
| Adecuación al nivel solicitado | No adecuado | Parcial | Adecuado |
| Actividad evaluativa | Trivial / no evalúa | Razonable | Exige comprensión |

Total: 0–12. Umbral de aceptación: ≥ 9.

## 2. Cuestionario pre-test (estudiantes)

1. ¿Has programado antes en Python? (sí/no)
2. ¿Cómo evalúas tu comprensión sobre…? (Likert 1–5)
 - Variables y tipos
 - Bucles
 - Funciones
 - Clases y objetos
 - Algoritmos básicos
3. ¿Has usado IA generativa para programar? (sí/no/parcial)

## 3. Cuestionario post-test (estudiantes)

1. Tras usar el sistema, ¿cómo evalúas tu comprensión sobre…? (Likert 1–5)
2. Las explicaciones línea por línea, ¿cuánto te ayudaron? (Likert 1–5)
3. Las actividades evaluativas, ¿cuánto te ayudaron a confirmar tu
 comprensión? (Likert 1–5)
4. ¿Recomendarías el sistema a un compañero? (sí/no/quizá)
5. Comentarios abiertos.

## 4. Tarea de comprensión algorítmica

Cinco problemas progresivos. El estudiante debe predecir la salida o
identificar la complejidad **sin ejecutar** el código. Las puntuaciones
se contrastan con el grupo control (sin sistema).

## 5. Rúbrica multi-criterio del sistema de recompensas (V2)

Aplicada por seis modelos de recompensa propios entrenados, replicando
el juicio agregado de tres jueces LLM por dimensión. Cada dimensión
puntúa 0–10 según la siguiente escala estandarizada:

### Dimensión SEG — Seguridad

| Rango | Descriptor |
|---|---|
| 0–2 | SQL/command/template injection, hardcoded secrets, eval inseguro, XSS evidente. |
| 3–4 | Vulnerable a edge cases obvios (timing attacks, validación débil, dependencias inseguras). |
| 5–6 | Básicamente seguro pero con omisiones notables (sin rate limit, sin sanitización plena). |
| 7–8 | Aplica buenas prácticas conocidas (parametrized queries, secrets en env, auth correcta). |
| 9–10 | Defensive coding completo; considera amenazas no triviales (CSRF, replay, supply chain). |

### Dimensión LEG — Legibilidad

| Rango | Descriptor |
|---|---|
| 0–2 | Nombres crípticos, código denso, sin formato. |
| 3–4 | Parcialmente legible pero hay funciones largas, anidamiento profundo, magic numbers. |
| 5–6 | Nombres aceptables, estructura razonable, faltan algunos type hints. |
| 7–8 | Nombres descriptivos, funciones pequeñas y cohesivas, type hints completos. |
| 9–10 | Código que se lee como prosa, intención evidente sin necesidad de comentarios. |

### Dimensión ESC — Escalabilidad

| Rango | Descriptor |
|---|---|
| 0–2 | O(n²) o peor sin necesidad, carga todo en memoria, no pagina. |
| 3–4 | Funciona para datos pequeños pero rompe pasando un umbral evidente. |
| 5–6 | Algoritmos correctos pero sin paginación / streaming / cache. |
| 7–8 | Complejidad óptima, paginación correcta, streaming donde aplica. |
| 9–10 | Escala horizontalmente, cache strategy, índices y batching considerados. |

### Dimensión ARQ — Arquitectura

| Rango | Descriptor |
|---|---|
| 0–2 | Lógica de negocio mezclada con I/O, dependencias circulares, todo en un main. |
| 3–4 | Separación incipiente pero capas se filtran (controller con SQL directo). |
| 5–6 | Capas presentes pero acoplamiento alto, sin tests aislables. |
| 7–8 | Capas limpias, dependencias inyectadas, tests aislados son posibles. |
| 9–10 | Arquitectura hexagonal/clean, dominios separados, fácil de extender. |

### Dimensión REN — Rendimiento

| Rango | Descriptor |
|---|---|
| 0–2 | Recálculos en loop, conversiones innecesarias, listas donde van sets. |
| 3–4 | Funciona pero con allocations excesivas o pasos redundantes. |
| 5–6 | Rendimiento aceptable, sin optimizaciones notorias. |
| 7–8 | Uso apropiado de generators/sets/dict; evita trabajo innecesario. |
| 9–10 | Perfil considerado, cache de resultados costosos, vectorización donde aplica. |

### Dimensión MAN — Mantenibilidad

| Rango | Descriptor |
|---|---|
| 0–2 | Sin manejo de errores, sin tests, sin docs, configs hardcoded. |
| 3–4 | Try/except genérico que oculta errores, docstrings inútiles. |
| 5–6 | Errores manejados básicamente, hay docs mínimas, config en env. |
| 7–8 | Errores específicos, logs informativos, tests cubren el camino feliz. |
| 9–10 | Error model claro, tests + edge cases, logs estructurados, métricas. |

## 6. Benchmarks automáticos

| Instrumento | Qué mide | Cuándo se aplica |
|---|---|---|
| **HumanEval pass@1** | Capacidad de completar funciones Python a partir de su descripción y firma. | Al final de cada fase de SFT y tras el DPO. |
| **HumanEval+** | Versión con tests más rigurosos. | Al final del modelo B y C. |
| **MBPP pass@1** | Resolución de problemas básicos en Python con tests. | Al final de cada fase de SFT. |
| **MBPP+** | Versión robusta. | Al final del modelo B y C. |
| **APPS competitive** | Problemas competitivos de nivel introductorio. | Al final del modelo C. |
| **DS-1000** | Capacidad en data science (pandas, numpy, sklearn). | Al final del modelo C. |
| **Loss validación** | Calidad del lenguaje en hold-out. | Cada N pasos en todas las fases. |
| **Perplejidad** | Capacidad predictiva sobre corpus de referencia. | Después de cada fase de pretraining. |

## 7. Métricas de los reward models

Validación de los seis reward models contra los jueces LLM que los
entrenaron:

| Métrica | Cómo se calcula | Umbral mínimo aceptable |
|---|---|---|
| **Pearson correlation** | Por dimensión: correlación entre el score predicho por el RM y el score agregado del ensemble de jueces. | r ≥ 0.7 |
| **Kendall tau** | Por dimensión: concordancia de ordenamientos. | τ ≥ 0.6 |
| **Calibración** | Distribución de scores: que `score = 8` signifique consistentemente algo evaluable. | Histograma sin sesgos extremos. |
| **Validez convergente** | Test de robustez: agregar comentarios cambia LEG pero NO cambia SEG. | Cambio en la dimensión correcta. |

## 8. Métricas DPO multi-objetivo

| Métrica | Cómo se calcula |
|---|---|
| **Win rate global** | % de pares en validación donde el modelo entrenable prefiere `chosen` sobre `rejected`. |
| **Win rate por dimensión** | Filtrar los pares por dimensión y calcular win rate. |
| **Margen DPO promedio** | Mean de `β · (log_π_θ(y_w) - log_π_ref(y_w) - log_π_θ(y_l) + log_π_ref(y_l))`. |
| **KL divergencia respecto al modelo ref** | Asegurar que el modelo no se aleje demasiado del modelo de Fase 5a. |

## 9. Evaluación cualitativa con usuarios reales

Se mantiene la metodología original de la fase 1 (cuestionarios pre/post-test
y tarea de comprensión algorítmica), añadiendo:

- 100 prompts educativos canónicos (definidos en el repositorio).
- Cada estudiante usa el sistema con tres modelos: V1 (46 M), V2-B (150 M),
 V2-C (350 M).
- Calificación ciega: el estudiante no sabe qué modelo respondió.
- Análisis de varianza (ANOVA) para diferenciar la calidad percibida.
