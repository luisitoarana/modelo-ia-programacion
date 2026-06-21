"""Prepara el dataset de pares (chosen, rejected) para DPO.

Tres fuentes posibles:
    1. Feedback humano de la BD (votos 👍/👎 de usuarios) → vía
       `exportar_dataset.py` que ya existía.
    2. **RLAIF con Gemini**: para cada prompt del corpus, generar dos
       respuestas con el modelo base, hacer que Gemini elija cuál es
       mejor, guardar como par.
    3. **Pares sintéticos con reglas**: tomar respuestas de alta calidad
       como chosen, generar variantes degradadas (truncadas, con bugs
       inyectados) como rejected.

Uso:
    # Construir 5000 pares con RLAIF (Gemini juez)
    python -m ml.rlhf.preparar_pares \\
        --modo rlaif \\
        --base-checkpoint training/checkpoints/tesis_v2_best.pt \\
        --tokenizer ml/tokenizer/artefactos/tokenizer_tesis_v1.json \\
        --prompts ml/data/prompts_evaluacion.txt \\
        --salida ml/data/dpo_rlaif_v1.jsonl \\
        --n-pares 5000

    # Combinar feedback humano + RLAIF en un solo dataset
    python -m ml.rlhf.preparar_pares \\
        --modo combinar \\
        --entradas ml/data/dpo_humano.jsonl ml/data/dpo_rlaif_v1.jsonl \\
        --salida ml/data/dpo_v1_final.jsonl

Cada línea del JSONL de salida tiene:
    {
        "prompt": "Explica qué es una función lambda",
        "chosen": "Una función lambda es ...",
        "rejected": "lambda x: ...",
        "source": "rlaif_gemini" | "humano" | "sintetico_truncado",
        "meta": {... opcional ...}
    }
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import random
import sys
import time
from pathlib import Path
from typing import Iterator

import torch

from ml.config import resolver_device
from ml.model.transformer import GPTEducativo
from ml.rlhf.dpo import cargar_checkpoint
from ml.tokenizer.sp_tokenizer import SPTokenizer


# ════════════════════════════════════════════════════════════════════
# Modo 1: RLAIF con Gemini como juez
# ════════════════════════════════════════════════════════════════════

PROMPT_JUEZ = """Eres un profesor experto de Python evaluando respuestas
de un asistente educativo para estudiantes hispanohablantes.

Pregunta del estudiante:
{pregunta}

Respuesta A:
{respuesta_a}

Respuesta B:
{respuesta_b}

Criterios:
- Precisión técnica
- Claridad pedagógica
- Estructura (qué hace, por qué, ejemplo, ejercicio breve)
- Adecuación al nivel del estudiante

