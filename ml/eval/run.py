"""CLI principal del benchmark.

Evalúa un checkpoint en HumanEval (versión completa o demo) y genera
un reporte Markdown listo para el capítulo de Resultados de la tesis.

Ejemplos:

    # 1) Evaluar nuestro modelo propio
    python -m ml.eval.run \\
        --checkpoint training/checkpoints/tesis_v2_best.pt \\
        --tokenizer ml/tokenizer/artefactos/tokenizer_tesis_v1.json \\
        --salida docs/EXPERIMENTOS/eval_tesis_v2.md \\
        --modelo-nombre "tesis_v2 (modelo propio 46M, arch clásica)"

    # 2) Evaluar Gemini como baseline (necesita GEMINI_API_KEY)
    python -m ml.eval.run --gemini \\
        --salida docs/EXPERIMENTOS/eval_gemini_2flash.md \\
        --modelo-nombre "Gemini 2.0 Flash"

    # 3) Comparativa de varios resultados (post-ejecución)
    python -m ml.eval.run comparar \\
        --reportes docs/EXPERIMENTOS/eval_tesis_v2.md \\
                   docs/EXPERIMENTOS/eval_gemini_2flash.md \\
        --salida docs/EXPERIMENTOS/comparativa.md
"""

from __future__ import annotations

import argparse
import asyncio
import os
import sys
from pathlib import Path

from ml.eval.benchmarks import (
    cargar_humaneval, correr_humaneval,
    resultado_a_markdown, comparar_resultados,
)


# ════════════════════════════════════════════════════════════════════
# Wrappers de generación para distintos modelos
# ════════════════════════════════════════════════════════════════════

def hacer_generar_modelo_propio(checkpoint_path: str, tokenizer_path: str,
                                 max_tokens: int = 200) -> callable:
    """Devuelve generar_fn(prompt) → str usando nuestro modelo propio."""
    import torch
    from ml.config import resolver_device
    from ml.rlhf.dpo import cargar_checkpoint
    from ml.tokenizer.sp_tokenizer import SPTokenizer

    device = resolver_device("auto")
    print(f"[run] cargando modelo propio: {checkpoint_path}")
    modelo, _ = cargar_checkpoint(Path(checkpoint_path), device)
    modelo.eval()
    tok = SPTokenizer.cargar(Path(tokenizer_path))

    def generar(prompt: str) -> str:
        ids = torch.tensor(tok.codificar(prompt), dtype=torch.long, device=device)
        ids = ids.unsqueeze(0)
        with torch.no_grad():
            salida = modelo.generar(
                ids, max_new_tokens=max_tokens,
                temperatura=0.2, top_p=0.95,
            )
        return tok.decodificar(salida[0, ids.size(1):].tolist())

    return generar


def hacer_generar_gemini(modelo_id: str = "gemini-2.0-flash-exp",
                         max_tokens: int = 400) -> callable:
    """Devuelve generar_fn(prompt) → str usando Gemini API."""
    api_key = os.environ.get("GEMINI_API_KEY")
    if not api_key:
        print("[run] ERROR: define GEMINI_API_KEY en env", file=sys.stderr)
        sys.exit(1)
    try:
        import google.generativeai as genai
    except ImportError:
        print("[run] ERROR: pip install google-generativeai", file=sys.stderr)
        sys.exit(1)
    genai.configure(api_key=api_key)
    modelo = genai.GenerativeModel(modelo_id)

    instr = (
        "Completa la siguiente función Python. Responde SOLO con el "
        "cuerpo del código (sin texto explicativo, sin markdown). "
        "Mantén la signatura tal cual.\n\n"
    )

    def generar(prompt: str) -> str:
        try:
            rsp = modelo.generate_content(
                instr + prompt,
                generation_config={
                    "temperature": 0.2, "max_output_tokens": max_tokens,
                },
            )
            return rsp.text or ""
        except Exception as e:  # noqa: BLE001
            return f"# error: {e}"

    return generar


def hacer_generar_dummy() -> callable:
    """Wrapper de prueba: devuelve la solución canónica del problema demo.
    Útil para validar el harness sin GPU/API.
    """
    soluciones = {
        "def add": "    return a + b\n",
        "def es_primo": (
            "    if n < 2: return False\n"
            "    for i in range(2, int(n**0.5)+1):\n"
            "        if n % i == 0: return False\n"
            "    return True\n"
        ),
        "def invertir_string": "    return s[::-1]\n",
        "def factorial": (
            "    if n <= 1: return 1\n"
            "    r = 1\n"
            "    for i in range(2, n+1): r *= i\n"
            "    return r\n"
        ),
        "def fibonacci": (
            "    a, b = 0, 1\n"
            "    for _ in range(n): a, b = b, a+b\n"
            "    return a\n"
        ),
    }

    def generar(prompt: str) -> str:
        for k, v in soluciones.items():
            if k in prompt:
                return v
        return "    pass\n"
    return generar


