"""Categoría SEGURIDAD — Detectar vulnerabilidades y proponer código seguro.

Cada tarea pasa código vulnerable y espera que la respuesta:
  1. Identifique correctamente la vulnerabilidad por su nombre.
  2. Explique POR QUÉ es vulnerable.
  3. Proponga código seguro que mitigue el problema.
"""

from __future__ import annotations

import re
from typing import Any

from ..core import Tarea, Categoria


def _verificador_seguridad(
    *,
    nombres_vuln: list[str],
    patrones_codigo_seguro: list[str],
    patrones_explicacion: list[str] | None = None,
) -> callable:
    """Verificador para tareas de seguridad.

    Args:
        nombres_vuln           — Alias aceptables de la vuln (SQL injection,
                                 SQLi, "inyección SQL", etc.).
        patrones_codigo_seguro — Regexes que indican que el código propuesto
                                 mitiga la vulnerabilidad (parametrized
                                 queries, hash, etc.).
        patrones_explicacion   — Conceptos que se esperan en la explicación
                                 (qué hace el atacante, etc.).
    """
    patrones_explicacion = patrones_explicacion or []

    def _verif(respuesta: str) -> dict[str, Any]:
        detalle: dict[str, Any] = {
            "vuln_identificada": False,
            "codigo_seguro_presente": False,
            "explicacion_completa": [],
        }
        score = 0.0
        baja = respuesta.lower()

        # 1. Identificación de la vuln (0–35 puntos)
        nombres_lower = [n.lower() for n in nombres_vuln]
        if any(n in baja for n in nombres_lower):
            detalle["vuln_identificada"] = True
            score += 35.0
        else:
            detalle["motivo"] = "no nombró la vulnerabilidad"

        # 2. Código seguro propuesto (0–45 puntos)
        for patron in patrones_codigo_seguro:
            if re.search(patron, respuesta, re.IGNORECASE):
                detalle["codigo_seguro_presente"] = True
                score += 45.0
                break

        # 3. Explicación pedagógica de la vuln (0–20 puntos)
        if patrones_explicacion:
            cubiertos = 0
            for p in patrones_explicacion:
                if p.lower() in baja:
                    cubiertos += 1
                    detalle["explicacion_completa"].append(p)
            score += 20.0 * (cubiertos / len(patrones_explicacion))
        else:
            score += 20.0  # sin patrones definidos => crédito completo

        detalle["score"] = max(0.0, min(100.0, score))
        return detalle

    return _verif


