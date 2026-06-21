"""Generador de `anti_patron` — código que funciona pero es malo.

Esto rara vez aparece en corpus open: la mayoría de datasets enseñan
"código bueno". Para que el modelo aprenda ojo crítico, necesita ver
mucho código *que pasa los tests pero sería rechazado en code review*,
con explicación detallada del problema.

Cada ejemplo tiene `revision_codigo` con:
    - problemas (lista, mínimo 1)
    - por_que_funciona_pero_es_malo
    - problema_en_produccion
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


# 30 antipatrones canónicos. Cada uno se expandirá en varios ejemplos.
ANTIPATRONES: tuple[tuple[str, str, str], ...] = (
    # (nombre, descripcion corta, nivel)
    ("cadena_de_elif_para_roles", "if/elif gigante donde hay mapeo natural a dict", "intermedio"),
    ("magic_numbers_dispersos", "constantes literales repetidas en muchos sitios", "intermedio"),
    ("god_function", "funcion de 100+ lineas que hace todo", "intermedio"),
    ("bare_except", "`except:` o `except Exception` que oculta bugs", "intermedio"),
    ("mutable_default_args", "def f(x=[]) que comparte estado entre llamadas", "intermedio"),
    ("global_state_oculto", "variables globales modificadas desde funciones", "intermedio"),
    ("loops_con_indices_innecesarios", "for i in range(len(lista)) en vez de enumerate", "basico"),
    ("string_concatenacion_en_loop", "s += x dentro de loop en vez de join", "basico"),
    ("if_else_redundante_de_bool", "if x: return True else: return False", "basico"),
    ("deep_nesting_de_ifs", "5+ niveles de indentacion", "intermedio"),
    ("hardcoded_secrets", "password='admin123' en codigo", "intermedio"),
    ("sin_context_manager", "open(...) sin with, fugas de archivos", "basico"),
    ("eval_o_exec_innecesario", "eval(input()) para parsear numeros", "intermedio"),
    ("import_dentro_de_funcion_caliente", "import en cada llamada", "intermedio"),
    ("comparacion_con_True_False", "if x == True", "basico"),
    ("recreacion_de_objetos_costosos", "crear regex/conexion en cada iteracion", "intermedio"),
    ("type_check_con_type_eq", "type(x) == list en vez de isinstance", "intermedio"),
    ("docstring_que_repite_el_nombre", "def sumar(): '''suma'''", "basico"),
    ("try_except_que_traga_silenciosamente", "except: pass", "intermedio"),
    ("copia_manual_de_lista", "copia = []; for x in lista: copia.append(x)", "basico"),
    ("uso_de_listas_para_busqueda", "if x in lista_de_100k vs set", "intermedio"),
    ("strings_concatenados_para_SQL", "query = 'SELECT * FROM ' + tabla", "intermedio"),
    ("dependencias_circulares", "modulo A importa B que importa A", "avanzado"),
    ("inheritance_para_reuso_de_codigo", "subclasear solo para usar 2 metodos", "avanzado"),
    ("comentarios_que_repiten_codigo", "x += 1  # incrementa x", "basico"),
    ("validacion_dispersa", "if x is None en 20 sitios distintos", "intermedio"),
    ("singleton_global_mutable", "configuracion como dict modificable", "intermedio"),
    ("conexion_a_BD_sin_pool", "psycopg2.connect en cada request", "intermedio"),
    ("captura_de_KeyboardInterrupt", "except Exception captura Ctrl+C", "intermedio"),
    ("manejo_de_errores_con_None", "return None vs raise; usuario chequea", "intermedio"),
)


PROMPT_TEMPLATE = """Eres un revisor de codigo senior con 10+ anios. Generas
ejemplos de dataset que muestran el ANTIPATRON "{antipatron_nombre}", lo
explican como un mentor a un junior, y lo refactorizan a codigo senior con
justificacion explicita del cambio.

Descripcion del antipatron: {antipatron_desc}

La idea pedagogica clave (transformacion):

   Codigo malo (junior tipico) -> Codigo senior

El junior debe entender NO SOLO el cambio mecanico, sino POR QUE el cambio
es mejor en cada dimension: legibilidad, mantenibilidad, performance,
seguridad, escalabilidad.

