"""Validadores de calidad para el dataset V2.

Cada validador retorna (ok, motivo). Se usan antes de aceptar un ejemplo
generado por una API externa. Sin estos filtros, el corpus se llena de
basura (los proveedores free alucinan más que los pago).

Uso típico:
    from ml.data.validadores import validar_ejemplo
    ok, motivo = validar_ejemplo(ejemplo)
    if not ok:
        descartar(ejemplo, motivo)
"""

from __future__ import annotations

import ast
import re
from typing import Any

from ml.data.schema import (
    DIMENSIONES_PUNTUACION,
    EjemploEntrenamiento,
    NIVELES_PEDAGOGICOS,
)


# ════════════════════════════════════════════════════════════════════
# Validadores atómicos
# ════════════════════════════════════════════════════════════════════

def validar_codigo_python(codigo: str) -> tuple[bool, str]:
    """Compila el código con ast.parse. No ejecuta nada."""
    if not codigo or not codigo.strip():
        return True, "vacío (no se valida)"
    # Quitar fences markdown si aparecen accidentalmente.
    codigo = _limpiar_fences(codigo)
    try:
        ast.parse(codigo)
        return True, "ok"
    except SyntaxError as e:
        return False, f"SyntaxError: {e.msg} (línea {e.lineno})"


def validar_pensamiento(pensamiento: dict[str, Any]) -> tuple[bool, str]:
    """Chain-of-thought: secciones requeridas con contenido mínimo."""
    if not isinstance(pensamiento, dict):
        return False, "pensamiento no es dict"

    alternativas = pensamiento.get("alternativas_consideradas") or []
    if not isinstance(alternativas, list) or len(alternativas) < 2:
        return False, "necesita al menos 2 alternativas_consideradas"

    for i, alt in enumerate(alternativas):
        if not isinstance(alt, dict):
            return False, f"alternativa {i} no es dict"
        if "opcion" not in alt or "razon" not in alt:
            return False, f"alternativa {i} sin 'opcion' o 'razon'"

    # Exactamente una elegida.
    elegidas = sum(1 for a in alternativas if a.get("elegida"))
    if elegidas != 1:
        return False, f"debe haber exactamente 1 alternativa elegida (hay {elegidas})"

    criterios = pensamiento.get("criterios_decision") or []
    if not isinstance(criterios, list) or len(criterios) < 2:
        return False, "necesita al menos 2 criterios_decision"

    return True, "ok"


def validar_autocritica(pensamiento: dict[str, Any]) -> tuple[bool, str]:
    """Auto-crítica iterativa: A → B → C con código + crítica en cada paso.

    Estructura esperada:
        pensamiento = {
          "iteraciones": [
            {"version": "A",       "codigo": "...", "critica": "..."},
            {"version": "B",       "codigo": "...", "critica": "..."},
            {"version": "C_final", "codigo": "...", "critica": "sin problemas"}
          ]
        }
    """
    if not isinstance(pensamiento, dict):
        return False, "pensamiento no es dict"

    its = pensamiento.get("iteraciones")
    if not isinstance(its, list):
        return False, "falta 'iteraciones' o no es lista"
    if len(its) < 2:
        return False, f"necesita al menos 2 iteraciones (hay {len(its)})"
    if len(its) > 5:
        return False, f"demasiadas iteraciones ({len(its)}) — máx 5"

    versiones_vistas: list[str] = []
    for i, it in enumerate(its):
        if not isinstance(it, dict):
            return False, f"iteración {i} no es dict"

        for clave in ("version", "codigo", "critica"):
            if clave not in it:
                return False, f"iteración {i} sin '{clave}'"

        version = (it.get("version") or "").strip()
        codigo = (it.get("codigo") or "").strip()
        critica = (it.get("critica") or "").strip()

        if not version:
            return False, f"iteración {i} con 'version' vacía"
        if version in versiones_vistas:
            return False, f"version '{version}' repetida"
        versiones_vistas.append(version)

        # Código debe compilar en cada iteración.
        ok, motivo = validar_codigo_python(codigo)
        if not ok:
            return False, f"iteración {i} ({version}): {motivo}"

        # Crítica: no vacía y de longitud razonable.
        # En la última iteración admitimos cosas como "sin problemas".
        es_ultima = (i == len(its) - 1)
        if not es_ultima and len(critica) < 40:
            return False, f"iteración {i} ({version}): crítica muy corta (<40 chars)"
        if es_ultima and len(critica) < 10:
            return False, f"iteración final con crítica vacía"

    # Última versión debe parecer "final" (heurística suave).
    ultima_v = versiones_vistas[-1].lower()
    if not any(marcador in ultima_v for marcador in ("final", "_v3", "_v4", "_v5", "c_", "z_")):
        # No es error duro — solo si las versiones son A, B, C, ... permitimos.
        # Validar que el orden sea creciente (A < B < ... lexicograficamente).
        if versiones_vistas != sorted(versiones_vistas, key=str.lower):
            return False, "versiones no están en orden creciente"

    return True, "ok"


