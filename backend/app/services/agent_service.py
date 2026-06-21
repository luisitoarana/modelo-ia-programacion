"""Servicio Agente — convierte el chat en un AGENTE con tool calling.

El LLM, en lugar de solo responder texto, puede DECIDIR usar tools
del MCP server (leer archivos, listar directorios, ejecutar Python,
buscar en archivos, etc.). El backend interpreta esas decisiones,
invoca las tools y le devuelve los resultados al LLM hasta que produce
una respuesta final.

═══════════════════════════════════════════════════════════════════
ReAct loop (Reasoning + Acting)
═══════════════════════════════════════════════════════════════════

Ciclo por turno del usuario:

    1. Prompt sistema lista las tools disponibles con sus JSON schemas.
    2. LLM responde con:
         - Razonamiento en texto, Y/O
         - Una "tool call" en formato JSON.
    3. Si hay tool call:
            a. Backend parsea {"tool": ..., "args": ...}
            b. Backend invoca la tool via MCP client.
            c. Backend devuelve el resultado al LLM como observación.
            d. Volver a 2 (max N iteraciones para evitar bucles infinitos).
    4. Si no hay tool call → eso es la respuesta final.

═══════════════════════════════════════════════════════════════════
Formato del tool call que el LLM debe usar
═══════════════════════════════════════════════════════════════════

El LLM responde con UN bloque JSON delimitado, así:

    <tool_call>
    {"tool": "leer_archivo", "args": {"ruta": "C:/proyecto/main.py"}}
    </tool_call>

Y después del bloque puede seguir razonando o terminar. Si no incluye
bloque, su respuesta es la final.

═══════════════════════════════════════════════════════════════════
Por qué este diseño
═══════════════════════════════════════════════════════════════════

- Funciona con CUALQUIER LLM que sepa escribir JSON (Gemini, DeepSeek,
  modelos open source, nuestro modelo propio futuro).
- No depende del "function calling" propietario de cada proveedor.
- Es debuggable: el bloque <tool_call> queda en el log.
- Compatible con streaming (parseo incremental).

Ver `docs/AGENTE.md` para el plan completo.
"""

from __future__ import annotations

import json
import logging
import re
from dataclasses import dataclass, field
from typing import Any

from app.services.ai_provider import ProveedorIA, ProveedorIAError
from app.services.mcp_client import ClienteMcp, McpTool, obtener_cliente_mcp


log = logging.getLogger(__name__)


# ════════════════════════════════════════════════════════════════════
# DTOs
# ════════════════════════════════════════════════════════════════════

@dataclass
class PasoAgente:
    """Un paso del ciclo: pensamiento del LLM + tool call + observación."""
    iteracion: int
    razonamiento: str                  # texto antes/después del tool_call
    tool: str | None = None            # nombre de la tool (si llamó alguna)
    args: dict[str, Any] = field(default_factory=dict)
    observacion: str | None = None     # resultado de la tool
    es_error: bool = False


@dataclass
class ResultadoAgente:
    """Lo que devuelve el orquestador al final."""
    respuesta_final: str
    pasos: list[PasoAgente]
    tools_usadas: list[str]
    n_iteraciones: int
    tokens_totales: int = 0
    razon_fin: str = "respuesta_final"   # "respuesta_final" | "max_iters" | "error"


# ════════════════════════════════════════════════════════════════════
# Parser de tool_call
# ════════════════════════════════════════════════════════════════════

# Acepta varios delimitadores comunes para ser tolerante con el LLM:
#   <tool_call>{...}</tool_call>
#   ```tool_call\n{...}\n```
#   ```json\n{"tool":"...","args":{...}}\n```
_PATRONES_TOOLCALL = [
    re.compile(r"<tool_call>\s*(\{.*?\})\s*</tool_call>", re.DOTALL),
    re.compile(r"```(?:tool_call|json)\s*(\{.*?\})\s*```", re.DOTALL),
]


def extraer_tool_call(texto: str) -> tuple[dict | None, str]:
    """Extrae el primer bloque tool_call del texto y devuelve también
    el texto sin el bloque (la "razón" del modelo).

    Returns:
        (tool_call_dict, texto_sin_bloque)
        tool_call_dict = None si no hay tool call válida.
    """
    for patron in _PATRONES_TOOLCALL:
        m = patron.search(texto)
        if not m:
            continue
        bruto = m.group(1).strip()
        try:
            obj = json.loads(bruto)
        except json.JSONDecodeError:
            # Si el LLM puso JSON inválido, tratamos el texto como respuesta
            # final (no es tool call).
            continue
        if not isinstance(obj, dict):
            continue
        # Validar shape mínimo
        if "tool" not in obj:
            continue
        # Texto sin el bloque
        sin_bloque = texto.replace(m.group(0), "").strip()
        return obj, sin_bloque
    return None, texto.strip()


