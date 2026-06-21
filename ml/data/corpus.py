"""Corpus Builder: cargar, consolidar, deduplicar y describir el corpus."""

from __future__ import annotations

import json
from collections import Counter
from pathlib import Path
from typing import Iterable

from ml.data.schema import EjemploEntrenamiento


def cargar_jsonl(ruta: str | Path) -> list[EjemploEntrenamiento]:
    ruta = Path(ruta)
    if not ruta.exists():
        return []
    ejemplos: list[EjemploEntrenamiento] = []
    for linea in ruta.read_text(encoding="utf-8").splitlines():
        linea = linea.strip()
        if not linea:
            continue
        try:
            ejemplos.append(EjemploEntrenamiento.from_dict(json.loads(linea)))
        except json.JSONDecodeError:
            continue
    return ejemplos


def guardar_jsonl(ejemplos: Iterable[EjemploEntrenamiento], ruta: str | Path) -> Path:
    ruta = Path(ruta)
    ruta.parent.mkdir(parents=True, exist_ok=True)
    with ruta.open("w", encoding="utf-8") as f:
        for ej in ejemplos:
            f.write(json.dumps(ej.to_dict(), ensure_ascii=False) + "\n")
    return ruta


def deduplicar(ejemplos: list[EjemploEntrenamiento]) -> list[EjemploEntrenamiento]:
    vistos: set[str] = set()
    salida: list[EjemploEntrenamiento] = []
    for ej in ejemplos:
        clave = ej.clave_dedup()
        if clave in vistos:
            continue
        vistos.add(clave)
        salida.append(ej)
    return salida


def filtrar_validos(
    ejemplos: list[EjemploEntrenamiento],
) -> tuple[list[EjemploEntrenamiento], list[tuple[EjemploEntrenamiento, str]]]:
    validos: list[EjemploEntrenamiento] = []
    descartados: list[tuple[EjemploEntrenamiento, str]] = []
    for ej in ejemplos:
        ok, motivo = ej.es_valido()
        if ok:
            validos.append(ej)
        else:
            descartados.append((ej, motivo))
    return validos, descartados


def estadisticas_corpus(ejemplos: list[EjemploEntrenamiento]) -> dict[str, object]:
    por_nivel: Counter[str] = Counter(ej.nivel for ej in ejemplos)
    por_tema: Counter[str] = Counter(ej.tema for ej in ejemplos)
    por_tipo: Counter[str] = Counter(ej.tipo for ej in ejemplos)
    por_fuente: Counter[str] = Counter(ej.fuente for ej in ejemplos)
    chars = sum(len(ej.instruccion) + len(ej.entrada) + len(ej.salida) for ej in ejemplos)
    return {
        "total": len(ejemplos),
        "caracteres_totales": chars,
        "por_nivel": dict(por_nivel),
        "por_tema": dict(por_tema),
        "por_tipo": dict(por_tipo),
        "por_fuente": dict(por_fuente),
    }


def construir_textos_tokenizer(ejemplos: list[EjemploEntrenamiento]) -> list[str]:
    """Texto plano para entrenar el tokenizer (sin tokens especiales)."""
    textos: list[str] = []
    for ej in ejemplos:
        textos.append(ej.instruccion)
        if ej.entrada.strip():
            textos.append(ej.entrada)
        textos.append(ej.salida)
    return textos
