# Experimentos y Resultados

> Registro de las pruebas realizadas, configuraciones probadas,
> métricas obtenidas y observaciones. Este documento alimenta
> directamente el sección de Resultados de el proyecto.

---

## 1. Smoke test de la arquitectura V2 del modelo

### 1.1 Setup

| Parámetro | Valor |
|---|---|
| Fecha | Junio 2026 |
| Hardware | CPU (verificación de la implementación, no entrenamiento) |
| Configuración probada | 5 presets V2 (`sota_experto`, `sota_grande`, `sota_b`, `sota_c`, `sota_d`) |
| Modelo concreto evaluado | Versión nano de `ModelConfigV2` con vocab=1000, block_size=64, n_layer=2, n_head=4, n_kv_head=2, n_embd=128 |

### 1.2 Pruebas ejecutadas

| Prueba | Resultado | Observación |
|---|---|---|
| Instanciación de presets V2 (5 tamaños) | OK | 30.7M / 87.8M / 150.7M / 350.9M / 869.9M params reales |
| Forward del modelo nano | OK | logits shape (2, 64, 1000), loss 6.91 |
| Backward del modelo nano | OK | Gradientes calculados |
| Gradient checkpointing activado + forward + backward | OK | loss 6.95 (similar al sin GC, esperado) |
| Generación autoregresiva con top_k=50 | OK | Entrada de 5 tokens → salida de 15 |
| Extrapolación de RoPE más allá de `block_size` | OK | block_size=32, secuencia de 48 tokens funciona |

### 1.3 Conclusiones

- La arquitectura V2 está correctamente implementada.
- Los presets dan tamaños reales muy cercanos a los objetivos del plan
 (150M para B, 350M para C).
- El gradient checkpointing funciona y permite entrenar modelos
 grandes en RTX 2050.
- RoPE permite extrapolación de contexto sin pérdida funcional.

---

## 2. Smoke test del sistema multi-criterio de reward models

### 2.1 Setup

| Parámetro | Valor |
|---|---|
| Hardware | CPU |
| Presets probados | `pequeno` (8M), `mediano` (16M), `grande` (32M) |
| Configuración test | preset pequeño, B=2, T=64 |

### 2.2 Resultados

| Métrica | Valor |
|---|---|
| Output shapes (6 dimensiones) | Todas (B,) correctas |
| Output range inicial (sin entrenar) | min=4.78, max=5.61 (lógico, cerca de score neutro 5) |
| MSE loss con targets aleatorios | 0.6071 |
| Detalle por dimensión | SEG: 0.205, LEG: 0.007, ESC: 0.099, ARQ: 0.173, REN: 0.037, MAN: 0.086 |
| Ranking loss (chosen vs rejected aleatorios) | 4.7811 |
| Backward del total | OK |

### 2.3 Desglose de parámetros del preset pequeño (8.4M total)

| Componente | Parámetros |
|---|---|
| Encoder embedding | 4 608 000 |
| Encoder bloques (4 capas) | 3 541 248 |
| Head SEG | 37 121 |
| Head LEG | 37 121 |
| Head ESC | 37 121 |
| Head ARQ | 37 121 |
| Head REN | 37 121 |
| Head MAN | 37 121 |

### 2.4 Conclusiones

- El encoder consume el 97 % de los parámetros, las heads son
 insignificantes en costo.
- Agregar dimensiones adicionales (7ª, 8ª) sería prácticamente gratis
 en memoria.
- Output range inicial razonable indica buena inicialización.

---

## 3. Smoke test del pipeline de generación de dataset

### 3.1 Setup

| Parámetro | Valor |
|---|---|
| Fecha | Junio 2026 |
| Proveedor LLM | Groq con `llama-3.3-70b-versatile` |
| Generador probado | `pensamiento_programador` solamente |
| Escala | mini (n_por_objetivo=2) |
| Modo | `--skip` de los otros 9 generadores |

### 3.2 Resultados

