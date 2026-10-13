Plan de Entrenamiento — Modelo C (350M)
========================================

> Documento vivo del entrenamiento del modelo insignia de la tesis.
> Complementa `docs/PLAN_ENTRENAMIENTO_V2.md` (que cubre la filosofía
> from-scratch general) con el detalle específico del C 350M y la
> **fase avanzada** que lo diferencia del B v2.

---

1. Título y foco de la tesis
----------------------------

**Tesis**: "Sistema basado en deep learning para la generación y
explicación de código orientado a estudiantes de educación superior
(nivel universitario)."

- Foco de dominio: programación (Python en la tesis, arquitectura
  preparada para múltiples lenguajes en el sistema).
- Foco pedagógico: que el estudiante aprenda a **programar y a razonar
  sobre el código**, no que copie soluciones. El sistema explica clases,
  funciones, decisiones y flujo de ejecución.
- **No se valida contra modelos comerciales** (GPT, Claude, Gemini).
  La evaluación es sobre el modelo propio en su nicho: generación,
  explicación, refactorización, revisión, testing y seguridad en Python.

---

2. Hipótesis técnica defendible
-------------------------------

> Un modelo especializado de 350M parámetros, entrenado con una
> metodología orientada a ingeniería de software (curriculum en fases +
> dataset pedagógico multi-modo + flujo interno de razonamiento),
> obtiene mejores resultados en tareas específicas de generación,
> explicación, refactorización y revisión de código que un modelo
> generalista del mismo tamaño.

Esta hipótesis es la que se somete a EduCodeEval y a la evaluación
extendida documentada en `docs/ESTRATEGIA_EXPERIMENTAL.md §6`.

---

3. Principio metodológico
-------------------------

> El objetivo del entrenamiento no es maximizar la capacidad de
> predicción del siguiente token, sino desarrollar un modelo capaz de
> razonar como un ingeniero de software, generar soluciones
> profesionales, explicarlas de forma pedagógica y autoevaluar su
> calidad antes de entregarlas.

Toda decisión de dataset, config, curriculum y evaluación se justifica
en función de este principio.

---

4. Entrenamiento por fases (curriculum específico del C 350M)
-------------------------------------------------------------

A diferencia del B v2 (que se entrena en modo SFT directo sobre todo el
corpus consolidado), el C 350M se entrena en **7 fases de dificultad y
especialización creciente**. Cada fase parte del checkpoint de la
anterior (continued pretraining).

| Fase | Nombre | Objetivo | Corpus principal | Pasos estimados |
|---|---|---|---|---|
| **A** | Sintaxis | Aprender la gramática y patrones básicos de Python (+ JS, SQL) | codeparrot-py, magicoder-oss, codealpaca | 8K |
| **B** | Arquitectura | Diseño de sistemas, patrones, módulos | dataset V2 `arquitectura_sistema`, `decision_diseno` | 4K |
| **C** | Seguridad | OWASP, criptografía básica, malas prácticas | dataset V2 `seguridad`, filtrado de codefeedback | 4K |
| **D** | Explicación pedagógica | Explicar código en 4 niveles (niño, principiante, intermedio, profesional) | dataset V2 `explicacion_multinivel` | 5K |
| **E** | Razonamiento | Chain-of-thought — pensar antes de escribir | dataset V2 `pensamiento_programador`, `decision_diseno` | 5K |
| **F** | Depuración | Detectar y explicar bugs sutiles, feedback de ejecución | dataset V2 `bug_sutil`, `anti_patron`, open-code-interp | 4K |
| **G** | Optimización + Autocrítica | Refactor, complejidad, autoevaluación iterativa v1→v5 | dataset V2 `evolucion_codigo`, `testing_complejidad`, `pensamiento_autocritico` | 5K |
| — | **Total pasos** | | | **~35K** |

**Meta agregada al plan por acuerdo con el usuario (2026-07-19)**: si el
compute alcanza (créditos pagados de Lightning), extender G hasta 40K
totales para dejar más margen a la autocrítica iterativa.

**Regla**: cada fase termina con evaluación EduCodeEval sobre su
categoría específica antes de pasar a la siguiente. Si una fase no
mejora respecto al checkpoint anterior en esa categoría, se ajustan
hiperparámetros antes de seguir.

---

