# MCP Server — Explicador Python IA

Servidor MCP (Model Context Protocol) propio que expone tools del
sistema al LLM: leer/escribir archivos, listar directorios, buscar,
ejecutar Python sandboxed.

## Cómo correrlo

```powershell
cd C:\Users\tanyi\OneDrive\Escritorio\sistema-explicador-python-ia
python -m mcp_server
```

Espera mensajes JSON-RPC por **stdin** y responde por **stdout**. Los
logs salen por **stderr** (no contamina el protocolo).

## Cómo probarlo a mano

```powershell
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05"}}' | python -m mcp_server
```

Debería responder:

```json
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2024-11-05","capabilities":{"tools":{"listChanged":false}},"serverInfo":{"name":"explicador-python-ia","version":"0.1.0"}}}
```

## Tools expuestas

| Tool | Permiso requerido |
|---|---|
| `leer_archivo` | ruta en `directorios_permitidos` |
| `listar_directorio` | ruta en `directorios_permitidos` |
| `buscar_en_archivos` | ruta en `directorios_permitidos` |
| `escribir_archivo` | `modo_escribir` ≠ `bloquear` + ruta permitida |
| `ejecutar_python` | `modo_ejecutar` ≠ `bloquear`, sandbox aislado |

## Configuración

Se guarda en `~/.explicador/mcp.json`:

```json
{
  "directorios_permitidos": ["C:/Users/tanyi/Proyectos"],
  "tools_habilitadas": ["leer_archivo", "listar_directorio", "buscar_en_archivos"],
  "modo_escribir": "bloquear",
  "modo_ejecutar": "bloquear",
  "max_bytes_lectura": 262144,
  "timeout_ejecucion_segundos": 10
}
```

Por defecto solo lectura y sin directorios permitidos — **el usuario
tiene que opt-in explícitamente**.

## Arquitectura

- `server.py` — loop JSON-RPC stdio + dispatcher de métodos
- `tools.py` — implementación de las 5 tools + catálogo
- `sandbox.py` — ejecutor de Python con subprocess + timeout
- `permisos.py` — whitelist + persistencia config
- `__main__.py` — entry point CLI

~600 líneas de Python, sin dependencias externas.
Ver [`docs/MCP_PLAN.md`](../docs/MCP_PLAN.md) para diseño completo.