# ════════════════════════════════════════════════════════════════════
# Construcción del prompt sistema con catálogo de tools
# ════════════════════════════════════════════════════════════════════

_PROMPT_BASE_AGENTE = """Eres un asistente educativo de Python con
ACCESO A HERRAMIENTAS. Puedes razonar paso a paso, leer archivos,
ejecutar código, buscar texto y más.

═══════════════════════════════════════════════════════════════
CÓMO USAR LAS HERRAMIENTAS
═══════════════════════════════════════════════════════════════
Cuando necesites usar una herramienta, responde EXACTAMENTE así:

<tool_call>
{{"tool": "nombre_de_la_tool", "args": {{"clave": "valor"}}}}
</tool_call>

Después de cada <tool_call>, el sistema ejecutará la herramienta y te
mostrará el resultado en un mensaje "Observación:". Luego continuarás
hasta que tengas la respuesta completa para el estudiante.

REGLAS IMPORTANTES:
  • Si NO necesitas herramientas, responde DIRECTAMENTE sin <tool_call>.
  • Solo UN <tool_call> por mensaje. Encadena observaciones secuencialmente.
  • Cuando tengas la respuesta final, NO incluyas <tool_call> — solo el texto.

═══════════════════════════════════════════════════════════════
HERRAMIENTAS DISPONIBLES
═══════════════════════════════════════════════════════════════
{tools_descripcion}

═══════════════════════════════════════════════════════════════
ESTILO DE RESPUESTA
═══════════════════════════════════════════════════════════════
- Tono pedagógico, claro y cercano.
- Estructura: qué hace / por qué / ejemplo / ejercicio breve.
- En español.
"""


def construir_prompt_sistema_agente(tools: list[McpTool]) -> str:
    """Construye el prompt sistema describiendo las tools al LLM."""
    if not tools:
        descripciones = "(Sin herramientas disponibles)"
    else:
        bloques = []
        for t in tools:
            schema_json = json.dumps(t.input_schema, ensure_ascii=False, indent=2)
            bloques.append(
                f"### `{t.name}`\n"
                f"{t.description}\n\n"
                f"Schema de argumentos:\n```json\n{schema_json}\n```\n"
            )
        descripciones = "\n".join(bloques)
    return _PROMPT_BASE_AGENTE.format(tools_descripcion=descripciones)


# ════════════════════════════════════════════════════════════════════
# Orquestador del agente
# ════════════════════════════════════════════════════════════════════

