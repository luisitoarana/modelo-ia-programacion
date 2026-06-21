# Capacidades de una IA avanzada y su aplicación al sistema

> Investigación del estado del arte (2026) sobre lo que hace "avanzada" a una
> IA actual, y cómo aplicarlo —de forma realista y segura— a nuestro sistema
> educativo (web + app de escritorio + backend + modelo propio).

## 1. Idea central: inteligencia ≠ capacidades

Una IA moderna se compone de **dos cosas separadas**:

1. **El cerebro (el modelo / LLM):** razona y genera lenguaje/código.
2. **La capa de capacidades (el "agente"):** rodea al modelo y le da manos:
 buscar en internet, leer/editar archivos, ejecutar comandos, conectarse a
 herramientas externas (MCP), recordar, etc.

Lo que percibimos como "IA superavanzada" (Claude, Gemini, ChatGPT con agentes)
es **un modelo capaz + una buena capa de capacidades**. Esto es clave para
nuestra proyecto: aunque nuestro modelo propio sea pequeño, **la capa de
capacidades sí podemos construirla a nivel profesional**, y el "cerebro" puede
ser temporalmente una API (Gemini/DeepSeek) mientras entrenamos el propio.

## 2. Estado del arte (2026)

### 2.1 El bucle agéntico (think → act → observe)
Un agente es un LLM que ejecuta un ciclo: **piensa** qué hacer → **actúa**
llamando a una herramienta → **observa** el resultado → vuelve a pensar. Repite
hasta cumplir el objetivo. Así un agente "se queda" hasta que los tests pasan o
la tarea se completa.

### 2.2 Tool use / Function calling
El modelo recibe descripciones (esquemas) de funciones disponibles y decide
cuándo llamarlas. Ocurre dentro del ciclo petición-respuesta del modelo; el
costo crece con el número de herramientas (todos los esquemas viajan en cada
petición). Lo soportan Gemini, OpenAI y DeepSeek.

### 2.3 MCP (Model Context Protocol)
Estándar abierto (creado por Anthropic, donado a fines de 2025 a la **Agentic
AI Foundation** de la Linux Foundation, co-fundada con Block y OpenAI). Modelo
**cliente-servidor**: la app (host) se conecta a **servidores MCP** que exponen
herramientas, datos y plantillas, vía **JSON-RPC 2.0** sobre stdio (local) o
HTTP+SSE (remoto). Ventaja sobre function calling puro: el agente **descubre**
las herramientas dinámicamente y escala a cientos sin inflar el prompt. En 2026
hay **+10.000 servidores MCP** públicos; OpenAI y Gemini lo soportan.

### 2.4 Recuperación de contexto (RAG) y ventanas grandes
Para trabajar con código real, los agentes **indexan el repositorio** (estructura
de archivos, dependencias, commits, tests) y recuperan lo relevante (RAG), o
usan **ventanas de contexto enormes** (hasta ~1M tokens) para cargar gran parte
del proyecto en memoria.

### 2.5 Capacidades agénticas de programación
Los agentes de código actuales (Claude Code, Cursor, Codex, Gemini CLI, Aider…):
- Exploran el **sistema de archivos** y editan código en varios archivos.
- Usan la **terminal**: ejecutan builds, tests, linters y **leen la salida**;
 si falla, corrigen y reintentan.
- Integran **control de versiones** (git, pull requests).
- Usan **arquitecturas multi-agente** (un agente líder delega subtareas a
 sub-agentes en paralelo).
- Operan desde **CLI** para mayor acceso al sistema y scripting.

### 2.6 Búsqueda web y actualización
Mediante "grounding"/búsqueda, el modelo consulta internet para datos frescos y
no quedarse estancado en su fecha de corte. Gemini ofrece grounding con Google
Search; también se usan APIs de búsqueda dedicadas.

### 2.7 Seguridad (imprescindible)
Las capacidades agénticas abren riesgos reales, sobre todo **inyección de
prompts** (instrucciones maliciosas escondidas en archivos/web/herramientas que
secuestran al agente). Mitigaciones: **permisos explícitos** por acción,
**sandbox**, lista blanca de comandos/dominios, confirmación humana para
acciones destructivas, y registro/auditoría. Nuestro sistema ya cifra las API
keys y separa roles; hay que extender eso a las herramientas.

## 3. Aplicación a NUESTRO sistema

| Capacidad | Dónde se implementa | Factibilidad |
|---|---|---|
| Bucle agéntico (tool use) | Backend (orquestador) | Alta (con API como cerebro) |
| Búsqueda web / actualización | Backend (herramienta) | Alta (con API de búsqueda o grounding) |
| Leer/editar **archivos** | App escritorio (nativa) + backend | Media (nativa: sí; web: solo subir) |
| **Terminal**/comandos | App escritorio (nativa) | Media-alta (nativa, con permisos) |
| Cliente **MCP** | Backend / app escritorio | Media (estándar claro) |
| RAG sobre el proyecto | Backend (índice + recuperación) | Alta |
| **Explicar lo que hace** (diferenciador educativo) | Backend + UI | Alta — nuestro valor único |

