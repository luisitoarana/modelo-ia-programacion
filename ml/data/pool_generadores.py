"""Pool de generadores LLM gratuitos con rotación, rate limiting y fallback.

Abstracción común sobre los proveedores que ofrecen tier gratuito útil
para construir el dataset:

    - Gemini (Google)         — fuerte en chain-of-thought
    - DeepSeek                — fuerte en código
    - Groq (Llama 3.3 70B)    — alta velocidad, alto rate limit
    - Together AI             — Llama y modelos open
    - Mistral La Plateforme   — Mistral Large
    - OpenRouter              — fallback con varios modelos free

Cada proveedor declara su rate limit (rpm, rpd) y un score subjetivo de
calidad por tarea. El pool elige el proveedor disponible con mejor score
para la tarea actual; si está rate-limited, cae al siguiente.

Variables de entorno opcionales:
    GEMINI_API_KEY, DEEPSEEK_API_KEY, GROQ_API_KEY,
    TOGETHER_API_KEY, MISTRAL_API_KEY, OPENROUTER_API_KEY

Solo se usan los proveedores con clave configurada. Si ninguno está,
falla con instrucciones claras.

Uso típico:
    from ml.data.pool_generadores import Pool, Tarea

    pool = Pool.desde_env()
    texto = await pool.generar(prompt="...", tarea=Tarea.COT)
"""

from __future__ import annotations

import asyncio
import enum
import json
import os
import re
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable


# ════════════════════════════════════════════════════════════════════
# Tareas y prioridades
# ════════════════════════════════════════════════════════════════════

class Tarea(str, enum.Enum):
    """Tipo de tarea que se pide al LLM. Determina qué proveedor priorizar."""
    COT = "cot"                  # chain-of-thought (Gemini >)
    CODIGO = "codigo"            # generación de código (DeepSeek >)
    EXPLICACION = "explicacion"  # explicación pedagógica
    EVALUACION = "evaluacion"    # juez 0-10 o A/B
    VOLUMEN = "volumen"          # generación masiva (Groq >)
    GENERICA = "generica"


# (proveedor, score 0-10) ordenado de mejor a peor por tarea.
PRIORIDADES: dict[Tarea, list[tuple[str, int]]] = {
    Tarea.COT:         [("gemini", 9), ("deepseek", 8), ("mistral", 8), ("groq", 7), ("together", 7), ("openrouter", 6)],
    Tarea.CODIGO:      [("deepseek", 9), ("gemini", 8), ("together", 8), ("groq", 7), ("mistral", 7), ("openrouter", 6)],
    Tarea.EXPLICACION: [("gemini", 9), ("mistral", 8), ("deepseek", 8), ("groq", 7), ("together", 7), ("openrouter", 6)],
    Tarea.EVALUACION:  [("gemini", 9), ("groq", 8), ("deepseek", 7), ("mistral", 7), ("together", 7), ("openrouter", 6)],
    Tarea.VOLUMEN:     [("groq", 9), ("together", 8), ("gemini", 7), ("deepseek", 7), ("mistral", 7), ("openrouter", 6)],
    Tarea.GENERICA:    [("gemini", 8), ("deepseek", 8), ("groq", 7), ("together", 7), ("mistral", 7), ("openrouter", 6)],
}


# ════════════════════════════════════════════════════════════════════
# Rate limiter
# ════════════════════════════════════════════════════════════════════

