"""Categoría REFACTORIZACIÓN — Detectar antipatrones y mejorar código.

La respuesta esperada nombra el antipatrón, explica el problema y muestra
un refactor que es estrictamente mejor.
"""

from __future__ import annotations

import re
from typing import Any

from ..core import Tarea, Categoria, _codigo_compila


_FENCE_RE = re.compile(r"```(?:python|py)?\s*\n?(.*?)```", re.DOTALL | re.IGNORECASE)


def _verificador_refactor(
    *,
    nombres_antipatron: list[str],
    patrones_refactor_aceptable: list[str],
    contraindica_si_aparece: list[str] | None = None,
) -> callable:
    """Verificador para tareas de refactorización.

    Args:
        nombres_antipatron        — Aliases del antipatrón a detectar.
        patrones_refactor_aceptable — Regexes en el código nuevo que indican
                                      que efectivamente se refactorizó bien.
        contraindica_si_aparece   — Si la respuesta dice "no hay problema",
                                    pierde puntos.
    """
    contraindica_si_aparece = contraindica_si_aparece or []

    def _verif(respuesta: str) -> dict[str, Any]:
        detalle: dict[str, Any] = {
            "antipatron_identificado": False,
            "refactor_propuesto": False,
            "refactor_compila": False,
        }
        score = 0.0
        baja = respuesta.lower()

        # 1. Identifica el antipatrón (0–30)
        if any(n.lower() in baja for n in nombres_antipatron):
            detalle["antipatron_identificado"] = True
            score += 30.0

        # 2. Hay un refactor con código (0–25)
        matches = _FENCE_RE.findall(respuesta)
        codigos = [m.strip() for m in matches if m.strip()]
        if codigos:
            detalle["refactor_propuesto"] = True
            score += 25.0
            # Tomamos el último bloque de código como el "refactor".
            refactor = codigos[-1]
            if _codigo_compila(refactor):
                detalle["refactor_compila"] = True
                score += 10.0

        # 3. El refactor matchea al menos un patrón esperado (0–25)
        codigo_total = "\n".join(codigos)
        for patron in patrones_refactor_aceptable:
            if re.search(patron, codigo_total, re.IGNORECASE):
                score += 25.0
                detalle["patron_matched"] = patron
                break

        # 4. Penalización si dice "no hay problema" (0–20)
        if not any(c.lower() in baja for c in contraindica_si_aparece):
            score += 10.0

        detalle["score"] = max(0.0, min(100.0, score))
        return detalle

    return _verif


