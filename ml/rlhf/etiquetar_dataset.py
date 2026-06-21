"""Etiqueta un dataset de respuestas con los 6 jueces multi-criterio.

Lee un JSONL de respuestas (cada línea con `prompt` y `respuesta`) y
escribe otro JSONL agregando 6 scores 0-10 (SEG/LEG/ESC/ARQ/REN/MAN).

El dataset etiquetado alimenta:
    - DPO multi-objetivo (ml/rlhf/dpo.py extendido)
    - Entrenamiento de los 6 reward models propios

Características:
    - Resume automático: si el archivo de salida existe, continúa donde
      quedó (clave: prompt + hash de respuesta).
    - Concurrencia limitada para no saturar rate limits.
    - Progreso con velocidad real y ETA.
    - Guarda el `detalle` completo de cada juez si se pasa `--con-detalle`.

Uso (típico):
    python -m ml.rlhf.etiquetar_dataset \\
        --entrada datasets/raw/respuestas_modelo.jsonl \\
        --salida datasets/etiquetado/scores_v1.jsonl \\
        --concurrencia 4

Esquema de entrada esperado:
    {"prompt": "...", "respuesta": "..."}
    (campos extra son preservados en la salida)

Esquema de salida:
    {"prompt": "...", "respuesta": "...",
     "scores": {"SEG": 8, "LEG": 7, ...},
     "scores_completos": <bool: True si las 6 dim tienen score>,
     ... resto de campos originales}
"""

from __future__ import annotations

import argparse
import asyncio
import hashlib
import json
import sys
import time
from pathlib import Path
from typing import Any

from ml.data.pool_generadores import Pool
from ml.data.schema import DIMENSIONES_PUNTUACION
from ml.rlhf.jueces import calificar_respuesta


# ════════════════════════════════════════════════════════════════════
# I/O helpers
# ════════════════════════════════════════════════════════════════════

def _leer_jsonl(ruta: Path) -> list[dict[str, Any]]:
    if not ruta.exists():
        return []
    out: list[dict[str, Any]] = []
    for linea in ruta.read_text(encoding="utf-8").splitlines():
        linea = linea.strip()
        if not linea:
            continue
        try:
            out.append(json.loads(linea))
        except json.JSONDecodeError:
            continue
    return out


def _clave(reg: dict[str, Any]) -> str:
    """Hash estable de (prompt, respuesta) para resume."""
    base = (reg.get("prompt", "") + "||" + reg.get("respuesta", ""))
    return hashlib.sha1(base.encode("utf-8")).hexdigest()


def _extraer_prompt_respuesta(reg: dict[str, Any]) -> tuple[str, str] | None:
    """Soporta varios esquemas comunes."""
    prompt = reg.get("prompt") or reg.get("instruccion") or reg.get("instruction") or ""
    respuesta = (
        reg.get("respuesta") or reg.get("salida") or reg.get("response")
        or reg.get("chosen") or ""
    )
    prompt = prompt.strip() if isinstance(prompt, str) else ""
    respuesta = respuesta.strip() if isinstance(respuesta, str) else ""
    if not prompt or not respuesta:
        return None
    return prompt, respuesta


# ════════════════════════════════════════════════════════════════════
# Calificación con concurrencia limitada
# ════════════════════════════════════════════════════════════════════

async def _calificar_uno(
    pool: Pool, sem: asyncio.Semaphore, reg: dict[str, Any],
    *, con_detalle: bool,
) -> dict[str, Any] | None:
    pr = _extraer_prompt_respuesta(reg)
    if pr is None:
        return None
    prompt, respuesta = pr

    async with sem:
        try:
            resultado = await calificar_respuesta(pool, prompt, respuesta)
        except Exception as exc:
            return {
                **reg,
                "scores": {},
                "scores_completos": False,
                "error_etiquetado": str(exc)[:200],
            }

    salida = dict(reg)
    salida["prompt"] = prompt
    salida["respuesta"] = respuesta
    salida["scores"] = resultado["scores"]
    salida["scores_completos"] = (
        set(resultado["scores"].keys()) == set(DIMENSIONES_PUNTUACION)
    )
    if con_detalle:
        salida["scores_detalle"] = resultado["detalle"]
    return salida


# ════════════════════════════════════════════════════════════════════
# Pipeline
# ════════════════════════════════════════════════════════════════════

