# Plan de pruebas

## 1. Pruebas funcionales del backend

| ID | Descripción | Criterio de éxito |
|----|-------------|--------------------|
| PF-01 | Registro de usuario válido | 201 + usuario en BD |
| PF-02 | Registro con email duplicado | 409 |
| PF-03 | Login correcto | 200 + JWT válido |
| PF-04 | Login con contraseña errónea | 401 |
| PF-05 | `/ai/generar` con Gemini configurado | 201 + JSON válido |
| PF-06 | `/ai/generar` con respuesta IA malformada | retry exitoso o 502 controlado |
| PF-07 | Historial filtra solo del usuario actual | sin fugas entre cuentas |
| PF-08 | Validar dataset sin rol investigador | 403 |
| PF-09 | Exportar JSONL solo validados | archivo conteniendo N registros |
| PF-10 | Evaluación opción múltiple correcta | puntaje 1.0 |

## 2. Pruebas de integración

- Backend ↔ PostgreSQL: crear, leer, actualizar `DatasetEducativo` con JSONB.
- Backend ↔ Gemini: prompt mínimo y validación de respuesta.
- Backend ↔ DeepSeek: idem.
- Frontend ↔ Backend: flujo completo registro → generación → historial.

## 3. Pruebas no funcionales

- Latencia promedio por consulta exitosa ≤ 6 s (Gemini Flash, prompts cortos).
- Tasa de respuestas JSON-válidas en primer intento ≥ 90 %.
- Sin pérdida de consultas en estado `FALLIDA` (todas auditadas).
- Logs rotan correctamente al superar 5 MB.

## 4. Pruebas con usuarios

- Tamaño muestra: 20 estudiantes (10 grupo experimental, 10 control).
- Duración: 2 sesiones de 60 min.
- Instrumentos: ver [instrumentos_evaluacion.md](instrumentos_evaluacion.md).
- Análisis: comparación pre/post test + diferencias entre grupos.

## 5. Criterios de aceptación globales

- Cobertura ≥ 70 % en `services/` (futuro).
- Cero errores 500 sin manejar en la API.
- Auto-curación recupera ≥ 50 % de las respuestas inicialmente inválidas.

---

## 6. Pruebas del pipeline V2 de construcción de dataset

| ID | Descripción | Criterio de éxito |
|---|---|---|
| PV-01 | Schema V2: aceptar ejemplo V1 clásico | `validar_ejemplo` retorna `(True, "ok")`. |
| PV-02 | Schema V2: aceptar ejemplo con `pensamiento` bien formado | `(True, "ok")`. |
| PV-03 | Schema V2: rechazar ejemplo con dos alternativas elegidas | `(False, "...exactamente 1 alternativa elegida...")`. |
| PV-04 | Validador código Python: aceptar código que compila | `ast.parse` no lanza. |
| PV-05 | Validador código Python: rechazar SyntaxError | `(False,...)`. |
| PV-06 | Validador autocrítica: rechazar < 2 iteraciones | `(False,...)`. |
| PV-07 | Validador multinivel: rechazar texto idéntico entre niveles | `(False, "...niveles con texto idéntico...")`. |
| PV-08 | Pool: detectar proveedores activos según `.env` | `Pool.desde_env().disponibles` no vacío. |
| PV-09 | Pool: rotar al siguiente proveedor en caso de fallo no rate-limit | Llamada exitosa al fallback. |
| PV-10 | Pool: esperar 60 segundos ante 429 con `esperar_si_rate_limited` | Retry exitoso tras 60 s. |
| PV-11 | Parser de JSON robusto: extraer objetos de array truncado | Recuperar al menos un objeto del array. |
| PV-12 | Auditoría: detectar tema sobre-representado | Advertencia en reporte. |
| PV-13 | Auditoría: detectar baja proporción de chain-of-thought | Advertencia. |
| PV-14 | Roundtrip JSON: ejemplo → JSONL → ejemplo es idempotente | Igualdad de campos. |
| PV-15 | Generadores: cada uno produce ≥ 70 % de ejemplos válidos | En smoke test con Groq 70B. |

