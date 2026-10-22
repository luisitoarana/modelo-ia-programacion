"""Diagnósticos estáticos; nunca ejecuta ni completa programas del modelo."""
import ast
from pyflakes.checker import Checker
from pyflakes.messages import UndefinedName, UndefinedLocal


def errores_nombres(codigo: str) -> list[str]:
    arbol = ast.parse(codigo)
    return [str(m) for m in Checker(arbol, filename='programa.py').messages
            if isinstance(m, (UndefinedName, UndefinedLocal))]