> **El diferenciador del proyecto:** cualquier agente genera/ejecuta. El nuestro,
> además, **explica el porqué** de cada paso (qué carpeta creó y para qué, qué
> comando usó, qué framework instaló y por qué) para enseñar al estudiante.

## 4. Arquitectura propuesta (capa de agente)

```
 Estudiante / Administrador
 │
 Interfaz (web / escritorio)
 │
 ┌─────────▼──────────┐
 │ MOTOR AGÉNTICO │ bucle think→act→observe
 │ (backend) │
 └───┬───────┬─────────┘
 │ │ decide qué herramienta usar
 ┌────────▼─┐ ┌──▼─────────┐ ┌───────────────┐
 │ CEREBRO │ │ HERRAMIENTAS│ │ EXPLICADOR │
 │ modelo │ │ - web_search│ │ (narra y │
 │ propio │ │ - leer_arch │ │ enseña cada │
 │ ó API │ │ - terminal │ │ acción) │
 │ (Gemini) │ │ - mcp_* │ └────────────────┘
 └──────────┘ │ - rag_proj │
 └─────────────┘
```

- **Cerebro intercambiable:** API (Gemini/DeepSeek) ahora; modelo propio cuando
 esté entrenado. La interfaz del motor no cambia.
- **Herramientas con permisos:** cada acción peligrosa requiere confirmación.
- **Explicador transversal:** cada acción del agente se acompaña de su
 explicación pedagógica.

## 5. Hoja de ruta realista (por fases)

| Fase | Capacidad | Requiere |
|---|---|---|
| A | **Tool use / function calling** en el backend (esquema de herramientas + bucle) | API key (Gemini) |
| B | **Búsqueda web** como herramienta (actualizarse) | API de búsqueda / grounding |
| C | **RAG del proyecto** (indexar y recuperar archivos) | — (local) |
| D | App escritorio: **leer/editar archivos** reales (nativa) | Visual Studio (build nativo) |
| E | App escritorio: **terminal**/comandos con permisos | Build nativo + sandbox |
| F | **Cliente MCP** (conectar herramientas externas) | — |
| G | **Destilar** las trazas agénticas (API) como datos para entrenar el modelo propio | Dataset + entrenamiento |

> Nota: **todo lo agéntico necesita un cerebro que decida** qué herramienta
> usar. Sin API key configurada (o modelo entrenado), el agente no puede operar.
> Por eso el primer desbloqueo sigue siendo conectar una API.

## 6. La verdad honesta sobre el cerebro

- La **capa de capacidades** (agente, herramientas, web, archivos, terminal,
 MCP, explicación) la construimos a nivel profesional: es ingeniería.
- La **inteligencia bruta** del modelo propio está limitada por el hardware
 (GPU de 4 GB). No igualará a GPT/Claude. **Es esperable y es proyecto válida.**
- Camino realista: **API como cerebro** para las capacidades avanzadas hoy +
 **modelo propio** como aporte científico y como destino futuro. Las propias
 interacciones agénticas (generadas con APIs) se convierten en **datos de
 entrenamiento** para que el modelo propio aprenda a usar herramientas y a
 explicar (destilación de comportamiento agéntico).

## 7. Fuentes

- ByteByteGo — *Connecting LLMs to the Real World: Tool Use, Function Calling, and MCP*: https://blog.bytebytego.com/p/connecting-llms-to-the-real-world
- ClickHouse — *How to build AI agents with MCP (2025)*: https://clickhouse.com/blog/how-to-build-ai-agents-mcp-12-frameworks
- Portkey — *MCP vs Function Calling*: https://portkey.ai/blog/mcp-vs-function-calling/
- Anthropic Engineering — *Code execution with MCP*: https://www.anthropic.com/engineering/code-execution-with-mcp
- MCP Playground — *AI Agent + MCP Explained (2026)*: https://mcpplaygroundonline.com/blog/ai-agent-mcp-explained
- Webfuse — *Agentic Coding in 2026*: https://www.webfuse.com/blog/agentic-coding-in-2026
- plus8soft — *AI Coding Agents in 2026*: https://plus8soft.com/blog/ai-coding-agents/
- arXiv — *Prompt Injection Attacks on Agentic Coding Assistants*: https://arxiv.org/pdf/2601.17548

---

## 8. Implementación V2 (junio 2026)

Mapeo entre las capacidades avanzadas descritas en este documento y los
archivos del proyecto que las realizan.

### 8.1 Razonamiento estructurado (chain-of-thought)

- **Dataset**: tipo `pensamiento_programador` con campo `pensamiento`
 estructurado (aclaraciones, restricciones, alternativas, criterios).