TAREAS: list[Tarea] = [

    Tarea(
        id="seg_01_sql_injection",
        categoria=Categoria.SEGURIDAD,
        prompt=(
            "Revisa este código y dime si tiene problemas de seguridad. "
            "Si los tiene, explica cuál es y muestra cómo corregirlo:\n\n"
            "```python\n"
            "def buscar_usuario(cursor, nombre):\n"
            "    query = \"SELECT * FROM users WHERE name = '\" + nombre + \"'\"\n"
            "    cursor.execute(query)\n"
            "    return cursor.fetchone()\n"
            "```"
        ),
        descripcion="SQL Injection clásico",
        verificador=_verificador_seguridad(
            nombres_vuln=[
                "sql injection", "sqli", "inyección sql", "inyeccion sql",
            ],
            patrones_codigo_seguro=[
                r"cursor\.execute\([^,]+,\s*\(",      # parametrized con tupla
                r"cursor\.execute\([^,]+,\s*\{",      # parametrized con dict
                r"%s",                                 # placeholder
                r"\?",                                 # placeholder sqlite
                r"text\(.*?bindparams",                # sqlalchemy
            ],
            patrones_explicacion=[
                "concatena", "atacante", "comilla",
            ],
        ),
    ),

    Tarea(
        id="seg_02_command_injection",
        categoria=Categoria.SEGURIDAD,
        prompt=(
            "¿Qué problema tiene este endpoint y cómo se podría explotar?\n\n"
            "```python\n"
            "import subprocess\n"
            "from flask import request\n\n"
            "@app.post('/ping')\n"
            "def ping():\n"
            "    host = request.args['host']\n"
            "    r = subprocess.check_output(f'ping -c 1 {host}', shell=True)\n"
            "    return r\n"
            "```"
        ),
        descripcion="Command Injection vía shell=True",
        verificador=_verificador_seguridad(
            nombres_vuln=[
                "command injection", "inyección de comandos",
                "inyeccion de comandos", "shell injection",
            ],
            patrones_codigo_seguro=[
                r"shell\s*=\s*False",
                r"subprocess\.\w+\(\[",     # lista de args en vez de string
                r"shlex\.quote",
                r"shlex\.split",
            ],
            patrones_explicacion=[
                "shell=true", ";", "&&", "|", "atacante",
            ],
        ),
    ),

    Tarea(
        id="seg_03_pickle_inseguro",
        categoria=Categoria.SEGURIDAD,
        prompt=(
            "Una aplicación deserializa datos enviados por el cliente con:\n\n"
            "```python\n"
            "import pickle\n\n"
            "@app.post('/cargar')\n"
            "def cargar(request):\n"
            "    obj = pickle.loads(request.body)\n"
            "    return procesar(obj)\n"
            "```\n\n"
            "¿Qué problema tiene esto? ¿Cómo lo arreglarías?"
        ),
        descripcion="Deserialización insegura con pickle",
        verificador=_verificador_seguridad(
            nombres_vuln=[
                "deserialización insegura", "deserializacion insegura",
                "pickle", "ejecución arbitraria", "ejecucion arbitraria",
                "rce", "remote code execution",
            ],
            patrones_codigo_seguro=[
                r"json\.loads",
                r"marshal\.loads",
                r"messagepack",
                r"firmar|firma|hmac",
            ],
            patrones_explicacion=[
                "__reduce__", "atacante", "código arbitrario", "codigo arbitrario",
            ],
        ),
    ),

    Tarea(
        id="seg_04_password_hashing",
        categoria=Categoria.SEGURIDAD,
        prompt=(
            "Una aplicación almacena passwords así:\n\n"
            "```python\n"
            "import hashlib\n\n"
            "def crear_usuario(email, password):\n"
            "    h = hashlib.md5(password.encode()).hexdigest()\n"
            "    db.users.insert({'email': email, 'pass_hash': h})\n"
            "```\n\n"
            "¿Qué tiene de malo? Propone una solución segura."
        ),
        descripcion="MD5 inseguro para passwords",
        verificador=_verificador_seguridad(
            nombres_vuln=[
                "md5", "hash débil", "hash debil",
                "rainbow table", "sin sal", "sin salt",
            ],
            patrones_codigo_seguro=[
                r"bcrypt", r"argon2", r"scrypt", r"pbkdf2",
                r"passlib", r"hashlib\.pbkdf2_hmac",
            ],
            patrones_explicacion=[
                "salt", "sal", "colisiones", "rápido",
            ],
        ),
    ),

    Tarea(
        id="seg_05_jwt_alg_none",
        categoria=Categoria.SEGURIDAD,
        prompt=(
            "Este código valida JWTs:\n\n"
            "```python\n"
            "import jwt\n\n"
            "def validar(token):\n"
            "    return jwt.decode(token, verify=False)\n"
            "```\n\n"
            "¿Es seguro? Si no, explica por qué y arréglalo."
        ),
        descripcion="JWT sin verificación de firma",
        verificador=_verificador_seguridad(
            nombres_vuln=[
                "verify=false", "sin verificación", "sin verificacion",
                "alg=none", "alg none", "firma", "token falso",
            ],
            patrones_codigo_seguro=[
                r"jwt\.decode\([^)]+algorithms=",
                r"algorithms\s*=\s*\[\s*['\"](HS|RS|ES)",
                r"verify\s*=\s*True",
            ],
            patrones_explicacion=[
                "firma", "secret", "clave",
            ],
        ),
    ),
]
