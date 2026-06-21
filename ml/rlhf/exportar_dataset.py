"""Exporta feedback acumulado en la BD como dataset DPO listo para entrenar.

Genera un .jsonl donde cada línea es:
    { "prompt": ..., "chosen": ..., "rejected": ..., "source": ... }

Estrategias para construir pares:
1) Pares directos: por cada prompt votado positiva Y negativamente,
   tomamos el positivo como `chosen` y el negativo como `rejected`.
2) Bootstrap con juez LLM (Gemini): cuando solo hay 👎, le pedimos a
   Gemini que genere una `chosen` mejorada. Activable con --rlaif.
3) Bootstrap inverso: cuando solo hay 👍, lo dejamos sin par (no
   contribuye a DPO directo). En futuro podría compararse con baseline.

Uso:
    python -m ml.rlhf.exportar_dataset \
        --salida ml/data/dpo_v1.jsonl \
        --min-comentario 0 \
        --marcar-procesados

    # Con generación RLAIF:
    GEMINI_API_KEY=... python -m ml.rlhf.exportar_dataset \
        --salida ml/data/dpo_v1.jsonl --rlaif

Ver: docs/RLHF_PLAN.md
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import sys
from collections import defaultdict
from pathlib import Path
from typing import Iterable

# Hacemos visible el backend desde aquí para reusar sus modelos ORM.
_RAIZ = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(_RAIZ / "backend"))


async def _conectar():
    """Devuelve sesión async y modelos del backend."""
    from app.database import async_session_factory  # type: ignore
    from app.models.feedback import Feedback  # type: ignore

    return async_session_factory, Feedback


async def _generar_chosen_con_gemini(prompt: str, rejected: str) -> str | None:
    """Pide a Gemini una respuesta mejorada para usar como `chosen`."""
    api_key = os.environ.get("GEMINI_API_KEY")
    if not api_key:
        return None
    try:
        import google.generativeai as genai
    except ImportError:
        print("[rlaif] google-generativeai no está instalado, skip", file=sys.stderr)
        return None
    genai.configure(api_key=api_key)
    modelo = genai.GenerativeModel("gemini-2.0-flash-exp")

    instr = (
        "Eres un profesor de Python que ayuda a estudiantes. La siguiente "
        "respuesta fue marcada como deficiente por un usuario. Genera una "
        "respuesta MEJORADA siguiendo la estructura pedagógica: "
        "(1) Qué hace, (2) Por qué, (3) Ejemplo, (4) Ejercicio breve. "
        "Mantén el tono cercano y claro.\n\n"
        f"Pregunta del estudiante:\n{prompt}\n\n"
        f"Respuesta deficiente:\n{rejected}\n\n"
        "Respuesta mejorada:"
    )
    try:
        rsp = await modelo.generate_content_async(instr)
        return rsp.text.strip()
    except Exception as e:
        print(f"[rlaif] error Gemini: {e}", file=sys.stderr)
        return None


async def construir_pares(
    factory,
    Feedback,
    rlaif: bool = False,
    marcar_procesados: bool = False,
) -> Iterable[dict]:
    """Itera la tabla feedbacks y genera pares (chosen, rejected)."""
    async with factory() as ses:
        from sqlalchemy import select

        # Traemos todos los feedbacks no procesados (o todos si se quiere).
        stmt = select(Feedback)
        result = await ses.execute(stmt)
        feedbacks = result.scalars().all()

        # Agrupar por prompt (normalizado) — así podemos cruzar 👍/👎 del
        # mismo prompt si existen.
        por_prompt: dict[str, dict[str, list[Feedback]]] = defaultdict(
            lambda: {"pos": [], "neg": []}
        )
        for fb in feedbacks:
            clave = (fb.prompt or "").strip().lower()
            if fb.voto > 0:
                por_prompt[clave]["pos"].append(fb)
            else:
                por_prompt[clave]["neg"].append(fb)

        ids_procesados: list = []

        # Estrategia 1: pares directos del mismo prompt
        for clave, grupos in por_prompt.items():
            pos = grupos["pos"]
            neg = grupos["neg"]
            for p in pos:
                for n in neg:
                    yield {
                        "prompt": p.prompt,
                        "chosen": p.respuesta,
                        "rejected": n.respuesta,
                        "source": "human_pair",
                        "metadata": {
                            "modelo_chosen": p.modelo,
                            "modelo_rejected": n.modelo,
                            "razon_rejected": n.razon,
                        },
                    }
                    ids_procesados.extend([p.id, n.id])

        # Estrategia 2: RLAIF — para feedbacks 👎 sin contrapar humano
        if rlaif:
            for clave, grupos in por_prompt.items():
                if grupos["pos"]:
                    continue  # ya tiene par humano
                for n in grupos["neg"]:
                    chosen = await _generar_chosen_con_gemini(n.prompt, n.respuesta)
                    if chosen:
                        yield {
                            "prompt": n.prompt,
                            "chosen": chosen,
                            "rejected": n.respuesta,
                            "source": "rlaif_gemini",
                            "metadata": {
                                "modelo_rejected": n.modelo,
                                "razon_rejected": n.razon,
                            },
                        }
                        ids_procesados.append(n.id)

        # Marcar como procesados en la BD si se pidió.
        if marcar_procesados and ids_procesados:
            from sqlalchemy import update

            await ses.execute(
                update(Feedback)
                .where(Feedback.id.in_(ids_procesados))
                .values(procesado=True)
            )
            await ses.commit()


async def main_async(args: argparse.Namespace) -> None:
    factory, Feedback = await _conectar()
    salida = Path(args.salida)
    salida.parent.mkdir(parents=True, exist_ok=True)

    n = 0
    fuentes: dict[str, int] = defaultdict(int)
    with salida.open("w", encoding="utf-8") as f:
        async for par in construir_pares(
            factory, Feedback,
            rlaif=args.rlaif,
            marcar_procesados=args.marcar_procesados,
        ):
            f.write(json.dumps(par, ensure_ascii=False) + "\n")
            n += 1
            fuentes[par["source"]] += 1

    print(f"OK · {n} pares escritos en {salida}")
    for fuente, c in fuentes.items():
        print(f"  - {fuente}: {c}")


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--salida", required=True, help="Ruta del .jsonl de salida")
    p.add_argument(
        "--rlaif",
        action="store_true",
        help="Pide a Gemini que genere `chosen` para los 👎 sin par humano",
    )
    p.add_argument(
        "--marcar-procesados",
        action="store_true",
        help="Marca los feedbacks usados como procesados (no se reusan)",
    )
    args = p.parse_args()
    asyncio.run(main_async(args))


if __name__ == "__main__":
    main()