5. Flujo interno de razonamiento (target de comportamiento)
-----------------------------------------------------------

El modelo, cuando recibe una consulta de un estudiante, debe seguir
internamente este flujo (aunque el usuario final solo vea la respuesta
final o el CoT resumido):

```
Usuario
  ↓
Analizar problema
  ↓
Detectar nivel del usuario  (niño / principiante / intermedio / profesional)
  ↓
Elegir arquitectura
  ↓
Pensar alternativas
  ↓
Elegir la mejor
  ↓
Analizar seguridad
  ↓
Analizar escalabilidad
  ↓
Analizar rendimiento
  ↓
Generar código
  ↓
Generar pruebas
  ↓
Autoevaluarse   (¿la respuesta cumple los criterios?)
  ↓
Entregar respuesta
```

Este flujo se enseña mediante:
- El tipo `pensamiento_programador` del dataset V2 (chain-of-thought
  explícito con alternativas y criterios).
- El tipo `pensamiento_autocritico` (iteraciones v1 → v2 → v_final con
  crítica entre versiones).
- Los tokens especiales `<think>…</think>` del tokenizer que encapsulan
  el razonamiento interno separado del código y la explicación.

---

6. Los 9 módulos del "Ingeniero de Software Artificial"
--------------------------------------------------------

En vez de tratarlo como "un LLM que predice tokens", pensamos el
sistema como un ingeniero con capacidades bien definidas:

1. **Comprensión del problema** — parseo semántico de la pregunta.
2. **Diseño arquitectónico** — elección de patrones y estructura.
3. **Generación de código** — implementación en el lenguaje pedido.
4. **Análisis de seguridad** — OWASP, sanitización, buenas prácticas.
5. **Optimización** — complejidad algorítmica, uso de memoria.
6. **Testing** — pruebas unitarias generadas automáticamente.
7. **Refactorización** — mejora iterativa v1 → v_final.
8. **Explicación pedagógica** — multinivel según el estudiante.
9. **Autoevaluación** — puntuación 0-10 en 6 dimensiones (SEG, ARQ,
   MAN, LEG, ESC, REN) antes de entregar.

Cada módulo se cubre por al menos una fase del curriculum y por al
menos un tipo del dataset V2.

---

7. Presupuesto de pasos y viabilidad
------------------------------------

- Compute estimado en T4: ~0.04–0.05 pasos/s para 350M con
  gradient_checkpointing y batch efectivo 16.
- 35K pasos ≈ 195–245 horas de GPU continua.
- Lightning gratis (~22h/mes) no alcanza — se requiere presupuesto
  pagado (~$20/mes Lightning interruptible da ~100h/mes).
- Estrategia realista con presupuesto pagado: dividir en 2 meses o
  usar GPU más rápida (A10G) para bajar tiempo total.

**Plan concreto** (agosto-septiembre 2026):
- Agosto: fases A → E (~26K pasos, ~130h) con créditos pagados.
- Septiembre: fases F → G + evaluación final + prueba con estudiantes.

---

8. Lo que NO se hace (para mantener el norte)
---------------------------------------------

- No se compara contra GPT/Claude/Gemini en la tesis (no es una
  comparación justa por diferencia de escala y datos).
- No se descarga Qwen, Llama, SmolLM ni ningún modelo base externo.
- No se incluye el uso de créditos pagados en la propuesta de
  investigación (por decisión pedagógica: la propuesta se presenta
  con recursos accesibles al estudiante promedio).

---

9. Referencias cruzadas
------------------------

- `docs/PLAN_ENTRENAMIENTO_V2.md` — filosofía general y fases del B.
- `docs/ESTRATEGIA_EXPERIMENTAL.md` — curriculum de 8 etapas, dataset
  multi-modo y protocolo de evaluación.
- `docs/DATASET_V2.md` — especificación del dataset propio y sus 17
  tipos pedagógicos.
- `docs/REWARD_MODELS.md` — 6 reward models multi-criterio para la
  autoevaluación del módulo 9.
- `docs/MANUAL_ENTRENAMIENTO.md` — recetas reproducibles en Kaggle y
  Lightning.
- `ml/training/configs/c_350m_{5k,10k,20k,30k}.yaml` — configs base.
  Faltan por crear los configs por fase (`c_fase{A..G}.yaml`).
