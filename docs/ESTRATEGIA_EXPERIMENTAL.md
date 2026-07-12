# Estrategia Experimental — Diseño científico del entrenamiento y evaluación

> Documento que define la estrategia experimental de la investigación:
> curriculum learning, diseño multi-modo del dataset, comparación
> sistemática de modelos por escala y protocolo de evaluación ampliado.
> Es la base metodológica del capítulo de desarrollo de la tesis.

---

## 1. Objetivo del sistema (foco de especialización)

El modelo NO compite con modelos generalistas gigantes (GPT, Claude,
Anthropic). Se especializa en **programación y explicación pedagógica de
código**, con la hipótesis de que un modelo pequeño especializado supera
a uno grande generalista en su nicho específico.

Dominios objetivo del modelo:
- Lenguajes: Python, JavaScript, Java, SQL, HTML/CSS, Go, Rust, C++
- Librerías y documentación oficial
- Depuración (debugging)
- Arquitectura de software
- Seguridad (OWASP)
- Optimización y análisis de complejidad
- Explicación pedagógica multinivel
- Revisión de código (code review)
- Testing

**Meta pedagógica**: que el estudiante, en vez de solo copiar código,
entienda qué hace cada función, para qué sirve cada clase, cómo se
estructura la lógica, y desarrolle su propio razonamiento. El sistema
explica, depura, revisa y enseña — no solo genera.

---

## 2. Curriculum learning (entrenamiento por etapas)

En lugar de mezclar todos los datos desde el inicio, se entrena en
etapas de dificultad y especialización creciente. Es una técnica
reconocida en aprendizaje automático (el modelo aprende mejor de lo
simple a lo complejo).

### Etapas propuestas

| Etapa | Contenido | Por qué en este orden |
|---|---|---|
| 1 | Sintaxis de lenguajes | Base fundamental |
| 2 | Librerías y documentación oficial | Vocabulario técnico |
| 3 | Depuración | Requiere entender sintaxis previa |
| 4 | Arquitectura de software | Requiere entender código completo |
| 5 | Seguridad | Requiere entender arquitectura |
| 6 | Optimización | Nivel avanzado |
| 7 | Explicación pedagógica | Integra todo lo anterior |
| 8 | Revisión de código | Nivel experto, integra todo |

### Estado actual e implementación

Actualmente el entrenamiento mezcla todo el corpus (SFT directo). La
transición a curriculum learning se implementa mediante el campo
`filtro_tipos` del runner (`run_fase.py`), que ya permite filtrar el
corpus por tipo de ejemplo. Los configs de fase (fase1..fase5) ya
prevén este enfoque por etapas.

---

## 3. Diseño multi-modo del dataset (ya implementado)

El dataset NO es solo "prompt → código". El schema V2 define 17 tipos
de ejemplo que enseñan distintos "modos" de respuesta:

| Modo | Tipo en schema V2 | Generador |
|---|---|---|
| Explicar una función | explicacion_multinivel | generar_multinivel |
| Detectar un error | bug_sutil | generar_bug_sutil |
| Corregir un error | anti_patron | generar_antipatron |
| Diseñar arquitectura | arquitectura_sistema | generar_arquitectura |
| Elegir entre tecnologías | decision_diseno | generar_decision |
| Revisar código | pensamiento_autocritico | generar_autocritica |
| Escribir pruebas | testing_complejidad | generar_testing |
| Analizar complejidad | testing_complejidad | generar_testing |
| Explicar a distintos niveles | explicacion_multinivel | generar_multinivel |
| Razonamiento paso a paso | pensamiento_programador | generar_pensamiento |
| Evolución de código v1→v5 | evolucion_codigo | generar_evolucion |
| Seguridad OWASP | seguridad | generar_seguridad |

Así el modelo aprende a responder en distintos modos según lo que se
le pida, no solo a generar código.

---

## 4. Densidad de conocimiento (hipótesis de especialización)

No todos los parámetros almacenan conocimiento igual de útil para una
tarea. Un modelo generalista reparte su capacidad entre miles de temas;
un modelo especializado usa casi toda su capacidad para un dominio
concreto.

**Hipótesis medible**: al concentrar los 88M-350M parámetros
exclusivamente en programación (Python, Java, SQL, Docker, Linux,
redes, bases de datos, arquitectura, DevOps), el modelo alcanza una
"densidad de conocimiento" en ese dominio superior a la de un modelo
generalista del mismo tamaño.

Esta especialización es una ventaja cuantificable mediante EduCodeEval.

---

## 5. Comparación sistemática de modelos por escala

Se entrenan cuatro modelos con el MISMO dataset y protocolo, para
aislar el efecto del tamaño:

| Modelo | Params | Estado | Plataforma |
|---|---|---|---|
| Grande | 88M | 5K pasos ✅ (descargado) | Kaggle |
| B | 150M | 15K pasos (en curso) | Lightning |
| C | 350M | por entrenar | Lightning |
| D | 500M | probablemente inviable (hardware) | — |

> Nota de hardware: el modelo de 500M es probablemente inviable con la
> infraestructura gratuita disponible (T4). El objetivo firme es llegar
> al de 350M sí o sí y evaluarlo.

### Protocolo idéntico

- Mismo corpus (882K ejemplos consolidados).
- Misma arquitectura V2 (RoPE + GQA + SwiGLU + RMSNorm), escalada.
- Mismo tokenizer (sp_v2_16k).
- Mismos hiperparámetros base (LR, batch efectivo, warmup).

---

## 6. Protocolo de evaluación ampliado

No basta con EduCodeEval. Cada modelo se evalúa en múltiples dimensiones:

### Calidad (EduCodeEval + tareas específicas)
- Generación de código
- Depuración (debugging)
- Revisión de código (code review)
- Explicaciones pedagógicas
- Diseño de arquitectura
- Seguridad

### Eficiencia computacional
- Velocidad de inferencia (tokens/segundo)
- Consumo de memoria (VRAM en inferencia)
- Tamaño del checkpoint

### Preguntas de investigación que responde
1. ¿A partir de qué tamaño dejan de aparecer mejoras significativas?
2. ¿Dónde está el mejor equilibrio entre calidad y coste computacional?
3. ¿La especialización compensa el menor tamaño frente a generalistas?

Este tipo de análisis (curva de scaling laws propia + trade-off
calidad/coste) es un aporte valioso y publicable de la tesis.

---

## 7. Continuidad más allá de la tesis

Este proyecto no se limita a la tesis. Si los resultados son buenos,
se continuará escalando (más pasos, modelos mayores, más datos) para
llegar a un sistema de programación cada vez más capaz. La tesis es
el primer hito documentado de un desarrollo continuo.

---

## 8. Documentación obligatoria

Todo experimento se documenta: qué se hizo, cómo, por qué, y qué
resultado se obtuvo. Las capturas van a `docs/capturas/`, las métricas
a `docs/EXPERIMENTOS.md`, la cronología a `docs/DIARIO_PROGRESO.md`.
La tesis se construye a partir de esta documentación acumulada.
