"""Generador de `evolucion_codigo` — mismo problema, 5 versiones de calidad.

Para cada problema (un endpoint, un servicio, una funcion), pedimos al
LLM las 5 versiones del mismo codigo, mostrando como evoluciona de
"funciona" a "production-grade":

    v1_junior        funciona, sin proteccion
    v2_junior_plus   con validacion basica
    v3_mid           try/except, status codes, type hints
    v4_senior        inyeccion de dependencias, repository, tests
    v5_staff         idempotency, rate limit, observability

Esto entrena al modelo a entender "mejor" como gradiente, no dicotomia.
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
from ml.data.schema import EjemploEntrenamiento, VERSIONES_EVOLUTIVAS
from ml.data.validadores import validar_ejemplo


# Cada problema generara los 5 niveles. Empezamos con problemas tipicos.
PROBLEMAS: tuple[str, ...] = (
    "Endpoint para crear un usuario (POST /users)",
    "Endpoint para autenticar (POST /login con JWT)",
    "Endpoint de busqueda con filtros (GET /products?q=...)",
    "Endpoint para subir un archivo (POST /upload)",
    "Worker que procesa una cola de tareas",
    "Funcion que envia email transaccional",
    "Funcion que cobra un pago con un provider",
    "Funcion que sincroniza datos entre dos sistemas",
    "Endpoint que devuelve dashboard agregado",
    "Funcion que genera reporte PDF",
    "Funcion que importa un CSV grande a BD",
    "Endpoint para actualizar perfil de usuario",
    "Funcion que invalida cache distribuido",
    "Servicio que valida y normaliza una direccion postal",
    "Funcion que reintenta una llamada HTTP",
)


DESCRIPCIONES_VERSIONES = {
    "v1_junior": (
        "Solo funcionalidad happy path. Sin validacion, sin manejo de errores, "
        "sin types, sin tests. El codigo MINIMO que cumple la peticion."
    ),
    "v2_junior_plus": (
        "Agrega validacion basica de input (campos requeridos, tipos). "
        "Sigue siendo simple pero no acepta cualquier basura."
    ),
    "v3_mid": (
        "Type hints completos, manejo de errores especifico, status codes "
        "HTTP correctos, Pydantic/dataclass para input, logs basicos."
    ),
    "v4_senior": (
        "Inyeccion de dependencias, repository pattern, separacion de capas, "
        "unit tests del happy path y al menos 2 edge cases, manejo robusto."
    ),
    "v5_staff": (
        "Idempotency key, rate limit, observability (metrics + tracing), "
        "feature flags, retry/backoff, audit log, consideraciones de seguridad "
        "(autorizacion, sanitizacion), tests de integracion completos."
    ),
}


PROMPT_TEMPLATE = """Eres un programador senior generando un dataset que
muestra COMO evoluciona el codigo del MISMO PROBLEMA cuando lo escribe un
junior, despues un mid, despues un senior, despues un staff.

Este dataset es CRITICO porque ensena al modelo que "mejor codigo" no es una
dicotomia bueno/malo, sino un GRADIENTE de calidad. Cada nivel es una
fotografia de un programador real con cierta experiencia.

Problema: {problema}

Genera EXACTAMENTE 5 ejemplos como ARRAY JSON, uno por nivel:

  1. v1_junior         — {desc_v1}
  2. v2_junior_plus    — {desc_v2}
  3. v3_mid            — {desc_v3}
  4. v4_senior         — {desc_v4}
  5. v5_staff          — {desc_v5}

Estructura de cada elemento:

  "instruccion": "Resuelve: {problema}" + sufijo que indique nivel
                 (varia: "version basica", "como lo haria un senior",
                 "production-grade", etc.).

  "salida": Estructura interna (>=350 chars):
       1) Una linea con la version: "**Version v3_mid**".
       2) Codigo Python COMPLETO en ```python ... ``` con type hints
          apropiados a la version (v1 puede no tener, v5 si).
       3) "Que mejora respecto a la version anterior" — 2-4 puntos
          concretos (v1 no tiene anterior, asi que explica que cubre).
       4) "Que sigue faltando" — 1-3 puntos que la siguiente version
          arreglara (excepto v5).
       5) "Cuando esta version es suficiente" — un parrafo con el
          escenario donde NO se necesita escalar a la siguiente version
          (porque overengineering tambien es un antipatron).

  "nivel": "intermedio"
  "tema": "evolucion_de_codigo"
  "tipo": "evolucion_codigo"
  "version_evolutiva": uno EXACTO de v1_junior | v2_junior_plus | v3_mid |
                       v4_senior | v5_staff (en orden, uno por elemento).

