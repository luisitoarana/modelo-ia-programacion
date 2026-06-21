"""Combina, limpia y deduplica varios corpus JSONL en uno solo.

Útil cuando descargas datasets de distintas fuentes (CodeAlpaca,
CodeFeedback, alpaca-es, tu propio generador) y necesitas fusionarlos
en un único archivo para alimentar a `ml/train.py` o `ml/finetune.py`.

Operaciones que hace:
  1. Lee N archivos JSONL.
  2. Normaliza cada ejemplo a un formato canónico:
        {"instruction": str, "input": str, "response": str}
  3. Filtra:
        - Ejemplos vacíos (instruction o response < N chars)
        - Ejemplos demasiado largos (más de max-chars)
        - Líneas con JSON inválido
  4. Deduplica por hash del par (instruction + response).
  5. Mezcla aleatoriamente (con semilla para reproducibilidad).
  6. (Opcional) limita a max-items totales.
  7. (Opcional) reserva un % para validación.

Uso:
    # Combinar todo en uno
    python -m ml.data.combinar \\
        --entradas datasets/raw/codealpaca.jsonl \\
                   datasets/raw/codefeedback.jsonl \\
                   datasets/raw/alpaca_es.jsonl \\
                   datasets/raw/generado_deepseek.jsonl \\
        --salida datasets/processed/corpus_combinado.jsonl

    # Con split de validación 10%
    python -m ml.data.combinar \\
        --entradas datasets/raw/*.jsonl \\
        --salida datasets/processed/train.jsonl \\
        --validacion datasets/processed/val.jsonl \\
        --pct-validacion 10

    # Limitar tamaño total (útil para iterar rápido)
    python -m ml.data.combinar \\
        --entradas datasets/raw/*.jsonl \\
        --salida datasets/processed/corpus_5k.jsonl \\
        --max-items 5000
"""

from __future__ import annotations

import argparse
import hashlib
import json
import random
import sys
from pathlib import Path


# ───────────────────────────── Normalización ─────────────────────────────

def _inferir_tipo_y_tema(instruccion: str, salida: str) -> tuple[str, str]:
    """Heurística simple para asignar tipo + tema válidos del schema."""
    txt = (instruccion + " " + salida).lower()
    # tipo
    if any(k in txt for k in ("error", "bug", "incorrecto", "corrig")):
        tipo = "correccion_error"
    elif any(k in txt for k in ("explic", "qué es", "por qué", "como funciona")):
        tipo = "explicacion_codigo"
    elif any(k in txt for k in ("escrib", "genera", "crea", "implementa", "write a")):
        tipo = "generacion_codigo"
    else:
        tipo = "concepto"
    # tema
    if "def " in salida or "función" in txt or "function" in txt:
        tema = "funciones"
    elif "class " in salida or "clase" in txt or "objeto" in txt:
        tema = "oop"
    elif "for " in salida or "while " in salida or "bucle" in txt or "loop" in txt:
        tema = "bucles"
    elif "try:" in salida or "except" in salida or "excepc" in txt or "error" in txt:
        tema = "excepciones"
    elif "list" in txt or "dict" in txt or "diccionario" in txt or "tupla" in txt:
        tema = "estructuras"
    elif "algoritmo" in txt or "ordenamiento" in txt or "complejidad" in txt:
        tema = "algoritmos"
    elif "archivo" in txt or "open(" in salida or "file" in txt:
        tema = "archivos"
    elif "variable" in txt or "asignaci" in txt:
        tema = "variables"
    else:
        tema = "otro"
    return tipo, tema


def _normalizar(ej: dict, fuente: str = "huggingface") -> dict | None:
    """Convierte cualquier formato al schema canónico del proyecto.

    Schema destino (ml/data/schema.py):
        {instruccion, entrada, salida, nivel, tema, tipo, fuente}
    """
    # Formato chat (lista de messages)
    if "messages" in ej and isinstance(ej["messages"], list):
        msgs = ej["messages"]
        user = next((m for m in msgs if m.get("role") == "user"), None)
        ai = next((m for m in msgs if m.get("role") == "assistant"), None)
        if not user or not ai:
            return None
        instr = (user.get("content") or "").strip()
        inp = ""
        salida = (ai.get("content") or "").strip()
    else:
        # Si ya viene en formato del proyecto (campos en español).
        instr = (
            ej.get("instruccion")
            or ej.get("instruction")
            or ej.get("pregunta")
            or ej.get("prompt")
            or ej.get("query")
            or ""
        )
        inp = ej.get("entrada") or ej.get("input") or ""
        salida = (
            ej.get("salida")
            or ej.get("response")
            or ej.get("output")
            or ej.get("respuesta")
            or ej.get("answer")
            or ""
        )

    if not instr or not salida:
        return None

    tipo, tema = _inferir_tipo_y_tema(str(instr), str(salida))
    return {
        "instruccion": str(instr).strip(),
        "entrada": str(inp).strip(),
        "salida": str(salida).strip(),
        "nivel": ej.get("nivel") or "intermedio",  # default razonable
        "tema": ej.get("tema") or tema,
        "tipo": ej.get("tipo") or tipo,
        "fuente": ej.get("fuente") or fuente,
    }


