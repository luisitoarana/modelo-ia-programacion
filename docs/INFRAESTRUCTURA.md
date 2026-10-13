# Infraestructura del Sistema

> Instalación vigente: [README principal](../README.md), [guía del jurado](INSTALACION_JURADO.md) y [validación de entrega](VALIDACION_INSTALACION_2026-10-13.md). Los puertos públicos locales son API 8765 y web 3000; PostgreSQL 16 en Docker permanece privado.

> Documentación completa de la infraestructura técnica del proyecto:
> backend, frontend, aplicación de escritorio, MCP server, sistema RAG,
> bases de datos, contenedores, despliegue y monitoreo.
>
> El usuario destacó que la infraestructura es tan principal como la
> documentación: desde ahí se hace todo. Este documento la describe
> entera.

---

## 1. Vista general del sistema

```
 ┌─────────────────────────┐
 │ Usuario (estudiante, │
 │ investigador, docente) │
 └─────────┬───────────────┘
 │
 ┌─────────────────┼─────────────────┐
 │ │ │
 ▼ ▼ ▼
 ┌──────────────┐ ┌──────────────┐ ┌──────────────┐
 │ Frontend │ │ App Desktop │ │ Cliente MCP │
 │ Next.js │ │ Flutter │ │ externo │
 │ + Tailwind │ │ │ │ │
 └──────┬───────┘ └──────┬───────┘ └──────┬───────┘
 │ │ │
 └────────┬─────────┴────────┬─────────┘
 │ │
 ▼ ▼
 ┌──────────────────────────────────┐
 │ Backend FastAPI (async) │
 │ ┌────────────────────────────┐ │
 │ │ Auth + RBAC + Audit log │ │
 │ ├────────────────────────────┤ │
 │ │ Servicios: │ │
 │ │ - educational_engine │ │
 │ │ - model_inference │ │
 │ │ - quality_service │ │
 │ │ - retrieval_service (RAG) │ │
 │ │ - knowledge_generation │ │
 │ └────────────────────────────┘ │
 └─────┬──────────────┬────────────┬┘
 │ │ │
 ┌──────────────┼──────────────┼────────────┼─────────────┐
 │ │ │ │ │
 ▼ ▼ ▼ ▼ ▼
┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌────────────┐
│Postgres  │ │ Modelo   │ │ Vector   │ │ MCP      │ │ Telemetría │
│ + JSONB  │ │ propio   │ │ store    │ │ Server   │ │ GPU CUDA   │
│          │ │ (V1/V2)  │ │ (RAG)    │ │ propio   │ │            │
│Auth, datos│ │          │ │          │ │          │ │ Rendimiento│
│de cursos, │ │Inference │ │          │ │ Tools    │ │ Tokens/seg │
│dataset,  │ │ local    │ │          │ │ del      │ │ y latencia │
│historial │ │          │ │          │ │ sistema  │ │            │
└──────────┘ └──────────┘ └──────────┘ └──────────┘ └────────────┘
```

---

## 2. Backend (FastAPI)

### 2.1 Stack

- **Lenguaje**: Python 3.11+
- **Framework**: FastAPI (asíncrono, con Pydantic v2)
- **Servidor**: Uvicorn con workers para producción
- **Base de datos**: PostgreSQL 15+ con extensión JSONB
- **ORM**: SQLAlchemy 2.0 async
- **Migraciones**: Alembic
- **Autenticación**: JWT con HS256
- **Cifrado de secretos**: AES-256 para claves API por usuario

### 2.2 Estructura

```
backend/
├── app/
│ ├── api/v1/ # Routers REST
│ │ ├── auth.py
│ │ ├── chat.py
│ │ ├── dataset.py
│ │ ├── ai.py
│ │ ├── modelo.py
│ │ ├── feedback.py
│ │ ├── knowledge.py
│ │ └──...
│ ├── core/ # Configuración y dependencias globales
│ │ ├── config.py
│ │ ├── security.py
│ │ └──...
│ ├── domain/ # Lógica del dominio
│ │ ├── curriculo.py
│ │ ├── prompts/
│ │ └──...
│ ├── models/ # ORM SQLAlchemy
│ │ ├── usuario.py
│ │ ├── conversacion.py
│ │ ├── mensaje.py
│ │ ├── feedback.py
│ │ ├── dataset_educativo.py
│ │ ├── conocimiento.py
│ │ └──...
│ ├── schemas/ # Pydantic
│ ├── services/ # Lógica de aplicación
│ │ ├── educational_engine.py
│ │ ├── model_inference_service.py
│ │ ├── quality_service.py
│ │ ├── retrieval_service.py
│ │ ├── knowledge_generation_service.py
│ │ ├── local_inference_service.py
│ │ └──...
│ ├── training/ # Pipeline de export para fine-tuning
│ │ ├── prepare_dataset.py
│ │ └── export_jsonl.py
│ └── main.py # Entry point
├── alembic/ # Migraciones BD
├── requirements.txt
└── Dockerfile
```