REGLAS ESTRICTAS:
  - Las 5 versiones DEBEN resolver EXACTAMENTE el MISMO problema (misma
    firma de funcion / mismo endpoint / mismo contrato externo).
  - Misma interfaz publica, distinta implementacion interna.
  - Cada version sucesiva agrega VALOR REAL: validacion, manejo de error,
    tests, observabilidad, idempotency, etc. NO cosmetica.
  - El codigo de TODOS los niveles debe COMPILAR (sintacticamente valido).
  - v5 staff: production-grade. Incluye idempotency, retry/backoff,
    rate-limit interno, observabilidad (metrics + tracing hooks),
    feature flag, error model, etc. NO debe verse exagerado ni academico.
  - Solo el array JSON. SIN texto antes/despues.

IMPORTANTE — diferenciacion clara entre niveles:
  v1: tipicamente 5-15 lineas. Sin tests. Sin error handling. Sin types.
  v2: agrega 1-3 validaciones de input y un try/except minimo.
  v3: 30-60 lineas. Type hints. Status codes correctos. Pydantic/dataclass.
  v4: 80-150 lineas. Repository pattern. Inyeccion. Unit tests del happy +
      2 edge cases.
  v5: 150-300 lineas. Idempotency key. Rate limit. OpenTelemetry hooks.
      Audit log. Tests de integracion + property based + edge cases.
"""


async def generar_problema(
    pool: Pool, problema: str, *, temperatura: float
) -> list[EjemploEntrenamiento]:
    prompt = PROMPT_TEMPLATE.format(
        problema=problema,
        desc_v1=DESCRIPCIONES_VERSIONES["v1_junior"],
        desc_v2=DESCRIPCIONES_VERSIONES["v2_junior_plus"],
        desc_v3=DESCRIPCIONES_VERSIONES["v3_mid"],
        desc_v4=DESCRIPCIONES_VERSIONES["v4_senior"],
        desc_v5=DESCRIPCIONES_VERSIONES["v5_staff"],
    )
    try:
        texto, proveedor = await pool.generar(
            prompt, tarea=Tarea.CODIGO, temperatura=temperatura,
            max_tokens=6144, esperar_si_rate_limited=True,
        )
    except Exception as exc:
        print(f"  [!] {problema}: {exc}", file=sys.stderr)
        return []

    bruto = extraer_json_array(texto) or []
    ejemplos: list[EjemploEntrenamiento] = []
    for d in bruto:
        if not isinstance(d, dict):
            continue
        d["tipo"] = "evolucion_codigo"
        d.setdefault("tema", "evolucion_de_codigo")
        d.setdefault("nivel", "intermedio")
        d["fuente"] = proveedor
        # Validar que version_evolutiva sea una de las permitidas
        if d.get("version_evolutiva") not in VERSIONES_EVOLUTIVAS:
            continue
        try:
            ejemplos.append(EjemploEntrenamiento.from_dict(d))
        except Exception:  # noqa: BLE001
            continue
    return ejemplos


async def generar_corpus(
    pool: Pool, salida: Path, *, temperatura: float,
) -> dict[str, Any]:
    todos: list[EjemploEntrenamiento] = []
    descartes: dict[str, int] = {}
    inicio = time.time()

    for i, problema in enumerate(PROBLEMAS, 1):
        print(f"[{i:2d}/{len(PROBLEMAS)}] problema: {problema[:50]}", flush=True)
        cinco = await generar_problema(pool, problema, temperatura=temperatura)
        # Avisar si no llegaron las 5 versiones.
        versiones_obtenidas = {ej.version_evolutiva for ej in cinco}
        faltantes = set(VERSIONES_EVOLUTIVAS) - versiones_obtenidas
        if faltantes:
            print(f"    aviso: faltan versiones {sorted(faltantes)}", file=sys.stderr)
        for ej in cinco:
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
    parser.add_argument("--temperatura", type=float, default=0.7)
    args = parser.parse_args()

    pool = Pool.desde_env()
    print(f"Pool activo: {pool.disponibles}")

    stats = asyncio.run(generar_corpus(
        pool, Path(args.salida), temperatura=args.temperatura,
    ))
    print("\n=== RESULTADO ===")
    print(json.dumps(stats, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
