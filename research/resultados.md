# Resultados

> A completar tras la fase de validación.

## Estructura sugerida

### 1. Caracterización de la muestra

- Total de usuarios estudiantes.
- Total de consultas generadas.
- Distribución por nivel y tema.

### 2. Confiabilidad del sistema

- Latencia promedio y desviación.
- Tasa de JSON válido en primer intento (por proveedor).
- Tasa de éxito tras auto-curación.
- Errores 5xx por cada 1000 consultas.

### 3. Calidad pedagógica del dataset

- % validado sobre total.
- Puntuación promedio de rúbrica por dimensión.
- Comparativa Gemini vs. DeepSeek.

### 4. Impacto en la comprensión algorítmica

- Comparación pre/post test (grupo experimental).
- Comparación entre grupo experimental y control.
- Tamaño de efecto (d de Cohen).

### 5. Discusión

- Hallazgos esperados vs. observados.
- Limitaciones (sesgos, tamaño muestra, cobertura curricular).
- Recomendaciones para fases posteriores (fine-tuning).

---

## Resultados del modelo V2 (a completar tras entrenamiento)

### 6. Caracterización del corpus V2

- Total de ejemplos generados por tipo (objetivo: 333 000):
 - `pensamiento_programador`: TBD
 - `explicacion_multinivel`: TBD
 - `anti_patron`: TBD
 - `bug_sutil`: TBD
 - `evolucion_codigo`: TBD
 - `decision_diseno`: TBD
 - `arquitectura_sistema`: TBD
 - `seguridad`: TBD
 - `testing_complejidad`: TBD
 - `pensamiento_autocritico`: TBD
- Distribución por proveedor (Gemini / Groq / DeepSeek / Together / Mistral / OpenRouter).
- Porcentaje de válidos según `validar_ejemplo` por tipo.
- Distribución de longitudes de `salida` por tipo.

### 7. Calidad multi-criterio del corpus (jueces LLM)

Distribución de scores 0–10 por dimensión sobre la muestra etiquetada
(n_etiquetada ≥ 30 000):

| Dimensión | Promedio | Mediana | DE | Distribución |
|---|---|---|---|---|
| SEG | TBD | TBD | TBD | (histograma) |
| LEG | TBD | TBD | TBD | (histograma) |
| ESC | TBD | TBD | TBD | (histograma) |
| ARQ | TBD | TBD | TBD | (histograma) |
| REN | TBD | TBD | TBD | (histograma) |
| MAN | TBD | TBD | TBD | (histograma) |

### 8. Calibración de los reward models propios

Pearson correlation entre los seis RM propios y los jueces LLM que los
entrenaron, evaluada en hold-out:

| Dimensión | Pearson | Kendall tau | Calibración |
|---|---|---|---|
| SEG | objetivo ≥ 0.7 | objetivo ≥ 0.6 | TBD |
| LEG | objetivo ≥ 0.7 | objetivo ≥ 0.6 | TBD |
| ESC | objetivo ≥ 0.7 | objetivo ≥ 0.6 | TBD |
| ARQ | objetivo ≥ 0.7 | objetivo ≥ 0.6 | TBD |
| REN | objetivo ≥ 0.7 | objetivo ≥ 0.6 | TBD |
| MAN | objetivo ≥ 0.7 | objetivo ≥ 0.6 | TBD |

### 9. Resultados del modelo B (150 M parámetros)

#### 9.1 Curvas de entrenamiento por fase

- Fase 1 (pretraining código): loss inicial / final, PPL final, tiempo total.
- Fase 2 (continued pretraining docs): loss final, PPL en docs Python.
- Fase 3 (SFT con CoT): val_loss final, % respuestas con CoT visible.
- Fase 4 (SFT distillation): val_loss final.
- Fase 5a (SFT senior): val_loss final, mejora en detección de bugs.
- Fase 5b (DPO multi-objetivo): win rate vs Fase 5a, mejora por dim.

#### 9.2 Benchmarks finales

| Métrica | Modelo A (46 M, baseline) | Modelo B (150 M) | Mejora |
|---|---|---|---|
| HumanEval pass@1 | TBD | TBD | TBD |
| HumanEval+ pass@1 | — | TBD | — |
| MBPP pass@1 | TBD | TBD | TBD |
| MBPP+ pass@1 | — | TBD | — |
| APPS introductory | — | TBD | — |
| Pedagógico promedio (1–10) | TBD | TBD | TBD |

#### 9.3 Análisis por dimensión

Comparativa de scores promedio de los reward models propios sobre 100
prompts educativos canónicos:

| Dimensión | Modelo A | Modelo B | Mejora absoluta |
|---|---|---|---|
| SEG | TBD | TBD | TBD |
| LEG | TBD | TBD | TBD |
| ESC | TBD | TBD | TBD |
| ARQ | TBD | TBD | TBD |
| REN | TBD | TBD | TBD |
| MAN | TBD | TBD | TBD |

### 10. Resultados del modelo C (350 M parámetros)

Misma estructura que sección 9, pero comparando contra Modelo B.

### 11. Análisis comparativo de las decisiones de diseño

Para cada decisión técnica significativa (ver
[`docs/DECISIONES_DISENO.md`](../docs/DECISIONES_DISENO.md)), análisis
empírico:

- **DD-08 (DPO vs PPO)**: comparativa de win rate del modelo entrenado
 con DPO frente al modelo de Fase 5a (sin DPO).
- **DD-09 (pesos por dimensión)**: ablation con pesos uniformes vs
 pesos diferenciados.
- **DD-12 (currículum por fases)**: comparativa con un modelo entrenado
 con mezcla uniforme de todos los datos.

### 12. Análisis cualitativo con estudiantes (V2)

- Comparación ciega entre Modelo A, Modelo B y Modelo C en 100 prompts.
- Análisis de respuestas con chain-of-thought visible vs sin.
- Preferencia subjetiva de los estudiantes (Likert 1–5).
- Comentarios abiertos analizados por tema.

### 13. Limitaciones identificadas

- Restricciones de hardware (RTX 2050 + tiers gratuitos cloud).
- Cobertura limitada a Python como lenguaje principal.
- Diversidad limitada del corpus respecto a modelos comerciales con
 trillones de tokens.
- Sesgo del corpus generado por LLMs comerciales (heredan sus sesgos).

### 14. Conclusiones y trabajos futuros

- Cumplimiento de los siete objetivos específicos (OE1–OE7).
- Aportes originales validados empíricamente.
- Líneas de investigación derivadas (modelos D de 1 B, especialización
 por dominio, integración con MCP, etc.).
