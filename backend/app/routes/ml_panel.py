"""Panel de ML (solo lectura): experimentos y estado del modelo propio.

Permite que el frontend muestre la curva de pérdida, los hiperparámetros y el
estado del LLM entrenado, sin lanzar entrenamientos desde la web (el
entrenamiento se ejecuta con `python -m ml.train`, donde está la GPU).
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException

from app.core.security import requerir_rol
from app.models.usuario import RolUsuario, Usuario
from app.services import model_inference_service as modelo


router = APIRouter()

_RAIZ = Path(__file__).resolve().parents[3]
_DIR_EXPERIMENTOS = _RAIZ / "training" / "experiments"

_SOLO_INVESTIGADOR = requerir_rol(RolUsuario.INVESTIGADOR, RolUsuario.ADMINISTRADOR)


def _leer_metrics(ruta: Path) -> list[dict]:
    if not ruta.exists():
        return []
    registros: list[dict] = []
    for linea in ruta.read_text(encoding="utf-8").splitlines():
        linea = linea.strip()
        if not linea:
            continue
        try:
            registros.append(json.loads(linea))
        except json.JSONDecodeError:
            continue
    return registros


@router.get("/estado-modelo", summary="Estado del LLM propio")
async def estado_modelo(
    _u: Annotated[Usuario, Depends(_SOLO_INVESTIGADOR)],
) -> dict[str, object]:
    return modelo.estado_modelo()


@router.get("/experimentos", summary="Listar experimentos de entrenamiento")
async def listar_experimentos(
    _u: Annotated[Usuario, Depends(_SOLO_INVESTIGADOR)],
) -> dict[str, object]:
    if not _DIR_EXPERIMENTOS.exists():
        return {"experimentos": []}
    salida = []
    for carpeta in sorted(_DIR_EXPERIMENTOS.iterdir()):
        if not carpeta.is_dir():
            continue
        cfg_path = carpeta / "config.json"
        metrics = _leer_metrics(carpeta / "metrics.jsonl")
        config = {}
        if cfg_path.exists():
            try:
                config = json.loads(cfg_path.read_text(encoding="utf-8"))
            except json.JSONDecodeError:
                config = {}
        ultimo = metrics[-1] if metrics else {}
        salida.append(
            {
                "nombre": carpeta.name,
                "num_parametros": config.get("num_parametros"),
                "device": config.get("device"),
                "iteraciones": len(metrics),
                "ultimo_val_loss": ultimo.get("val_loss"),
                "ultimo_train_loss": ultimo.get("train_loss"),
            }
        )
    return {"experimentos": salida}


@router.get("/experimentos/{nombre}", summary="Detalle y métricas de un experimento")
async def detalle_experimento(
    nombre: str,
    _u: Annotated[Usuario, Depends(_SOLO_INVESTIGADOR)],
) -> dict[str, object]:
    seguro = "".join(c for c in nombre if c.isalnum() or c in ("_", "-"))
    carpeta = _DIR_EXPERIMENTOS / seguro
    if not carpeta.is_dir():
        raise HTTPException(status_code=404, detail="Experimento no encontrado.")
    config = {}
    cfg_path = carpeta / "config.json"
    if cfg_path.exists():
        try:
            config = json.loads(cfg_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            config = {}
    return {
        "nombre": seguro,
        "config": config,
        "metrics": _leer_metrics(carpeta / "metrics.jsonl"),
    }
