"""Auditoría de calidad del dataset.

Reporta métricas que decidieron si un corpus está listo para entrenar:

    - % de ejemplos válidos según validadores V2
    - duplicados
    - distribución por tipo / nivel / tema / fuente
    - estadísticas de longitud (chars y aprox tokens)
    - % de código en bloques que compila (ast.parse OK)
    - % de ejemplos con CoT, multinivel, revisión, puntuación
    - bilingüismo aproximado es/en

Uso:
    python -m ml.data.audit --corpus data/dataset_v2.jsonl

    # Salida JSON para CI:
    python -m ml.data.audit --corpus data/dataset_v2.jsonl --json
"""

from __future__ import annotations

import argparse
import json
import re
from collections import Counter
from pathlib import Path
from statistics import mean, median
from typing import Any

from ml.data.corpus import cargar_jsonl
from ml.data.schema import EjemploEntrenamiento
from ml.data.validadores import validar_codigo_python, validar_ejemplo

# Targets recomendados — la auditoría avisa si no se cumplen.
OBJETIVOS = {
    "pct_validos_min": 98.0,
    "pct_duplicados_max": 1.0,
    "pct_codigo_compila_min": 95.0,
    "pct_cot_poblado_min": 30.0,
    "tema_dominante_max": 25.0,
    "longitud_chars_min": 60,
    "longitud_chars_max_promedio": 5000,
}


_FENCE_RE = re.compile(r"```(?:python|py)?\s*\n?(.*?)```", re.DOTALL | re.IGNORECASE)


def _bloques_codigo(texto: str) -> list[str]:
    return [m.group(1).strip() for m in _FENCE_RE.finditer(texto) if m.group(1).strip()]


def _pct(numerador: int, denominador: int) -> float:
    return round(100 * numerador / denominador, 2) if denominador else 0.0


def _es_principalmente_espanol(texto: str) -> bool:
    """Heurística: presencia de tildes, ñ o palabras muy frecuentes en es."""
    indicadores = ("ó", "á", "é", "í", "ú", "ñ", "¿", "¡", " que ", " para ", " con ", " esto ", " porque ")
    score = sum(1 for ind in indicadores if ind in texto.lower())
    return score >= 3


def auditar(ejemplos: list[EjemploEntrenamiento]) -> dict[str, Any]:
    total = len(ejemplos)
    if total == 0:
        return {"error": "corpus vacío", "total": 0}

    # Validación + dedup.
    descartados: Counter[str] = Counter()
    validos: list[EjemploEntrenamiento] = []
    for ej in ejemplos:
        ok, motivo = validar_ejemplo(ej)
        if ok:
            validos.append(ej)
        else:
            descartados[motivo.split(":", 1)[0]] += 1

    claves_dedup = Counter(ej.clave_dedup() for ej in ejemplos)
    duplicados = sum(c - 1 for c in claves_dedup.values() if c > 1)

    # Distribuciones.
    por_nivel = Counter(ej.nivel for ej in ejemplos)
    por_tema = Counter(ej.tema for ej in ejemplos)
    por_tipo = Counter(ej.tipo for ej in ejemplos)
    por_fuente = Counter(ej.fuente for ej in ejemplos)

    # Longitudes (chars).
    longitudes_instr = [len(ej.instruccion) for ej in ejemplos]
    longitudes_salida = [len(ej.salida) for ej in ejemplos]

    # Código que compila.
    bloques_total = 0
    bloques_ok = 0
    for ej in ejemplos:
        for bloque in _bloques_codigo(ej.salida):
            bloques_total += 1
            ok, _ = validar_codigo_python(bloque)
            if ok:
                bloques_ok += 1

    # Campos V2 poblados.
    con_cot = sum(1 for ej in ejemplos if ej.pensamiento is not None)
    con_multinivel = sum(1 for ej in ejemplos if ej.explicacion_por_nivel is not None)
    con_revision = sum(1 for ej in ejemplos if ej.revision_codigo is not None)
    con_puntuacion = sum(1 for ej in ejemplos if ej.puntuacion is not None)
    con_version_evol = sum(1 for ej in ejemplos if ej.version_evolutiva is not None)

    # Bilingüismo.
    es = sum(1 for ej in ejemplos if _es_principalmente_espanol(ej.instruccion + " " + ej.salida))

    pct_validos = _pct(len(validos), total)
    pct_duplicados = _pct(duplicados, total)
    pct_codigo_compila = _pct(bloques_ok, bloques_total) if bloques_total else 100.0
    pct_cot = _pct(con_cot, total)
    pct_es = _pct(es, total)

    tema_dominante = por_tema.most_common(1)[0] if por_tema else ("-", 0)
    pct_tema_dominante = _pct(tema_dominante[1], total)

    advertencias: list[str] = []
    if pct_validos < OBJETIVOS["pct_validos_min"]:
        advertencias.append(
            f"pct_validos={pct_validos}% < objetivo {OBJETIVOS['pct_validos_min']}%"
        )
    if pct_duplicados > OBJETIVOS["pct_duplicados_max"]:
        advertencias.append(
            f"pct_duplicados={pct_duplicados}% > objetivo {OBJETIVOS['pct_duplicados_max']}%"
        )
    if pct_codigo_compila < OBJETIVOS["pct_codigo_compila_min"]:
        advertencias.append(
            f"pct_codigo_compila={pct_codigo_compila}% < objetivo "
            f"{OBJETIVOS['pct_codigo_compila_min']}%"
        )
    if pct_cot < OBJETIVOS["pct_cot_poblado_min"]:
        advertencias.append(
            f"pct_cot_poblado={pct_cot}% < objetivo {OBJETIVOS['pct_cot_poblado_min']}%  "
            f"(necesario para que el modelo razone)"
        )
    if pct_tema_dominante > OBJETIVOS["tema_dominante_max"]:
        advertencias.append(
            f"tema '{tema_dominante[0]}' domina con {pct_tema_dominante}% > "
            f"{OBJETIVOS['tema_dominante_max']}% (rebalancear)"
        )

    return {
        "total": total,
        "validos": len(validos),
        "pct_validos": pct_validos,
        "duplicados": duplicados,
        "pct_duplicados": pct_duplicados,
        "descartados_por_motivo": dict(descartados),

        "por_nivel": dict(por_nivel),
        "por_tema": dict(por_tema),
        "por_tipo": dict(por_tipo),
        "por_fuente": dict(por_fuente),

        "longitud_chars": {
            "instruccion": {
                "promedio": round(mean(longitudes_instr), 1),
                "mediana": median(longitudes_instr),
                "max": max(longitudes_instr),
            },
            "salida": {
                "promedio": round(mean(longitudes_salida), 1),
                "mediana": median(longitudes_salida),
                "max": max(longitudes_salida),
            },
        },

        "codigo": {
            "bloques_totales": bloques_total,
            "bloques_compilan": bloques_ok,
            "pct_compila": pct_codigo_compila,
        },

        "campos_v2": {
            "con_pensamiento": con_cot,
            "pct_pensamiento": pct_cot,
            "con_multinivel": con_multinivel,
            "con_revision": con_revision,
            "con_puntuacion": con_puntuacion,
            "con_version_evolutiva": con_version_evol,
        },

        "idioma": {
            "principalmente_espanol": es,
            "pct_espanol": pct_es,
        },

        "tema_dominante": {
            "nombre": tema_dominante[0],
            "cantidad": tema_dominante[1],
            "porcentaje": pct_tema_dominante,
        },

        "advertencias": advertencias,
        "ok_para_entrenar": len(advertencias) == 0,
    }