### 2.3 Endpoints principales

| Endpoint | Método | Función |
|---|---|---|
| `/api/v1/auth/registro` | POST | Crear cuenta |
| `/api/v1/auth/login` | POST | Login con JWT |
| `/api/v1/chat/enviar` | POST | Enviar mensaje, recibir respuesta |
| `/api/v1/chat/enviar-stream` | POST | Streaming token-by-token (SSE) |
| `/api/v1/ai/generar` | POST | Generar JSON pedagógico estricto |
| `/api/v1/ai/preguntar-modelo` | POST | Usar modelo propio |
| `/api/v1/modelo/estado` | GET | Estado del modelo propio cargado |
| `/api/v1/dataset/{id}/validar` | POST | Validar registro del dataset |
| `/api/v1/feedback` | POST | 👍/👎 sobre una respuesta |
| `/api/v1/knowledge-gen/estadisticas` | GET | Métricas de independencia de APIs |
| `/api/v1/research/reporte-general` | GET | Métricas agregadas del proyecto |

### 2.4 Servicios clave

#### `educational_engine`

Estrategia "recuperación primero": busca en base de conocimiento
local antes de llamar a una API. Documentado en
[`research/arquitectura_cientifica.md`](../research/arquitectura_cientifica.md).

#### `model_inference_service`

Carga y sirve el modelo propio (V1 de 46 M o V2 de 150-350 M).
Inferencia autoregresiva con muestreo temperatura/top-k/top-p.

#### `quality_service`

Validador automático con rúbrica computable (AST + heurísticas). En V2
se complementa con los 6 reward models propios.

#### `retrieval_service`

Sistema RAG: busca documentos relevantes en el vector store antes de
generar respuesta. Ver [`docs/RAG.md`](./RAG.md).

#### `knowledge_generation_service`

Genera ejemplos pedagógicos usando los proveedores externos. La salida
se valida y se incorpora a la base de conocimiento.

#### `local_inference_service`

Motor de inferencia local de alta velocidad con soporte de aceleración
GPU CUDA, auto-curación de JSON sintáctico y andamiaje estructurado.

### 2.5 Modelo de datos

Tablas principales:

| Tabla | Función |
|---|---|
| `usuarios` | Cuentas de estudiantes, investigadores, admin |
| `conversaciones` | Conversaciones del chat |
| `mensajes` | Mensajes individuales |
| `feedback` | 👍/👎 por mensaje (alimenta DPO) |
| `dataset_educativo` | Registros del dataset (con respuesta_json JSONB) |
| `unidad_conocimiento` | Base de conocimiento reutilizable |
| `consultas` | Auditoría de consultas a APIs |
| `audit_log` | Log de acciones administrativas |

---

## 3. Frontend (Next.js)

### 3.1 Stack

- **Framework**: Next.js 14 (App Router)
- **UI**: React 18 + Tailwind CSS
- **Estado**: Zustand (cliente), React Query (servidor)
- **Editor de código**: Monaco editor o code_text_field
- **Markdown**: react-markdown con highlight.js
- **i18n**: next-intl
- **Tema**: 5 paletas de color (incluida la Anthropic-inspired)

### 3.2 Estructura

```
frontend/
├── app/
│ ├── (auth)/login/
│ ├── (auth)/registro/
│ ├── chat/ # Página principal de chat
│ ├── editor/ # Modo IDE
│ ├── dataset/ # Validación de dataset
│ ├── research/ # Panel de investigador
│ └── layout.tsx
├── components/
│ ├── chat/
│ │ ├── ChatPanel.tsx
│ │ ├── MensajeBubble.tsx
│ │ └── EntradaPrompt.tsx
│ ├── editor/
│ │ ├── EditorPanel.tsx
│ │ └── TerminalEmbedded.tsx
│ ├── ui/ # Botones, modales, etc.
│ └──...
├── lib/
│ ├── api.ts # Cliente del backend
│ └── auth.ts
└── public/
```

### 3.3 Funcionalidades implementadas

- Chat con historial.
- Vista dividida (editor + chat lateral).
- Búsqueda web integrada.
- Adjuntos (imágenes, PDFs).
- Dictado por voz (Web Speech API).
- 5 paletas de color.
- i18n parcial (es/en).
- Atajos globales (Ctrl+K para command palette).
- Onboarding interactivo.
- Modal de confirmación de acciones críticas.
- Export a Markdown / PDF.

