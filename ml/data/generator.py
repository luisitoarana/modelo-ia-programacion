"""Dataset Generator: usa Gemini/DeepSeek SOLO para crear datos de entrenamiento.

Este es el ÚNICO punto del sistema donde se llaman APIs externas. Generan
ejemplos educativos en el formato de entrenamiento, que luego se validan
localmente y se consolidan en el corpus con el que se entrena el modelo propio.

Uso:
    python -m ml.data.generator --proveedor gemini --por-objetivo 8 \
        --salida datasets/raw/generado_gemini.jsonl

Requiere GEMINI_API_KEY o DEEPSEEK_API_KEY en el entorno o en .env.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import re
from dataclasses import dataclass
from pathlib import Path

from ml.data.corpus import deduplicar, estadisticas_corpus, filtrar_validos, guardar_jsonl
from ml.data.schema import EjemploEntrenamiento


# Objetivos de generación (tema, nivel) alineados con el currículo educativo.
OBJETIVOS: tuple[tuple[str, str], ...] = (
    ("variables", "basico"),
    ("bucles", "basico"),
    ("funciones", "basico"),
    ("funciones", "intermedio"),
    ("estructuras", "intermedio"),
    ("excepciones", "intermedio"),
    ("oop", "intermedio"),
    ("oop", "avanzado"),
    ("algoritmos", "intermedio"),
    ("algoritmos", "avanzado"),
)

_PROMPT = """Eres un generador de DATASET para entrenar un modelo educativo de Python.
Genera {n} ejemplos variados de enseñanza sobre el tema "{tema}" para nivel "{nivel}".