¿Cuál respuesta es mejor? Responde EXACTAMENTE con una sola letra:
"A" o "B" (sin explicación, sin punto final, sin comillas).
"""


async def _consultar_gemini_juez(
    pregunta: str, resp_a: str, resp_b: str, api_key: str
) -> str | None:
    """Pregunta a Gemini cuál de dos respuestas es mejor."""
    try:
        import google.generativeai as genai
    except ImportError:
        print("[rlaif] Instala google-generativeai: pip install google-generativeai",
              file=sys.stderr)
        return None
    genai.configure(api_key=api_key)
    modelo = genai.GenerativeModel("gemini-2.0-flash-exp")
    prompt = PROMPT_JUEZ.format(
        pregunta=pregunta, respuesta_a=resp_a, respuesta_b=resp_b,
    )
    try:
        rsp = await modelo.generate_content_async(prompt)
        texto = rsp.text.strip().upper()
        # Sacar la primera A o B encontrada
        for c in texto:
            if c in ("A", "B"):
                return c
        return None
    except Exception as e:
        print(f"[rlaif] error juez: {e}", file=sys.stderr)
        return None


def _generar_dos_respuestas(
    modelo: GPTEducativo, tokenizer: SPTokenizer, prompt: str,
    device: str, *, max_tokens: int = 200, temperatura: float = 0.85,
) -> tuple[str, str]:
    """Genera dos respuestas distintas variando la temperatura."""
    prompt_ids = torch.tensor(tokenizer.codificar(prompt), dtype=torch.long, device=device)
    prompt_ids = prompt_ids.unsqueeze(0)
    with torch.no_grad():
        # Respuesta A: temperatura moderada
        salida_a = modelo.generar(
            prompt_ids, max_new_tokens=max_tokens,
            temperatura=temperatura, top_p=0.9,
        )
        # Respuesta B: temperatura más alta + top-k restrictivo
        salida_b = modelo.generar(
            prompt_ids, max_new_tokens=max_tokens,
            temperatura=temperatura + 0.2, top_k=40,
        )
    # Descodificar solo lo nuevo
    a = tokenizer.decodificar(salida_a[0, prompt_ids.size(1):].tolist())
    b = tokenizer.decodificar(salida_b[0, prompt_ids.size(1):].tolist())
    return a, b


async def modo_rlaif(args: argparse.Namespace) -> None:
    """Genera pares con RLAIF: modelo genera 2 respuestas, Gemini juzga."""
    api_key = os.environ.get("GEMINI_API_KEY")
    if not api_key:
        print("[rlaif] ERROR: define GEMINI_API_KEY en env.", file=sys.stderr)
        sys.exit(1)

    device = resolver_device(args.device)
    print(f"[rlaif] device={device}")
    print(f"[rlaif] cargando base modelo desde {args.base_checkpoint}")
    modelo, _ = cargar_checkpoint(Path(args.base_checkpoint), device)
    modelo.eval()
    tokenizer = SPTokenizer.cargar(Path(args.tokenizer))

    # Cargar prompts
    prompts = []
    with open(args.prompts, "r", encoding="utf-8") as f:
        for linea in f:
            p = linea.strip()
            if p:
                prompts.append(p)
    random.shuffle(prompts)
    print(f"[rlaif] {len(prompts)} prompts disponibles")

    salida = Path(args.salida)
    salida.parent.mkdir(parents=True, exist_ok=True)

    n_pares = args.n_pares
    pares_generados = 0
    pares_descartados = 0
    inicio = time.time()

    with salida.open("w", encoding="utf-8") as out:
        for i, prompt in enumerate(prompts):
            if pares_generados >= n_pares:
                break
            try:
                a, b = _generar_dos_respuestas(
                    modelo, tokenizer, prompt, device,
                    max_tokens=args.max_tokens,
                    temperatura=args.temperatura,
                )
            except Exception as e:
                print(f"[rlaif] error generando ({i}): {e}", file=sys.stderr)
                continue

            # Si las dos respuestas son casi iguales, descartar.
            if a.strip() == b.strip() or len(a) < 20 or len(b) < 20:
                pares_descartados += 1
                continue

            ganador = await _consultar_gemini_juez(prompt, a, b, api_key)
            if ganador not in ("A", "B"):
                pares_descartados += 1
                continue

            chosen, rejected = (a, b) if ganador == "A" else (b, a)
            registro = {
                "prompt": prompt,
                "chosen": chosen,
                "rejected": rejected,
                "source": "rlaif_gemini",
                "meta": {"ganador_gemini": ganador, "indice_prompt": i},
            }
            out.write(json.dumps(registro, ensure_ascii=False) + "\n")
            pares_generados += 1

            if pares_generados % 10 == 0:
                t = time.time() - inicio
                tps = pares_generados / t if t > 0 else 0
                eta = (n_pares - pares_generados) / max(tps, 1e-6)
                print(
                    f"[rlaif] {pares_generados}/{n_pares} pares "
                    f"({tps:.2f}/s · descartados {pares_descartados} · "
                    f"ETA {eta/60:.1f} min)"
                )

    t_total = time.time() - inicio
    print(f"\n[rlaif] OK · {pares_generados} pares en {t_total/60:.1f} min")
    print(f"        descartados: {pares_descartados}")
    print(f"        salida: {salida}")


# ════════════════════════════════════════════════════════════════════
# Modo 2: combinar varios JSONL en uno solo (dedup)
# ════════════════════════════════════════════════════════════════════

def modo_combinar(args: argparse.Namespace) -> None:
    """Combina varios .jsonl de pares en uno, eliminando duplicados."""
    salida = Path(args.salida)
    salida.parent.mkdir(parents=True, exist_ok=True)
    vistos: set[tuple[str, str]] = set()
    total_lineas = 0
    duplicados = 0
    fuentes: dict[str, int] = {}

    with salida.open("w", encoding="utf-8") as out:
        for ruta in args.entradas:
            p = Path(ruta)
            if not p.exists():
                print(f"[combinar] aviso: {p} no existe, skip", file=sys.stderr)
                continue
            with p.open("r", encoding="utf-8") as f:
                for linea in f:
                    linea = linea.strip()
                    if not linea:
                        continue
                    try:
                        obj = json.loads(linea)
                    except json.JSONDecodeError:
                        continue
                    clave = (obj.get("prompt", "").strip(),
                             obj.get("chosen", "").strip())
                    if clave in vistos:
                        duplicados += 1
                        continue
                    vistos.add(clave)
                    out.write(json.dumps(obj, ensure_ascii=False) + "\n")
                    total_lineas += 1
                    src = obj.get("source", "desconocido")
                    fuentes[src] = fuentes.get(src, 0) + 1

    print(f"[combinar] OK · {total_lineas} pares únicos en {salida}")
    print(f"           duplicados eliminados: {duplicados}")
    for src, n in sorted(fuentes.items(), key=lambda x: -x[1]):
        print(f"           - {src}: {n}")


# ════════════════════════════════════════════════════════════════════
# Modo 3: sintéticos por reglas (truncados, alterados)
# ════════════════════════════════════════════════════════════════════

def modo_sintetico(args: argparse.Namespace) -> None:
    """Genera pares sintéticos rápidos desde respuestas de calidad.

    Toma un JSONL del corpus de entrenamiento donde cada línea tiene
    {instruccion, salida} y produce pares:
        chosen   = salida original
        rejected = salida truncada o con bugs inyectados
    """
    entrada = Path(args.corpus)
    salida = Path(args.salida)
    salida.parent.mkdir(parents=True, exist_ok=True)

    n_pares = 0
    with entrada.open("r", encoding="utf-8") as inp, \
         salida.open("w", encoding="utf-8") as out:
        for linea in inp:
            try:
                obj = json.loads(linea)
            except json.JSONDecodeError:
                continue
            prompt = obj.get("instruccion") or obj.get("prompt")
            salida_buena = obj.get("salida") or obj.get("response")
            if not prompt or not salida_buena or len(salida_buena) < 40:
                continue

            # Generar respuesta "mala" — truncamos al 30% de la buena.
            corte = max(20, int(len(salida_buena) * 0.3))
            salida_mala = salida_buena[:corte] + "..."

            out.write(json.dumps({
                "prompt": prompt,
                "chosen": salida_buena,
                "rejected": salida_mala,
                "source": "sintetico_truncado",
            }, ensure_ascii=False) + "\n")
            n_pares += 1
            if n_pares >= args.n_pares:
                break
    print(f"[sintetico] {n_pares} pares sintéticos en {salida}")


# ════════════════════════════════════════════════════════════════════
# CLI
# ════════════════════════════════════════════════════════════════════

def main() -> None:
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="modo", required=True)

    # ── rlaif ──
    pr = sub.add_parser("rlaif", help="Generar pares con Gemini como juez")
    pr.add_argument("--base-checkpoint", required=True)
    pr.add_argument("--tokenizer", required=True)
    pr.add_argument("--prompts", required=True,
                    help="Archivo .txt con un prompt por línea")
    pr.add_argument("--salida", required=True)
    pr.add_argument("--n-pares", type=int, default=1000)
    pr.add_argument("--max-tokens", type=int, default=200)
    pr.add_argument("--temperatura", type=float, default=0.85)
    pr.add_argument("--device", default="auto")

    # ── combinar ──
    pc = sub.add_parser("combinar", help="Combinar varios .jsonl en uno (dedup)")
    pc.add_argument("--entradas", nargs="+", required=True)
    pc.add_argument("--salida", required=True)

    # ── sintetico ──
    ps = sub.add_parser("sintetico",
                        help="Pares por reglas (truncados, etc.) desde corpus")
    ps.add_argument("--corpus", required=True,
                    help="JSONL con instruccion/salida")
    ps.add_argument("--salida", required=True)
    ps.add_argument("--n-pares", type=int, default=2000)

    args = p.parse_args()
    if args.modo == "rlaif":
        asyncio.run(modo_rlaif(args))
    elif args.modo == "combinar":
        modo_combinar(args)
    elif args.modo == "sintetico":
        modo_sintetico(args)


if __name__ == "__main__":
    main()
