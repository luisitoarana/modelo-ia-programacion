# Agente con Tool Calling — Arquitectura ReAct

> Documento técnico del proyecto. Describe cómo el sistema pasa de "chat
> que solo responde texto" a **agente que decide y actúa**.

---

## 1. ¿Qué es un agente?

Un **agente LLM** es un modelo de lenguaje que:
1. **Razona** sobre un problema
2. **Decide** qué herramienta usar (de un catálogo)
3. **Observa** el resultado
4. **Itera** hasta dar una respuesta final

Es la diferencia entre **ChatGPT clásico** (solo texto) y
**Claude/Cursor moderno** (puede leer archivos, ejecutar código, etc.).

---

## 2. El patrón ReAct (Reasoning + Acting)

**Paper**: Yao et al., "ReAct: Synergizing Reasoning and Acting in Language Models", 2023.

Ciclo en cada turno:

```
USUARIO: "Lee main.py y dime qué hace"

ITER 1
 ASISTENTE razona: "Necesito ver el archivo"
 ASISTENTE actúa: <tool_call>{"tool": "leer_archivo", "args": {"ruta": "main.py"}}</tool_call>
 SISTEMA invoca tool → observación:
 "def saludar(nombre): print(f'Hola {nombre}')"

ITER 2
 ASISTENTE razona: "Ya tengo el contenido, voy a explicar"
 ASISTENTE responde:
 "El archivo define una función saludar() que..."
 (sin tool_call → fin del ciclo)
```

---

## 3. Diseño en este proyecto

### 3.1 Componentes

```
┌──────────────────────────────────────────────────────────────┐
│ POST /api/v1/agente/consultar │
│ Body: {pregunta, proveedor, max_iteraciones, historial} │
└──────────────────────────────┬───────────────────────────────┘
 ▼
 ┌────────────────────────────────────────┐
 │ AgenteOrquestador │
 │ (backend/app/services/agent_service) │
 └─────┬──────────────────────┬──────────┘
 │ │
 usa LLM │ │ usa MCP
 ▼ ▼
 ┌──────────────────┐ ┌──────────────────────┐
 │ ProveedorIA │ │ ClienteMcp │
 │ (Gemini/DeepSeek)│ │ (subprocess MCP) │
 └──────────────────┘ └──────────────────────┘
 │
 ▼
 ┌──────────────────────┐
 │ mcp_server (stdio) │
 │ - leer_archivo │
 │ - listar_directorio │
 │ - ejecutar_python │
 │ - buscar_en_archivos │
 │ - escribir_archivo │
 └──────────────────────┘
```

### 3.2 Formato del tool call

El LLM responde con un bloque delimitado:

```
<tool_call>
{"tool": "leer_archivo", "args": {"ruta": "main.py"}}
</tool_call>
```

**Por qué este formato y no "function calling" propietario:**

| Enfoque | Pros | Contras |
|---|---|---|
| Function calling de Gemini/OpenAI | Estructurado, garantizado por el SDK | Lock-in con un proveedor |
| **`<tool_call>` en texto** (el nuestro) | Funciona con CUALQUIER LLM que escriba JSON | El LLM tiene que aprender el formato |

Como nuestro objetivo es que **el modelo PROPIO** (futuro) también
pueda actuar como agente, elegimos el segundo enfoque. Cualquier LLM
de tamaño razonable aprende a producir esa estructura con pocos
ejemplos en el prompt sistema.

### 3.3 El parser

`extraer_tool_call(texto)` busca con 2 regex:
- `<tool_call>...</tool_call>` (formato preferido)
- ` ```json... ``` ` (fallback común que muchos LLMs usan por defecto)

Si el JSON dentro es inválido, se trata como respuesta final (el LLM
quizá quiso decir algo con llaves). Esto es **robusto** ante salidas
imperfectas.

### 3.4 Loop con límite

`max_iteraciones` (default 6, max 15) evita bucles infinitos donde el
modelo se queda llamando tools sin converger. Si lo alcanza, se devuelve
un resumen de lo encontrado.

---

## 4. Anatomía de una llamada

```python
POST /api/v1/agente/consultar
{
 "pregunta": "Lee main.py de C:/proyecto y dime qué hace",
 "proveedor": "gemini",
 "max_iteraciones": 6,
 "historial": []
}
```

### Respuesta:

```json
{
 "respuesta_final": "El archivo define una función saludar() que...",
 "pasos": [
 {
 "iteracion": 1,
 "razonamiento": "Voy a leer el archivo para entender qué hace.",
 "tool": "leer_archivo",
 "args": {"ruta": "C:/proyecto/main.py"},
 "observacion": "def saludar(nombre):\n print(f'Hola {nombre}')",
 "es_error": false
 },
 {
 "iteracion": 2,
 "razonamiento": "El archivo define una función saludar()...",
 "tool": null,
 "args": {},
 "observacion": null,
 "es_error": false
 }
 ],
 "tools_usadas": ["leer_archivo"],
 "n_iteraciones": 2,
 "tokens_totales": 850,
 "razon_fin": "respuesta_final"
}
```

El frontend puede mostrar **cada paso** mientras el agente piensa
("⚙️ leyendo archivo main.py..."), tipo Claude Desktop.

---

## 5. Prompt sistema (catálogo de tools)

Generado dinámicamente desde MCP `tools/list`. Para cada tool incluye:

- Nombre
- Descripción (que ve el LLM)
- JSON schema de argumentos
- Instrucciones de formato

Cuando el MCP server expone una tool nueva, el agente **automáticamente**
la conoce — sin re-deploy del backend.

---

## 6. Manejo de errores

| Caso | Comportamiento |
|---|---|
| Tool inexistente | Error: "Tool no encontrada"; LLM lo ve como observación; suele autocorregirse |
| Args inválidos | Error de la tool; LLM ve `[error tool]...` |
| Tool autorizada pero falla | Igual: error como observación |
| Tool no autorizada (permisos) | "Ruta no autorizada" — LLM aprende a no insistir |
| Max iteraciones | Devuelve resumen con `razon_fin: "max_iters"` |
| Error del proveedor LLM | `razon_fin: "error"` con mensaje claro |

---

## 7. Costo y latencia

Por consulta agentica típica:

| Métrica | Sin agente | Con agente (3 tools) |
|---|---|---|
| Llamadas al LLM | 1 | 3-4 |
| Tokens (entrada) | 800 | ~3,500 (contexto crece) |
| Tokens (salida) | 600 | ~1,200 (cada iter genera) |
| Latencia | ~2s | ~6-10s |
| Costo Gemini Flash | ~$0.0008 | ~$0.003 |

El usuario lo nota porque la respuesta tarda más, pero la calidad y
**utilidad** de la respuesta saltan a otro nivel.

---

## 8. Permisos: el agente respeta el MCP

Las herramientas se ejecutan a través del `mcp_client`, que a su vez
respeta los **permisos del MCP server** (`~/.explicador/mcp.json`):

- `directorios_permitidos`: el LLM puede pedir leer cualquier ruta,
 pero el MCP server rechaza las no autorizadas y devuelve error.
- `modo_escribir`: incluso si el LLM intenta `escribir_archivo`, si
 está en `bloquear` el server lo rechaza.
- `modo_ejecutar`: idem para `ejecutar_python`.

**El agente nunca puede romper el sandbox de seguridad** del MCP.

---

## 9. Cuándo usar el agente vs el chat clásico

| Usa `/chat/enviar` cuando... | Usa `/agente/consultar` cuando... |
|---|---|
| Pregunta conceptual general | El usuario menciona archivos concretos |
| Explicación de un código pegado en el mensaje | "Lee X y..." / "Ejecuta Y y..." |
| Conversación libre | Tareas que requieren MÚLTIPLES pasos |
| Latencia importa más que profundidad | Profundidad importa más que latencia |

El frontend puede detectar heurísticamente cuándo activar agente
(palabras clave: "lee", "ejecuta", "abre", "busca en") o exponer un
toggle "🤖 Modo agente" al usuario.

---

## 10. Próximos pasos

- **Self-reflection**: una iteración extra donde el LLM critica su
 propia respuesta y la mejora (+15% accuracy según paper Reflexion).
- **Streaming de pasos**: el cliente recibe cada paso vía SSE
 mientras el agente piensa (no espera al final).
- **Memoria por sesión**: el agente recuerda qué tools ya usó en
 esta conversación para no repetir.
- **Plan-and-execute**: para tareas grandes, un planner genera la
 lista de pasos y un executor los ejecuta. Útil para "crea una API
 REST con FastAPI".

---

## 11. Referencias

```bibtex
@inproceedings{yao2023react,
 title={ReAct: Synergizing Reasoning and Acting in Language Models},
 author={Yao, Shunyu et al.}, year={2023}, booktitle={ICLR}
}

@article{shinn2023reflexion,
 title={Reflexion: Language Agents with Verbal Reinforcement Learning},
 author={Shinn, Noah et al.}, year={2023}, journal={NeurIPS}
}

@misc{mcp2024,
 title={Model Context Protocol},
 author={Anthropic}, year={2024},
 howpublished={\url{https://modelcontextprotocol.io/}}
}
```