async def etiquetar(
    entrada: Path,
    salida: Path,
    *,
    concurrencia: int,
    con_detalle: bool,
    limite: int | None,
) -> dict[str, Any]:
    if not entrada.exists():
        raise FileNotFoundError(entrada)

    todos = _leer_jsonl(entrada)
    if limite:
        todos = todos[:limite]
    print(f"[entrada] {entrada}: {len(todos)} registros")

    # Resume: detectar lo ya hecho.
    ya_hecho: set[str] = set()
    if salida.exists():
        existentes = _leer_jsonl(salida)
        ya_hecho = {_clave(r) for r in existentes if r.get("scores_completos")}
        print(f"[resume] {len(existentes)} ya en salida ({len(ya_hecho)} completos)")
    else:
        salida.parent.mkdir(parents=True, exist_ok=True)

    pendientes = [r for r in todos if _clave(r) not in ya_hecho]
    if not pendientes:
        print("[ok] nada pendiente, salida ya está al día.")
        return {"total": len(todos), "nuevos": 0, "completos_post": len(ya_hecho)}

    print(f"[trabajo] {len(pendientes)} pendientes con concurrencia={concurrencia}")
    pool = Pool.desde_env()
    print(f"[pool] proveedores: {pool.disponibles}")

    sem = asyncio.Semaphore(concurrencia)
    inicio = time.time()
    completados = 0
    errores = 0
    omitidos = 0

    # Abrir salida en modo append (preserva lo ya hecho).
    with salida.open("a", encoding="utf-8") as fout:
        # Lanzar todas las tareas; consumimos a medida que terminan.
        tareas = [
            asyncio.create_task(
                _calificar_uno(pool, sem, reg, con_detalle=con_detalle)
            )
            for reg in pendientes
        ]
        try:
            for fut in asyncio.as_completed(tareas):
                res = await fut
                if res is None:
                    omitidos += 1
                    continue
                fout.write(json.dumps(res, ensure_ascii=False) + "\n")
                fout.flush()
                completados += 1
                if not res.get("scores_completos"):
                    errores += 1

                if completados % 10 == 0 or completados == len(pendientes):
                    elapsed = time.time() - inicio
                    velocidad = completados / elapsed if elapsed > 0 else 0
                    restantes = len(pendientes) - completados
                    eta_min = (restantes / velocidad / 60) if velocidad > 0 else 0
                    print(
                        f"  [{completados}/{len(pendientes)}] "
                        f"vel={velocidad:.2f}/s  ETA {eta_min:.1f} min  "
                        f"errores={errores}  omitidos={omitidos}",
                        flush=True,
                    )
        except KeyboardInterrupt:
            print("\n[interrupcion] cancelando tareas pendientes...")
            for t in tareas:
                t.cancel()
            raise

    tiempo_min = (time.time() - inicio) / 60
    print(f"\n[done] {completados} etiquetados en {tiempo_min:.1f} min")
    print(f"       errores: {errores}   omitidos: {omitidos}")
    print(f"       pool stats: {json.dumps(pool.stats(), indent=2)}")

    return {
        "total_entrada": len(todos),
        "ya_hechos_previos": len(ya_hecho),
        "nuevos_completados": completados,
        "errores": errores,
        "omitidos": omitidos,
        "tiempo_minutos": round(tiempo_min, 1),
        "pool_stats": pool.stats(),
    }


# ════════════════════════════════════════════════════════════════════
# CLI
# ════════════════════════════════════════════════════════════════════

def main() -> None:
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--entrada", required=True,
                   help="JSONL de entrada con prompt/respuesta")
    p.add_argument("--salida", required=True,
                   help="JSONL de salida (resume si existe)")
    p.add_argument("--concurrencia", type=int, default=4,
                   help="Llamadas simultáneas a los jueces (ojo con rate limits)")
    p.add_argument("--con-detalle", action="store_true",
                   help="Incluir scores_detalle por juez (archivo crece ~3x)")
    p.add_argument("--limite", type=int, default=None,
                   help="Tope de registros a procesar (debug)")
    args = p.parse_args()

    try:
        resumen = asyncio.run(etiquetar(
            Path(args.entrada), Path(args.salida),
            concurrencia=args.concurrencia,
            con_detalle=args.con_detalle,
            limite=args.limite,
        ))
    except FileNotFoundError as exc:
        print(f"ERROR: no existe {exc}", file=sys.stderr)
        raise SystemExit(2)
    except KeyboardInterrupt:
        print("interrumpido por usuario", file=sys.stderr)
        raise SystemExit(130)

    print("\n=== RESUMEN ===")
    print(json.dumps(resumen, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
