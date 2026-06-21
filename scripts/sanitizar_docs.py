"""Sanitiza la documentación: elimina referencias a 'tesis', 'jurado',
'manuscrito', 'defensa' y otras palabras que el sistema NO debe contener.

El sistema es un modelo de IA, NO un trabajo académico. La documentación
acompaña al sistema y debe leerse como documentación técnica normal.
"""

from __future__ import annotations

import re
from pathlib import Path

# Reglas de reemplazo en orden de aplicación. Las primeras se aplican antes
# para evitar interferencias (p.ej. "defensa de tesis" debe reemplazarse antes
# que "tesis" sola).
REGLAS: list[tuple[str, str]] = [
    # Frases compuestas primero
    (r"\bdefensa de [Tt]esis\b",            "presentación del proyecto"),
    (r"\b[Pp]ropuesta de [Tt]esis\b",       "propuesta del proyecto"),
    (r"\b[Mm]anuscrito de [Tt]esis\b",      "documentación del proyecto"),
    (r"\b[Cc]apítulo del manuscrito\b",     "sección de la documentación"),
    (r"\b[Cc]apítulo[s]? de la [Tt]esis\b", "sección de la documentación"),
    (r"\b[Cc]apítulo de Metodología\b",     "sección de Metodología"),
    (r"\b[Cc]apítulo de Resultados\b",      "sección de Resultados"),
    (r"\b[Cc]apítulo de Implementación\b",  "sección de Implementación"),
    (r"\b[Cc]apítulo de Diseño\b",          "sección de Diseño"),
    (r"\b[Cc]apítulo de Desarrollo\b",      "sección de Desarrollo"),
    (r"\b[Cc]apítulo de Introducción\b",    "sección de Introducción"),
    (r"\b[Cc]apítulo de Conclusiones\b",    "sección de Conclusiones"),
    (r"\b[Cc]apítulo de Marco [Tt]eórico\b","sección de Marco Teórico"),
    (r"\bcapítulo[s]? de la propuesta\b",   "sección de la propuesta"),
    (r"\b[Tt]esis de pregrado\b",           "proyecto de investigación"),
    (r"\b[Tt]esis de grado\b",              "proyecto de investigación"),
    (r"\b[Pp]ara la [Tt]esis\b",            "del proyecto"),
    (r"\bpara [Tt]esis\b",                  "del proyecto"),
    (r"\b[Dd]e [Tt]esis\b",                 "del proyecto"),
    (r"\b[Mm]anuscrito final\b",            "documentación final"),
    (r"\b[Dd]efensa del proyecto\b",        "presentación del proyecto"),
    (r"\b[Dd]efensa[s]?\b",                 "presentación"),
    (r"\b[Jj]urado[s]?\b",                  "revisor"),

    # Singulares
    (r"\bTESIS\b",                          "PROYECTO"),
    (r"\bTesis\b",                          "Proyecto"),
    (r"\btesis\b",                          "proyecto"),
    (r"\bMANUSCRITO\b",                     "DOCUMENTACIÓN"),
    (r"\bManuscrito\b",                     "Documentación"),
    (r"\bmanuscrito\b",                     "documentación"),

    # Limpieza: doble espacio sobrante, "del proyecto del proyecto"
    (r"del proyecto del proyecto",          "del proyecto"),
    (r"  +",                                " "),

    # ──────── Segunda pasada: arreglar concordancia ─────────
    # "la proyecto" → "el proyecto"
    (r"\b[Ll]a proyecto\b",                 "el proyecto"),
    (r"\b[Dd]e la proyecto\b",              "del proyecto"),
    (r"\b[Pp]ara la proyecto\b",            "para el proyecto"),
    (r"\b[Ee]n la proyecto\b",              "en el proyecto"),
    (r"\b[Cc]on la proyecto\b",             "con el proyecto"),
    (r"\b[Aa] la proyecto\b",               "al proyecto"),
    (r"\b[Uu]na proyecto\b",                "un proyecto"),
    (r"\b[Ee]sta proyecto\b",               "este proyecto"),
    (r"\b[Ll]as proyectos\b",               "los proyectos"),

    # "documentación" cuando reemplazó a "manuscrito" puede dejar
    # frases redundantes
    (r"documentación de la documentación",  "documentación"),
    (r"documentación del proyecto final",   "documentación final"),

    # Frases que reflejan tono académico/defensa, neutralizar
    (r"\bpresentación académica\b",         "argumentación técnica"),
    (r"\bpresentación metodológica\b",      "argumentación metodológica"),
    (r"\bpresentación principal del proyecto\b",
                                            "contribución principal del proyecto"),
    (r"\bpresentación del proyecto, cuando\b",
                                            "presentación, cuando"),
    (r"\bla presentación principal\b",      "la contribución principal"),

    # Limpieza adicional
    (r"  +",                                " "),
    (r" +,",                                ","),
    (r" +\.",                               "."),
]


def sanitizar_texto(texto: str) -> tuple[str, int]:
    """Aplica todas las reglas. Devuelve (texto_nuevo, n_reemplazos)."""
    n = 0
    for patron, reemplazo in REGLAS:
        nuevo, k = re.subn(patron, reemplazo, texto)
        n += k
        texto = nuevo
    return texto, n


def sanitizar_archivo(ruta: Path) -> int:
    contenido = ruta.read_text(encoding="utf-8")
    nuevo, n = sanitizar_texto(contenido)
    if n > 0:
        ruta.write_text(nuevo, encoding="utf-8")
    return n


def main() -> None:
    raiz = Path(__file__).resolve().parent.parent
    objetivos = list((raiz / "docs").glob("**/*.md")) + list(
        (raiz / "research").glob("**/*.md")
    )

    total = 0
    archivos_modificados = 0
    print(f"Sanitizando {len(objetivos)} archivos...")
    for ruta in objetivos:
        n = sanitizar_archivo(ruta)
        if n > 0:
            archivos_modificados += 1
            total += n
            print(f"  {ruta.relative_to(raiz)}: {n} reemplazos")

    print()
    print(f"Total: {total} reemplazos en {archivos_modificados} archivos.")


if __name__ == "__main__":
    main()
