"""Servidor MCP (Model Context Protocol) propio del Explicador Python IA.

Implementa el protocolo JSON-RPC 2.0 sobre stdio según la especificación
MCP 2024-11-05. No depende de SDKs externos — el código completo del
protocolo está en este paquete, lo que facilita su documentación en la
tesis.

Tools expuestas:
    - leer_archivo
    - escribir_archivo
    - listar_directorio
    - buscar_en_archivos
    - ejecutar_python  (sandbox con timeout)

Ejecutar como servidor stdio:
    python -m mcp_server

Ver: docs/MCP_PLAN.md
"""

__version__ = "0.1.0"
PROTOCOL_VERSION = "2024-11-05"
