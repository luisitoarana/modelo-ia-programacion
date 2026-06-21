"""Orquestador del Dataset V2 — corre los 10 generadores en serie y consolida.

Pipeline:
    1. ml.data.generar_pensamiento     → pensamiento_v1.jsonl
    2. ml.data.generar_multinivel      → multinivel_v1.jsonl
    3. ml.data.generar_antipatron      → antipatron_v1.jsonl
    4. ml.data.generar_bug_sutil       → bugs_v1.jsonl
    5. ml.data.generar_evolucion       → evolucion_v1.jsonl
    6. ml.data.generar_decision        → decision_v1.jsonl
    7. ml.data.generar_arquitectura    → arquitectura_v1.jsonl
    8. ml.data.generar_seguridad       → seguridad_v1.jsonl
    9. ml.data.generar_testing         → testing_v1.jsonl
   10. ml.data.generar_autocritica     → autocritica_v1.jsonl  (Nivel 12)

    → combinar + dedup global → dataset_v2.jsonl
    → audit del corpus consolidado

Uso (rápido, para pilotear que todo funcione):
    python -m ml.data.construir_dataset_v2 --salida-dir datasets/raw --escala mini

Uso (producción):
    python -m ml.data.construir_dataset_v2 --salida-dir datasets/raw --escala completa

Skip de generadores ya corridos (útil para reanudar tras fallo):
    python -m ml.data.construir_dataset_v2 --salida-dir datasets/raw \\
        --escala completa --skip pensamiento multinivel
"""

from __future__ import annotations

import argparse
import asyncio
import json
import sys
import time
from pathlib import Path
from typing import Any, Callable, Coroutine

from ml.data.audit import auditar, imprimir_humano
from ml.data.corpus import cargar_jsonl, deduplicar, guardar_jsonl
from ml.data.pool_generadores import Pool

# Importar las funciones generar_corpus de cada módulo
from ml.data import generar_pensamiento
from ml.data import generar_multinivel
from ml.data import generar_antipatron
from ml.data import generar_bug_sutil
from ml.data import generar_evolucion
from ml.data import generar_decision
from ml.data import generar_arquitectura
from ml.data import generar_seguridad
from ml.data import generar_testing
from ml.data import generar_autocritica


# ════════════════════════════════════════════════════════════════════
# Configuración de escala
# ════════════════════════════════════════════════════════════════════

# (nombre, parámetros para escala 'mini', 'media', 'completa')
ESCALAS: dict[str, dict[str, dict[str, Any]]] = {
    "mini": {
        # Solo para verificar que todo funciona end-to-end.
        # ~50-100 ejemplos por generador. ~10 minutos total.
        "pensamiento":   {"n_por_objetivo": 2},
        "multinivel":    {"repeticiones": 1},
        "antipatron":    {"n_por_antipatron": 2},
        "bug_sutil":     {"n_por_categoria": 2},
        "evolucion":     {},
        "decision":      {"repeticiones": 1},
        "arquitectura":  {"repeticiones": 1},
        "seguridad":     {"n_por_categoria": 2},
        "testing":       {"repeticiones": 1},
        "autocritica":   {"repeticiones": 1},
    },
    "media": {
        # Volumen razonable para experimentos. ~5k ejemplos total.
        "pensamiento":   {"n_por_objetivo": 4},
        "multinivel":    {"repeticiones": 2},
        "antipatron":    {"n_por_antipatron": 4},
        "bug_sutil":     {"n_por_categoria": 4},
        "evolucion":     {},
        "decision":      {"repeticiones": 2},
        "arquitectura":  {"repeticiones": 2},
        "seguridad":     {"n_por_categoria": 4},
        "testing":       {"repeticiones": 2},
        "autocritica":   {"repeticiones": 2},
    },
    "completa": {
        # Target hacia el dataset V2 final (~146k nuevos del plan).
        "pensamiento":   {"n_por_objetivo": 8},
        "multinivel":    {"repeticiones": 4},
        "antipatron":    {"n_por_antipatron": 8},
        "bug_sutil":     {"n_por_categoria": 8},
        "evolucion":     {},  # 5 versiones x 15 problemas = fijo
        "decision":      {"repeticiones": 5},
        "arquitectura":  {"repeticiones": 5},
        "seguridad":     {"n_por_categoria": 8},
        "testing":       {"repeticiones": 4},
        "autocritica":   {"repeticiones": 5},
    },
}


# (nombre, módulo, función que recibe pool/salida/**kwargs y devuelve dict de stats)
GENERADORES: list[tuple[str, Callable[..., Coroutine[Any, Any, dict[str, Any]]]]] = [
    ("pensamiento",  generar_pensamiento.generar_corpus),
    ("multinivel",   generar_multinivel.generar_corpus),
    ("antipatron",   generar_antipatron.generar_corpus),
    ("bug_sutil",    generar_bug_sutil.generar_corpus),
    ("evolucion",    generar_evolucion.generar_corpus),
    ("decision",     generar_decision.generar_corpus),
    ("arquitectura", generar_arquitectura.generar_corpus),
    ("seguridad",    generar_seguridad.generar_corpus),
    ("testing",      generar_testing.generar_corpus),
    ("autocritica",  generar_autocritica.generar_corpus),
]


# ════════════════════════════════════════════════════════════════════
# Orquestación
# ════════════════════════════════════════════════════════════════════