def validar_multinivel(explicacion_por_nivel: dict[str, str]) -> tuple[bool, str]:
    """Las 4 explicaciones presentes, con longitud y vocabulario calibrados.

    Reglas (alineadas con el prompt fortalecido):
        - nino:         >= 80 chars, SIN jerga técnica, SIN bloques de código.
        - principiante: >= 200 chars, con código en fences.
        - intermedio:   >= 350 chars, con código y "cuando NO usar".
        - profesional:  >= 500 chars, mencionando internals, PEP o edge case.

    El validador rechaza textos copiados entre niveles (sin diferenciación real).
    """
    if not isinstance(explicacion_por_nivel, dict):
        return False, "explicacion_por_nivel no es dict"

    # Longitudes mínimas por nivel (alineadas con la calibración del prompt).
    minimos = {
        "nino": 80,
        "principiante": 200,
        "intermedio": 350,
        "profesional": 500,
    }

    for nivel in NIVELES_PEDAGOGICOS:
        texto = explicacion_por_nivel.get(nivel, "")
        if not texto or not isinstance(texto, str):
            return False, f"nivel {nivel} ausente o no string"
        if len(texto.strip()) < minimos[nivel]:
            return False, f"nivel {nivel} demasiado corto ({len(texto)} < {minimos[nivel]})"

    # Detectar copia textual (mismo string en 2+ niveles).
    textos = [explicacion_por_nivel[n].strip() for n in NIVELES_PEDAGOGICOS]
    if len(set(textos)) < len(textos):
        return False, "hay niveles con texto idéntico (no hubo adaptación real)"

    # Nivel "nino" NO debe contener jerga técnica obvia (la sigla del nivel
    # busca enseñar con analogías cotidianas, no con palabras técnicas).
    jerga_prohibida_nino = (
        " variable", " funcion", " función", " método", " metodo",
        " objeto", " iterador", " interprete", " intérprete",
        " heap", " memoria", " bytecode", " compilador",
        " polimorf", " encapsul",
    )
    nino_lower = " " + explicacion_por_nivel["nino"].lower() + " "
    encontradas = [j.strip() for j in jerga_prohibida_nino if j in nino_lower]
    if encontradas:
        return False, f"nivel 'nino' usa jerga técnica: {encontradas[:3]}"

    # Nivel "nino" NO debe tener bloques de código (un niño no entiende sintaxis).
    if "```" in explicacion_por_nivel["nino"]:
        return False, "nivel 'nino' contiene bloque de código (debe ser solo analogía)"

    return True, "ok"


def validar_revision_codigo(revision: dict[str, Any]) -> tuple[bool, str]:
    """Antipatrón: debe explicar problemas, no solo dar versión nueva."""
    if not isinstance(revision, dict):
        return False, "revision_codigo no es dict"

    problemas = revision.get("problemas") or []
    if not isinstance(problemas, list) or len(problemas) < 1:
        return False, "necesita al menos 1 problema identificado"

    if not revision.get("por_que_funciona_pero_es_malo"):
        return False, "falta 'por_que_funciona_pero_es_malo'"

    if not revision.get("problema_en_produccion"):
        return False, "falta 'problema_en_produccion'"

    return True, "ok"


def validar_puntuacion(puntuacion: dict[str, int]) -> tuple[bool, str]:
    """6 dimensiones, todas en [0,10]."""
    if not isinstance(puntuacion, dict):
        return False, "puntuacion no es dict"

    faltan = [d for d in DIMENSIONES_PUNTUACION if d not in puntuacion]
    if faltan:
        return False, f"faltan dimensiones: {faltan}"

    for dim, val in puntuacion.items():
        if dim not in DIMENSIONES_PUNTUACION:
            return False, f"dimensión desconocida: {dim}"
        if not isinstance(val, int) or not (0 <= val <= 10):
            return False, f"{dim}={val} fuera de [0,10]"

    return True, "ok"