TAREAS: list[Tarea] = [

    Tarea(
        id="ref_01_elif_chain_a_dict",
        categoria=Categoria.REFACTORIZACION,
        prompt=(
            "Revisa este código. ¿Cómo lo refactorizarías?\n\n"
            "```python\n"
            "def descuento_por_rol(rol):\n"
            "    if rol == 'admin':\n"
            "        return 0.5\n"
            "    elif rol == 'staff':\n"
            "        return 0.3\n"
            "    elif rol == 'gold':\n"
            "        return 0.2\n"
            "    elif rol == 'silver':\n"
            "        return 0.1\n"
            "    elif rol == 'bronze':\n"
            "        return 0.05\n"
            "    else:\n"
            "        return 0\n"
            "```"
        ),
        descripcion="Cadena de elif → diccionario",
        verificador=_verificador_refactor(
            nombres_antipatron=[
                "cadena de elif", "elif", "diccionario",
                "tabla de búsqueda", "tabla de busqueda",
            ],
            patrones_refactor_aceptable=[
                r"DESCUENTOS?\s*=\s*\{",
                r"return\s+\w+\.get\(",
                r"return\s+\w+\[\w+\]",
            ],
            contraindica_si_aparece=[
                "no hay problema", "está bien", "esta bien",
            ],
        ),
    ),

    Tarea(
        id="ref_02_bare_except",
        categoria=Categoria.REFACTORIZACION,
        prompt=(
            "¿Qué refactorizarías aquí?\n\n"
            "```python\n"
            "def cargar_config(ruta):\n"
            "    try:\n"
            "        with open(ruta) as f:\n"
            "            return json.load(f)\n"
            "    except:\n"
            "        return {}\n"
            "```"
        ),
        descripcion="bare except → excepciones específicas",
        verificador=_verificador_refactor(
            nombres_antipatron=[
                "bare except", "except sin", "captura genérica",
                "captura generica", "oculta",
            ],
            patrones_refactor_aceptable=[
                r"except\s+FileNotFoundError",
                r"except\s+JSONDecodeError",
                r"except\s+\(.*?,.*?\)",
                r"raise\s+",
            ],
        ),
    ),

    Tarea(
        id="ref_03_string_concat_loop",
        categoria=Categoria.REFACTORIZACION,
        prompt=(
            "Este código es lento para listas grandes. ¿Cómo lo mejorarías?\n\n"
            "```python\n"
            "def render_csv(filas):\n"
            "    salida = ''\n"
            "    for fila in filas:\n"
            "        salida += ','.join(str(c) for c in fila) + '\\n'\n"
            "    return salida\n"
            "```"
        ),
        descripcion="Concatenación de strings en loop",
        verificador=_verificador_refactor(
            nombres_antipatron=[
                "concatenación", "concatenacion", "join",
                "string", "inmutable",
            ],
            patrones_refactor_aceptable=[
                r"['\"]\\n['\"]\.join\(",
                r"io\.StringIO",
                r"csv\.writer",
                r"return\s+['\"]\\n['\"]\.join",
            ],
        ),
    ),

    Tarea(
        id="ref_04_mutable_default",
        categoria=Categoria.REFACTORIZACION,
        prompt=(
            "Refactoriza:\n\n"
            "```python\n"
            "def agregar_log(mensaje, historial=[]):\n"
            "    historial.append(mensaje)\n"
            "    return historial\n"
            "```"
        ),
        descripcion="Mutable default argument",
        verificador=_verificador_refactor(
            nombres_antipatron=[
                "mutable default", "argumento mutable",
                "compartida", "compartido",
            ],
            patrones_refactor_aceptable=[
                r"historial\s*=\s*None",
                r"if\s+historial\s+is\s+None",
                r"historial\s*=\s*\[\]\s*$",
            ],
        ),
    ),

    Tarea(
        id="ref_05_god_function",
        categoria=Categoria.REFACTORIZACION,
        prompt=(
            "Esta función hace demasiado. ¿Cómo la refactorizarías?\n\n"
            "```python\n"
            "def procesar_pedido(pedido):\n"
            "    # validar\n"
            "    if not pedido.items: raise ValueError('vacío')\n"
            "    for it in pedido.items:\n"
            "        if it.cantidad <= 0: raise ValueError('cantidad inválida')\n"
            "    # calcular total\n"
            "    total = sum(it.precio * it.cantidad for it in pedido.items)\n"
            "    if pedido.cupon: total *= 0.9\n"
            "    # cobrar\n"
            "    resultado = stripe.charge(pedido.cliente.tarjeta, total)\n"
            "    if not resultado.ok: raise PagoFalloError()\n"
            "    # email\n"
            "    smtp = SMTP('smtp.ejemplo.com')\n"
            "    smtp.send(pedido.cliente.email, f'Total ${total}')\n"
            "    return total\n"
            "```"
        ),
        descripcion="God function — separar responsabilidades",
        verificador=_verificador_refactor(
            nombres_antipatron=[
                "god function", "single responsibility",
                "responsabilidad", "dios", "hace demasiado",
            ],
            patrones_refactor_aceptable=[
                r"def\s+validar_",
                r"def\s+calcular_",
                r"def\s+cobrar",
                r"def\s+notificar|enviar_",
            ],
        ),
    ),
]
