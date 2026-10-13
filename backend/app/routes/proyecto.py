"""Rutas del explorador de proyecto (capacidad de acceso a archivos, segura).

Permite recorrer el proyecto real y leer archivos para luego explicarlos.
Solo lectura, confinado a la raíz del proyecto.
"""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, status

from app.core.security import obtener_usuario_actual
from app.models.usuario import Usuario
from app.services.project_explorer import ExploradorProyecto


router = APIRouter()


def _nodos_a_dict(nodos) -> list[dict]:
    return [
        {
            "nombre": n.nombre,
            "ruta": n.ruta,
            "tipo": n.tipo,
            "tamano": n.tamano,
            "es_texto": n.es_texto,
        }
        for n in nodos
    ]


@router.get("/arbol", summary="Listar carpetas y archivos de una ruta del proyecto")
async def arbol(
    _u: Annotated[Usuario, Depends(obtener_usuario_actual)],
    ruta: str = Query(default="", description="Ruta relativa dentro del proyecto"),
) -> dict[str, object]:
    explorador = ExploradorProyecto()
    try:
        nodos = explorador.listar(ruta)
    except PermissionError as exc:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail=str(exc))
    except (NotADirectoryError, FileNotFoundError) as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc))
    return {"ruta": ruta, "elementos": _nodos_a_dict(nodos)}


@router.get("/archivo", summary="Leer el contenido de un archivo del proyecto")
async def archivo(
    _u: Annotated[Usuario, Depends(obtener_usuario_actual)],
    ruta: str = Query(min_length=1, description="Ruta relativa del archivo"),
) -> dict[str, object]:
    explorador = ExploradorProyecto()
    try:
        return explorador.leer(ruta)
    except PermissionError as exc:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail=str(exc))
    except FileNotFoundError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc))


@router.get("/buscar", summary="Buscar archivos por nombre en el proyecto")
async def buscar(
    _u: Annotated[Usuario, Depends(obtener_usuario_actual)],
    q: str = Query(min_length=1, max_length=120),
) -> dict[str, object]:
    explorador = ExploradorProyecto()
    return {"resultados": _nodos_a_dict(explorador.buscar(q))}


@router.post("/auditoria-ast", summary="Auditar arquitectura completa del proyecto mediante AST")
async def auditoria_ast(
    _u: Annotated[Usuario, Depends(obtener_usuario_actual)],
    con_auditoria_ia: bool = Query(default=True, description="Generar informe de auditoría con IA"),
    proveedor: str = Query(default="auto", description="Proveedor IA"),
) -> dict[str, object]:
    import asyncio
    from app.services.ast_auditor import escanear_proyecto_ast
    from app.services.ai_provider import obtener_proveedor, proveedores_disponibles
    from app.services import motor_pedagogico_service

    datos_ast = escanear_proyecto_ast()
    informe_ia = ""
    motor_usado = "Análisis AST Puro"

    if con_auditoria_ia:
        prompt_sistema = (
            "Eres un Arquitecto de Software Principal y Auditor de Sistemas Python.\n"
            "Analiza el siguiente mapa arquitectónico extraído mediante AST de un proyecto Python real.\n"
            "Genera una auditoría arquitectónica exhaustiva en Markdown estructurada con:\n"
            "1. 🏛️ Diagnóstico Arquitectónico General (Patrón de diseño, responsabilidades y cohesión).\n"
            "2. 🔄 Flujo de Componentes y Modularidad (interacción entre módulos).\n"
            "3. ⚠️ Riesgos Estructurales y Puntos Críticos (análisis de los riesgos estáticos listados).\n"
            "4. 🚀 Recomendaciones de Refactorización y Escalabilidad."
        )
        prompt_usuario = (
            f"Por favor audita la arquitectura completa del proyecto a partir de este mapa AST:\n\n"
            f"{datos_ast['sintesis_arquitectura']}\n\n"
            f"Riesgos estáticos detectados ({datos_ast['total_riesgos']}):\n"
            f"{datos_ast['riesgos'][:20]}"
        )

        prov_str = proveedor.lower().strip()
        # Intentar proveedor en cascada o local
        orden = [prov_str] if prov_str not in ("auto", "propio") else ["groq", "gemini", "deepseek", "openrouter", "openai"]
        disponibles = proveedores_disponibles()

        for p_nombre in orden:
            if p_nombre in disponibles:
                try:
                    p = obtener_proveedor(p_nombre)
                    res = await p.generar(sistema=prompt_sistema, usuario=prompt_usuario, max_tokens=2000, temperatura=0.3)
                    informe_ia = res.texto
                    motor_usado = f"Motor Neuronal ({p_nombre.capitalize()})"
                    break
                except Exception:
                    continue

        if not informe_ia and motor_pedagogico_service.esta_disponible():
            try:
                res_motor = await asyncio.to_thread(
                    motor_pedagogico_service.generar_respuesta,
                    f"{prompt_sistema}\n\n{prompt_usuario}",
                    max_tokens=1400,
                    temperatura=0.3,
                )
                if res_motor:
                    informe_ia = res_motor.texto
                    motor_usado = "Motor Propio Local Offline"
            except Exception:
                pass

        if not informe_ia:
            informe_ia = (
                f"### Resumen de Auditoría AST\n\n"
                f"Se auditaron exitosamente **{datos_ast['total_archivos']} archivos** "
                f"con **{datos_ast['total_lineas']} líneas de código**, identificando "
                f"**{datos_ast['total_clases']} clases**, **{datos_ast['total_funciones']} funciones** "
                f"y **{datos_ast['total_riesgos']} riesgos estáticos**.\n\n"
                f"{datos_ast['sintesis_arquitectura']}"
            )

    return {
        **datos_ast,
        "informe_ia": informe_ia,
        "motor_usado": motor_usado,
    }
