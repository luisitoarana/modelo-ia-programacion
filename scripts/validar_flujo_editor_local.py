"""Comprobación manual del GGUF local: dos turnos de código y un archivo largo."""
from pathlib import Path
import ast
import json
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "backend"))
from app.services.motor_pedagogico_service import generar_respuesta


def consultar(pedido: str, tokens: int = 320):
    resultado = generar_respuesta(pedido, max_tokens=tokens, temperatura=0.0)
    assert resultado is not None and resultado.texto, "El motor no respondió."
    return resultado


if __name__ == "__main__":
    inicial = consultar(
        "Petición actual del estudiante: Crea la función calcular(a, b) que devuelva a + b."
    )
    assert inicial.codigo, inicial.texto
    ast.parse(inicial.codigo)
    correccion = consultar(
        "[HISTORIAL PREVIO DEL DIÁLOGO]\nEstudiante: Crea una función de suma\n"
        "Asistente: Función creada\n[/HISTORIAL PREVIO]\n\n[PETICIÓN ACTUAL]\n"
        "Petición actual del estudiante: Corrige calcular(a, b) para devolver a - b. "
        "Devuelve el archivo completo en un bloque Python.\n"
        f"Código actual en el editor (calcular.py):\n```python\n{inicial.codigo}\n```"
    )
    assert correccion.codigo, correccion.texto
    arbol = ast.parse(correccion.codigo)
    assert any(isinstance(n, ast.BinOp) and isinstance(n.op, ast.Sub) for n in ast.walk(arbol)), correccion.texto
    assert not correccion.contexto_recortado and not correccion.respuesta_incompleta
    largo = consultar(
        "Explica brevemente la estructura de este archivo Python:\n```python\n"
        + "valor = 1\n" * 2500 + "print(valor)\n```", tokens=96,
    )
    assert largo.contexto_recortado
    print(json.dumps({
        "funcion_inicial": inicial.codigo,
        "funcion_corregida": correccion.codigo,
        "archivo_largo_aceptado_por_motor": True,
        "analisis_largo_es_parcial": largo.contexto_recortado,
        "latencias_segundos": [inicial.latencia_segundos, correccion.latencia_segundos, largo.latencia_segundos],
    }, ensure_ascii=False))