Devuelve EXCLUSIVAMENTE un array JSON válido (sin markdown, sin ```), donde cada
elemento tenga EXACTAMENTE estas claves:
  "instruccion": petición clara en español (explicar, generar, corregir, etc.)
  "entrada": código Python de contexto si aplica, o cadena vacía ""
  "salida": respuesta pedagógica clara que explique el porqué, no solo el qué
  "nivel": "{nivel}"
  "tema": "{tema}"
  "tipo": uno de explicacion_codigo|generacion_codigo|concepto|explicacion_linea|actividad|correccion_error|comprension

Reglas: español correcto, código Python válido y limpio (sin ```), explicaciones
con enfoque en comprensión algorítmica. Varía los tipos. Solo el array JSON."""


def _cargar_env() -> None:
    """Carga .env de forma simple si las claves no están en el entorno."""
    if os.environ.get("GEMINI_API_KEY") or os.environ.get("DEEPSEEK_API_KEY"):
        return
    for ruta in (Path(".env"), Path(__file__).resolve().parents[2] / ".env"):
        if ruta.exists():
            for linea in ruta.read_text(encoding="utf-8").splitlines():
                linea = linea.strip()
                if not linea or linea.startswith("#") or "=" not in linea:
                    continue
                k, _, v = linea.partition("=")
                os.environ.setdefault(k.strip(), v.strip())
            break


def _extraer_json_array(texto: str) -> list[dict]:
    texto = texto.strip()
    m = re.search(r"```(?:json)?\s*(.*?)\s*```", texto, re.DOTALL)
    if m:
        texto = m.group(1).strip()
    inicio = texto.find("[")
    fin = texto.rfind("]")
    if inicio != -1 and fin != -1 and fin > inicio:
        texto = texto[inicio : fin + 1]
    try:
        data = json.loads(texto)
        return data if isinstance(data, list) else []
    except json.JSONDecodeError:
        return []


@dataclass(slots=True)
class _ClienteGemini:
    api_key: str
    modelo: str = "gemini-2.0-flash"
    base_url: str = "https://generativelanguage.googleapis.com/v1beta"

    async def generar(self, prompt: str) -> str:
        import httpx

        url = f"{self.base_url}/models/{self.modelo}:generateContent"
        cuerpo = {
            "contents": [{"role": "user", "parts": [{"text": prompt}]}],
            "generationConfig": {"temperature": 0.9, "maxOutputTokens": 4096},
        }
        async with httpx.AsyncClient(timeout=90) as c:
            r = await c.post(url, json=cuerpo, params={"key": self.api_key})
            r.raise_for_status()
            data = r.json()
        cands = data.get("candidates") or []
        if not cands:
            return ""
        partes = (cands[0].get("content") or {}).get("parts") or []
        return "".join(p.get("text", "") for p in partes)


@dataclass(slots=True)
class _ClienteDeepSeek:
    api_key: str
    modelo: str = "deepseek-chat"
    base_url: str = "https://api.deepseek.com/v1"

    async def generar(self, prompt: str) -> str:
        import httpx

        url = f"{self.base_url}/chat/completions"
        cuerpo = {
            "model": self.modelo,
            "messages": [{"role": "user", "content": prompt}],
            "temperature": 0.9,
            "max_tokens": 4096,
        }
        headers = {"Authorization": f"Bearer {self.api_key}"}
        async with httpx.AsyncClient(timeout=90) as c:
            r = await c.post(url, json=cuerpo, headers=headers)
            r.raise_for_status()
            data = r.json()
        return ((data.get("choices") or [{}])[0].get("message") or {}).get("content", "")


def _crear_cliente(proveedor: str):
    _cargar_env()
    if proveedor == "gemini":
        key = os.environ.get("GEMINI_API_KEY", "")
        if not key:
            raise SystemExit("Falta GEMINI_API_KEY en el entorno o .env")
        return _ClienteGemini(api_key=key, modelo=os.environ.get("GEMINI_MODEL", "gemini-2.0-flash"))
    key = os.environ.get("DEEPSEEK_API_KEY", "")
    if not key:
        raise SystemExit("Falta DEEPSEEK_API_KEY en el entorno o .env")
    return _ClienteDeepSeek(api_key=key, modelo=os.environ.get("DEEPSEEK_MODEL", "deepseek-chat"))


async def generar_objetivo(cliente, tema: str, nivel: str, n: int, proveedor: str) -> list[EjemploEntrenamiento]:
    prompt = _PROMPT.format(n=n, tema=tema, nivel=nivel)
    try:
        texto = await cliente.generar(prompt)
    except Exception as exc:  # noqa: BLE001
        print(f"  [!] Error generando {tema}/{nivel}: {exc}")
        return []
    bruto = _extraer_json_array(texto)
    salida: list[EjemploEntrenamiento] = []
    for d in bruto:
        if not isinstance(d, dict):
            continue
        d.setdefault("tema", tema)
        d.setdefault("nivel", nivel)
        d["fuente"] = proveedor
        salida.append(EjemploEntrenamiento.from_dict(d))
    return salida


async def generar_dataset(
    proveedor: str,
    por_objetivo: int,
    salida_jsonl: str,
) -> dict:
    cliente = _crear_cliente(proveedor)
    todos: list[EjemploEntrenamiento] = []
    for tema, nivel in OBJETIVOS:
        print(f"  Generando {por_objetivo} ejemplos de {tema}/{nivel} con {proveedor}...")
        lote = await generar_objetivo(cliente, tema, nivel, por_objetivo, proveedor)
        todos.extend(lote)

    validos, descartados = filtrar_validos(todos)
    validos = deduplicar(validos)
    guardar_jsonl(validos, salida_jsonl)
    stats = estadisticas_corpus(validos)
    stats["descartados"] = len(descartados)
    stats["archivo"] = salida_jsonl
    return stats


def main() -> None:
    parser = argparse.ArgumentParser(description="Genera dataset educativo con APIs.")
    parser.add_argument("--proveedor", default="gemini", choices=["gemini", "deepseek"])
    parser.add_argument("--por-objetivo", type=int, default=8)
    parser.add_argument("--salida", default="datasets/raw/generado.jsonl")
    args = parser.parse_args()

    stats = asyncio.run(
        generar_dataset(args.proveedor, args.por_objetivo, args.salida)
    )
    print("\n=== DATASET GENERADO ===")
    print(json.dumps(stats, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