def _hash_ejemplo(ej: dict) -> str:
    """Hash para deduplicación: MD5 del par instruccion+salida."""
    clave = (ej["instruccion"].lower() + "||" + ej["salida"].lower()).encode()
    return hashlib.md5(clave).hexdigest()


def _es_valido(ej: dict, min_instr: int, min_resp: int, max_total: int) -> bool:
    li = len(ej["instruccion"])
    lr = len(ej["salida"])
    if li < min_instr or lr < min_resp:
        return False
    if li + lr > max_total:
        return False
    return True


# ───────────────────────────── Carga ─────────────────────────────

def _cargar_archivo(ruta: Path) -> list[dict]:
    ejs = []
    invalidos = 0
    with open(ruta, "r", encoding="utf-8") as f:
        for linea in f:
            linea = linea.strip()
            if not linea:
                continue
            try:
                ejs.append(json.loads(linea))
            except json.JSONDecodeError:
                invalidos += 1
    if invalidos:
        print(f"   ⚠ {invalidos} líneas con JSON inválido en {ruta.name}")
    return ejs


# ───────────────────────────── Main ─────────────────────────────

def main() -> None:
    p = argparse.ArgumentParser(
        description="Combina, limpia y deduplica varios corpus JSONL.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    p.add_argument(
        "--entradas",
        nargs="+",
        required=True,
        help="Uno o más archivos JSONL de entrada.",
    )
    p.add_argument(
        "--salida",
        required=True,
        help="JSONL combinado de salida (corpus de entrenamiento).",
    )
    p.add_argument(
        "--validacion",
        default=None,
        help="(Opcional) JSONL para el split de validación.",
    )
    p.add_argument(
        "--pct-validacion",
        type=float,
        default=0.0,
        help="Porcentaje de ejemplos reservado a validación (0-50). Default: 0.",
    )
    p.add_argument(
        "--max-items",
        type=int,
        default=None,
        help="Tope total de ejemplos tras filtros.",
    )
    p.add_argument(
        "--min-instr",
        type=int,
        default=10,
        help="Mínimo de caracteres en la instrucción. Default: 10.",
    )
    p.add_argument(
        "--min-resp",
        type=int,
        default=20,
        help="Mínimo de caracteres en la respuesta. Default: 20.",
    )
    p.add_argument(
        "--max-total",
        type=int,
        default=8000,
        help="Máximo de caracteres (instr + resp). Default: 8000.",
    )
    p.add_argument(
        "--seed",
        type=int,
        default=42,
        help="Semilla para mezclar y split de validación.",
    )
    args = p.parse_args()

    # ── Validar argumentos ──
    if args.pct_validacion < 0 or args.pct_validacion > 50:
        print("❌ --pct-validacion debe estar entre 0 y 50.")
        sys.exit(1)
    if args.pct_validacion > 0 and not args.validacion:
        print("❌ Si pides --pct-validacion debes pasar --validacion <ruta.jsonl>.")
        sys.exit(1)

    # ── Cargar y normalizar ──
    print(f"📂 Leyendo {len(args.entradas)} archivo(s)…")
    todos_raw: list[tuple[dict, str]] = []  # (ejemplo, fuente)
    por_archivo: list[tuple[str, int]] = []
    for ruta_str in args.entradas:
        ruta = Path(ruta_str)
        if not ruta.exists():
            print(f"   ⚠ no existe (saltado): {ruta}")
            continue
        ejs = _cargar_archivo(ruta)
        # Etiqueta de fuente derivada del nombre de archivo
        fuente = ruta.stem.replace("generado_", "")
        por_archivo.append((ruta.name, len(ejs)))
        for ej in ejs:
            todos_raw.append((ej, fuente))
        print(f"   {ruta.name}: {len(ejs):>6} crudos  (fuente='{fuente}')")

    if not todos_raw:
        print("❌ No se cargó ningún ejemplo. Revisa las rutas.")
        sys.exit(1)
    print(f"   Total crudo: {len(todos_raw)}")
    print()

    # ── Normalizar ──
    print("🔧 Normalizando al schema del proyecto…")
    normalizados: list[dict] = []
    para_drop_formato = 0
    for ej, fuente in todos_raw:
        n = _normalizar(ej, fuente=fuente)
        if n is None:
            para_drop_formato += 1
            continue
        normalizados.append(n)
    print(f"   {len(normalizados)} normalizados, {para_drop_formato} descartados por formato.")

    # ── Filtrar ──
    print(f"🧹 Filtrando (instr≥{args.min_instr}, resp≥{args.min_resp}, total≤{args.max_total} chars)…")
    validos = [
        ej for ej in normalizados
        if _es_valido(ej, args.min_instr, args.min_resp, args.max_total)
    ]
    print(f"   {len(validos)} válidos ({len(normalizados) - len(validos)} descartados por longitud).")

    # ── Deduplicar ──
    print("🪞 Deduplicando…")
    vistos: set[str] = set()
    unicos: list[dict] = []
    for ej in validos:
        h = _hash_ejemplo(ej)
        if h in vistos:
            continue
        vistos.add(h)
        unicos.append(ej)
    print(f"   {len(unicos)} únicos ({len(validos) - len(unicos)} duplicados eliminados).")

    # ── Mezclar ──
    rng = random.Random(args.seed)
    rng.shuffle(unicos)

    # ── Limitar tamaño ──
    if args.max_items and len(unicos) > args.max_items:
        unicos = unicos[: args.max_items]
        print(f"✂  Recortado a max-items: {len(unicos)}")

    # ── Split train/val ──
    if args.pct_validacion > 0:
        n_val = int(len(unicos) * args.pct_validacion / 100)
        val_set = unicos[:n_val]
        train_set = unicos[n_val:]
    else:
        val_set = []
        train_set = unicos

    # ── Guardar ──
    salida_train = Path(args.salida)
    salida_train.parent.mkdir(parents=True, exist_ok=True)
    with open(salida_train, "w", encoding="utf-8") as f:
        for ej in train_set:
            f.write(json.dumps(ej, ensure_ascii=False) + "\n")

    if val_set:
        salida_val = Path(args.validacion)
        salida_val.parent.mkdir(parents=True, exist_ok=True)
        with open(salida_val, "w", encoding="utf-8") as f:
            for ej in val_set:
                f.write(json.dumps(ej, ensure_ascii=False) + "\n")

    # ── Reporte final ──
    print()
    print("=" * 60)
    print("✓ COMBINACIÓN COMPLETA")
    print("=" * 60)
    print(f"  Entradas:      {sum(c for _, c in por_archivo)} crudos de {len(por_archivo)} archivos")
    print(f"  Tras filtros:  {len(unicos)} ejemplos únicos válidos")
    print(f"  Train:         {len(train_set)} → {salida_train}")
    if val_set:
        print(f"  Validación:    {len(val_set)} → {Path(args.validacion)}")
    print()

    # Estadísticas de longitud
    if train_set:
        len_instr = [len(e["instruccion"]) for e in train_set]
        len_resp = [len(e["salida"]) for e in train_set]
        print("  📊 Longitudes (caracteres):")
        print(f"     instrucción: media {sum(len_instr)//len(len_instr)}, "
              f"min {min(len_instr)}, max {max(len_instr)}")
        print(f"     salida:      media {sum(len_resp)//len(len_resp)}, "
              f"min {min(len_resp)}, max {max(len_resp)}")
        chars_totales = sum(len_instr) + sum(len_resp)
        tokens_aprox = chars_totales // 4  # ~4 chars/token
        print(f"     ~{tokens_aprox // 1_000_000} M tokens estimados en el corpus.")
        # Distribución por tipo y tema (sample)
        from collections import Counter
        tipos = Counter(e["tipo"] for e in train_set)
        temas = Counter(e["tema"] for e in train_set)
        print(f"  📊 Tipos: {dict(tipos.most_common(5))}")
        print(f"  📊 Temas: {dict(temas.most_common(8))}")


if __name__ == "__main__":
    main()