@dataclass(slots=True)
class RateLimit:
    """Token bucket simple por proveedor."""
    rpm: int          # requests por minuto
    rpd: int          # requests por día
    timestamps_min: list[float] = field(default_factory=list)
    timestamps_dia: list[float] = field(default_factory=list)

    def disponible(self) -> bool:
        ahora = time.time()
        self.timestamps_min = [t for t in self.timestamps_min if ahora - t < 60]
        self.timestamps_dia = [t for t in self.timestamps_dia if ahora - t < 86400]
        if len(self.timestamps_min) >= self.rpm:
            return False
        if len(self.timestamps_dia) >= self.rpd:
            return False
        return True

    def registrar(self) -> None:
        ahora = time.time()
        self.timestamps_min.append(ahora)
        self.timestamps_dia.append(ahora)

    def proximo_disponible(self) -> float:
        ahora = time.time()
        esperas: list[float] = []
        if len(self.timestamps_min) >= self.rpm:
            esperas.append(60 - (ahora - self.timestamps_min[0]))
        if len(self.timestamps_dia) >= self.rpd:
            esperas.append(86400 - (ahora - self.timestamps_dia[0]))
        return max(esperas) if esperas else 0.0


# ════════════════════════════════════════════════════════════════════
# Proveedores (cada uno con su forma de hablarle al endpoint)
# ════════════════════════════════════════════════════════════════════

@dataclass(slots=True)
class Proveedor:
    nombre: str
    api_key: str
    modelo: str
    rate_limit: RateLimit
    _llamador: Callable[[str, str, str, float, int], Any]

    async def generar(self, prompt: str, *, temperatura: float = 0.7,
                      max_tokens: int = 2048) -> str:
        return await self._llamador(self.api_key, self.modelo, prompt,
                                    temperatura, max_tokens)


async def _llamar_gemini(api_key: str, modelo: str, prompt: str,
                         temperatura: float, max_tokens: int) -> str:
    import httpx
    url = f"https://generativelanguage.googleapis.com/v1beta/models/{modelo}:generateContent"
    cuerpo = {
        "contents": [{"role": "user", "parts": [{"text": prompt}]}],
        "generationConfig": {"temperature": temperatura, "maxOutputTokens": max_tokens},
    }
    async with httpx.AsyncClient(timeout=120) as c:
        r = await c.post(url, json=cuerpo, params={"key": api_key})
        r.raise_for_status()
        data = r.json()
    cands = data.get("candidates") or []
    if not cands:
        return ""
    partes = (cands[0].get("content") or {}).get("parts") or []
    return "".join(p.get("text", "") for p in partes)


async def _llamar_openai_compatible(api_key: str, modelo: str, prompt: str,
                                    temperatura: float, max_tokens: int,
                                    *, base_url: str) -> str:
    """Endpoint OpenAI-compatible: DeepSeek, Groq, Together, Mistral, OpenRouter."""
    import httpx
    url = f"{base_url}/chat/completions"
    cuerpo = {
        "model": modelo,
        "messages": [{"role": "user", "content": prompt}],
        "temperature": temperatura,
        "max_tokens": max_tokens,
    }
    headers = {"Authorization": f"Bearer {api_key}"}
    async with httpx.AsyncClient(timeout=120) as c:
        r = await c.post(url, json=cuerpo, headers=headers)
        r.raise_for_status()
        data = r.json()
    choices = data.get("choices") or []
    if not choices:
        return ""
    return ((choices[0].get("message") or {}).get("content")) or ""


def _hacer_llamador_openai(base_url: str):
    async def llamador(api_key, modelo, prompt, temperatura, max_tokens):
        return await _llamar_openai_compatible(
            api_key, modelo, prompt, temperatura, max_tokens, base_url=base_url
        )
    return llamador