def imprimir_humano(reporte: dict[str, Any]) -> None:
    print("=" * 60)
    print(f"  AUDITORIA DE DATASET — {reporte['total']} ejemplos")
    print("=" * 60)

    print(f"\nVálidos: {reporte['validos']} ({reporte['pct_validos']}%)")
    print(f"Duplicados: {reporte['duplicados']} ({reporte['pct_duplicados']}%)")
    if reporte["descartados_por_motivo"]:
        print("Descartes por motivo:")
        for motivo, n in sorted(reporte["descartados_por_motivo"].items(),
                                key=lambda x: -x[1]):
            print(f"    {motivo}: {n}")

    print("\nDistribución por tipo:")
    for tipo, n in sorted(reporte["por_tipo"].items(), key=lambda x: -x[1]):
        print(f"    {tipo:<28} {n:>6} ({_pct(n, reporte['total'])}%)")

    print("\nDistribución por nivel:")
    for nivel, n in reporte["por_nivel"].items():
        print(f"    {nivel:<12} {n:>6} ({_pct(n, reporte['total'])}%)")

    print(f"\nTema dominante: {reporte['tema_dominante']['nombre']} "
          f"({reporte['tema_dominante']['porcentaje']}%)")

    print(f"\nLongitud salida: media {reporte['longitud_chars']['salida']['promedio']} chars, "
          f"max {reporte['longitud_chars']['salida']['max']}")

    print(f"\nCódigo: {reporte['codigo']['bloques_compilan']}/{reporte['codigo']['bloques_totales']} "
          f"bloques compilan ({reporte['codigo']['pct_compila']}%)")

    print(f"\nCampos V2:")
    for k, v in reporte["campos_v2"].items():
        print(f"    {k:<28} {v}")

    print(f"\nIdioma: {reporte['idioma']['pct_espanol']}% principalmente español")

    if reporte["advertencias"]:
        print("\n[AVISO] Advertencias:")
        for adv in reporte["advertencias"]:
            print(f"    - {adv}")
        print("\n=> Corpus NO listo para entrenar.")
    else:
        print("\n[OK] Corpus pasa todos los umbrales objetivo. LISTO para entrenar.")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--corpus", required=True, help="Ruta a .jsonl del corpus")
    parser.add_argument("--json", action="store_true",
                        help="Salida en JSON (para CI/scripts)")
    parser.add_argument("--salida-reporte", default=None,
                        help="Guarda reporte JSON en archivo")
    args = parser.parse_args()

    ruta = Path(args.corpus)
    if not ruta.exists():
        print(f"ERROR: no existe {ruta}")
        raise SystemExit(2)

    ejemplos = cargar_jsonl(ruta)
    reporte = auditar(ejemplos)

    if args.salida_reporte:
        Path(args.salida_reporte).write_text(
            json.dumps(reporte, indent=2, ensure_ascii=False), encoding="utf-8"
        )

    if args.json:
        print(json.dumps(reporte, indent=2, ensure_ascii=False))
    else:
        imprimir_humano(reporte)

    raise SystemExit(0 if reporte.get("ok_para_entrenar") else 1)


if __name__ == "__main__":
    main()
