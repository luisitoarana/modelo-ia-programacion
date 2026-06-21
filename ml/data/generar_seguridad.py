"""Generador de `seguridad` — OWASP Top 10 + criptografia + secrets.

Cada ejemplo muestra codigo vulnerable + diagnostico + version segura.
Cubre las 10 categorias OWASP y temas transversales (auth, secrets, crypto,
supply chain). Los tags incluyen el ID OWASP cuando aplica.
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


# (categoria_owasp, descripcion_humana, tag_corto)
CATEGORIAS_SEG: tuple[tuple[str, str, str], ...] = (
    ("A01_broken_access_control", "Endpoints sin autorizacion, IDOR, exposicion de objetos por ID", "owasp_a01"),
    ("A02_cryptographic_failures", "MD5/SHA1 para passwords, secrets en logs, HTTP sin TLS", "owasp_a02"),
    ("A03_injection_sql", "SQL injection: concatenacion de strings en queries", "owasp_a03"),
    ("A03_injection_command", "command injection: subprocess con shell=True y user input", "owasp_a03"),
    ("A03_injection_template", "SSTI: render_template_string con user input", "owasp_a03"),
    ("A04_insecure_design", "logica de negocio sin throttle, sin validacion de estado", "owasp_a04"),
    ("A05_security_misconfiguration", "DEBUG=True en prod, CORS *, headers ausentes", "owasp_a05"),
    ("A06_vulnerable_components", "deps con CVE, no se hace pip-audit", "owasp_a06"),
    ("A07_auth_failures", "rate limit ausente en login, recovery por email sin verificar", "owasp_a07"),
    ("A08_software_data_integrity", "deserializacion insegura (pickle), unsafe yaml.load", "owasp_a08"),
    ("A09_logging_failures", "no se loguea, o se loguean passwords, sin alertas", "owasp_a09"),
    ("A10_ssrf", "user provee URL que el server fetcha", "owasp_a10"),
    ("secrets_en_repo", ".env commiteado, API keys en codigo", "secrets"),
    ("crypto_password_hashing", "almacenar passwords con MD5 o sin sal", "crypto"),
    ("crypto_random_inseguro", "random.random() para tokens en vez de secrets", "crypto"),
    ("crypto_aes_modo_ecb", "AES en modo ECB que filtra patrones", "crypto"),
    ("crypto_jwt_alg_none", "JWT que acepta alg=none o secret debil", "crypto"),
    ("crypto_timing_attack", "comparacion de tokens con == en vez de hmac.compare_digest", "crypto"),
    ("xxe_xml", "parseo XML con entidades externas habilitadas", "xxe"),
    ("path_traversal", "user provee filename y se concatena a un path base", "path"),
    ("cors_amplio", "CORS_ORIGINS=['*'] con credentials", "cors"),
    ("clickjacking_sin_xframe", "no se setea X-Frame-Options/CSP frame-ancestors", "headers"),
    ("csrf_sin_token", "POST sin verificacion CSRF en session-based", "csrf"),
    ("file_upload_inseguro", "subir y servir archivos sin validar MIME ni renombrar", "upload"),
    ("supply_chain_pip", "pip install sin pinning ni hashes", "supply_chain"),
)


PROMPT_TEMPLATE = """Eres un especialista en seguridad de aplicaciones.
Genera ejemplos del tipo de vulnerabilidad "{categoria}" en Python.

Descripcion: {descripcion}

Devuelve {n} ejemplos como ARRAY JSON. Cada uno:

  "instruccion": "Revisa este codigo. ¿Tiene problemas de seguridad?" (variar)
  "entrada": codigo Python REAL que muestra la vulnerabilidad. Debe:
       - compilar (sintacticamente valido),
       - ser realista (un endpoint, una funcion utilitaria, etc.),
       - NO ser obvio: parecer codigo normal a primera vista.
  "salida": respuesta pedagogica (>=350 chars):
       1) "Si, vulnerabilidad: <nombre tecnico>" + categoria OWASP si aplica;
       2) que ataque concreto la explota (con input ejemplo);
       3) por que el codigo es vulnerable (tecnicamente);
       4) version segura en ```python ... ```;
       5) buenas practicas adicionales para esa familia de bugs.
  "nivel": "intermedio" o "avanzado"
  "tema": "seguridad"
  "tipo": "seguridad"
  "tags": ["{tag}", "<otros tags relevantes>"]
  "errores_comunes": [array de 2-4 errores que estudiantes cometen al intentar arreglar esto]

REGLAS:
  - Solo el array JSON.
  - Cada ejemplo en CONTEXTO distinto (web API, CLI, ML pipeline, etc.).
  - "entrada" debe compilar.
  - NO incluir el nombre de la vulnerabilidad en el codigo de "entrada" (haria trampa).
"""


async def generar_objetivo(
    pool: Pool, categoria: str, descripcion: str, tag: str, n: int, *,
    temperatura: float,
) -> list[EjemploEntrenamiento]:
    prompt = PROMPT_TEMPLATE.format(
        categoria=categoria, descripcion=descripcion, tag=tag, n=n,
    )
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
        d["tipo"] = "seguridad"
        d.setdefault("tema", "seguridad")
        d.setdefault("nivel", "intermedio")
        d["fuente"] = proveedor
        tags = d.get("tags") or []
        if tag not in tags:
            tags.append(tag)
        d["tags"] = tags
        try:
            ejemplos.append(EjemploEntrenamiento.from_dict(d))
        except Exception:  # noqa: BLE001
            continue
    return ejemplos


async def generar_corpus(
    pool: Pool, salida: Path, *, n_por_categoria: int, temperatura: float,
) -> dict[str, Any]:
    todos: list[EjemploEntrenamiento] = []
    descartes: dict[str, int] = {}
    inicio = time.time()

    for i, (categoria, desc, tag) in enumerate(CATEGORIAS_SEG, 1):
        print(f"[{i:2d}/{len(CATEGORIAS_SEG)}] {categoria}", flush=True)
        lote = await generar_objetivo(
            pool, categoria, desc, tag, n_por_categoria, temperatura=temperatura,
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
