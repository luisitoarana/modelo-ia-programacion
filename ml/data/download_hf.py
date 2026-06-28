"""Descarga datasets de HuggingFace y los convierte al formato JSONL
que esperan ``ml/train.py`` (corpus desde cero) y ``ml/finetune.py``
(fine-tuning con QLoRA).

Datasets disponibles (gratis, sin login):

  ─────────────────────── Programación / código ───────────────────────
  codealpaca       — 20k pares instrucción→código (didáctico)
  codefeedback     — 70 MB instrucción + crítica de código (Hugo + Magicoder)
  codeparrot-py    — 50 GB Python limpio (¡pesado!)
  python-edu       — Python educativo curado
  magicoder-oss    — 75k Magicoder OSS-Instruct (instrucciones derivadas de OSS)
  magicoder-evol   — 110k Magicoder Evol-Instruct (evolución de instrucciones)
  apps             — 10k problemas competitivos Python con tests
  ds-1000          — 1k problemas data science Python
  open-code-interp — 68k OpenCodeInterpreter con execution feedback

  ─────────────────── Conversación / instrucciones ────────────────────
  oasst1-es        — Open Assistant filtrado a español
  openhermes       — Conversaciones generales de alta calidad
  alpaca-es        — Alpaca traducido al español

  ─────────────────── Razonamiento / explicaciones ────────────────────
  cot              — Chain of Thought (razonamiento paso a paso)

  ────────────────────── Evaluación (no entrenar) ─────────────────────
  humaneval        — Benchmark estándar para evaluar capacidad de código
  humaneval-plus   — HumanEval extendido (164 problemas, tests más rigurosos)
  mbpp             — Mostly Basic Python Problems
  mbpp-plus        — MBPP+ (tests más rigurosos)

Output schemas:
  V1 (default): {"instruction": "...", "input": "...", "response": "..."}
  V2 (--schema-v2): formato ml/data/schema.EjemploEntrenamiento, con
       tipo/tema/nivel/fuente — compatible con el corpus V2 generado.

Uso:
    pip install datasets

    # Listar lo disponible
    python -m ml.data.download_hf --listar

    # Descargar uno
    python -m ml.data.download_hf --dataset codealpaca \\
        --salida datasets/raw/codealpaca.jsonl

    # Descargar varios
    python -m ml.data.download_hf --dataset codealpaca,oasst1-es \\
        --salida-dir datasets/raw/

    # Limitar tamaño (útil para pruebas)
    python -m ml.data.download_hf --dataset codeparrot-py \\
        --max-items 5000 \\
        --salida datasets/raw/codeparrot_5k.jsonl

Formato de salida (JSONL — una línea por ejemplo):
    {"instruction": "...", "input": "", "response": "..."}

Compatible directamente con ``ml/finetune.py``. Para entrenar desde
cero con ``ml/train.py`` también funciona — el corpus loader lo lee.
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Iterable


# ──────────────────────── Descripciones de cada dataset ────────────────────

@dataclass
class DatasetSpec:
    hf_id: str
    config: str | None
    split: str
    descripcion: str
    transformer: Callable[[dict], dict | None]
    streaming: bool = False


def _t_codealpaca(ej: dict) -> dict | None:
    instr = ej.get("instruction", "").strip()
    inp = ej.get("input", "").strip()
    out = ej.get("output", "").strip()
    if not instr or not out:
        return None
    return {"instruction": instr, "input": inp, "response": out}


def _t_codefeedback(ej: dict) -> dict | None:
    q = ej.get("query") or ej.get("instruction") or ""
    a = ej.get("answer") or ej.get("response") or ""
    if not q or not a:
        return None
    return {"instruction": str(q).strip(), "input": "", "response": str(a).strip()}


def _t_codeparrot(ej: dict) -> dict | None:
    contenido = ej.get("content", "").strip()
    if not contenido or len(contenido) < 40:
        return None
    # Para entrenamiento desde cero (sin pares instr/resp), guardamos como
    # un ejemplo de "lectura de código" con prompt sintético.
    return {
        "instruction": "Lee y comprende el siguiente código Python.",
        "input": "",
        "response": contenido[:4000],
    }


def _t_oasst1_es(ej: dict) -> dict | None:
    if ej.get("lang") != "es":
        return None
    if ej.get("role") != "prompter":
        return None
    # Filtramos solo los prompts en español. La respuesta del assistant
    # vive en otro registro vinculado por parent_id — el dataset OASST
    # requiere reconstruir conversaciones. Para simplificar usamos un
    # placeholder y dejamos la respuesta vacía si no se enlaza.
    texto = (ej.get("text") or "").strip()
    if not texto:
        return None
    return {"instruction": texto, "input": "", "response": ""}


def _t_openhermes(ej: dict) -> dict | None:
    # Formato conversational (lista de mensajes).
    convs = ej.get("conversations") or ej.get("messages")
    if not convs or len(convs) < 2:
        return None
    user_msg = next((m for m in convs if m.get("from") == "human" or m.get("role") == "user"), None)
    ai_msg = next((m for m in convs if m.get("from") == "gpt" or m.get("role") == "assistant"), None)
    if not user_msg or not ai_msg:
        return None
    instr = (user_msg.get("value") or user_msg.get("content") or "").strip()
    resp = (ai_msg.get("value") or ai_msg.get("content") or "").strip()
    if not instr or not resp:
        return None
    return {"instruction": instr, "input": "", "response": resp}


def _t_alpaca_es(ej: dict) -> dict | None:
    return _t_codealpaca(ej)


def _t_cot(ej: dict) -> dict | None:
    pregunta = (ej.get("source") or ej.get("question") or "").strip()
    razonamiento = (ej.get("rationale") or ej.get("explanation") or "").strip()
    respuesta = (ej.get("target") or ej.get("answer") or "").strip()
    if not pregunta or not respuesta:
        return None
    resp_completa = f"{razonamiento}\n\nRespuesta: {respuesta}" if razonamiento else respuesta
    return {"instruction": pregunta, "input": "", "response": resp_completa}


def _t_humaneval(ej: dict) -> dict | None:
    prompt = (ej.get("prompt") or "").strip()
    sol = (ej.get("canonical_solution") or "").strip()
    if not prompt or not sol:
        return None
    return {"instruction": "Completa la siguiente función:", "input": prompt, "response": sol}


def _t_mbpp(ej: dict) -> dict | None:
    desc = (ej.get("text") or ej.get("problem") or "").strip()
    code = (ej.get("code") or ej.get("solution") or "").strip()
    if not desc or not code:
        return None
    return {"instruction": desc, "input": "", "response": code}


def _t_python_edu(ej: dict) -> dict | None:
    return _t_codeparrot(ej)


# ──────────────────────── Nuevos datasets V2 ────────────────────────

def _t_magicoder_oss(ej: dict) -> dict | None:
    """Magicoder OSS-Instruct (ise-uiuc/Magicoder-OSS-Instruct-75K)."""
    instr = (ej.get("problem") or ej.get("instruction") or "").strip()
    sol = (ej.get("solution") or ej.get("response") or ej.get("output") or "").strip()
    if not instr or not sol or len(sol) < 40:
        return None
    return {"instruction": instr, "input": "", "response": sol}


def _t_magicoder_evol(ej: dict) -> dict | None:
    """Magicoder Evol-Instruct (ise-uiuc/Magicoder-Evol-Instruct-110K)."""
    instr = (ej.get("instruction") or "").strip()
    sol = (ej.get("response") or ej.get("output") or "").strip()
    if not instr or not sol or len(sol) < 40:
        return None
    return {"instruction": instr, "input": "", "response": sol}


def _t_apps(ej: dict) -> dict | None:
    """APPS (codeparrot/apps): problemas competitivos con tests."""
    question = (ej.get("question") or "").strip()
    soluciones = ej.get("solutions") or "[]"
    # En APPS, solutions viene como string JSON con una lista.
    try:
        lista = json.loads(soluciones) if isinstance(soluciones, str) else soluciones
    except json.JSONDecodeError:
        lista = []
    if not lista:
        return None
    sol = (lista[0] if isinstance(lista[0], str) else "").strip()
    if not question or not sol or len(sol) < 30:
        return None
    return {"instruction": question, "input": "", "response": sol}


def _t_ds1000(ej: dict) -> dict | None:
    """DS-1000 (xlangai/DS-1000): problemas data science."""
    prompt = (ej.get("prompt") or ej.get("problem") or "").strip()
    sol = (ej.get("reference_code") or ej.get("solution") or ej.get("code") or "").strip()
    if not prompt or not sol:
        return None
    return {"instruction": prompt, "input": "", "response": sol}


def _t_open_code_interp(ej: dict) -> dict | None:
    """OpenCodeInterpreter — m-a-p/Code-Feedback."""
    msgs = ej.get("messages") or []
    if len(msgs) < 2:
        return None
    user = next((m for m in msgs if m.get("role") == "user"), None)
    asis = next((m for m in msgs if m.get("role") == "assistant"), None)
    if not user or not asis:
        return None
    instr = (user.get("content") or "").strip()
    resp = (asis.get("content") or "").strip()
    if not instr or len(resp) < 40:
        return None
    return {"instruction": instr, "input": "", "response": resp}


def _t_humaneval_plus(ej: dict) -> dict | None:
    """HumanEvalPlus (evalplus/humanevalplus): solo evaluación."""
    prompt = (ej.get("prompt") or "").strip()
    sol = (ej.get("canonical_solution") or "").strip()
    if not prompt or not sol:
        return None
    return {"instruction": "Completa la siguiente función:", "input": prompt, "response": sol}


def _t_mbpp_plus(ej: dict) -> dict | None:
    """MBPP+ (evalplus/mbppplus): solo evaluación."""
    desc = (ej.get("prompt") or ej.get("text") or "").strip()
    code = (ej.get("code") or ej.get("canonical_solution") or "").strip()
    if not desc or not code:
        return None
    return {"instruction": desc, "input": "", "response": code}


DATASETS: dict[str, DatasetSpec] = {
    "codealpaca": DatasetSpec(
        hf_id="sahil2801/CodeAlpaca-20k",
        config=None,
        split="train",
        descripcion="20k pares instrucción → código didáctico",
        transformer=_t_codealpaca,
    ),
    "codefeedback": DatasetSpec(
        hf_id="m-a-p/CodeFeedback-Filtered-Instruction",
        config=None,
        split="train",
        descripcion="Instrucciones + crítica de código (filtrado)",
        transformer=_t_codefeedback,
    ),
    "codeparrot-py": DatasetSpec(
        hf_id="codeparrot/codeparrot-clean",
        config=None,
        split="train",
        descripcion="Python limpio (50 GB — usa --max-items)",
        transformer=_t_codeparrot,
        streaming=True,  # demasiado grande para cargar entero
    ),
    "python-edu": DatasetSpec(
        hf_id="HuggingFaceTB/smollm-corpus",
        config="python-edu",
        split="train",
        descripcion="Python educativo curado por HuggingFace",
        transformer=_t_python_edu,
        streaming=True,
    ),
    "oasst1-es": DatasetSpec(
        hf_id="OpenAssistant/oasst1",
        config=None,
        split="train",
        descripcion="Open Assistant — solo prompts en español",
        transformer=_t_oasst1_es,
    ),
    "openhermes": DatasetSpec(
        hf_id="teknium/OpenHermes-2.5",
        config=None,
        split="train",
        descripcion="Conversaciones generales de alta calidad",
        transformer=_t_openhermes,
    ),
    "alpaca-es": DatasetSpec(
        hf_id="bertin-project/alpaca-spanish",
        config=None,
        split="train",
        descripcion="Alpaca traducido al español",
        transformer=_t_alpaca_es,
    ),
    "cot": DatasetSpec(
        hf_id="kaist-ai/CoT-Collection",
        config=None,
        split="train",
        descripcion="Chain of Thought — razonamiento paso a paso",
        transformer=_t_cot,
        streaming=True,
    ),
    "humaneval": DatasetSpec(
        hf_id="openai/openai_humaneval",
        config=None,
        split="test",
        descripcion="Benchmark de código (¡no entrenar, solo evaluar!)",
        transformer=_t_humaneval,
    ),
    "mbpp": DatasetSpec(
        hf_id="google-research-datasets/mbpp",
        config="sanitized",
        split="train",
        descripcion="Mostly Basic Python Problems",
        transformer=_t_mbpp,
    ),
    "magicoder-oss": DatasetSpec(
        hf_id="ise-uiuc/Magicoder-OSS-Instruct-75K",
        config=None,
        split="train",
        descripcion="75k Magicoder OSS-Instruct (instrucciones derivadas de OSS, alta calidad)",
        transformer=_t_magicoder_oss,
    ),
    "magicoder-evol": DatasetSpec(
        hf_id="ise-uiuc/Magicoder-Evol-Instruct-110K",
        config=None,
        split="train",
        descripcion="110k Magicoder Evol-Instruct (instrucciones evolucionadas)",
        transformer=_t_magicoder_evol,
    ),
    "apps": DatasetSpec(
        hf_id="codeparrot/apps",
        config="all",
        split="train",
        descripcion="10k problemas competitivos Python con tests (razonamiento difícil)",
        transformer=_t_apps,
    ),
    "ds-1000": DatasetSpec(
        hf_id="xlangai/DS-1000",
        config=None,
        split="test",
        descripcion="1k problemas Data Science Python (pandas, numpy, sklearn, scipy)",
        transformer=_t_ds1000,
    ),
    "open-code-interp": DatasetSpec(
        hf_id="m-a-p/Code-Feedback",
        config=None,
        split="train",
        descripcion="68k OpenCodeInterpreter — código con execution feedback",
        transformer=_t_open_code_interp,
    ),
    "humaneval-plus": DatasetSpec(
        hf_id="evalplus/humanevalplus",
        config=None,
        split="test",
        descripcion="HumanEval+ (164 problemas, tests rigurosos) — ¡solo evaluar!",
        transformer=_t_humaneval_plus,
    ),
    "mbpp-plus": DatasetSpec(
        hf_id="evalplus/mbppplus",
        config=None,
        split="test",
        descripcion="MBPP+ (tests rigurosos sobre MBPP) — ¡solo evaluar!",
        transformer=_t_mbpp_plus,
    ),
}


# ──────────────────────── Mapeo a Schema V2 ────────────────────────

# Para cada dataset, decidimos cómo mapearlo al schema V2:
#   (tipo, tema, nivel) — heurísticas razonables, no perfectas.
_MAPEO_V2: dict[str, tuple[str, str, str]] = {
    "codealpaca":       ("generacion_codigo", "instrucciones",       "basico"),
    "codefeedback":     ("correccion_error",  "feedback_codigo",     "intermedio"),
    "codeparrot-py":    ("comprension",       "lectura_codigo",      "intermedio"),
    "python-edu":       ("comprension",       "python_educativo",    "basico"),
    "oasst1-es":        ("concepto",          "open_assistant_es",   "basico"),
    "openhermes":       ("explicacion_codigo","conversaciones",      "intermedio"),
    "alpaca-es":         ("generacion_codigo","alpaca_es",          "basico"),
    "cot":              ("pensamiento_programador", "razonamiento",  "intermedio"),
    "humaneval":        ("generacion_codigo", "evaluacion_humaneval","intermedio"),
    "mbpp":             ("generacion_codigo", "mbpp",                "basico"),
    "magicoder-oss":    ("generacion_codigo", "magicoder_oss",       "intermedio"),
    "magicoder-evol":   ("generacion_codigo", "magicoder_evol",      "avanzado"),
    "apps":             ("generacion_codigo", "competitivo",         "avanzado"),
    "ds-1000":          ("generacion_codigo", "data_science",        "intermedio"),
    "open-code-interp": ("explicacion_codigo","codigo_con_feedback", "intermedio"),
    "humaneval-plus":   ("generacion_codigo", "evaluacion_humaneval_plus", "intermedio"),
    "mbpp-plus":        ("generacion_codigo", "mbpp_plus",           "basico"),
}


def _convertir_a_v2(reg_v1: dict, nombre_dataset: str) -> dict:
    """Convierte un registro V1 (instruction/input/response) al schema V2."""
    tipo, tema, nivel = _MAPEO_V2.get(
        nombre_dataset, ("explicacion_codigo", "otro", "basico"),
    )
    return {
        "instruccion": reg_v1.get("instruction", ""),
        "entrada":     reg_v1.get("input", ""),
        "salida":      reg_v1.get("response", ""),
        "nivel":       nivel,
        "tema":        tema,
        "tipo":        tipo,
        "fuente":      "publico_hf",
        "metadata":    {"hf_dataset": nombre_dataset},
    }


# ──────────────────────── Descarga + conversión ────────────────────────

def descargar(
    nombre: str,
    salida: Path,
    max_items: int | None = None,
    *,
    schema_v2: bool = False,
) -> int:
    """Descarga y convierte un dataset. Devuelve nº de ejemplos guardados.

    Si `schema_v2=True`, emite cada ejemplo en el formato del schema V2
    (`ml/data/schema.EjemploEntrenamiento`) con tipo/tema/nivel/fuente
    inferidos del dataset de origen.
    """
    spec = DATASETS.get(nombre)
    if spec is None:
        raise ValueError(f"Dataset desconocido: {nombre}")
    try:
        from datasets import load_dataset
    except ImportError:
        print("Falta el paquete 'datasets'. Instala con: pip install datasets")
        sys.exit(1)

    print(f"Descargando {nombre} ({spec.hf_id})...")
    kw: dict = {}
    if spec.config:
        kw["name"] = spec.config
    kw["split"] = spec.split
    if spec.streaming:
        kw["streaming"] = True

    ds = load_dataset(spec.hf_id, **kw)

    salida.parent.mkdir(parents=True, exist_ok=True)
    n_guardados = 0
    n_descartados = 0
    iterador: Iterable[dict] = ds  # type: ignore[assignment]

    with open(salida, "w", encoding="utf-8") as f:
        for ej in iterador:
            transformado = spec.transformer(dict(ej))
            if transformado is None:
                n_descartados += 1
                continue
            if schema_v2:
                transformado = _convertir_a_v2(transformado, nombre)
            f.write(json.dumps(transformado, ensure_ascii=False) + "\n")
            n_guardados += 1
            if max_items and n_guardados >= max_items:
                break
            if n_guardados % 500 == 0:
                print(f"   ... {n_guardados} guardados", end="\r")

    print(f"\n[OK] {nombre}: {n_guardados} guardados, {n_descartados} descartados "
          f"(schema {'V2' if schema_v2 else 'V1'})")
    print(f"     -> {salida.absolute()}")
    return n_guardados


def listar() -> None:
    print()
    print("Datasets disponibles:")
    print("─" * 70)
    for nombre, spec in DATASETS.items():
        print(f"  {nombre:18}  {spec.descripcion}")
        print(f"  {'':18}  └─ {spec.hf_id}")
    print()
    print("Uso: python -m ml.data.download_hf --dataset <nombre> --salida <ruta.jsonl>")
    print()


def main() -> None:
    p = argparse.ArgumentParser(
        description="Descarga datasets de HuggingFace al formato JSONL del proyecto.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    p.add_argument("--listar", action="store_true", help="Listar datasets disponibles y salir.")
    p.add_argument(
        "--dataset",
        help="Nombre del dataset (o lista separada por comas). Ver --listar.",
    )
    p.add_argument(
        "--salida",
        help="Ruta del JSONL de salida (cuando descargas UN solo dataset).",
    )
    p.add_argument(
        "--salida-dir",
        help="Carpeta de salida (cuando descargas VARIOS — un JSONL por dataset).",
    )
    p.add_argument(
        "--max-items",
        type=int,
        default=None,
        help="Tope de ejemplos a guardar (útil para datasets enormes).",
    )
    p.add_argument(
        "--schema-v2",
        action="store_true",
        help="Emitir en el schema V2 (ml/data/schema) con tipo/tema/nivel/fuente. "
             "Por defecto se mantiene el schema V1 (instruction/input/response).",
    )
    args = p.parse_args()

    if args.listar or not args.dataset:
        listar()
        if not args.listar:
            print("Pasa --dataset para descargar.")
        return

    nombres = [n.strip() for n in args.dataset.split(",") if n.strip()]
    desconocidos = [n for n in nombres if n not in DATASETS]
    if desconocidos:
        print(f"❌ Desconocidos: {', '.join(desconocidos)}")
        print("   Usa --listar para ver los disponibles.")
        sys.exit(1)

    total = 0
    fallidos = []
    exitosos = []

    if len(nombres) == 1:
        ruta = Path(args.salida) if args.salida else Path(f"datasets/raw/{nombres[0]}.jsonl")
        try:
            total += descargar(nombres[0], ruta, args.max_items, schema_v2=args.schema_v2)
            exitosos.append(nombres[0])
        except Exception as exc:
            print(f"\n[!] FALLO {nombres[0]}: {type(exc).__name__}: {str(exc)[:200]}")
            fallidos.append((nombres[0], str(exc)[:200]))
    else:
        base = Path(args.salida_dir or "datasets/raw")
        for n in nombres:
            ruta = base / f"{n}.jsonl"
            try:
                total += descargar(n, ruta, args.max_items, schema_v2=args.schema_v2)
                exitosos.append(n)
            except KeyboardInterrupt:
                # No silenciar Ctrl+C
                print(f"\n[!] Interrumpido por el usuario en {n}")
                raise
            except Exception as exc:
                print(f"\n[!] FALLO {n}: {type(exc).__name__}: {str(exc)[:200]}")
                fallidos.append((n, str(exc)[:200]))
                # Sigue con el siguiente dataset
                continue

    print()
    print("=" * 60)
    print(f"RESUMEN DE DESCARGA")
    print("=" * 60)
    print(f"Total ejemplos descargados: {total}")
    print(f"Datasets exitosos ({len(exitosos)}): {', '.join(exitosos) if exitosos else '(ninguno)'}")
    if fallidos:
        print(f"Datasets fallidos ({len(fallidos)}):")
        for n, err in fallidos:
            print(f"  - {n}: {err}")
    print("=" * 60)


if __name__ == "__main__":
    main()