# Configuración por proveedor (modelos free al 2026-06).
PROVEEDORES_DISPONIBLES = {
    "gemini": {
        "env": "GEMINI_API_KEY",
        "modelo_default": "gemini-2.0-flash",
        "rate": (15, 1500),
        "llamador": _llamar_gemini,
    },
    "deepseek": {
        "env": "DEEPSEEK_API_KEY",
        "modelo_default": "deepseek-chat",
        "rate": (60, 5000),
        "llamador": _hacer_llamador_openai("https://api.deepseek.com/v1"),
    },
    "groq": {
        "env": "GROQ_API_KEY",
        "modelo_default": "llama-3.3-70b-versatile",
        "rate": (30, 14400),
        "llamador": _hacer_llamador_openai("https://api.groq.com/openai/v1"),
    },
    "together": {
        "env": "TOGETHER_API_KEY",
        "modelo_default": "meta-llama/Llama-3.3-70B-Instruct-Turbo",
        "rate": (60, 1000),
        "llamador": _hacer_llamador_openai("https://api.together.xyz/v1"),
    },
    "mistral": {
        "env": "MISTRAL_API_KEY",
        "modelo_default": "mistral-large-latest",
        "rate": (30, 1000),
        "llamador": _hacer_llamador_openai("https://api.mistral.ai/v1"),
    },
    "openrouter": {
        "env": "OPENROUTER_API_KEY",
        "modelo_default": "meta-llama/llama-3.1-8b-instruct:free",
        "rate": (20, 200),
        "llamador": _hacer_llamador_openai("https://openrouter.ai/api/v1"),
    },
}


# ════════════════════════════════════════════════════════════════════
# Pool
# ════════════════════════════════════════════════════════════════════

@dataclass(slots=True)
class _Stats:
    exitos: int = 0
    fallos: int = 0
    rate_limited: int = 0
    tokens_estimados: int = 0


