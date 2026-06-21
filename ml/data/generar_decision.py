"""Generador de `decision_diseno` — comparativas tecnologicas con razones.

Cada ejemplo es una decision tecnica explicada: PostgreSQL vs MongoDB,
FastAPI vs Flask, JWT vs sessions, etc. La salida muestra el proceso
mental, no solo "X es mejor". Esto entrena al modelo a razonar antes
de recomendar.
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


# 30 decisiones canonicas en backend / data / web / devops.
DECISIONES: tuple[tuple[str, str], ...] = (
    # (pregunta, tema)
    ("¿PostgreSQL o MongoDB para una API de e-commerce?", "base_de_datos"),
    ("¿FastAPI o Flask para una API REST nueva en 2026?", "frameworks_web"),
    ("¿Django o FastAPI para SaaS B2B con admin panel?", "frameworks_web"),
    ("¿JWT o session cookies para autenticacion web?", "autenticacion"),
    ("¿OAuth2 o tokens propios para terceros?", "autenticacion"),
    ("¿SQLAlchemy o SQLModel o Tortoise ORM?", "orm"),
    ("¿Redis o Memcached para cache de sesion?", "cache"),
    ("¿RabbitMQ o Kafka para colas de eventos?", "mensajeria"),
    ("¿Celery o Dramatiq o RQ para tareas async?", "tareas_async"),
    ("¿Docker Compose o Kubernetes para deploy temprano?", "deploy"),
    ("¿REST o GraphQL o gRPC para API publica?", "api_design"),
    ("¿Pydantic v1 o v2 (migracion)?", "validacion"),
    ("¿asyncio o threading o multiprocessing en CPU-bound?", "concurrencia"),
    ("¿poetry o uv o pip-tools para dependencias?", "tooling"),
    ("¿pytest o unittest en proyecto nuevo?", "testing"),
    ("¿logging stdlib o structlog o loguru?", "logging"),
    ("¿Prometheus o OpenTelemetry para metricas?", "observabilidad"),
    ("¿GitHub Actions o GitLab CI para un solo repo?", "ci_cd"),
    ("¿Postgres pgvector o Qdrant o Chroma para RAG?", "vector_db"),
    ("¿Pandas o Polars o DuckDB para ETL local?", "data_engineering"),
    ("¿NumPy o JAX para prototipos ML?", "ml_frameworks"),
    ("¿venv o conda o uv para entornos?", "tooling"),
    ("¿Argon2 o bcrypt o scrypt para passwords?", "criptografia"),
    ("¿HTTPS via Caddy o Nginx + Certbot?", "infra"),
    ("¿migrate con Alembic o Atlas?", "migraciones"),
    ("¿CDN ante S3 estatico: Cloudflare o CloudFront?", "infra"),
    ("¿pytest-asyncio o anyio para test async?", "testing"),
    ("¿Pyright o Mypy para type checking?", "tooling"),
    ("¿uvicorn o gunicorn+uvicorn workers en produccion?", "servidor"),
    ("¿WebSockets o Server-Sent Events para tiempo real?", "tiempo_real"),
)


PROMPT_TEMPLATE = """Eres un arquitecto de software ayudando a un estudiante
a tomar una decision tecnica. Genera UN ejemplo de dataset que responda:

Pregunta: {pregunta}
Contexto general: para un estudiante de ciencias de la computacion / dev junior-mid.

Devuelve un array JSON con UN solo elemento. Estructura:

[
  {{
    "instruccion": "{pregunta}",
    "salida": "<respuesta pedagogica completa de 500+ chars que incluya:
       1) en una linea: la recomendacion;
       2) cuando elegir A;
       3) cuando elegir B (y C si aplica);
       4) errores comunes al elegir mal;
       5) regla heuristica para futuras decisiones similares>",
    "nivel": "intermedio",
    "tema": "{tema}",
    "tipo": "decision_diseno",
    "pensamiento": {{
       "aclaraciones": [array de 1-3 preguntas que un arquitecto pediria antes de responder],
       "restricciones_implicitas": [array de 2-4 supuestos que la respuesta asume],
       "alternativas_consideradas": [array de 2-4 objetos:
         {{"opcion": "<nombre>", "elegida": true|false, "razon": "<frase corta>"}}
         (EXACTAMENTE una con elegida=true)
       ],
       "criterios_decision": [array de 3-5 criterios usados para decidir]
    }}
  }}
]

REGLAS:
  - Solo el array JSON.
  - La recomendacion debe ser DEFENDIBLE (no "depende"; di QUE elegir y por que).
  - Cita criterios concretos (latencia, escalabilidad, curva de aprendizaje, costo).
  - NO inventes versiones especificas de libs si no estas seguro.
"""


async def generar_objetivo(
    pool: Pool, pregunta: str, tema: str, *, temperatura: float
) -> list[EjemploEntrenamiento]:
    prompt = PROMPT_TEMPLATE.format(pregunta=pregunta, tema=tema)
    try:
        texto, proveedor = await pool.generar(
            prompt, tarea=Tarea.COT, temperatura=temperatura,
            max_tokens=3072, esperar_si_rate_limited=True,
        )
    except Exception as exc:
        print(f"  [!] {pregunta[:40]}: {exc}", file=sys.stderr)
        return []

    bruto = extraer_json_array(texto) or []
    ejemplos: list[EjemploEntrenamiento] = []
    for d in bruto:
        if not isinstance(d, dict):
            continue
        d["tipo"] = "decision_diseno"
        d.setdefault("tema", tema)
        d.setdefault("nivel", "intermedio")
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

    total = len(DECISIONES) * repeticiones
    contador = 0
    for pregunta, tema in DECISIONES:
        for r in range(repeticiones):
            contador += 1
            print(f"[{contador:3d}/{total}] {pregunta[:50]} (rep {r+1})", flush=True)
            lote = await generar_objetivo(pool, pregunta, tema, temperatura=temperatura)
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
                        help="Cuantas veces pedir la misma decision (variar fraseo)")
    parser.add_argument("--temperatura", type=float, default=0.85)
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
