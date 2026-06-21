"""Generador de `bug_sutil` — bugs lógicos que un junior no ve.

NO errores de sintaxis (esos los detecta el intérprete). Bugs que pasan
los tests obvios pero rompen en edge cases. Este dataset entrena el
"ojo de senior" — la capacidad de mirar código aparentemente correcto y
detectar el problema sutil.
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


# 25 categorías canónicas de bugs sutiles.
CATEGORIAS_BUGS: tuple[tuple[str, str], ...] = (
    ("off_by_one", "for i in range(len(lista)+1) o slicing [0:n+1]"),
    ("lista_vacia_no_manejada", "min/max/sum sobre lista vacia, division por cero implicita"),
    ("mutable_default_argument", "def f(x=[]): comparte estado"),
    ("float_comparison", "if x == 0.1 + 0.2 (False por precision binaria)"),
    ("integer_overflow_logico", "asume int 32-bit cuando Python es arbitrary precision"),
    ("late_binding_en_closures", "[lambda: i for i in range(n)] captura por referencia"),
    ("modificar_lista_durante_iteracion", "for x in lista: lista.remove(x)"),
    ("encoding_implicito", "open() sin encoding='utf-8' en Windows"),
    ("timezone_naive", "datetime.now() sin tz info, comparar con aware"),
    ("dict_orden_asumido", "asumir orden de iteracion en Python <3.7"),
    ("compartir_referencias", "[ [] ] * 3 crea 3 referencias al mismo []"),
    ("is_vs_eq", "if x is 256 (CPython optimiza int pequenos, falla con grandes)"),
    ("regex_codicioso", ".* que captura mas de lo esperado"),
    ("race_condition_en_async", "modificar variable compartida sin lock"),
    ("excepcion_traga_traceback", "except Exception: raise SomeOtherException sin from"),
    ("recursion_sin_caso_base", "limite de recursion alcanzado en input grande"),
    ("dependencia_de_orden_de_dict", "{**a, **b} si se asume comportamiento especifico"),
    ("comparar_None_con_eq", "if x == None vs is None"),
    ("compartir_archivo_descriptor", "no cerrar archivo en path de error"),
    ("dividir_int_por_int", "asumir resultado float en Python 2 vs 3"),
    ("modificar_kwargs_dict", "kwargs es referencia, no copia"),
    ("operador_walrus_mal_alcanzado", "(:=) en list comp con scope confuso"),
    ("set_no_garantiza_orden", "list(set(x)) cambia orden inesperadamente"),
    ("max_con_key_y_lista_vacia", "max(lista, key=...) con lista vacia lanza ValueError"),
    ("cache_lru_con_argumentos_no_hashables", "lru_cache falla con lista/dict como arg"),
)


PROMPT_TEMPLATE = """Eres un revisor senior entrenando estudiantes. Genera
ejemplos del bug sutil "{categoria}" en codigo Python real.

Descripcion: {descripcion}

Devuelve {n} ejemplos como ARRAY JSON. Cada uno:

  "instruccion": "Revisa esta funcion. ¿Tiene algun problema?" (varia el fraseo)
  "entrada": codigo Python REAL que CONTIENE el bug sutil. Debe:
       - compilar (sintacticamente valido)
       - parecer correcto a primera vista
       - pasar tests obvios
       - romper en un edge case especifico
  "salida": explicacion pedagogica:
       1) "Si, hay un bug sutil: <descripcion>"
       2) que entrada lo dispara (ejemplo concreto)
       3) por que pasa (tecnicamente)
       4) version corregida en ```python ... ```
       5) por que la correccion es robusta
       (minimo 350 chars)
  "nivel": "intermedio" o "avanzado" segun complejidad
  "tema": "debugging"
  "tipo": "bug_sutil"
  "tags": ["{categoria}"]
  "errores_comunes": [array de 2-3 strings con que suele equivocarse un estudiante aqui]

REGLAS:
  - Solo el array JSON.
  - Cada ejemplo del array debe usar un CONTEXTO distinto (web API, ML, scripting, CLI).
  - El codigo de "entrada" DEBE compilar.
  - NO mostrar el bug como comentario en el codigo: el codigo se ve normal.
"""


async def generar_objetivo(
    pool: Pool, categoria: str, descripcion: str, n: int, *, temperatura: float
) -> list[EjemploEntrenamiento]:
    prompt = PROMPT_TEMPLATE.format(categoria=categoria, descripcion=descripcion, n=n)
    try:
        texto, proveedor = await pool.generar(
            prompt, tarea=Tarea.CODIGO, temperatura=temperatura,
            max_tokens=4096, esperar_si_rate_limited=True,
        )
    except Exception as exc:
        print(f"  [!] {categoria}: {exc}", file=sys.stderr)
        return []

    bruto = extraer_json_array(texto) or []
    ejemplos: list[EjemploEntrenamiento] = []
    for d in bruto:
        if not isinstance(d, dict):
            continue
        d["tipo"] = "bug_sutil"
        d.setdefault("tema", "debugging")
        d.setdefault("nivel", "intermedio")
        d["fuente"] = proveedor
        d.setdefault("tags", [categoria])
        try:
            ejemplos.append(EjemploEntrenamiento.from_dict(d))
        except Exception:  # noqa: BLE001
            continue
    return ejemplos


async def generar_corpus(
    pool: Pool, salida: Path, *,
    n_por_categoria: int, temperatura: float,
) -> dict[str, Any]:
    todos: list[EjemploEntrenamiento] = []
    descartes: dict[str, int] = {}
    inicio = time.time()

    for i, (categoria, desc) in enumerate(CATEGORIAS_BUGS, 1):
        print(f"[{i:2d}/{len(CATEGORIAS_BUGS)}] bug: {categoria}", flush=True)
        lote = await generar_objetivo(
            pool, categoria, desc, n_por_categoria, temperatura=temperatura
        )
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
    parser.add_argument("--n-por-categoria", type=int, default=6)
    parser.add_argument("--temperatura", type=float, default=0.85)
    args = parser.parse_args()

    pool = Pool.desde_env()
    print(f"Pool activo: {pool.disponibles}")

    stats = asyncio.run(generar_corpus(
        pool, Path(args.salida),
        n_por_categoria=args.n_por_categoria, temperatura=args.temperatura,
    ))
    print("\n=== RESULTADO ===")
    print(json.dumps(stats, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