- **Generador**: `ml/data/generar_pensamiento.py` (20 objetivos
 tema × nivel, prompt que pide explícitamente la cadena de razonamiento).
- **Validador**: `validar_pensamiento` en `ml/data/validadores.py`
 asegura mínimo dos alternativas, una elegida, dos criterios.
- **Fase de entrenamiento**: Fase 3 SFT con CoT
 (`ml/training/configs/fase3_cot_B.yaml`) filtra los tipos con
 razonamiento explícito.

### 8.2 Razonamiento multi-paso (autocrítica iterativa)

- **Dataset**: tipo `pensamiento_autocritico` con campo
 `pensamiento.iteraciones` = `[{version, codigo, critica},...]`.
- **Generador**: `ml/data/generar_autocritica.py` (20 problemas, tres
 iteraciones A → B → C).
- **Validador**: `validar_autocritica` exige iteraciones distintas,
 cada código compila, críticas con longitud mínima.
- **Razón**: refleja el Nivel 12 de la visión del usuario ("enseñarle a
 criticarse"). El modelo aprende a iterar internamente.

### 8.3 Razonamiento multi-criterio (sistema de seis dimensiones)

- **Rúbricas**: `ml/rlhf/jueces.py` define seis dimensiones SEG/LEG/ESC/
 ARQ/REN/MAN con descriptores 0–10.
- **Reward models propios**: `ml/rlhf/reward_model.py` con encoder
 compartido (~16 M params) + seis cabezas independientes.
- **Entrenamiento**: `ml/rlhf/entrenar_rm.py` con MSE multi-dim o
 ranking pairwise.
- **Alineamiento del modelo principal**: `ml/rlhf/dpo_multi.py` con
 pesos por dimensión.

### 8.4 Manejo de herramientas (tool calling)

- **Backend**: MCP server propio expone `leer_archivo`, `escribir_archivo`,
 `ejecutar_python`, `buscar_en_web`, etc.
- **Dataset**: pendiente generar tipo `tool_use` que capture (prompt
 estudiante → razonamiento → tool call → resultado → respuesta).
- **Inferencia**: pendiente integrar el loop ReAct en el endpoint
 `/api/v1/chat` del backend.

### 8.5 Multimodalidad (visión)

- **Modelo de visión**: ViT propio en `ml/model/vision/` + projector
 en `ml/model/multimodal_model.py`.
- **Dataset**: `ml/data/generar_imagenes_codigo.py` produce pares
 (imagen de código, descripción).
- **Entrenamiento**: `ml/train_multimodal.py` pendiente integrarse con
 el runner por YAML.

### 8.6 RAG (Retrieval-Augmented Generation)

- **Embeddings**: `ml/rag/embeddings.py`.
- **Vector store**: `ml/rag/vector_store.py`.
- **Indexador**: `ml/rag/indexar.py`.
- **Uso**: el backend consulta primero la base local antes de pasar al
 modelo. Compatible con [`docs/RAG.md`](../docs/RAG.md).

### 8.7 Auto-actualización continua

- **Crawlers de docs**: pendientes en `ml/data/crawler_docs.py`
 (mencionado en `docs/DATASET_V2.md` sección 6.1). Plan: cron mensual
 que detecta cambios en Python Docs, MDN, PEPs.
- **Re-entrenamiento incremental**: LoRA delta sobre el checkpoint
 más reciente con el delta-corpus del mes.
- **Versionado**: cada deploy genera un nuevo
 `prod_vX.Y_YYYY-MM/` en `backend/app/services/modelo_propio/`.

### 8.8 Control en inferencia (control codes)

- **Tokens especiales planificados**: `<NIVEL=basico>`,
 `<NIVEL=intermedio>`, `<NIVEL=avanzado>`, `<SEG=10>`, `<LEG=10>`, etc.
- **Entrenamiento**: durante SFT, un porcentaje del corpus se anota
 con los control codes correspondientes (basados en la `puntuacion`
 del ejemplo).
- **Inferencia**: el backend inyecta los control codes según el
 contexto (estudiante junior vs senior, modo IDE vs modo educativo).

### 8.9 Tabla resumen — cobertura V2 de las capacidades avanzadas

| Capacidad | Estado en V2 | Archivo principal |
|---|---|---|
| Chain-of-thought | Implementado | `generar_pensamiento.py` |
| Autocrítica iterativa | Implementado | `generar_autocritica.py` |
| Multi-criterio de calidad | Implementado | `jueces.py`, `reward_model.py` |
| Tool calling | Infra existente, falta dataset | `mcp_server/` |
| Multimodalidad visión | Modelo propio implementado | `ml/model/vision/` |
| RAG | Implementado | `ml/rag/` |
| Auto-actualización | Plan, no implementado | (pendiente) |
| Control codes | Planificado | (tokenizer V2 + SFT) |
| Función-llamada estructurada | Falta integrar | (pendiente) |
| Self-reflection en inferencia | DPO multi-obj aproxima | `dpo_multi.py` |