async def correr_pipeline(
    salida_dir: Path,
    escala: str,
    *,
    skip: set[str],
    temperatura: float,
) -> dict[str, Any]:
    config = ESCALAS[escala]
    pool = Pool.desde_env()
    print(f"\n=== Pool activo: {pool.disponibles} ===")
    print(f"=== Escala: {escala} ===\n")

    salida_dir.mkdir(parents=True, exist_ok=True)
    stats_por_gen: dict[str, dict[str, Any]] = {}
    inicio_total = time.time()

    for nombre, fn_generar in GENERADORES:
        if nombre in skip:
            print(f"\n>>> SKIP {nombre} <<<\n")
            continue

        salida = salida_dir / f"{nombre}_v1.jsonl"
        if salida.exists() and salida.stat().st_size > 0:
            print(f"\n>>> {nombre}: ya existe {salida.name}, salto (use --reset para regenerar) <<<\n")
            continue

        print(f"\n{'='*60}")
        print(f"  GENERADOR: {nombre}")
        print(f"{'='*60}")
        params = dict(config.get(nombre, {}))
        params["temperatura"] = temperatura
        try:
            stats = await fn_generar(pool, salida, **params)
            stats_por_gen[nombre] = stats
            print(f"\n>>> {nombre}: {stats.get('total', 0)} ejemplos, "
                  f"{stats.get('tiempo_minutos', 0)} min <<<")
        except Exception as exc:
            print(f"\n>>> {nombre}: FALLO — {exc} <<<", file=sys.stderr)
            stats_por_gen[nombre] = {"error": str(exc)}

    # Consolidar.
    print(f"\n{'='*60}")
    print("  CONSOLIDANDO CORPUS FINAL")
    print(f"{'='*60}\n")
    salida_consolidada = salida_dir / "dataset_v2.jsonl"
    todos = []
    for nombre, _ in GENERADORES:
        ruta = salida_dir / f"{nombre}_v1.jsonl"
        if ruta.exists():
            ejemplos = cargar_jsonl(ruta)
            todos.extend(ejemplos)
            print(f"  +{nombre}: {len(ejemplos)} ejemplos cargados")

    antes = len(todos)
    todos = deduplicar(todos)
    print(f"\n  Total bruto: {antes}")
    print(f"  Duplicados eliminados: {antes - len(todos)}")
    print(f"  Total final: {len(todos)}")

    guardar_jsonl(todos, salida_consolidada)
    print(f"  Guardado en: {salida_consolidada}")

    # Auditoría final.
    print(f"\n{'='*60}")
    print("  AUDITORIA DEL CORPUS CONSOLIDADO")
    print(f"{'='*60}\n")
    reporte = auditar(todos)
    imprimir_humano(reporte)

    tiempo_total_min = (time.time() - inicio_total) / 60

    resumen = {
        "escala": escala,
        "tiempo_total_minutos": round(tiempo_total_min, 1),
        "archivo_consolidado": str(salida_consolidada),
        "total_ejemplos_final": len(todos),
        "duplicados_eliminados": antes - len(todos),
        "stats_por_generador": stats_por_gen,
        "auditoria": reporte,
        "pool_stats_final": pool.stats(),
    }

    # Guardar resumen JSON para registro de la tesis.
    Path(salida_dir / "resumen_construccion.json").write_text(
        json.dumps(resumen, indent=2, ensure_ascii=False), encoding="utf-8",
    )
    return resumen


# ════════════════════════════════════════════════════════════════════
# CLI
# ════════════════════════════════════════════════════════════════════

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--salida-dir", required=True,
                        help="Directorio donde se guardan los JSONL por generador y el final")
    parser.add_argument("--escala", choices=["mini", "media", "completa"], default="mini",
                        help="mini = test rapido; media = experimentos; completa = produccion")
    parser.add_argument("--skip", nargs="*", default=[],
                        help="Nombres de generadores a saltar (p.ej. pensamiento multinivel)")
    parser.add_argument("--temperatura", type=float, default=0.85)
    parser.add_argument("--reset", action="store_true",
                        help="Borra JSONL existentes en salida-dir antes de empezar")
    args = parser.parse_args()

    salida_dir = Path(args.salida_dir)
    skip = set(args.skip)

    if args.reset:
        for nombre, _ in GENERADORES:
            f = salida_dir / f"{nombre}_v1.jsonl"
            if f.exists():
                f.unlink()
                print(f"[reset] borrado: {f}")
        consolidado = salida_dir / "dataset_v2.jsonl"
        if consolidado.exists():
            consolidado.unlink()

    nombres_validos = {n for n, _ in GENERADORES}
    invalidos = skip - nombres_validos
    if invalidos:
        print(f"ERROR: --skip contiene generadores desconocidos: {invalidos}")
        print(f"Validos: {sorted(nombres_validos)}")
        raise SystemExit(2)

    resumen = asyncio.run(correr_pipeline(
        salida_dir, args.escala,
        skip=skip,
        temperatura=args.temperatura,
    ))

    print(f"\n{'='*60}")
    print(f"  TIEMPO TOTAL: {resumen['tiempo_total_minutos']} min")
    print(f"  EJEMPLOS FINALES: {resumen['total_ejemplos_final']}")
    print(f"  ARCHIVO: {resumen['archivo_consolidado']}")
    print(f"{'='*60}")


if __name__ == "__main__":
    main()
