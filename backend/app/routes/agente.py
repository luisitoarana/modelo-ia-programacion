"""Endpoint /agente — chat con tool calling sobre MCP server.

POST /api/v1/agente/consultar
    Body: ConsultarAgenteRequest (pregunta, proveedor, max_iteraciones, historial)
    Returns: ConsultarAgenteRespuesta (respuesta_final + traza de pasos)

Diferencia con /chat/enviar:
    - /chat/enviar       : una sola llamada al LLM, sin tools.
    - /agente/consultar  : N llamadas al LLM con tool calling iterativo.

Ver `docs/AGENTE.md` para arquitectura y el ReAct loop.
"""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, status

from app.core.security import obtener_usuario_actual
from app.models.usuario import Usuario
from app.schemas.agente import (
    ConsultarAgenteRequest,
    ConsultarAgenteRespuesta,
    PasoAgenteOut,
)
from app.services.agent_service import responder_como_agente
from app.services.ai_provider import obtener_proveedor


router = APIRouter()


@router.post(
    "/consultar",
    response_model=ConsultarAgenteRespuesta,
    summary="Consultar al agente con tool calling (ReAct loop)",
)
async def consultar_agente(
    datos: ConsultarAgenteRequest,
    _usuario: Annotated[Usuario, Depends(obtener_usuario_actual)],
) -> ConsultarAgenteRespuesta:
    """Ejecuta el agente: el LLM puede invocar tools del MCP server
    iterativamente hasta producir una respuesta final.

    Cada paso intermedio queda registrado en `pasos` para auditoría
    y para que el frontend pueda mostrar "el modelo está leyendo
    archivo X..." en vivo.
    """
    proveedor = obtener_proveedor(datos.proveedor)
    if not proveedor.esta_configurado:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=(
                f"El proveedor '{proveedor.nombre}' no está configurado. "
                "Añade su API key en el panel de administrador."
            ),
        )

    try:
        resultado = await responder_como_agente(
            datos.pregunta,
            proveedor,
            historial=datos.historial,
            max_iteraciones=datos.max_iteraciones,
        )
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Error en el agente: {exc}",
        ) from exc

    return ConsultarAgenteRespuesta(
        respuesta_final=resultado.respuesta_final,
        pasos=[
            PasoAgenteOut(
                iteracion=p.iteracion,
                razonamiento=p.razonamiento,
                tool=p.tool,
                args=p.args,
                observacion=p.observacion,
                es_error=p.es_error,
            )
            for p in resultado.pasos
        ],
        tools_usadas=resultado.tools_usadas,
        n_iteraciones=resultado.n_iteraciones,
        tokens_totales=resultado.tokens_totales,
        razon_fin=resultado.razon_fin,
    )
