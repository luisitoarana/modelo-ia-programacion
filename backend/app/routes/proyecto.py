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