def validar_salida_pedagogica(texto: str) -> tuple[bool, str]:
    """Heurísticas para descartar salidas de baja calidad.

    No queremos: respuestas de 3 líneas, copia del prompt, solo código sin
    explicación, marcadores de placeholder ('...', 'TODO', 'lorem ipsum').
    """
    if len(texto.strip()) < 60:
        return False, "salida muy corta (< 60 chars)"

    if texto.strip().count("...") >= 3:
        return False, "demasiados '...' (placeholder)"

    txt_lower = texto.lower()
    placeholders = ["lorem ipsum", "todo:", "fixme:", "<placeholder>", "...etc...", "etcetera"]
    for ph in placeholders:
        if ph in txt_lower:
            return False, f"contiene placeholder '{ph}'"

    # Detectar respuestas que son solo un bloque de código sin explicación.
    # Si > 80% del texto está dentro de fences ``` y < 100 chars fuera, mal.
    fuera_fence = re.sub(r"```.*?```", "", texto, flags=re.DOTALL)
    if len(fuera_fence.strip()) < 100 and "```" in texto:
        return False, "solo código, sin explicación pedagógica"

    return True, "ok"


# ════════════════════════════════════════════════════════════════════
# Validador agregado
# ════════════════════════════════════════════════════════════════════

def validar_ejemplo(ej: EjemploEntrenamiento) -> tuple[bool, str]:
    """Aplica el validador del schema + los específicos por tipo."""
    ok, motivo = ej.es_valido()
    if not ok:
        return False, f"schema: {motivo}"

    ok, motivo = validar_salida_pedagogica(ej.salida)
    if not ok:
        return False, f"salida_pedagogica: {motivo}"

    # Si trae entrada con código Python explícito, validar.
    if ej.entrada and _parece_codigo_python(ej.entrada):
        ok, motivo = validar_codigo_python(ej.entrada)
        if not ok:
            return False, f"entrada_codigo: {motivo}"

    # Validar bloques de código en la salida.
    for bloque in _extraer_bloques_codigo(ej.salida):
        ok, motivo = validar_codigo_python(bloque)
        if not ok:
            return False, f"salida_codigo: {motivo}"

    # Validaciones por tipo V2.
    if ej.tipo == "pensamiento_programador":
        if ej.pensamiento is None:
            return False, "pensamiento_programador requiere campo 'pensamiento'"
        ok, motivo = validar_pensamiento(ej.pensamiento)
        if not ok:
            return False, f"pensamiento: {motivo}"

    if ej.tipo == "explicacion_multinivel":
        if ej.explicacion_por_nivel is None:
            return False, "explicacion_multinivel requiere 'explicacion_por_nivel'"
        ok, motivo = validar_multinivel(ej.explicacion_por_nivel)
        if not ok:
            return False, f"multinivel: {motivo}"

    if ej.tipo == "anti_patron":
        if ej.revision_codigo is None:
            return False, "anti_patron requiere 'revision_codigo'"
        ok, motivo = validar_revision_codigo(ej.revision_codigo)
        if not ok:
            return False, f"revision_codigo: {motivo}"

    if ej.tipo == "evolucion_codigo":
        if ej.version_evolutiva is None:
            return False, "evolucion_codigo requiere 'version_evolutiva'"

    if ej.tipo == "decision_diseno":
        if ej.pensamiento is None:
            return False, "decision_diseno requiere 'pensamiento'"
        ok, motivo = validar_pensamiento(ej.pensamiento)
        if not ok:
            return False, f"pensamiento: {motivo}"

    if ej.tipo == "pensamiento_autocritico":
        if ej.pensamiento is None:
            return False, "pensamiento_autocritico requiere 'pensamiento'"
        ok, motivo = validar_autocritica(ej.pensamiento)
        if not ok:
            return False, f"autocritica: {motivo}"

    if ej.puntuacion is not None:
        ok, motivo = validar_puntuacion(ej.puntuacion)
        if not ok:
            return False, f"puntuacion: {motivo}"

    return True, "ok"


# ════════════════════════════════════════════════════════════════════
# Helpers
# ════════════════════════════════════════════════════════════════════

_FENCE_RE = re.compile(r"```(?:python|py)?\s*\n?(.*?)```", re.DOTALL | re.IGNORECASE)


def _extraer_bloques_codigo(texto: str) -> list[str]:
    return [m.group(1).strip() for m in _FENCE_RE.finditer(texto) if m.group(1).strip()]


def _limpiar_fences(codigo: str) -> str:
    m = _FENCE_RE.search(codigo)
    return m.group(1).strip() if m else codigo


_INDICADORES_PYTHON = ("def ", "class ", "import ", "from ", "->", "self.", "print(", "lambda ")


def _parece_codigo_python(texto: str) -> bool:
    return any(ind in texto for ind in _INDICADORES_PYTHON)