class AgenteOrquestador:
    """Ejecuta el ciclo ReAct usando un proveedor IA + cliente MCP."""

    def __init__(
        self,
        proveedor: ProveedorIA,
        cliente_mcp: ClienteMcp,
        *,
        max_iteraciones: int = 6,
        max_tokens_por_paso: int = 1024,
    ) -> None:
        self.proveedor = proveedor
        self.cliente = cliente_mcp
        self.max_iteraciones = max_iteraciones
        self.max_tokens_por_paso = max_tokens_por_paso

    async def responder(
        self,
        pregunta_usuario: str,
        historial: list[dict] | None = None,
    ) -> ResultadoAgente:
        """Ejecuta el loop ReAct y devuelve la respuesta final + traza."""
        # 1. Descubrir tools disponibles
        try:
            tools = await self.cliente.listar_tools()
        except Exception as e:
            log.warning(f"No se pudieron listar tools MCP: {e}")
            tools = []

        sistema = construir_prompt_sistema_agente(tools)

        # 2. Construir el "usuario" inicial = pregunta + historial opcional
        usuario_acumulado = ""
        if historial:
            for m in historial[-6:]:  # últimos 6 mensajes de contexto
                rol = m.get("rol", "usuario")
                cont = m.get("contenido", "")
                usuario_acumulado += f"{rol.upper()}: {cont}\n\n"
        usuario_acumulado += f"USUARIO: {pregunta_usuario}\n\nASISTENTE:"

        pasos: list[PasoAgente] = []
        tools_usadas: list[str] = []
        tokens_totales = 0

        # 3. Loop ReAct
        for it in range(1, self.max_iteraciones + 1):
            try:
                resultado_llm = await self.proveedor.generar(
                    sistema=sistema,
                    usuario=usuario_acumulado,
                    temperatura=0.4,    # más determinista para tool use
                    max_tokens=self.max_tokens_por_paso,
                    json_mode=False,
                )
            except ProveedorIAError as e:
                log.error(f"Error LLM en iter {it}: {e}")
                pasos.append(PasoAgente(
                    iteracion=it, razonamiento="",
                    observacion=f"[error del modelo: {e}]",
                    es_error=True,
                ))
                return ResultadoAgente(
                    respuesta_final=(
                        "Disculpa, no pude completar la consulta por un error "
                        f"del modelo: {e}"
                    ),
                    pasos=pasos,
                    tools_usadas=tools_usadas,
                    n_iteraciones=it,
                    tokens_totales=tokens_totales,
                    razon_fin="error",
                )

            tokens_totales += getattr(resultado_llm, "tokens_totales", 0)
            texto_llm = (resultado_llm.texto or "").strip()
            tool_call, razonamiento = extraer_tool_call(texto_llm)

            # ─── Caso A: no hay tool call → respuesta final ───
            if tool_call is None:
                # El LLM terminó de razonar.
                pasos.append(PasoAgente(
                    iteracion=it, razonamiento=razonamiento,
                ))
                return ResultadoAgente(
                    respuesta_final=razonamiento or "(sin respuesta)",
                    pasos=pasos,
                    tools_usadas=tools_usadas,
                    n_iteraciones=it,
                    tokens_totales=tokens_totales,
                    razon_fin="respuesta_final",
                )

            # ─── Caso B: hay tool call → invocar y observar ───
            nombre = tool_call.get("tool")
            args = tool_call.get("args") or {}
            paso = PasoAgente(
                iteracion=it,
                razonamiento=razonamiento,
                tool=nombre,
                args=args,
            )

            try:
                resultado_tool = await self.cliente.invocar_tool(nombre, args)
                if resultado_tool.es_error:
                    paso.observacion = f"[error tool] {resultado_tool.contenido}"
                    paso.es_error = True
                else:
                    paso.observacion = resultado_tool.contenido
                tools_usadas.append(nombre)
            except Exception as e:
                paso.observacion = f"[error invocando tool: {e}]"
                paso.es_error = True

            pasos.append(paso)

            # Construir el siguiente turno: tomar lo que el LLM dijo + observación
            usuario_acumulado += f"\n{texto_llm}\n\n"
            usuario_acumulado += (
                f"OBSERVACIÓN ({nombre}):\n"
                f"{paso.observacion}\n\n"
                f"ASISTENTE:"
            )

        # ─── Salida por max_iteraciones ───
        respuesta_final = (
            "He explorado varios caminos pero no llegué a una respuesta "
            "definitiva en el límite de pasos. Esto es lo que encontré:\n\n"
        )
        for p in pasos:
            if p.tool:
                respuesta_final += f"- Usé `{p.tool}` → "
                respuesta_final += (
                    f"{p.observacion[:200]}...\n" if p.observacion and len(p.observacion) > 200
                    else f"{p.observacion or 'sin observación'}\n"
                )
        return ResultadoAgente(
            respuesta_final=respuesta_final,
            pasos=pasos,
            tools_usadas=tools_usadas,
            n_iteraciones=self.max_iteraciones,
            tokens_totales=tokens_totales,
            razon_fin="max_iters",
        )


# ════════════════════════════════════════════════════════════════════
# Helper público
# ════════════════════════════════════════════════════════════════════

async def responder_como_agente(
    pregunta: str,
    proveedor: ProveedorIA,
    *,
    historial: list[dict] | None = None,
    max_iteraciones: int = 6,
) -> ResultadoAgente:
    """Helper de alto nivel para usar el agente sin armar el orquestador.

    Ejemplo:
        from app.services.ai_provider import obtener_proveedor
        from app.services.agent_service import responder_como_agente

        prov = obtener_proveedor("gemini")
        resultado = await responder_como_agente(
            "Lee main.py y dime qué hace", prov,
        )
        print(resultado.respuesta_final)
        for paso in resultado.pasos:
            print(f"  iter {paso.iteracion}: tool={paso.tool}")
    """
    cliente = await obtener_cliente_mcp()
    orq = AgenteOrquestador(
        proveedor, cliente, max_iteraciones=max_iteraciones,
    )
    return await orq.responder(pregunta, historial=historial)
