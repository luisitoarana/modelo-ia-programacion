# Plan MCP — Model Context Protocol

> El sistema expone y consume herramientas vía MCP, el protocolo abierto
> de Anthropic. Esto permite que **el asistente actúe** sobre la PC del
> usuario (filesystem, terminal) y que **otras herramientas externas**
> (Unity, Blender, Notion) puedan integrarse.

---

## 1. Qué es MCP (en una frase)

> Un protocolo cliente-servidor sobre **JSON-RPC** donde un servidor
> expone "tools" (funciones), "resources" (lectura) y "prompts"
> (templates) que un cliente LLM puede invocar de forma estructurada.

Equivalencia simple:
- **MCP server** = un proceso que dice "yo sé hacer X cosas"
- **MCP client** = la app que las usa (nuestro chat)
- **Tool** = una función que el LLM puede llamar (ej. `leer_archivo`)
- **Resource** = un dato que el LLM puede leer (ej. contenido de un
 archivo o tabla de BD)

---

## 2. Arquitectura propuesta

```
┌────────────────────────────────────────────┐
│ App Desktop (Flutter) │
│ ┌───────────────────────────────────────┐ │
│ │ MCP Client (Dart) │ │
│ │ - Se conecta a servidores MCP │ │
│ │ - Descubre tools │ │
│ │ - Invoca tools cuando el LLM lo pide │ │
│ └───────────────────────────────────────┘ │
└──────────────────┬─────────────────────────┘
 │ JSON-RPC over stdio / HTTP-SSE
 v
┌──────────────────────────────────────────────────────────┐
│ MCP Servers (independientes) │
│ │
│ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ │
│ │ Filesystem │ │ Python REPL │ │ Web search │ │
│ │ - leer │ │ - ejecutar │ │ - buscar │ │
│ │ - escribir │ │ - kernel │ │ - resumir │ │
│ │ - listar │ │ persistente│ │ │ │
│ └──────────────┘ └──────────────┘ └──────────────┘ │
│ │
│ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ │
│ │ GitHub │ │ Unity │ │ Notion │ │
│ │ (oficial) │ │ (terceros) │ │ (oficial) │ │
│ └──────────────┘ └──────────────┘ └──────────────┘ │
└──────────────────────────────────────────────────────────┘
```

---

## 3. Tools propias (servidor MCP nuestro)

Empaquetar en `mcp_server/` con 3 tools mínimas:

### 3.1 `leer_archivo`
```json
{
 "name": "leer_archivo",
 "description": "Lee el contenido de un archivo del disco del usuario",
 "inputSchema": {
 "type": "object",
 "properties": {
 "ruta": { "type": "string", "description": "Ruta absoluta o relativa" }
 },
 "required": ["ruta"]
 }
}
```

### 3.2 `ejecutar_python`
```json
{
 "name": "ejecutar_python",
 "description": "Ejecuta código Python en un sandbox y devuelve stdout/stderr",
 "inputSchema": {
 "type": "object",
 "properties": {
 "codigo": { "type": "string" },
 "timeout_segundos": { "type": "integer", "default": 10 }
 },
 "required": ["codigo"]
 }
}
```

### 3.3 `listar_directorio`
```json
{
 "name": "listar_directorio",
 "description": "Lista archivos y subdirectorios de una ruta",
 "inputSchema": {
 "type": "object",
 "properties": {
 "ruta": { "type": "string" },
 "recursivo": { "type": "boolean", "default": false }
 },
 "required": ["ruta"]
 }
}
```

---

## 4. Cómo el LLM decide qué tool usar

Flujo en cada turno del chat:

```
1. Usuario: "Mira mi script en C:/proyecto/main.py y dime qué hace"
2. Backend recibe + manda al LLM con catálogo de tools disponibles
3. LLM responde con tool_call:
 { "tool": "leer_archivo", "args": {"ruta": "C:/proyecto/main.py"} }
4. Backend invoca MCP -> tool ejecuta -> devuelve contenido
5. Backend manda contenido + pregunta original al LLM otra vez
6. LLM ahora responde con análisis del código
7. Usuario ve la respuesta final
```

Modelos que soportan tool calling: **Gemini ≥ 1.5**, **DeepSeek**,
nuestro modelo propio cuando lo entrenemos con dataset de tool-use
(planeado Fase 4 de hoja de ruta).

---

## 5. Permisos y seguridad

**Crítico**: que el LLM ejecute código en la PC del usuario es
peligroso. Reglas:

| Tool | Riesgo | Mitigación |
|---|---|---|
| `leer_archivo` | Lee secrets si no se restringe | Whitelist de directorios permitidos en Settings |
| `escribir_archivo` | Sobrescribe trabajo | Pedir confirmación visual antes de cada escritura |
| `ejecutar_python` | Puede borrar archivos, hacer requests | Sandbox: timeout, sin red por default, en venv aislado |
| `ejecutar_shell` | Lo mismo + sistémico | **No exponemos** por defecto. Opt-in en Settings → Avanzado |

