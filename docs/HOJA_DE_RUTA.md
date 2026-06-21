# Hoja de Ruta — Sistema Explicador Python IA

> **Documento vivo.** Define la visión completa del proyecto desde la
> fase actual hasta el sistema final propuesto del proyecto. Cada
> sección marca qué está hecho (✓), qué está en curso (◐) y qué queda
> por hacer (○).
>
> **Para una visión completa del proyecto orientada a el proyecto, ver
> los siguientes documentos** (creados en la sesión de junio 2026):
>
> - [`PROPUESTA_INVESTIGACION.md`](./PROPUESTA_INVESTIGACION.md) — propuesta académica formal con objetivos, metodología, resultados esperados.
> - [`CATALOGO_ARCHIVOS.md`](./CATALOGO_ARCHIVOS.md) — inventario completo de archivos del proyecto.
> - [`BITACORA_DESARROLLO.md`](./BITACORA_DESARROLLO.md) — registro cronológico de implementación.
> - [`ARQUITECTURA_TECNICA.md`](./ARQUITECTURA_TECNICA.md) — descripción técnica detallada.
> - [`DECISIONES_DISENO.md`](./DECISIONES_DISENO.md) — 20 decisiones técnicas con justificación.
> - [`BUGS_Y_SOLUCIONES.md`](./BUGS_Y_SOLUCIONES.md) — incidentes y soluciones aplicadas.
> - [`EXPERIMENTOS.md`](./EXPERIMENTOS.md) — registro de smoke tests y resultados.
> - [`DATASET_V2.md`](./DATASET_V2.md) — especificación del corpus pedagógico.
> - [`REWARD_MODELS.md`](./REWARD_MODELS.md) — sistema de 6 reward models multi-criterio.
> - [`PLAN_ENTRENAMIENTO_V2.md`](./PLAN_ENTRENAMIENTO_V2.md) — plan técnico de las 5 fases.

---

## 1. Visión general

Construir un **LLM educativo propio en español** especializado en la
enseñanza de Python, entrenado desde cero y mejorado iterativamente con
APIs comerciales, datasets curados y feedback de usuarios reales. El
sistema debe:

1. **Razonar y generar código** a nivel competitivo con asistentes
 comerciales, especialmente en el dominio Python.
2. **Explicar** lo que genera, paso a paso, con tono pedagógico.
3. **Mejorar continuamente** con feedback humano (RLHF) y APIs externas
 como maestros (RLAIF).
4. **Ver imágenes** (multimodal) para diagnosticar errores en pantalla,
 capturas de IDE, diagramas a mano.
5. **Actuar sobre la PC** del usuario (filesystem, terminal, MCP
 externos) — modo IDE para acelerar desarrollo real.
6. **Conocer programación desde sus orígenes** hasta lo más actual
 (frameworks 2025, paradigmas emergentes, mejores prácticas).

---

## 2. Fases del proyecto

### Fase 1 — Plataforma funcional (terminada)

✓ Backend FastAPI + Postgres con autenticación, RBAC, audit log
✓ Frontend web (Next.js + Tailwind, paleta Anthropic)
✓ App desktop Flutter con paridad funcional
✓ Endpoint de chat con routing a Gemini / DeepSeek
✓ Cifrado AES-256 de claves API
✓ Filtro de contenido pedagógico
✓ Sistema de prompts maestros (qué hace / por qué / alternativas /
 ejercicios)
✓ Adjuntos, dictado por voz, búsqueda web integrada
✓ 5 paletas de color, i18n parcial es/en, atajos globales, command
 palette, onboarding, modal confirmación, exportar MD/PDF
✓ Pipeline de entrenamiento desde cero (sentencepiece + custom
 Transformer 46M params)

### Fase 2 — Modelo propio entrenado (esta semana)

◐ Primer entrenamiento end-to-end con preset `experto` (RTX 2050)
○ Métricas finales: loss train < 4.0, val < 4.5, BLEU > 12
○ Servir el checkpoint vía endpoint del backend
○ A/B test contra Gemini en consultas educativas

📄 Ver [`ENTRENAMIENTO.md`](./ENTRENAMIENTO.md) para guía paso a paso.

### Fase 3 — Feedback loop + RLHF (próxima)

○ Tabla `Feedback` en BD + endpoint REST
○ Botones 👍/👎 + comentario opcional en cada respuesta del chat
○ Exportador `dataset_rlhf.jsonl` (formato DPO)
○ Juez LLM (Gemini) para etiquetar automáticamente pares preferidos
○ Entrenamiento DPO sobre checkpoint base
○ Comparativa antes/después con prompts de evaluación

📄 Ver [`RLHF_PLAN.md`](./RLHF_PLAN.md) para detalles.

### Fase 4 — Visión multimodal (próxima)

○ Subir imagen al chat (PNG/JPG, max 5 MB, web + desktop)
○ Backend acepta `imagenes[]` en `/chat/enviar`
○ Routing automático a Gemini Vision para consultas con imagen
○ Casos de uso: capturas de error de consola, diagramas a mano, código
 en pizarra
○ Visión propia (cuando entrenemos un modelo multimodal — fase tardía)

📄 Ver [`VISION_PLAN.md`](./VISION_PLAN.md) para detalles.

### Fase 5 — MCP (Model Context Protocol)

