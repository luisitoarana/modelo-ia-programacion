"""CLI de EduCodeEval — ejecuta el benchmark sobre un modelo.

Uso:

    # Evaluar Gemini como baseline
    python -m ml.eval.edu_code_eval --modelo gemini-api

    # Evaluar el modelo propio (cuando esté entrenado)
    python -m ml.eval.edu_code_eval \\
        --modelo local \\
        --checkpoint training/checkpoints/B_fase5b_dpo/checkpoint_best.pt \\
        --tokenizer ml/tokenizer/artefactos/sp_v2_16k.model

    # Evaluar un proveedor cualquiera del pool
    python -m ml.eval.edu_code_eval --modelo groq

    # Guardar resultado a JSON
    python -m ml.eval.edu_code_eval --modelo gemini-api \\
        --salida training/experiments/educode_gemini_baseline.json

Resultado en stdout (o JSON con --salida): score por categoría + score global.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import sys
from pathlib import Path

from .core import EduCodeEval, cargar_tareas


def _crear_callable_local(checkpoint: Path, tokenizer: Path):
    """Carga el modelo propio (V2) y devuelve un callable prompt -> respuesta."""
    import torch
    from ml.config import resolver_device
    from ml.model.transformer_v2 import GPTEducativoV2
    from ml.training.run_fase import _Tokenizer

    device = resolver_device("auto")
    tok = _Tokenizer(tokenizer)
    ck = torch.load(checkpoint, map_location=device)
    from ml.model.transformer_v2 import ModelConfigV2
    cfg = ModelConfigV2(**ck["modelo_cfg"])
    modelo = GPTEducativoV2(cfg).to(device)
    modelo.load_state_dict(ck["model_state"])
    modelo.eval()

    def _generar(prompt: str) -> str:
        ids = torch.tensor(tok.codificar(prompt), dtype=torch.long, device=device)
        ids = ids.unsqueeze(0)
        with torch.no_grad():
            out = modelo.generar(ids, max_new_tokens=512, temperatura=0.7, top_p=0.9)
        nuevo = out[0, ids.size(1):].tolist()
        return tok.decodificar(nuevo)

    return _generar


def _crear_callable_pool(proveedor: str):
    """Usa un proveedor del pool (gemini, deepseek, groq, etc.)."""
    from ml.data.pool_generadores import Pool, Tarea

    pool = Pool.desde_env()
    if proveedor not in pool.disponibles:
        raise RuntimeError(
            f"Proveedor '{proveedor}' no configurado. "
            f"Disponibles: {pool.disponibles}"
        )

    async def _async_gen(prompt: str) -> str:
        texto, _ = await pool.generar(
            prompt, tarea=Tarea.GENERICA,
            temperatura=0.4, max_tokens=2048,
            proveedor_forzado=proveedor,
        )
        return texto

    def _sync(prompt: str) -> str:
        return asyncio.run(_async_gen(prompt))

    return _sync


def main() -> None:
    p = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    p.add_argument("--modelo", required=True,
                   choices=["local", "gemini-api", "groq", "deepseek",
                            "together", "mistral", "openrouter", "gemini"],
                   help="Qué modelo evaluar.")
    p.add_argument("--checkpoint", type=Path,
                   help="Ruta al checkpoint (sólo con --modelo local).")
    p.add_argument("--tokenizer", type=Path,
                   help="Ruta al tokenizer.model (sólo con --modelo local).")
    p.add_argument("--salida", type=Path, default=None,
                   help="Guardar resultado JSON a esta ruta.")
    p.add_argument("--nombre-corrida", default=None,
                   help="Nombre del experimento para el reporte.")
    args = p.parse_args()

    # Construir callable del modelo
    if args.modelo == "local":
        if not args.checkpoint or not args.tokenizer:
            print("ERROR: --modelo local requiere --checkpoint y --tokenizer",
                  file=sys.stderr)
            raise SystemExit(2)
        modelo_call = _crear_callable_local(args.checkpoint, args.tokenizer)
        nombre = args.nombre_corrida or f"local_{args.checkpoint.parent.name}"
    elif args.modelo in ("gemini-api", "gemini"):
        modelo_call = _crear_callable_pool("gemini")
        nombre = args.nombre_corrida or "gemini-2.0-flash"
    else:
        modelo_call = _crear_callable_pool(args.modelo)
        nombre = args.nombre_corrida or args.modelo

    # Cargar tareas y correr
    tareas = cargar_tareas()
    print(f"EduCodeEval — {len(tareas)} tareas | modelo: {nombre}\n")

    bench = EduCodeEval(tareas=tareas)
    resultado = bench.ejecutar(modelo_call, nombre_modelo=nombre)

    # Reporte
    print("\n" + "=" * 64)
    print(f"  RESULTADO — {resultado.nombre_modelo}")
    print("=" * 64)
    print(f"\nTareas aprobadas: "
          f"{resultado.n_tareas_aprobadas}/{resultado.n_tareas_total} "
          f"({100*resultado.n_tareas_aprobadas/max(1,resultado.n_tareas_total):.1f} %)")
    print("\nScore por categoría:")
    for cat, score in sorted(
        resultado.score_por_categoria.items(),
        key=lambda kv: -kv[1],
    ):
        print(f"   {cat:<18} {score:6.2f} / 100")
    print(f"\nSCORE GLOBAL: {resultado.score_global:.2f} / 100")
    print("=" * 64)

    if args.salida:
        args.salida.parent.mkdir(parents=True, exist_ok=True)
        args.salida.write_text(
            json.dumps(resultado.to_dict(), indent=2, ensure_ascii=False),
            encoding="utf-8",
        )
        print(f"\nResultado guardado en: {args.salida}")


if __name__ == "__main__":
    main()