Devuelve {n} ejemplos como ARRAY JSON. Cada elemento tiene:

  "instruccion": "Revisa este codigo y dime si tiene problemas" o variante
                 similar (varia el fraseo: "este codigo paso review?",
                 "que problemas ves aqui?", "como mejorarias esto?")

  "entrada": codigo Python REAL que muestra el antipatron, sintacticamente
             valido pero malo. Debe ser realista (algo que un junior
             escribiria en un Pull Request real).

  "salida": explicacion pedagogica como un MENTOR a un JUNIOR (>=500 chars):
       1) "Lo que veo aqui es ANTIPATRON X" (nombrar el problema).
       2) Diagnostico tecnico: por que pasa, que sintoma genera.
       3) Por que funciona pero es malo (cuando se rompe).
       4) Codigo refactorizado dentro de ```python ... ``` con type hints.
       5) Comparativa explicita: "antes era O(n^2), ahora es O(n)" o
          "antes ocultaba el error, ahora propaga uno especifico".
       6) Cuando NO refactorizar (cuando el antipatron es aceptable: ej.
          en throwaway scripts, en hot paths probados, etc.).

  "nivel": "{nivel}"
  "tema": "refactorizacion"
  "tipo": "anti_patron"

  "revision_codigo": objeto con:
       "problemas": [array de 2-5 strings; cada uno una falla CONCRETA
                     con nombre tecnico, no general].
       "por_que_funciona_pero_es_malo": "<2-3 lineas explicando que el
                     codigo pasa los tests del happy path pero falla en
                     produccion / escalando / al evolucionarlo>".
       "problema_en_produccion": "<escenario concreto donde explota:
                     'cuando llegan 50 roles', 'cuando un usuario manda
                     1MB', 'cuando dos requests caen al mismo tiempo'>".
       "dimensiones_mejoradas": [2-4 dimensiones donde el refactor gana,
                     ej: "legibilidad", "performance O(n) vs O(n^2)",
                     "seguridad", "mantenibilidad", "testabilidad"].
       "principio_violado": "<principio de diseno violado por el
                     antipatron, ej: 'Single Responsibility',
                     'DRY', 'YAGNI', 'open/closed', 'fail fast'>".

REGLAS ESTRICTAS:
  - Solo el array JSON.
  - Los {n} ejemplos DEBEN ser contextos REALMENTE distintos del mismo
    antipatron (e-commerce, API, ML, CLI, DevOps, data pipeline, etc.).
    No copies el mismo problema con nombres distintos.
  - El codigo en "entrada" debe COMPILAR.
  - El codigo corregido debe ser ESTRICTAMENTE mejor en al menos 2
    dimensiones, no solo cosmetico.
  - El refactor debe seguir conservando el mismo COMPORTAMIENTO funcional
    (mismos inputs -> mismos outputs en el happy path).
  - Variar la longitud y complejidad: algunos antipatrones son simples
    (10 lineas), otros requieren ver mas contexto (40+ lineas).
"""


async def generar_objetivo(
    pool: Pool, nombre: str, desc: str, nivel: str, n: int, *, temperatura: float
) -> list[EjemploEntrenamiento]:
    prompt = PROMPT_TEMPLATE.format(
        antipatron_nombre=nombre, antipatron_desc=desc, nivel=nivel, n=n,
    )
    try:
        texto, proveedor = await pool.generar(
            prompt, tarea=Tarea.CODIGO, temperatura=temperatura,
            max_tokens=4096, esperar_si_rate_limited=True,
        )
    except Exception as exc:
        print(f"  [!] {nombre}: {exc}", file=sys.stderr)
        return []

    bruto = extraer_json_array(texto) or []
    ejemplos: list[EjemploEntrenamiento] = []
    for d in bruto:
        if not isinstance(d, dict):
            continue
        d["tipo"] = "anti_patron"
        d.setdefault("nivel", nivel)
        d.setdefault("tema", "refactorizacion")
        d["fuente"] = proveedor
        d.setdefault("tags", [nombre])
        try:
            ejemplos.append(EjemploEntrenamiento.from_dict(d))
        except Exception:  # noqa: BLE001
            continue
    return ejemplos


async def generar_corpus(
    pool: Pool, salida: Path, *,
    n_por_antipatron: int, temperatura: float,
) -> dict[str, Any]:
    todos: list[EjemploEntrenamiento] = []
    descartes: dict[str, int] = {}
    inicio = time.time()

    for i, (nombre, desc, nivel) in enumerate(ANTIPATRONES, 1):
        print(f"[{i:2d}/{len(ANTIPATRONES)}] antipatron: {nombre}", flush=True)
        lote = await generar_objetivo(
            pool, nombre, desc, nivel, n_por_antipatron, temperatura=temperatura,
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
    parser.add_argument("--n-por-antipatron", type=int, default=5)
    parser.add_argument("--temperatura", type=float, default=0.85)
    args = parser.parse_args()

    pool = Pool.desde_env()
    print(f"Pool activo: {pool.disponibles}")

    stats = asyncio.run(generar_corpus(
        pool, Path(args.salida),
        n_por_antipatron=args.n_por_antipatron, temperatura=args.temperatura,
    ))
    print("\n=== RESULTADO ===")
    print(json.dumps(stats, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