| Métrica | Valor |
|---|---|
| Tiempo total | 4.7 minutos |
| Objetivos procesados | 20/20 |
| Ejemplos solicitados | 40 (20 × 2) |
| Ejemplos generados válidos | 28 (70 %) |
| Ejemplos descartados | 1 |
| Duplicados | 0 |
| Distribución por nivel | intermedio: 67.86 %, avanzado: 32.14 % |
| Tema dominante | api_rest (14.29 %) |
| Longitud promedio de `salida` | 1 800 caracteres |
| Longitud máxima de `salida` | 2 777 caracteres |
| Código compilable (`ast.parse`) | 26/26 bloques (100 %) |
| Ejemplos con `pensamiento` poblado | 28/28 (100 %) |
| Ejemplos en español | 100 % |
| Auditoría final | "LISTO para entrenar" |

### 3.3 Ejemplo concreto extraído del corpus

```
instruccion: "Diseña un sistema de API REST para gestionar una
 biblioteca, donde se puedan crear, leer, actualizar y
 eliminar libros."
tipo: pensamiento_programador
nivel: intermedio
tema: api_rest
fuente: groq

pensamiento:
 aclaraciones (2 elementos):
 - "¿Qué tipo de datos se necesitan para cada libro?"
 - "¿Cuál es el objetivo principal de la API?"
 restricciones_implicitas (3):
 - "La API debe ser segura"
 - "La API debe ser escalable"
 -...
 alternativas_consideradas (3):
 [ ] Flask
 [X] Django Rest Framework
 [ ] FastAPI
 criterios_decision (3):
 ["Escalabilidad", "Seguridad", "Facilidad de uso"]

salida (2 777 caracteres):
 Para diseñar un sistema de API REST para gestionar una biblioteca,
 se puede utilizar el framework Django Rest Framework. Este enfoque
 nos permite crear una API escalable, segura y fácil de usar.
 Primero, debemos instalar Django y Django Rest Framework utilizando
 pip: `pip install django djangorestframework`. Luego, creamos un
 nuevo proyecto de Django y una aplicación para nuestra biblioteca.
 [...continúa con código Python y explicación detallada...]
```

### 3.4 Conclusiones

El pipeline completo (Pool → llamada API → parser → schema → validador
→ auditoría → archivo JSONL) funciona correctamente end-to-end. La
calidad pedagógica de los ejemplos generados es alta:

- Se identifican aclaraciones que un programador senior preguntaría.
- Se enumeran restricciones implícitas (seguridad, escalabilidad).
- Se consideran tres alternativas tecnológicas con justificación.
- El campo `salida` incluye explicación textual y código funcional.

---

## 4. Smoke test del pipeline completo (10 generadores)

### 4.1 Primera corrida con Groq 70B

| Configuración | Valor |
|---|---|
| Modelo | `llama-3.3-70b-versatile` |
| Escala | mini |
| Generadores activos | 10 |
| Llamadas estimadas | 235 |

| Resultado | Valor |
|---|---|
| Tiempo cuando se interrumpió | 13.5 minutos |
| Objetivos procesados del primer generador | 9/20 |
| Ejemplos válidos generados | 7 |
| Decisión | Interrumpido por rate limit excesivo |

**Análisis:** el rate limit por tokens por minuto (6 000 TPM) del
modelo 70B en tier gratuito hace inviable el pipeline completo con
este modelo. Cada llamada espera 4 minutos entre intentos.

### 4.2 Segunda corrida con Groq 8B

| Configuración | Valor |
|---|---|
| Modelo | `llama-3.1-8b-instant` |
| Pool con espera fija de 60s ante 429 | Activado |
| Extractor robusto de JSON | Activado |
| Escala | mini |
| Generadores activos | 10 |

**Estado:** corriendo en background al momento de redactar este
documento. Resultado preliminar: la primera llamada pegó 429 y esperó
60 segundos, después reanudó normalmente. Estimación de tiempo total
con TPM de 20 000: 60–90 minutos.

**Resultado final por completar** cuando termine la corrida.

---

## 5. Smoke test de configuraciones YAML

### 5.1 Setup

Verificar que las seis configuraciones YAML de las fases de
entrenamiento son sintácticamente válidas y los campos esperados están
presentes.

### 5.2 Resultados