○ Servidor MCP local en el backend que expone tools del sistema:
 - `leer_archivo`, `escribir_archivo`, `listar_directorio`
 - `ejecutar_python`, `ejecutar_shell`
 - `buscar_en_web`, `consultar_doc_oficial`
○ Cliente MCP en la app desktop para conectarse a MCPs externos
 (Unity, Blender, Notion, GitHub)
○ El LLM elige qué herramienta usar según la pregunta

📄 Ver [`MCP_PLAN.md`](./MCP_PLAN.md) para detalles.

### Fase 6 — Modo IDE en desktop

○ Editor de código embebido (Monaco o code_text_field)
○ Vista split: editor + chat lateral
○ Run/debug integrado (botón "ejecutar" → terminal embebida)
○ Tabs de archivos abiertos
○ Diff viewer para sugerencias del asistente
○ Inline completions tipo Copilot (cuando el modelo lo soporte)

### Fase 7 — Mejora continua

○ Re-entrenamiento mensual con feedback acumulado
○ Curriculum learning: empezar con código simple, escalar a frameworks
○ Distillation: aprender de respuestas de Gemini con `--maestro`
○ Multi-turno: mantener contexto de toda la conversación
○ Personalización por usuario: el asistente recuerda su nivel y estilo

### Fase 8 — Escalar de 46M a 120M y 350M (FROM SCRATCH)

○ Modernizar arquitectura: RoPE + GQA + SwiGLU + RMSNorm + FlashAttention v2
○ Entrenar modelo B (120M) DESDE CERO con currículum de 5 fases
○ Entrenar modelo C (350M) DESDE CERO con la misma metodología escalada
○ Dataset V2 enriquecido (333k ejemplos, 10 tipos pedagógicos)
○ 6 reward models multi-criterio (SEG/LEG/ESC/ARQ/REN/MAN)
○ DPO multi-objetivo con pesos por dimensión
○ Actualización mensual automática
○ Opcional: modelo D (700M-1B) si tiers gratis cloud alcanzan

**NO descargar Qwen, Llama, ni ningún modelo base externo.** Las APIs
externas solo sirven como profesores para generar dataset.

📄 Ver [`DATASET_V2.md`](./DATASET_V2.md), [`REWARD_MODELS.md`](./REWARD_MODELS.md),
[`PLAN_ENTRENAMIENTO_V2.md`](./PLAN_ENTRENAMIENTO_V2.md).

---

## 3. Qué tiene que saber el sistema

Categorías de conocimiento que el LLM debe dominar:

### Programación
- Python 3.6 → 3.13 (sintaxis, builtins, stdlib completa)
- Frameworks web: Flask, FastAPI, Django, Streamlit
- Data: NumPy, Pandas, Polars, Matplotlib, Seaborn, Plotly
- ML/IA: PyTorch, TensorFlow, scikit-learn, HuggingFace, transformers
- Bases de datos: SQL, SQLAlchemy, MongoDB, Redis
- Async / concurrencia: asyncio, threading, multiprocessing
- Testing: pytest, unittest, hypothesis, coverage
- DevOps: Docker, GitHub Actions, deployment a Railway/Fly/AWS

### Historia de la programación
- Paradigmas: imperativo, OOP, funcional, lógico, reactivo
- Lenguajes históricos: Fortran, Lisp, C, Smalltalk, Pascal
- Evolución de Python (CPython, PyPy, Cython, Mojo)
- Estándares actuales (PEP 8, 484, 695)

### Académico
- Algoritmos clásicos y análisis de complejidad
- Estructuras de datos
- Sistemas operativos básicos
- Redes (TCP/IP, HTTP, REST, gRPC)
- Seguridad (OWASP top 10, criptografía básica)

### Actualidad
- Frameworks emergentes (Tauri, Solid.js, Bun)
- Mejores prácticas 2024-2025
- Eventos relevantes del mundo tech
- (Vía búsqueda web cuando el modelo no esté actualizado)

---

## 4. Métricas objetivo (proyecto)

| Métrica | Baseline (sin entrenar) | Meta Fase 2 | Meta Fase 7 |
|---|---|---|---|
| Loss validación | ~9.6 | < 4.5 | < 3.0 |
| HumanEval pass@1 | 0% | 8% | 25% |
| Satisfacción usuario (👍 rate) | — | 60% | 85% |
| Latencia respuesta (p95) | — | < 3s | < 2s |
| Disponibilidad | — | 99% | 99.9% |
| Costo por 1k tokens | — | $0 (propio) | $0 (propio) |

---

## 5. Entregables del proyecto

1. **Sistema funcional** desplegado (lo que hay)
2. **Dataset propio** curado y validado (CodeAlpaca-es + feedback)
3. **Modelo propio** entrenado desde cero
4. **Modelo refinado** con RLHF
5. **Documentación completa** (esta carpeta `docs/`)
6. **Experimentos** comparativos (modelo propio vs API comercial)
7. **Documentación** con metodología, resultados, conclusiones

---

## 6. Para el mercado (futuro)

El sistema está diseñado de modo que, después de el proyecto, pueda
**comercializarse**:

- Licencia clara del corpus de entrenamiento
- Modelo en HuggingFace Hub para investigación
- App desktop como producto freemium para estudiantes
- API SaaS para academias/universidades
- Plugin para VS Code, JetBrains

Esta hoja de ruta deja preparada toda la infraestructura para llegar
ahí sin reescribir nada.
