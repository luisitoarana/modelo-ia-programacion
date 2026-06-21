"""Generador de `arquitectura_sistema` — disenos end-to-end de sistemas.

Cada ejemplo presenta un problema de sistemas (red social para 1M users,
ETL diario, video streaming, etc.) y la arquitectura propuesta con
tradeoffs. Es el dataset mas "caro" de generar bien — pocos ejemplos pero
de alta calidad.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import sys
import time
from pathlib import Path
from typing import Any

from ml.data.corpus import deduplicar, estadisticas_corpus, guardar_jsonl
from ml.data.pool_generadores import Pool, Tarea, extraer_json_array
from ml.data.schema import EjemploEntrenamiento
from ml.data.validadores import validar_ejemplo


# 25 sistemas tipicos para system design. Inspirados en problemas
# clasicos de entrevistas + casos reales utiles para enseñanza.
SISTEMAS: tuple[str, ...] = (
    "Red social para 1 millon de usuarios con feed personalizado",
    "Plataforma de cursos online con video y quizzes (10k estudiantes simultaneos)",
    "Sistema de chat en tiempo real (estilo WhatsApp simplificado)",
    "Servicio de acortador de URLs con metricas",
    "Plataforma de e-commerce con catalogo de 100k productos",
    "Sistema de notificaciones push multi-canal (email, SMS, push)",
    "Pipeline ETL diario que ingiere 100GB y produce reportes",
    "Servicio de busqueda full-text sobre 10M documentos",
    "Sistema de pagos: cobros recurrentes + reembolsos + auditoria",
    "Plataforma de streaming de audio (estilo Spotify simplificado)",
    "Sistema de reservas tipo Airbnb con disponibilidad en tiempo real",
    "Marketplace P2P con sistema de reputacion",
    "Plataforma de telemetria IoT (1M dispositivos enviando cada 10s)",
    "Servicio de feature flags + A/B testing",
    "Sistema de file storage estilo Dropbox con sync",
    "Backend para un juego multiplayer con leaderboard",
    "Sistema de delivery con tracking en tiempo real",
    "Plataforma de blogging con comentarios y moderacion",
    "Sistema de gestion documental con OCR y firma electronica",
    "Plataforma de tickets / soporte con SLA",
    "Servicio de monitoreo de uptime de sitios externos",
    "Sistema de recomendaciones colaborativo en tiempo real",
    "Plataforma de cursos sincronos con whiteboard compartido",
    "Sistema de email marketing con segmentacion",
    "Backend de banca digital basica (cuentas, transferencias, historial)",
)


PROMPT_TEMPLATE = """Eres un arquitecto de sistemas senior. Disena la
arquitectura del siguiente sistema y explica las decisiones para un
estudiante avanzado.

Sistema a disenar: {sistema}

Genera UN ejemplo en un array JSON de UN elemento:

[
  {{
    "instruccion": "Disena la arquitectura para: {sistema}",
    "salida": "<respuesta de 600+ chars que incluya:
       1) Requisitos asumidos (funcionales + no funcionales: latencia, escala);
       2) Componentes principales (lista con rol de cada uno);
       3) Diagrama TEXTUAL (con ASCII o lista jerarquica) del flujo;
       4) Stack recomendado (con razones, no nombres sueltos);
       5) Modelo de datos a alto nivel;
       6) Como escala (que se replica, que se sharda, que cachea);
       7) Tradeoffs explicitos: que sacrificas eligiendo esta arquitectura;
       8) Que NO incluiria en MVP (para no over-engineer)>",
    "nivel": "avanzado",
    "tema": "arquitectura",
    "tipo": "arquitectura_sistema",
    "pensamiento": {{
       "aclaraciones": [array de 2-4 preguntas que un arquitecto pediria al cliente],
       "restricciones_implicitas": [array de 3-5 supuestos: latencia objetivo, presupuesto, equipo],
       "alternativas_consideradas": [array de 3-4 alternativas arquitectonicas:
         {{"opcion": "<descripcion corta>", "elegida": true|false, "razon": "<frase>"}}
         (EXACTAMENTE una con elegida=true)
       ],
       "criterios_decision": [array de 3-5 criterios: escalabilidad, complejidad operativa, costo, consistencia, etc.]
    }}
  }}
]

REGLAS:
  - Solo el array JSON.
  - La arquitectura debe ser DEFENDIBLE para el caso de uso, no maximalista.
  - Cita tecnologias concretas con razones (no "una BD" -> "PostgreSQL por X").
  - Manten en cuenta el coste/equipo (no proponer Kubernetes para 100 usuarios).
"""


async def generar_objetivo(
    pool: Pool, sistema: str, *, temperatura: float
) -> list[EjemploEntrenamiento]:
    prompt = PROMPT_TEMPLATE.format(sistema=sistema)
    try:
        texto, proveedor = await pool.generar(
            prompt, tarea=Tarea.COT, temperatura=temperatura,
            max_tokens=4096, esperar_si_rate_limited=True,
        )
    except Exception as exc:
        print(f"  [!] {sistema[:40]}: {exc}", file=sys.stderr)
        return []

    bruto = extraer_json_array(texto) or []
    ejemplos: list[EjemploEntrenamiento] = []
    for d in bruto:
        if not isinstance(d, dict):
            continue
        d["tipo"] = "arquitectura_sistema"
        d.setdefault("tema", "arquitectura")
        d.setdefault("nivel", "avanzado")
        d["fuente"] = proveedor
        try:
            ejemplos.append(EjemploEntrenamiento.from_dict(d))
        except Exception:  # noqa: BLE001
            continue
    return ejemplos


async def generar_corpus(
    pool: Pool, salida: Path, *, repeticiones: int, temperatura: float,
) -> dict[str, Any]:
    todos: list[EjemploEntrenamiento] = []
    descartes: dict[str, int] = {}
    inicio = time.time()

    total = len(SISTEMAS) * repeticiones
    contador = 0
    for sistema in SISTEMAS:
        for r in range(repeticiones):
            contador += 1
            print(f"[{contador:3d}/{total}] {sistema[:60]} (rep {r+1})", flush=True)
            lote = await generar_objetivo(pool, sistema, temperatura=temperatura)
            for ej in lote:
                ok, motivo = validar_ejemplo(ej)
                if ok:
                    todos.append(ej)
                else:
                    k = motivo.split(":", 1)[0]
                    descartes[k] = descartes.get(k, 0) + 1

    antes = len(todos)
    todos = deduplicar(todos)
    guardar_jsonl(todos, salida)
    stats = estadisticas_corpus(todos)
    stats.update({
        "archivo": str(salida),
        "duplicados_eliminados": antes - len(todos),
        "descartados_por_motivo": descartes,
        "tiempo_minutos": round((time.time() - inicio) / 60, 1),
        "pool_stats": pool.stats(),
    })
    return stats


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--salida", required=True)
    parser.add_argument("--repeticiones", type=int, default=4,
                        help="Cuantas veces pedir cada sistema (variando enfoque)")
    parser.add_argument("--temperatura", type=float, default=0.9)
    args = parser.parse_args()

    pool = Pool.desde_env()
    print(f"Pool activo: {pool.disponibles}")

    stats = asyncio.run(generar_corpus(
        pool, Path(args.salida),
        repeticiones=args.repeticiones, temperatura=args.temperatura,
    ))
    print("\n=== RESULTADO ===")
    print(json.dumps(stats, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