class Pool:
    """Selecciona proveedor, hace fallback, lleva estadísticas."""

    def __init__(self, proveedores: dict[str, Proveedor]):
        if not proveedores:
            raise RuntimeError(
                "No hay proveedores con API key configurada. "
                "Define al menos una de: GEMINI_API_KEY, DEEPSEEK_API_KEY, "
                "GROQ_API_KEY, TOGETHER_API_KEY, MISTRAL_API_KEY, OPENROUTER_API_KEY"
            )
        self._proveedores = proveedores
        self._stats: dict[str, _Stats] = {nombre: _Stats() for nombre in proveedores}

    @classmethod
    def desde_env(cls, modelos_override: dict[str, str] | None = None) -> "Pool":
        _cargar_dotenv()
        modelos_override = modelos_override or {}
        configurados: dict[str, Proveedor] = {}
        for nombre, cfg in PROVEEDORES_DISPONIBLES.items():
            key = os.environ.get(cfg["env"], "").strip()
            if not key:
                continue
            modelo = modelos_override.get(nombre) or os.environ.get(
                f"{nombre.upper()}_MODEL", cfg["modelo_default"]
            )
            rpm, rpd = cfg["rate"]
            configurados[nombre] = Proveedor(
                nombre=nombre,
                api_key=key,
                modelo=modelo,
                rate_limit=RateLimit(rpm=rpm, rpd=rpd),
                _llamador=cfg["llamador"],
            )
        return cls(configurados)

    @property
    def disponibles(self) -> list[str]:
        return list(self._proveedores.keys())

    async def generar(
        self,
        prompt: str,
        *,
        tarea: Tarea = Tarea.GENERICA,
        temperatura: float = 0.7,
        max_tokens: int = 2048,
        proveedor_forzado: str | None = None,
        max_intentos: int = 4,
        esperar_si_rate_limited: bool = False,
    ) -> tuple[str, str]:
        """Devuelve (texto, nombre_proveedor_usado).

        Si todos los proveedores fallan o están rate-limited, lanza
        RuntimeError. Con `esperar_si_rate_limited=True`, espera hasta
        que el primero esté disponible (útil para scripts batch).
        """
        if proveedor_forzado:
            if proveedor_forzado not in self._proveedores:
                raise ValueError(f"proveedor '{proveedor_forzado}' no configurado")
            return await self._llamar(
                self._proveedores[proveedor_forzado], prompt, temperatura, max_tokens
            )

        # Orden de preferencia por tarea, intersectado con disponibles.
        candidatos: list[Proveedor] = []
        for nombre, _score in PRIORIDADES[tarea]:
            if nombre in self._proveedores:
                candidatos.append(self._proveedores[nombre])

        ultimo_error: Exception | None = None
        intentos = 0
        candidatos_originales = list(candidatos)
        while intentos < max_intentos:
            disponible = next((p for p in candidatos if p.rate_limit.disponible()), None)
            if disponible is None:
                if not esperar_si_rate_limited:
                    raise RuntimeError(
                        "Todos los proveedores rate-limited. "
                        "Usa esperar_si_rate_limited=True o reduce el ritmo."
                    )
                espera = min(p.rate_limit.proximo_disponible() for p in candidatos)
                # Espera al menos 5s y máx 60s entre reintentos por rate limit.
                await asyncio.sleep(max(min(espera + 0.5, 60), 5))
                # No incrementar `intentos` cuando solo estamos esperando
                # rate limit (no es un intento de llamada real).
                continue

            intentos += 1
            try:
                texto, nombre = await self._llamar(disponible, prompt, temperatura, max_tokens)
                if texto.strip():
                    return texto, nombre
                ultimo_error = RuntimeError(f"{disponible.nombre} devolvió texto vacío")
                self._stats[disponible.nombre].fallos += 1
            except Exception as exc:
                ultimo_error = exc
                self._stats[disponible.nombre].fallos += 1
                if _es_rate_limit_error(exc):
                    self._stats[disponible.nombre].rate_limited += 1
                    if esperar_si_rate_limited:
                        # Espera FIJA (60s, lo típico de Groq/Gemini),
                        # NO acumulamos timestamps locales (eso multiplicaba
                        # la espera en cada 429 sucesivo).
                        print(f"  [pool] {disponible.nombre} 429, espera 60s...",
                              flush=True)
                        await asyncio.sleep(60)
                        # Restaurar candidatos por si los habíamos quitado en
                        # intentos anteriores.
                        candidatos = list(candidatos_originales)
                        continue
                # Penalizar este proveedor en intentos siguientes (errores no-rate-limit).
                candidatos = [p for p in candidatos if p is not disponible]
                if not candidatos:
                    break

        raise RuntimeError(f"todos los proveedores fallaron: {ultimo_error}")

    async def _llamar(self, proveedor: Proveedor, prompt: str,
                      temperatura: float, max_tokens: int) -> tuple[str, str]:
        proveedor.rate_limit.registrar()
        texto = await proveedor.generar(
            prompt, temperatura=temperatura, max_tokens=max_tokens
        )
        if texto.strip():
            self._stats[proveedor.nombre].exitos += 1
            # Estimación heurística de tokens (1 token ~= 4 chars).
            self._stats[proveedor.nombre].tokens_estimados += len(texto) // 4
        return texto, proveedor.nombre

    def stats(self) -> dict[str, dict[str, int]]:
        return {
            nombre: {
                "exitos": s.exitos,
                "fallos": s.fallos,
                "rate_limited": s.rate_limited,
                "tokens_estimados": s.tokens_estimados,
            }
            for nombre, s in self._stats.items()
        }


# ════════════════════════════════════════════════════════════════════
# Helpers de extracción JSON (los proveedores envuelven en markdown)
# ════════════════════════════════════════════════════════════════════

_JSON_OBJ_RE = re.compile(r"\{.*\}", re.DOTALL)
_JSON_ARR_RE = re.compile(r"\[.*\]", re.DOTALL)


def extraer_json_objeto(texto: str) -> dict[str, Any] | None:
    """Extrae el primer objeto JSON del texto, aunque venga con markdown.

    Usa `strict=False` para tolerar el caso muy común en que los LLMs
    emiten saltos de línea literales dentro de strings (al generar código
    Python dentro del JSON).
    """
    texto = _quitar_fences(texto)
    m = _JSON_OBJ_RE.search(texto)
    if not m:
        return None
    try:
        return json.loads(m.group(0), strict=False)
    except json.JSONDecodeError:
        return None