## 7. Pruebas del sistema multi-criterio

| ID | Descripción | Criterio de éxito |
|---|---|---|
| PR-01 | Reward model: instanciar tres presets | 8 M / 16 M / 32 M de parámetros reales. |
| PR-02 | Forward de RM: salidas en rango [0, 10] | Todas las 6 dimensiones. |
| PR-03 | Backward de loss MSE multi-dim | Sin errores, gradientes calculados. |
| PR-04 | Backward de loss ranking pairwise | Sin errores. |
| PR-05 | Encoder compartido: tres heads producen scores distintos | Probabilidad ≈ 1 de scores distintos en init. |
| PR-06 | Jueces: agregar mediana con tres jueces simulados | Mediana coincide con el del medio. |
| PR-07 | Etiquetador: resume desde JSONL parcial | No re-procesa registros ya etiquetados. |
| PR-08 | Pearson correlation post-entrenamiento | ≥ 0.7 en al menos cuatro dimensiones. |
| PR-09 | Kendall tau post-entrenamiento | ≥ 0.6 en al menos cuatro dimensiones. |

## 8. Pruebas del runner de fases

| ID | Descripción | Criterio de éxito |
|---|---|---|
| PT-01 | Cargar config YAML válida | Sin excepción. |
| PT-02 | Cargar config con preset inexistente | `ValueError` claro. |
| PT-03 | Crear modelo desde preset `sota_b` | 150 M de parámetros, dispositivo correcto. |
| PT-04 | Forward + backward de batch dummy | `loss.backward()` exitoso. |
| PT-05 | Reanudar entrenamiento desde checkpoint | Estado restaurado. |
| PT-06 | Detener por tiempo máximo (chunking Kaggle) | Guarda y termina cleanly. |
| PT-07 | Captura de SIGINT | Guarda checkpoint antes de morir. |
| PT-08 | Métricas a `metrics.jsonl` | Una línea JSON por evaluación. |

## 9. Pruebas del DPO multi-objetivo

| ID | Descripción | Criterio de éxito |
|---|---|---|
| PD-01 | Cargar modelo entrenable y modelo ref | Ambos en mismo device, ref con `requires_grad=False`. |
| PD-02 | Forward de batch con pares chosen/rejected | Cuatro forwards exitosos (π_θ chosen, π_θ rejected, π_ref chosen, π_ref rejected). |
| PD-03 | Pérdida DPO con pesos por dimensión | `loss_dpo_multi` retorna tensor escalar + detalle. |
| PD-04 | Métricas por dimensión: loss y accuracy | Presentes en `detalle`. |
| PD-05 | Acumulación de gradientes a través de batches | Convergencia visible en `loss_train`. |
| PD-06 | Modelo ref se mantiene congelado | Sus parámetros no cambian entre pasos. |

## 10. Benchmarks contra modelos comerciales

| Benchmark | Modelo A (46 M) | Modelo B (150 M) | Modelo C (350 M) | Gemini Flash | Claude 3.5 |
|---|---|---|---|---|---|
| HumanEval pass@1 | TBD | objetivo 15–20 % | objetivo 30–35 % | referencia | referencia |
| HumanEval+ pass@1 | TBD | TBD | TBD | referencia | referencia |
| MBPP pass@1 | TBD | objetivo ~20 % | objetivo ~35 % | referencia | referencia |
| MBPP+ pass@1 | TBD | TBD | TBD | referencia | referencia |
| APPS introductory | — | TBD | TBD | referencia | referencia |
| DS-1000 | — | TBD | TBD | referencia | referencia |
| Pedagógico (1–10) | TBD | objetivo ~7 | objetivo ~8 | referencia | referencia |