---

## 4. Aplicación de escritorio (Flutter)

### 4.1 Stack

- **Framework**: Flutter 3.x
- **Plataformas**: Windows, macOS, Linux
- **Estado**: Riverpod
- **Almacenamiento local**: Hive

### 4.2 Estructura

```
app-desktop/
├── lib/
│ ├── main.dart
│ ├── screens/
│ │ ├── chat_screen.dart
│ │ ├── editor_screen.dart
│ │ └──...
│ ├── widgets/
│ ├── services/
│ │ ├── api_client.dart
│ │ ├── mcp_client.dart
│ │ └──...
│ └── models/
├── pubspec.yaml
└── windows/, macos/, linux/
```

### 4.3 Paridad funcional con el frontend web

La aplicación de escritorio expone las mismas capacidades que el
frontend web, con tres diferencias:

1. **Modo IDE**: editor de código embebido (code_text_field) con
 syntax highlighting, terminal embebida, file tree.
2. **MCP cliente local**: puede conectarse a servidores MCP externos
 (Unity, Blender, GitHub, Notion).
3. **Modelo propio offline**: una vez descargado el checkpoint INT4,
 puede usarse sin conexión a internet.

---

## 5. MCP Server propio

### 5.1 Tools expuestas

| Tool | Función |
|---|---|
| `leer_archivo` | Lee un archivo del filesystem (con confirmación de path). |
| `escribir_archivo` | Escribe contenido (con confirmación). |
| `listar_directorio` | Lista archivos en un directorio. |
| `ejecutar_python` | Ejecuta script Python en sandbox. |
| `ejecutar_shell` | Comando shell (con whitelist de comandos). |
| `buscar_en_web` | Búsqueda web (usa API externa con caché). |
| `consultar_doc_oficial` | Recupera de docs.python.org, MDN, etc. |

### 5.2 Arquitectura

```
mcp_server/
├── server.py # Implementación del servidor MCP
├── tools/ # Cada tool en archivo separado
│ ├── leer_archivo.py
│ ├── escribir_archivo.py
│ ├── ejecutar_python.py
│ └──...
├── sandbox/ # Sandbox para ejecutar código
├── auth/ # Auth contra el backend
└── config.yaml
```

### 5.3 Seguridad

- Sandbox de Docker para `ejecutar_python` y `ejecutar_shell`.
- Whitelist de paths para `leer_archivo` y `escribir_archivo`.
- Whitelist de comandos para `ejecutar_shell`.
- Auditoría de cada invocación en `audit_log`.

---

## 6. Sistema RAG

### 6.1 Stack

- **Embeddings**: bge-code-v1 (especializado en código) o all-MiniLM (texto general).
- **Vector store**: Qdrant (planeado) o sqlite con pgvector (actual fase 1).
- **Búsqueda híbrida**: BM25 + vectores con reranker bge-reranker-large.

### 6.2 Estructura

```
ml/rag/
├── embeddings.py # Genera embeddings
├── vector_store.py # Interfaz al vector DB
└── indexar.py # Indexa documentos
```

### 6.3 Flujo

1. Documentos (Python Docs, libros, papers) → embeddings → vector store.
2. Pregunta del usuario → embedding → búsqueda top-k.
3. Top-k documentos + pregunta → contexto para el modelo.
4. Modelo genera respuesta citando las fuentes.

---

## 7. Bases de datos

### 7.1 PostgreSQL principal

- Tablas relacionales del backend (usuarios, mensajes, etc.).
- Campos JSONB para datos semi-estructurados (dataset, configs).
- Índices para búsqueda eficiente.

### 7.2 Vector store

- Embeddings de documentos para RAG.
- Embeddings de unidades de conocimiento.
- Embeddings de memorias de usuario (planeado, ver
 [`docs/MEJORAS_NIVEL_TOP.md`](./MEJORAS_NIVEL_TOP.md) sección 4.4).

### 7.3 Cache (planeado)

- Redis para cachear respuestas frecuentes.
- TTL configurable por endpoint.

---

## 8. Contenedores y despliegue

### 8.1 Docker Compose

`docker-compose.yml` levanta:

- `backend`: FastAPI en puerto interno 8000; acceso local por 8765.
- `db`: PostgreSQL 16, puerto interno 5432 sin publicación al host.
- `frontend`: Next.js en port 3000 (modo dev) o build estático.
- `mcp`: MCP server propio.
- (planeado) `redis`: cache.
- (planeado) `qdrant`: vector store.

### 8.2 Dockerfiles

- `backend/Dockerfile`: base python:3.11-slim, dependencias, copy app, uvicorn.
- `frontend/Dockerfile`: base node:20-alpine, build, serve.
- `docker/Dockerfile.training`: base con CUDA para correr entrenamiento.

