"""Esquema del ejemplo de entrenamiento (V2 compatible con V1).

Formato base (V1) — sigue funcionando sin cambio:

    {
      "instruccion": "Explica qué es una función en Python",
      "entrada": "def sumar(a, b): return a + b",
      "salida": "Una función es...",
      "nivel": "basico",
      "tema": "funciones",
      "tipo": "explicacion_codigo"
    }

Extensión V2 — campos opcionales para datasets pedagógicos enriquecidos
(chain-of-thought, multinivel, antipatrones, bugs sutiles, evolución,
decisiones de diseño, arquitectura, seguridad, testing). Ver
`docs/DATASET_V2.md`.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass, field
from typing import Any

NIVELES = ("basico", "intermedio", "avanzado")
TIPOS = (
    # V1 — formatos clásicos
    "explicacion_codigo",
    "generacion_codigo",
    "concepto",
    "explicacion_linea",
    "actividad",
    "correccion_error",
    "comprension",
    # V2 — formatos pedagógicos enriquecidos
    "pensamiento_programador",
    "explicacion_multinivel",
    "anti_patron",
    "bug_sutil",
    "evolucion_codigo",
    "decision_diseno",
    "arquitectura_sistema",
    "seguridad",
    "testing_complejidad",
    "pensamiento_autocritico",
)

FUENTES_VALIDAS = (
    "semilla", "humano",
    "gemini", "deepseek", "groq", "together", "mistral", "openrouter",
    "sintetico_reglas", "publico_hf",
)

NIVELES_PEDAGOGICOS = ("nino", "principiante", "intermedio", "profesional")
VERSIONES_EVOLUTIVAS = (
    "v1_junior", "v2_junior_plus", "v3_mid", "v4_senior", "v5_staff",
)
DIMENSIONES_PUNTUACION = ("SEG", "LEG", "ESC", "ARQ", "REN", "MAN")


@dataclass(slots=True)
class EjemploEntrenamiento:
    # === campos V1 (sin cambio) ===
    instruccion: str
    salida: str
    entrada: str = ""
    nivel: str = "basico"
    tema: str = "otro"
    tipo: str = "explicacion_codigo"
    fuente: str = "semilla"
    metadata: dict[str, Any] = field(default_factory=dict)

    # === campos V2 (opcionales, None = no aplica) ===
    pensamiento: dict[str, Any] | None = None
    explicacion_por_nivel: dict[str, str] | None = None
    alternativas: list[dict[str, Any]] | None = None
    errores_comunes: list[str] | None = None
    revision_codigo: dict[str, Any] | None = None
    puntuacion: dict[str, int] | None = None
    version_evolutiva: str | None = None
    tags: list[str] = field(default_factory=list)

    def es_valido(self) -> tuple[bool, str]:
        # Validaciones V1 (no se relajan)
        if not self.instruccion or not self.instruccion.strip():
            return False, "instruccion vacía"
        if not self.salida or len(self.salida.strip()) < 10:
            return False, "salida vacía o demasiado corta"
        if self.nivel not in NIVELES:
            return False, f"nivel inválido: {self.nivel}"
        if self.tipo not in TIPOS:
            return False, f"tipo inválido: {self.tipo}"

        # Validaciones V2 (solo si el campo está poblado)
        if self.explicacion_por_nivel is not None:
            faltan = [n for n in NIVELES_PEDAGOGICOS if n not in self.explicacion_por_nivel]
            if faltan:
                return False, f"explicacion_por_nivel incompleta: faltan {faltan}"

        if self.version_evolutiva is not None and self.version_evolutiva not in VERSIONES_EVOLUTIVAS:
            return False, f"version_evolutiva inválida: {self.version_evolutiva}"

        if self.puntuacion is not None:
            for dim, val in self.puntuacion.items():
                if dim not in DIMENSIONES_PUNTUACION:
                    return False, f"dimensión de puntuación inválida: {dim}"
                if not isinstance(val, int) or not (0 <= val <= 10):
                    return False, f"puntuación {dim}={val} fuera de [0,10]"

        if self.pensamiento is not None:
            # 'pensamiento' admite DOS estructuras según el tipo:
            #   1) planeación: alternativas_consideradas + criterios_decision
            #   2) autocrítica: iteraciones [{version, codigo, critica}, ...]
            tiene_iteraciones = "iteraciones" in self.pensamiento
            tiene_alternativas = "alternativas_consideradas" in self.pensamiento
            if not tiene_iteraciones and not tiene_alternativas:
                return False, "pensamiento debe tener 'iteraciones' o 'alternativas_consideradas'"
            if tiene_iteraciones:
                its = self.pensamiento.get("iteraciones")
                if not isinstance(its, list) or len(its) < 2:
                    return False, "iteraciones requiere lista con al menos 2 elementos"
            elif tiene_alternativas:
                if "criterios_decision" not in self.pensamiento:
                    return False, "pensamiento (planeación) requiere 'criterios_decision'"

        return True, "ok"

    def clave_dedup(self) -> str:
        # Incluye version_evolutiva para que distintas vN del mismo prompt
        # NO se consideren duplicadas.
        version = self.version_evolutiva or ""
        return "||".join((
            self.instruccion.strip().lower(),
            self.entrada.strip().lower(),
            version,
        ))

    def to_dict(self) -> dict[str, Any]:
        d = asdict(self)
        # No serializar campos V2 None (mantiene archivos pequeños y
        # compatibles con consumidores V1).
        opcionales_v2 = (
            "pensamiento", "explicacion_por_nivel", "alternativas",
            "errores_comunes", "revision_codigo", "puntuacion",
            "version_evolutiva",
        )
        for k in opcionales_v2:
            if d.get(k) is None:
                d.pop(k, None)
        if not d.get("tags"):
            d.pop("tags", None)
        return d

    @classmethod
    def from_dict(cls, d: dict[str, Any]) -> "EjemploEntrenamiento":
        return cls(
            instruccion=d.get("instruccion", ""),
            salida=d.get("salida", ""),
            entrada=d.get("entrada", ""),
            nivel=d.get("nivel", "basico"),
            tema=d.get("tema", "otro"),
            tipo=d.get("tipo", "explicacion_codigo"),
            fuente=d.get("fuente", "semilla"),
            metadata=d.get("metadata", {}) or {},
            pensamiento=d.get("pensamiento"),
            explicacion_por_nivel=d.get("explicacion_por_nivel"),
            alternativas=d.get("alternativas"),
            errores_comunes=d.get("errores_comunes"),
            revision_codigo=d.get("revision_codigo"),
            puntuacion=d.get("puntuacion"),
            version_evolutiva=d.get("version_evolutiva"),
            tags=list(d.get("tags") or []),
        )