UI: cuando el LLM intenta usar una tool destructiva, mostrar tarjeta:
> ⚠️ El asistente quiere ejecutar:
> ```python
> os.remove("config.json")
> ```
> **¿Permitir?** [Sí] [No] [No volver a preguntar para `ejecutar_python`]

---

## 6. Cliente MCP en desktop (Dart)

No hay SDK oficial Dart todavía (junio 2025), pero el protocolo es
JSON-RPC simple. Implementación:

```dart
// app-desktop/lib/services/mcp_client.dart
class McpClient {
 final Process _proceso;
 final StreamController<Map<String, dynamic>> _respuestas;
 int _proximoId = 1;

 Future<List<McpTool>> listarTools() async {
 return await _llamar('tools/list', {});
 }

 Future<dynamic> invocarTool(String nombre, Map<String, dynamic> args) async {
 return await _llamar('tools/call', {
 'name': nombre,
 'arguments': args,
 });
 }

 Future<dynamic> _llamar(String metodo, Map<String, dynamic> params) async {
 final id = _proximoId++;
 _proceso.stdin.writeln(jsonEncode({
 'jsonrpc': '2.0', 'id': id, 'method': metodo, 'params': params,
 }));
 //... espera respuesta con id matching
 }
}
```

---

## 7. Servidores externos

Anthropic mantiene un catálogo en
<https://github.com/modelcontextprotocol/servers>. Útiles para nosotros:

- `@modelcontextprotocol/server-filesystem` — más completo que el
 nuestro
- `@modelcontextprotocol/server-github` — leer issues, PRs, código
- `@modelcontextprotocol/server-fetch` — fetch genérico HTTP
- `@modelcontextprotocol/server-postgres` — consultas SQL

Para **Unity** específicamente: no hay MCP oficial. Habría que
construirlo o usar el Editor Scripting API + un puente HTTP.

---

## 8. Implementación por fases

| Fase | Tarea | Estado |
|---|---|---|
| **A** | Servidor MCP propio con 5 tools en `mcp_server/` | ✅ COMPLETO |
| **B** | Cliente MCP en backend (subprocess + handshake + lifecycle) | ✅ COMPLETO |
| **C** | UI de permisos en frontend (Settings → MCP) | ✅ COMPLETO |
| **D** | Cliente MCP en desktop Flutter (para conectar a otros servers) | ○ Próximo turno |
| **E** | LLM puede invocar tools (tool_calling en chat_service) | ○ Próximo turno |
| **F** | Integración con `@modelcontextprotocol/server-filesystem` | ○ Opcional |
| **G** | Bridge Unity vía MCP | ○ Largo plazo |

### Lo que YA está hecho (esta iteración)

**Backend Python `mcp_server/`** (~600 líneas, 0 deps externas):
- Protocolo JSON-RPC 2.0 sobre stdio según spec MCP 2024-11-05
- 5 tools: `leer_archivo`, `listar_directorio`, `escribir_archivo`,
 `buscar_en_archivos`, `ejecutar_python`
- Sandbox para Python (subprocess + timeout + env aislado + tempdir)
- Permisos con whitelist de directorios + modos `bloquear/confirmar/auto`
- Config persistida en `~/.explicador/mcp.json`
- Ejecutar: `python -m mcp_server`

**Cliente MCP en backend** (`backend/app/services/mcp_client.py`):
- Singleton con `obtener_cliente_mcp()`
- Lifecycle: lazy start, auto-restart, cierre limpio en shutdown
- `listar_tools()`, `invocar_tool()`, `ping()` async
- Fix UTF-8 para Windows (`PYTHONIOENCODING=utf-8`)

**Endpoints REST** (`backend/app/routes/mcp.py`):
- `GET /api/v1/mcp/estado` — info completa
- `GET /api/v1/mcp/tools` — lista de tools
- `GET/PUT /api/v1/mcp/permisos` — leer/actualizar permisos
- `POST /api/v1/mcp/invocar` — invocar tool a mano (admin)
- `POST /api/v1/mcp/ping` — ¿vive el server?

**UI en Settings web** (`Configuración → MCP` para admins):
- Estado del server con punto verde/gris
- Lista de tools con toggle individual + descripción del LLM
- Editor de directorios permitidos con add/remove
- 2 selectores: `modo_escribir` y `modo_ejecutar`
- Inputs de límites: max bytes lectura, timeout ejecución
- Auto-save en cada cambio + recarga del cliente

---

## 9. Por qué importa del proyecto

MCP es **un estándar emergente** (anunciado nov 2024 por Anthropic).
Que el proyecto lo implemente:

1. Demuestra que el sistema **no es un proyecto de juguete** sino que
 adopta protocolos modernos
2. Posiciona el trabajo como **vanguardia** vs asistentes legacy
3. Permite integrarse con el ecosistema de tools que va a crecer
 rápido en 2025-2026
4. Genera un capítulo entero del documentación sobre **agentic AI**

---

## 10. Referencias

- Anthropic, **Model Context Protocol Specification**, 2024
- <https://modelcontextprotocol.io/>
- <https://github.com/modelcontextprotocol/specification>
- Servers oficiales:
 <https://github.com/modelcontextprotocol/servers>
- SDKs: TypeScript, Python (sin Dart aún)
