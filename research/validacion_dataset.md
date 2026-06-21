# Validación del dataset educativo

## Por qué se valida

El dataset construido automáticamente no es válido por defecto: los LLMs
pueden alucinar código incorrecto, explicaciones imprecisas, actividades
triviales o desviaciones del nivel solicitado. La validación humana del
investigador es lo que convierte el registro en evidencia académica
**y** en material confiable para fine-tuning.

## Flujo

1. El estudiante genera una explicación → registro `validado=false`.
2. El investigador entra al panel (próxima iteración del frontend) o usa
 `POST /api/v1/dataset/{id}/validar`.
3. Aplica la rúbrica de [instrumentos_evaluacion.md](instrumentos_evaluacion.md).
4. Marca `validado=true` (o `false` con observaciones).
5. Solo registros validados se exportan a JSONL salvo orden explícita.

## Métricas del proyecto

- % de registros validados sobre el total.
- Distribución de puntuaciones de rúbrica.
- Tasa de validación por proveedor IA (Gemini vs. DeepSeek).
- Tasa de validación por nivel y por tema.
- Tiempo medio de validación por registro.

## Criterios de exclusión

Se descarta automáticamente del exportable cualquier registro cuyo
campo `respuesta_json` no cumpla:

- `codigo` no vacío.
- `explicacion_general` no vacía.
- Al menos un `concepto_clave`.

Esto se aplica en `backend/app/training/prepare_dataset.py`.

---

## Validación del Dataset V2 (junio 2026)

El dataset V2 introduce diez tipos pedagógicos enriquecidos (ver
[`docs/DATASET_V2.md`](../docs/DATASET_V2.md)). La validación se vuelve
de dos pasos: **automática estricta** (al generar) y **agregada
estadística** (al final del corpus).

### Validación automática por ejemplo

Cada ejemplo recién generado por el pool (`ml/data/pool_generadores.py`)
pasa por `validar_ejemplo` antes de ser aceptado al corpus. Las
verificaciones son:

| # | Verificación | Aplica a |
|---|---|---|
| 1 | Esquema básico V1 (instrucción ≥ 1 char, salida ≥ 10 chars, nivel y tipo en listas válidas). | Todos. |
| 2 | Salida pedagógica (no menor a 60 caracteres, sin placeholders como `lorem ipsum`, `TODO`, `...etc...`, sin que sea solo bloque de código). | Todos. |
| 3 | Si la entrada parece código Python (palabras clave), `ast.parse` debe compilar. | Cuando aplica. |
| 4 | Cada bloque de código extraído de la salida (regex de fences Markdown) debe compilar. | Todos. |
| 5 | Si el tipo es `pensamiento_programador` o `decision_diseno`: campo `pensamiento` con al menos dos alternativas, exactamente una elegida, al menos dos criterios. | Tipos específicos. |
| 6 | Si el tipo es `explicacion_multinivel`: las cuatro explicaciones (niño/principiante/intermedio/profesional) presentes, con longitudes mínimas y sin repetición textual. | Tipo específico. |
| 7 | Si el tipo es `anti_patron`: campo `revision_codigo` con al menos un problema identificado, `por_que_funciona_pero_es_malo`, `problema_en_produccion`. | Tipo específico. |
| 8 | Si el tipo es `pensamiento_autocritico`: dos a cinco iteraciones, cada una con `version`, `codigo` que compila y `critica` con longitud mínima. | Tipo específico. |
| 9 | Si trae `puntuacion`, las seis dimensiones presentes con valores enteros en `[0, 10]`. | Tipos específicos. |

Un ejemplo que falla cualquier punto se descarta y se cuenta en
`descartados_por_motivo` para análisis posterior.

### Validación agregada del corpus

Después de generar el corpus completo, `ml/data/audit.py` calcula y
reporta:

- Porcentaje de válidos según `validar_ejemplo` (umbral mínimo: 98 %).
- Duplicados según hash de instrucción+entrada+versión (umbral máximo:
 1 %).
- Distribución por tipo / nivel / tema / fuente.
- Estadísticos de longitud de `instruccion` y `salida` (promedio,
 mediana, máximo).
- Porcentaje de bloques de código que compilan correctamente (umbral
 mínimo: 95 %).
- Porcentaje de ejemplos con cada campo V2 poblado.
- Idioma predominante (heurística por marcadores españoles).

Si alguna métrica está bajo el umbral, el corpus no se acepta para
entrenamiento y se debe regenerar o ajustar parámetros.

### Validación pedagógica del investigador (extensión V2)

La rúbrica original 0–2 por dimensión se conserva para la validación
manual del investigador, ahora aplicada también a los nuevos tipos:

- **Para `pensamiento_programador` y `decision_diseno`**: se evalúa la
 pertinencia de las aclaraciones, restricciones identificadas,
 alternativas con justificación, y criterios de decisión.
- **Para `explicacion_multinivel`**: se evalúa la diferenciación real
 entre las cuatro audiencias y la adecuación del vocabulario.
- **Para `anti_patron` y `bug_sutil`**: se verifica que el problema
 señalado sea real y que la refactorización sea estrictamente mejor.
- **Para `evolucion_codigo`**: se verifica que las cinco versiones
 formen una progresión defendible (no solo cambios cosméticos).
- **Para `pensamiento_autocritico`**: se verifica que las críticas
 sean válidas y la versión final esté libre de los problemas
 señalados.

### Validación por jueces LLM (sistema multi-criterio)

Adicionalmente, el sistema introduce **etiquetado automatizado con
seis jueces LLM por dimensión** (ver
[`docs/REWARD_MODELS.md`](../docs/REWARD_MODELS.md) Fase A).

| Dimensión | Tres jueces asignados | Agregación |
|---|---|---|
| SEG | Gemini + DeepSeek + Groq | Mediana |
| LEG | Gemini + Mistral + Groq | Mediana |
| ESC | DeepSeek + Gemini + Groq | Mediana |
| ARQ | Gemini + DeepSeek + Mistral | Mediana |
| REN | DeepSeek + Groq + Together AI | Mediana |
| MAN | Gemini + DeepSeek + Mistral | Mediana |

Estos scores 0–10 por dimensión alimentan el entrenamiento de los seis
reward models propios.

### Métricas adicionales V2 del proyecto

- Porcentaje de cobertura de los 12 niveles cognitivos identificados.
- Distribución de scores multi-criterio en el corpus etiquetado.
- Correlación entre `score multi-criterio del juez LLM` y `puntuación
 de la rúbrica humana` en una sub-muestra (n ≥ 100) para validar la
 utilidad del etiquetado automático.