def extraer_json_array(texto: str) -> list[Any] | None:
    """Extrae un array JSON del texto. Robusto a JSON truncado o malformado.

    Estrategia:
      1) Intentar parsear el array completo con strict=False.
      2) Si falla, extraer objetos individuales {...} del texto y devolver
         la lista de los que se puedan parsear.
    """
    texto = _quitar_fences(texto)
    m = _JSON_ARR_RE.search(texto)
    if m:
        try:
            data = json.loads(m.group(0), strict=False)
            if isinstance(data, list):
                return data
        except json.JSONDecodeError:
            pass

    # Fallback: extraer objetos individuales balanceando llaves.
    objetos = _extraer_objetos_balanceados(texto)
    return objetos if objetos else None


def _extraer_objetos_balanceados(texto: str) -> list[Any]:
    """Recorre el texto buscando objetos JSON `{...}` balanceando llaves.

    Tolera:
      - Llaves dentro de strings (no las cuenta).
      - JSON truncado al final (descarta el último objeto incompleto).
      - Texto basura entre objetos.

    Devuelve la lista de objetos parseados exitosamente.
    """
    objetos: list[Any] = []
    i = 0
    n = len(texto)
    while i < n:
        if texto[i] != "{":
            i += 1
            continue
        # Buscar el cierre balanceado a partir de i.
        depth = 0
        in_string = False
        escape = False
        j = i
        while j < n:
            c = texto[j]
            if in_string:
                if escape:
                    escape = False
                elif c == "\\":
                    escape = True
                elif c == '"':
                    in_string = False
            else:
                if c == '"':
                    in_string = True
                elif c == "{":
                    depth += 1
                elif c == "}":
                    depth -= 1
                    if depth == 0:
                        # Tenemos un objeto candidato.
                        candidato = texto[i:j + 1]
                        try:
                            objetos.append(json.loads(candidato, strict=False))
                        except json.JSONDecodeError:
                            pass
                        i = j + 1
                        break
            j += 1
        else:
            # Nunca cerró → objeto truncado, terminar.
            break
    return objetos


def _quitar_fences(texto: str) -> str:
    """Solo quita un wrapper ```...``` cuando envuelve TODO el texto.

    Antes lo hacía siempre — y eso rompía respuestas donde el JSON contenía
    bloques ```python ...``` internos: la regex agarraba esos fences
    internos como wrapper externo y descartaba el JSON real.
    """
    texto_stripped = texto.strip()
    if not texto_stripped.startswith("```"):
        return texto
    # Empieza con ``` → quitamos solo el primer wrapper. Usamos un match
    # más estricto: la apertura debe estar al inicio, el cierre lo más
    # tarde posible. Si no cierra, devolvemos el texto desde el primer salto.
    m = re.match(r"```(?:json)?\s*(.*?)\s*```\s*$", texto_stripped, re.DOTALL)
    if m:
        return m.group(1)
    # Fallback: el texto empieza con ``` pero no cierra al final →
    # quitamos solo la primera línea (`` ```json `` o similar).
    return texto_stripped.split("\n", 1)[1] if "\n" in texto_stripped else texto


# ════════════════════════════════════════════════════════════════════
# .env loader (simple, sin dependencias)
# ════════════════════════════════════════════════════════════════════

def _cargar_dotenv() -> None:
    if any(os.environ.get(cfg["env"]) for cfg in PROVEEDORES_DISPONIBLES.values()):
        return
    for ruta in (Path(".env"), Path(__file__).resolve().parents[2] / ".env"):
        if ruta.exists():
            for linea in ruta.read_text(encoding="utf-8").splitlines():
                linea = linea.strip()
                if not linea or linea.startswith("#") or "=" not in linea:
                    continue
                k, _, v = linea.partition("=")
                os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))
            break


def _es_rate_limit_error(exc: Exception) -> bool:
    msg = str(exc).lower()
    return "429" in msg or "rate limit" in msg or "quota" in msg