### 8.3 Producción

Despliegue planeado:

- **Backend**: Railway / Fly.io / Hetzner Cloud.
- **Frontend**: Vercel (gratis) o servidor estático.
- **Modelo propio**: en el mismo host del backend (cuantizado INT4 cabe en ~200 MB).
- **PostgreSQL**: Supabase / Neon (free tier).

---

## 9. Pipeline de ML

### 9.1 Estructura

```
ml/
├── data/ # Pipeline de datasets (V1 y V2)
├── tokenizer/ # Tokenizers V1 (8k) y V2 (16k)
├── model/ # Arquitecturas V1 y V2
├── training/ # Trainers V1 y V2 + 6 YAMLs
├── rlhf/ # Reward models + DPO multi-obj
├── eval/ # Benchmarks (HumanEval, MBPP+,...)
├── inference/ # Motor de inferencia
└── rag/ # Sistema RAG
```

### 9.2 Artefactos producidos por el pipeline

- Datasets en `datasets/`.
- Tokenizers en `ml/tokenizer/artefactos/`.
- Checkpoints en `training/checkpoints/`.
- Métricas en `training/experiments/`.
- Modelos para servir en `backend/app/services/modelo_propio/`.

### 9.3 Hardware soportado

| Hardware | Modelos que entrena | Tiempos típicos |
|---|---|---|
| RTX 2050 4 GB (local) | Modelo A (46 M), preset_pequeno (16 M RM), tokenizer | Horas |
| RTX 3060 12 GB | Modelo B (150 M) | Días |
| RTX 4090 24 GB | Modelo C (350 M) | 1-2 días |
| Kaggle T4 16 GB | Cualquier modelo con gradient_checkpointing | Chunks de 9 h |
| Modal A10G 24 GB | Modelo D (870 M, opcional) | Días |
| Modal A100 40 GB | Modelo D + DPO | Horas |

---

## 10. Monitoreo y observabilidad (planeado)

| Componente | Tecnología | Función |
|---|---|---|
| Logging estructurado | structlog | Logs en JSON |
| Métricas | Prometheus + Grafana Cloud | Latencia, tasa de éxito |
| Tracing | OpenTelemetry | Tracear cada request end-to-end |
| Errors | Sentry | Captura de excepciones |
| Alertas | Grafana alerting | Notificación si tasa de error > umbral |

---

## 11. Seguridad

### 11.1 Backend

- JWT con expiración corta (24 h) + refresh tokens.
- AES-256 para cifrar claves API por usuario.
- Hashing de contraseñas con bcrypt + sal.
- CORS configurado por entorno.
- Rate limiting por IP y por usuario (planeado).
- Validación estricta de entrada con Pydantic.
- Sanitización de outputs en el frontend (XSS).

### 11.2 MCP

- Sandbox de Docker para ejecución de código.
- Whitelist de paths y comandos.
- Auditoría de cada invocación.

### 11.3 Modelo propio

- No expone interfaces RPC públicas.
- Solo accesible vía backend autenticado.
- Logs anonimizados (no se almacena PII en los prompts).

---

## 12. Configuración y secretos

| Variable | Origen | Uso |
|---|---|---|
| `SECRET_KEY` | Aleatorio 48 bytes | Firmar JWT |
| `DATABASE_URL` | Compose / local | Conexión BD (PostgreSQL / SQLite) |
| `MODEL_ENABLED` | Config | Activar modelo propio local |
| `MODEL_CHECKPOINT_PATH` | Config | Ruta del checkpoint entrenado |
| `MODEL_TOKENIZER_PATH` | Config | Ruta del tokenizer propio |
| `MODEL_DEVICE` | Config | auto / cuda / cpu |

El sistema opera de forma **100% autónoma y offline**: el modelo propio
sirve todas las respuestas sin requerir servicios externos en tiempo de ejecución.

---

## 13. Resumen de la infraestructura V2

La infraestructura del sistema V2 está compuesta por:

- 4 superficies de cliente (web, desktop, MCP, CLI).
- 1 backend monolito modular FastAPI.
- 1 base de datos relacional PostgreSQL.
- 1 vector store para RAG.
- 1 modelo propio entrenado desde cero (V1 ya disponible, V2 en
 entrenamiento).
- 6 reward models propios.
- 6 APIs externas auxiliares (solo para dataset).
- 1 sistema de auto-evaluación multi-criterio.

Toda esta infraestructura se puede desplegar **en un solo VPS modesto
(4 vCPU, 8 GB RAM, 50 GB disco)** una vez cuantizado el modelo. El
costo de operación mensual es < 10 USD.