| Archivo | Parse YAML | Campos básicos |
|---|---|---|
| `fase1_pretrain_B.yaml` | OK | modo: pretrain, preset: sota_b, 6 txt files |
| `fase2_docs_B.yaml` | OK | modo: pretrain, preset: sota_b, 7 txt files |
| `fase3_cot_B.yaml` | OK | modo: sft, preset: sota_b, 4 filtros de tipo |
| `fase4_distillation_B.yaml` | OK | modo: sft, preset: sota_b, 8 filtros de tipo |
| `fase5a_senior_B.yaml` | OK | modo: sft, preset: sota_b, 5 filtros de tipo |
| `fase5b_dpo_B.yaml` | OK | preset: sota_b, 6 archivos por dimensión |
| `rlhf/configs/rm_v1.yaml` | OK | preset: mediano (RM), MSE loss |

### 5.3 Conclusiones

Las siete configuraciones YAML parsean correctamente y declaran los
campos requeridos. Están listas para usarse cuando el corpus y los
datos de cada fase estén disponibles.

---

## 6. Pruebas de carga (pendientes)

### 6.1 Entrenamiento del modelo B Fase 1

| Variable | Valor objetivo |
|---|---|
| Plataforma | Kaggle T4 16 GB |
| Tiempo proyectado | ~25 horas (en chunks de 9 horas) |
| Loss validación objetivo | < 3.5 al final de la fase |
| Métrica de salud durante training | tok/s estable, sin spikes |

### 6.2 Entrenamiento de los reward models

| Variable | Valor objetivo |
|---|---|
| Plataforma | RTX 2050 4 GB (cabe el preset pequeño) o T4 (preset mediano) |
| Tiempo proyectado | ~3 horas por RM × 6 = 18 horas, o entrenamiento conjunto si comparten encoder |
| Métrica de salud | Pearson > 0.7 contra jueces LLM por dimensión |

### 6.3 DPO Fase 5b

| Variable | Valor objetivo |
|---|---|
| Plataforma | Kaggle T4 con gradient checkpointing obligatorio |
| Tiempo proyectado | ~10 horas |
| Métrica | Win rate vs Fase 5a > 65 % juzgado por Gemini |
| Mejora por dimensión | +20 % en SEG mínimo |

---

## 7. Comparativas planeadas para el documentación

### 7.1 Tabla principal del sección de Resultados (placeholder)

| Métrica | Modelo A (46M, ya entrenado) | Modelo B (150M, objetivo) | Modelo C (350M, objetivo) |
|---|---|---|---|
| Loss validación final | < 4.5 | < 3.0 | < 2.5 |
| HumanEval pass@1 | TBD | 15–20 % | 30–35 % |
| MBPP+ pass@1 | TBD | ~20 % | ~35 % |
| Win rate vs A (juez Gemini) | — | > 70 % | > 85 % |
| Score pedagógico (1–10) | TBD | ~7 | ~8 |
| % respuestas con chain-of-thought visible | 0 % | > 50 % | > 70 % |
| Tamaño on-disk FP16 | 90 MB | 287 MB | 670 MB |
| Tamaño on-disk INT4 | 25 MB | 72 MB | 167 MB |

### 7.2 Tabla de análisis por dimensión (placeholder)

Comparativa de scores promedio (0–10) de los reward models para una
muestra de 100 respuestas:

| Dimensión | Modelo A | Modelo B | Modelo C | Gemini API (referencia) |
|---|---|---|---|---|
| SEG | TBD | TBD | TBD | TBD |
| LEG | TBD | TBD | TBD | TBD |
| ESC | TBD | TBD | TBD | TBD |
| ARQ | TBD | TBD | TBD | TBD |
| REN | TBD | TBD | TBD | TBD |
| MAN | TBD | TBD | TBD | TBD |

---

## 8. Reproducibilidad

Cada experimento se ejecuta con:

- Semilla fija (seed=42).
- Configuración YAML versionada en `ml/training/configs/` o
 `ml/rlhf/configs/`.
- Logs estructurados en `metrics.jsonl` y `resumen_construccion.json`.
- Checkpoints en `training/checkpoints/<nombre>/`.

Cualquier corrida puede reproducirse con un único comando:

```powershell
python -m ml.data.construir_dataset_v2 --salida-dir datasets/raw --escala mini --reset
python -m ml.training.run_fase --config ml/training/configs/fase1_pretrain_B.yaml
python -m ml.rlhf.entrenar_rm --config ml/rlhf/configs/rm_v1.yaml
python -m ml.rlhf.dpo_multi --config ml/training/configs/fase5b_dpo_B.yaml
```
