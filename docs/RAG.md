# Sistema RAG — Cómo la IA "sabe" de tus documentos

## Qué problema resuelve

Un modelo de lenguaje solo "sabe" lo que estaba en sus datos de entrenamiento.
Si le preguntas algo sobre **tu** documentación, **tu** código, un libro
nuevo o las notas que subiste ayer, **no puede saberlo** — y si responde,
está inventando. Eso se llama **alucinación**.

El sistema RAG (Retrieval-Augmented Generation) elimina la alucinación:

1. Subes documentos a un **índice vectorial**.
2. Cuando preguntas algo, el sistema **busca los fragmentos relevantes**.
3. Esos fragmentos se inyectan en el prompt **antes** de que el LLM responda.
4. El LLM responde citando esas fuentes, no de memoria.

Así es como funcionan ChatGPT con "Custom GPTs", Claude Projects, Gemini Gems,
NotebookLM y todas las IAs que "saben" de tus archivos.

## Cómo funciona en este sistema

```
 Pregunta del usuario
 │
 ▼
 ┌────────────────────────────┐
 │ rag_service.debe_recuperar │ ¿amerita buscar?
 └────────────┬───────────────┘
 │ sí
 ▼
 ┌────────────────────────────┐
 │ Embedder (all-MiniLM-L6) │ pregunta → vector 384-dim
 └────────────┬───────────────┘
 ▼
 ┌────────────────────────────┐
 │ VectorStore.buscar (k=4) │ producto punto vs todos los chunks
 └────────────┬───────────────┘
 ▼
 ┌────────────────────────────┐
 │ recuperar_y_formatear │ arma bloque "FUENTES:" para el prompt
 └────────────┬───────────────┘
 ▼
 ┌────────────────────────────┐
 │ LLM (modelo propio o API) │ responde citando fuentes
 └────────────────────────────┘
```

## Backend de embeddings

- **Default**: `sentence-transformers/all-MiniLM-L6-v2` (384 dims, 80 MB,
 multilingüe razonable, SOTA para retrieval).
- **Fallback**: hashing trick + TF-IDF puro Python, sin descargar nada. Menor
 calidad pero el sistema sigue funcionando offline.

El backend se elige automáticamente al primer uso.

## Endpoints REST

| Método | Ruta | Descripción |
|--------|------|-------------|
| GET | `/api/v1/rag/estado` | Disponibilidad + n_docs + backend |
| POST | `/api/v1/rag/subir` | Subir documento (JSON con texto) |
| POST | `/api/v1/rag/subir-archivo` | Subir como multipart (.txt/.md/.py)|
| GET | `/api/v1/rag/documentos` | Listar todos los documentos |
| DELETE | `/api/v1/rag/documentos/{id}` | Eliminar uno |
| POST | `/api/v1/rag/buscar` | Buscar chunks (debug) |

## Indexar tu corpus de un golpe

```powershell
# Toda la documentación del proyecto:
python -m ml.rag.indexar --carpeta docs --indice data/rag_index

# Solo.md y.py:
python -m ml.rag.indexar --carpeta. --extensiones.md.py
```

Recorre la carpeta recursivamente, ignora `.git/`, `.venv/`, `node_modules/`,
`__pycache__/`, `runs/`, `data/`.

## Integración automática en el chat

Cuando el usuario manda un mensaje, `chat_service`:

1. Llama a `rag_service.debe_recuperar(texto)`. Heurística:
 - Hay documentos indexados.
 - Y el mensaje tiene >6 palabras o usa frases como "según mis notas", "en el
 archivo", "qué dice el documento", "busca en".
2. Si sí: busca los **4 chunks más similares** y los inyecta como bloque
 `FUENTES DEL USUARIO`.
3. El prompt al LLM instruye: *"Si usas información de las FUENTES, cita el
 título entre paréntesis"*.
4. La respuesta incluye `meta.fuentes_rag` con los doc_ids y scores —
 la UI puede mostrarlos como chips clickables.

## Persistencia

```
data/rag_index/
 documentos.jsonl # metadatos
 chunks.jsonl # texto de cada chunk
 vectores.npy # matriz NumPy float32
 config.json # dim, backend, fecha
```

Re-indexa solo si cambias de backend (la dim cambia).

## Cuándo NO usar RAG

- Preguntas conceptuales generales ("¿qué es una clase en Python?"). Para eso
 está el conocimiento entrenado del LLM.
- Información del momento (versión de hoy de un paquete). Para eso está
 `web_search`.
- Acciones sobre un archivo concreto ("revisa este archivo"). Para eso están
 las **tools MCP** (`leer_archivo`, `ejecutar_python`).

Las tres capas se complementan: RAG → tu corpus; Web → mundo actual; MCP →
acciones concretas.