# ════════════════════════════════════════════════════════════════════
# Main
# ════════════════════════════════════════════════════════════════════

def main() -> None:
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd")

    # Subcomando default (no especificado): correr benchmark.
    pe = sub.add_parser("eval", help="Evaluar un modelo en HumanEval")
    pe.add_argument("--checkpoint", default=None, help="Ruta del .pt del modelo propio")
    pe.add_argument("--tokenizer", default=None, help="Ruta del tokenizer JSON")
    pe.add_argument("--gemini", action="store_true", help="Evaluar Gemini en lugar de modelo propio")
    pe.add_argument("--dummy", action="store_true", help="Wrapper trivial para validar harness")
    pe.add_argument("--humaneval", default=None,
                    help="JSONL de HumanEval (si no, usa set demo de 5 problemas)")
    pe.add_argument("--salida", default="docs/EXPERIMENTOS/eval.md")
    pe.add_argument("--modelo-nombre", default="modelo")
    pe.add_argument("--n-problemas", type=int, default=0,
                    help="Limita a N problemas (0 = todos)")

    # Subcomando comparar
    pc = sub.add_parser("comparar", help="Combinar varios reportes en una tabla")
    pc.add_argument("--reportes", nargs="+", required=True)
    pc.add_argument("--salida", required=True)

    args = p.parse_args()

    # Si no hay subcomando, asumimos `eval`.
    if args.cmd is None:
        # Re-parsear como eval
        args = p.parse_args(["eval"] + sys.argv[1:])

    if args.cmd == "comparar":
        comparar_cli(args)
        return
    eval_cli(args)


def eval_cli(args: argparse.Namespace) -> None:
    print("=" * 60)
    print(f" Benchmark: {args.modelo_nombre}")
    print("=" * 60)

    # Construir el generador apropiado
    if args.gemini:
        generar_fn = hacer_generar_gemini()
    elif args.dummy:
        generar_fn = hacer_generar_dummy()
    elif args.checkpoint:
        if not args.tokenizer:
            print("[ERR] --tokenizer requerido con --checkpoint", file=sys.stderr)
            sys.exit(1)
        generar_fn = hacer_generar_modelo_propio(args.checkpoint, args.tokenizer)
    else:
        print("[ERR] Especifica --checkpoint, --gemini o --dummy", file=sys.stderr)
        sys.exit(1)

    # Cargar problemas
    if args.humaneval:
        problemas = cargar_humaneval(Path(args.humaneval))
    else:
        problemas = cargar_humaneval(Path("non_existent"))  # → set demo
        print(f"[run] usando set demo ({len(problemas)} problemas) — "
              "pasa --humaneval para evaluación completa")

    if args.n_problemas > 0:
        problemas = problemas[: args.n_problemas]
    print(f"[run] {len(problemas)} problemas a evaluar")
    print()

    # Correr
    resultado = correr_humaneval(
        problemas, generar_fn, nombre_modelo=args.modelo_nombre,
    )

    # Resumen
    print()
    print("=" * 60)
    print(f" Resultado: {resultado.pass_at_1_pct} ({resultado.n_resueltos}/{resultado.n_problemas})")
    print(f" Duración: {resultado.duracion_segundos:.1f}s")
    print("=" * 60)

    # Guardar Markdown
    salida = Path(args.salida)
    salida.parent.mkdir(parents=True, exist_ok=True)
    md = resultado_a_markdown(
        resultado,
        contexto=f"_Generado automáticamente por `ml/eval/run.py`._",
    )
    salida.write_text(md, encoding="utf-8")
    print(f"\n[run] reporte guardado: {salida}")


def comparar_cli(args: argparse.Namespace) -> None:
    """Lee varios reportes Markdown, extrae sus métricas y combina.

    Por ahora hacemos una versión simple: re-leer JSON sidecar.
    Para una v1 funcional, sugerimos guardar también los ResultadoBenchmark
    como JSON al lado del .md.
    """
    print("[comparar] todavía esquemático — usa el formato:")
    print("  Para cada modelo: corre `ml.eval.run` y guarda .md.")
    print("  Combina manualmente o invoca `resultado_a_markdown` programáticamente.")


if __name__ == "__main__":
    main()
