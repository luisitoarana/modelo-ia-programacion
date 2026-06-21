"""Herramientas para extraer y reparar JSON proveniente de LLMs.

Los LLMs a menudo retornan JSON envuelto en bloques de markdown
(```json ... ```), con comas finales, comentarios o texto narrativo
alrededor. Esta utilidad intenta recuperar un objeto JSON válido sin
modificar la semántica.
"""

from __future__ import annotations

import json
import re
from typing import Any

# Bloques markdown ```json ... ``` o ``` ... ```
_PATRON_BLOQUE_MARKDOWN = re.compile(
    r"```(?:json|JSON)?\s*(.*?)\s*```",
    re.DOTALL,
)

# Coma final antes de } o ]
_PATRON_COMA_FINAL = re.compile(r",\s*([}\]])")


class JSONIrrecuperableError(ValueError):
    """Se lanza cuando el JSON no se puede parsear ni siquiera reparado."""


def _extraer_bloque_json(texto: str) -> str:
    """Devuelve el primer fragmento que parece JSON dentro del texto."""
    texto = texto.strip()

    # 1) Si viene en bloque markdown, lo extraemos
    coincidencia = _PATRON_BLOQUE_MARKDOWN.search(texto)
    if coincidencia:
        return coincidencia.group(1).strip()

    # 2) Buscamos el primer '{' y el último '}' balanceados
    inicio = texto.find("{")
    fin = texto.rfind("}")
    if inicio != -1 and fin != -1 and fin > inicio:
        return texto[inicio : fin + 1].strip()

    return texto


def _reparaciones_basicas(texto: str) -> str:
    """Aplica heurísticas seguras: quita BOM, normaliza comillas, comas."""
    if texto.startswith("﻿"):
        texto = texto.lstrip("﻿")
    texto = texto.replace("“", '"').replace("”", '"')
    texto = texto.replace("‘", "'").replace("’", "'")
    texto = _PATRON_COMA_FINAL.sub(r"\1", texto)
    return texto


def parsear_json_lenient(texto: str) -> dict[str, Any]:
    """Intenta parsear JSON desde una salida cruda de LLM.

    Estrategia:
      1) Extraer bloque candidato.
      2) Intentar json.loads directo.
      3) Aplicar reparaciones cosméticas seguras y reintentar.
      4) Si todo falla, lanzar JSONIrrecuperableError.
    """
    if not texto or not texto.strip():
        raise JSONIrrecuperableError("Respuesta vacía del modelo.")

    candidato = _extraer_bloque_json(texto)

    try:
        return json.loads(candidato)
    except json.JSONDecodeError:
        pass

    reparado = _reparaciones_basicas(candidato)
    try:
        return json.loads(reparado)
    except json.JSONDecodeError as exc:
        raise JSONIrrecuperableError(
            f"JSON inválido tras reparación básica: {exc.msg} en pos {exc.pos}"
        ) from exc


def construir_prompt_reparacion(json_invalido: str, error_msg: str) -> str:
    """Genera un prompt para pedir al LLM que corrija su salida."""
    return (
        "Tu respuesta anterior NO es JSON válido y rompió el parser del sistema.\n"
        f"Error reportado: {error_msg}\n\n"
        "REGLAS ABSOLUTAS:\n"
        "1. Devuelve EXCLUSIVAMENTE un objeto JSON válido.\n"
        "2. NO uses markdown, NO uses ``` de ningún tipo.\n"
        "3. NO agregues texto antes ni después del JSON.\n"
        "4. NO uses comentarios. NO uses comas finales.\n"
        "5. Usa comillas dobles \" para todas las claves y strings.\n"
        "6. Mantén la MISMA estructura y contenido educativo, solo corrige la forma.\n\n"
        "Respuesta corrupta a corregir:\n"
        f"<<<\n{json_invalido}\n>>>\n\n"
        "Devuelve ahora SOLO el JSON corregido:"
    )
