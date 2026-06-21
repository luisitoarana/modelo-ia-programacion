"""Filtro de contenido para mensajes del chat.

Bloquea consultas con intención claramente maliciosa (atacar a terceros,
crear malware, robar credenciales) y permite las educativas (qué es,
cómo funciona, cómo defenderme).

Diseño:
  * Lista corta de patrones de "intención dañina" — son los que bloquean.
  * Lista de patrones "educativos" que neutralizan el match dañino —
    si el mensaje tiene ambos, se permite (es una pregunta para aprender).
  * Mensaje de rechazo en lugar de respuesta del LLM cuando se bloquea,
    con sugerencia de cómo reformular la pregunta de manera educativa.

Esto NO es un sistema de moderación de producción — es un filtro inicial,
configurable y mejorable. La política completa de moderación pertenece a
una capa más sofisticada (clasificador entrenado, embeddings, etc.).
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from enum import Enum


class ResultadoFiltro(Enum):
    PERMITIDO = "permitido"
    BLOQUEADO = "bloqueado"


@dataclass(slots=True, frozen=True)
class EvaluacionContenido:
    resultado: ResultadoFiltro
    razon: str  # categoría legible, e.g. "intencion_maliciosa"
    mensaje_usuario: str  # texto educativo a mostrar si se bloquea

    @property
    def permitido(self) -> bool:
        return self.resultado == ResultadoFiltro.PERMITIDO


# ──────────────────────── Patrones dañinos ────────────────────────
# Cada patrón es (regex, categoria, mensaje_corto).
# Las regex son case-insensitive y buscan combinaciones de verbo + objeto que
# indican intención de actuar (no de aprender).

_PATRONES_DANINOS: list[tuple[re.Pattern[str], str]] = [
    # — Robo de credenciales / acceso no autorizado —
    (re.compile(
        r"\b(c[oó]mo\s+(hackear|crackear|robar|sacar|conseguir)\s+(la\s+)?(contrase[ñn]a|password|cuenta|gmail|facebook|instagram|whatsapp|wifi\s+(?:de|del))\b)",
        re.IGNORECASE,
    ), "robo_credenciales"),
    (re.compile(
        r"\bbypass(ear)?\s+(la\s+)?(autenticaci[oó]n|2fa|login|seguridad\s+(?:de|del))",
        re.IGNORECASE,
    ), "bypass_autenticacion"),
    (re.compile(
        r"\b(phishing|p[aá]gina\s+falsa|clonar\s+(p[aá]gina|sitio|web))\s+(para|de|que)\b",
        re.IGNORECASE,
    ), "phishing"),

    # — Creación de malware —
    (re.compile(
        r"\b(crea(r|me)?|escrib(e|ir|eme)|gener(a|ar|ame))\s+(un\s+)?(virus|malware|ransomware|keylogger|troyano|rat|backdoor|botnet|spyware|stealer)\b",
        re.IGNORECASE,
    ), "crear_malware"),
    (re.compile(
        r"\b(c[oó]digo|script)\s+(para|que)\s+(infect(ar|e)|destruir|borrar|cifrar)\s+(archivos|sistema|computadora|pc)\b",
        re.IGNORECASE,
    ), "crear_malware"),

    # — Ataques activos —
    (re.compile(
        r"\b(c[oó]mo\s+)?(hacer|lanzar|realizar)\s+(un\s+)?(ddos|dos|ataque\s+de\s+denegaci[oó]n)\b",
        re.IGNORECASE,
    ), "ataque_ddos"),
    (re.compile(
        r"\b(sql\s*injection|inyecci[oó]n\s+sql)\s+(para|contra|a)\b.*\b(robar|extraer|sacar)\b",
        re.IGNORECASE,
    ), "ataque_sql"),

    # — Crackeo de software / piratería ofensiva —
    (re.compile(
        r"\b(crack(ear)?|pirat(ear|a)?|burlar|saltar)\s+(licencia|drm|protecci[oó]n|antivirus)\b",
        re.IGNORECASE,
    ), "crackeo_software"),
    (re.compile(
        r"\b(generar|crear|hacer)\s+(keygen|n[uú]mero(s)?\s+de\s+serie\s+falso(s)?)\b",
        re.IGNORECASE,
    ), "crackeo_software"),

    # — Contenido ilegal explícito —
    (re.compile(
        r"\b(fabricar|sintetizar|cocinar)\s+(droga|metanfetamina|coca[íi]na|fentanilo|explosivo|bomba|arma\s+casera)\b",
        re.IGNORECASE,
    ), "ilegal_grave"),

    # — Doxing / acoso —
    (re.compile(
        r"\b(c[oó]mo\s+)?(encontrar|conseguir|sacar|rastrear)\s+(la\s+)?(direcci[oó]n|ubicaci[oó]n|tel[eé]fono|ip)\s+(de\s+una\s+persona|de\s+alguien|real)\b",
        re.IGNORECASE,
    ), "doxing"),
]


# Patrones que neutralizan el bloqueo — si el mensaje contiene ALGUNO de
# estos junto con un patrón dañino, se permite porque la intención es
# educativa (entender para defenderse).
_PATRONES_EDUCATIVOS: list[re.Pattern[str]] = [
    re.compile(r"\bqu[eé]\s+es\s+(un|una)\b", re.IGNORECASE),
    re.compile(r"\bc[oó]mo\s+(funciona|opera|trabaja)\b", re.IGNORECASE),
    re.compile(r"\b(defender|proteger|prevenir|evitar)me?\b", re.IGNORECASE),
    re.compile(r"\b(para\s+(la\s+clase|la\s+universidad|aprender|estudiar))\b", re.IGNORECASE),
    re.compile(r"\b(en\s+t[eé]rminos\s+(generales|acad[eé]micos))\b", re.IGNORECASE),
    re.compile(r"\b(ctf|capture\s+the\s+flag|pentest|hacking\s+[eé]tico)\b", re.IGNORECASE),
    re.compile(r"\b(diferencia\s+entre)\b", re.IGNORECASE),
]


def _mensaje_rechazo(categoria: str) -> str:
    """Mensaje educativo (no acusatorio) según la categoría bloqueada."""
    explicaciones = {
        "robo_credenciales":
            "Esa pregunta busca acceder a cuentas que no son tuyas, y eso no "
            "lo puedo asistir.",
        "bypass_autenticacion":
            "Saltarse mecanismos de autenticación ajenos es ilegal y no es "
            "algo que pueda ayudarte a hacer.",
        "phishing":
            "Crear páginas o herramientas para engañar a personas y robarles "
            "información no es algo con lo que pueda ayudarte.",
        "crear_malware":
            "No genero código para malware (virus, ransomware, keyloggers, "
            "etc.). Estos programas dañan a personas y son delitos en casi "
            "todos los países.",
        "ataque_ddos":
            "Lanzar ataques de denegación de servicio contra sistemas ajenos "
            "es ilegal. No puedo ayudarte con eso.",
        "ataque_sql":
            "Ejecutar SQL injection contra sistemas que no son tuyos es un "
            "delito. No puedo darte código para hacerlo.",
        "crackeo_software":
            "Romper licencias o protecciones de software comercial es ilegal "
            "y no puedo ayudarte con eso.",
        "ilegal_grave":
            "No puedo darte instrucciones sobre temas que ponen vidas en "
            "riesgo. Si estás en una situación difícil, hay líneas de ayuda "
            "disponibles.",
        "doxing":
            "Rastrear o exponer información personal de alguien sin su "
            "consentimiento es acoso y no puedo asistir con eso.",
    }
    base = explicaciones.get(
        categoria,
        "Esa consulta cae fuera de lo que puedo ayudarte a hacer.",
    )
    sugerencia = (
        "\n\n**¿Era para aprender?** Si lo que querías era entender el "
        "concepto para protegerte o estudiarlo, reformula la pregunta. "
        "Por ejemplo:\n"
        "- *¿Qué es un ataque XSS y cómo se previene?*\n"
        "- *¿Cómo funcionan los gestores de contraseñas seguras?*\n"
        "- *¿Qué prácticas de seguridad debe tener una app web?*\n\n"
        "Estoy hecho para enseñarte programación y seguridad de manera "
        "constructiva."
    )
    return f"{base}{sugerencia}"


def evaluar_mensaje(texto: str) -> EvaluacionContenido:
    """Evalúa el texto del usuario antes de enviarlo al LLM."""
    if not texto or len(texto.strip()) == 0:
        return EvaluacionContenido(
            ResultadoFiltro.PERMITIDO, "vacio", ""
        )

    # Si contiene un patrón educativo, se permite incluso si parece dañino.
    tiene_educativo = any(p.search(texto) for p in _PATRONES_EDUCATIVOS)
    if tiene_educativo:
        return EvaluacionContenido(
            ResultadoFiltro.PERMITIDO, "educativo", ""
        )

    for patron, categoria in _PATRONES_DANINOS:
        if patron.search(texto):
            return EvaluacionContenido(
                ResultadoFiltro.BLOQUEADO,
                categoria,
                _mensaje_rechazo(categoria),
            )

    return EvaluacionContenido(ResultadoFiltro.PERMITIDO, "ok", "")
