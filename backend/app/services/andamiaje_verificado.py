"""Ancla la pregunta final al AST real; no califica al estudiante ni ejecuta código."""
import ast
import re


def completar(texto: str, codigo: str) -> str:
    arbol = ast.parse(codigo)
    pregunta = None
    for nodo in ast.walk(arbol):
        if isinstance(nodo, ast.If):
            pregunta = f'¿Qué rama se ejecuta si la condición `{ast.unparse(nodo.test)}` es falsa? Explica por qué.'
            break
        if isinstance(nodo, ast.For):
            pregunta = f'¿Qué ocurre si la colección `{ast.unparse(nodo.iter)}` que recorre el bucle está vacía? Justifica tu respuesta.'
            break
        if isinstance(nodo, (ast.FunctionDef, ast.AsyncFunctionDef)) and nodo.args.args:
            pregunta = f'Si cambia el argumento `{nodo.args.args[0].arg}` al llamar a `{nodo.name}`, ¿cómo puede cambiar el resultado? Da un ejemplo usando esta función.'
            break
    hechos = []
    tipos = {str:'texto (str)', int:'entero (int)', float:'decimal (float)', bool:'booleano (bool)'}
    for nodo in ast.walk(arbol):
        if isinstance(nodo, ast.Assign) and isinstance(nodo.value, ast.Constant) and type(nodo.value.value) in tipos:
            if len(nodo.targets) == 1 and isinstance(nodo.targets[0], ast.Name):
                nombre = nodo.targets[0].id
                hechos.append(f'En `{ast.unparse(nodo)}`, el literal asignado es {tipos[type(nodo.value.value)]}.')
                if pregunta is None:
                    pregunta = f'Si cambias el valor de `{nombre}`, ¿qué resultado o línea de salida cambia y por qué?'
    if pregunta is None:
        pregunta = '¿Qué instrucción del código determina el resultado principal? Explica qué hace con los datos que utiliza.'
    # Sustituir la sección final del modelo; conservar código y explicación anteriores.
    lineas = texto.splitlines()
    dentro = False
    codigo_visto = False
    corte = len(lineas)
    for i, linea in enumerate(lineas):
        if linea.strip().startswith('```'):
            dentro = not dentro
            if not dentro:
                codigo_visto = True
        if codigo_visto and not dentro and (re.search(r'pregunta.*(?:autoevaluaci[oó]n|reflexi[oó]n|final|ser[ií]a|sobre)|^\W*autoevaluaci[oó]n', linea, re.I)
                           or codigo_visto and linea.lstrip().startswith('¿')):
            corte = i
            break
    base = '\n'.join(lineas[:corte]).rstrip()
    comprobacion = '\n\n**Datos comprobados en el código:**\n' + '\n'.join('- '+h for h in hechos[:5]) if hechos else ''
    return base + comprobacion + '\n\n**Pregunta sobre este código:**\n' + pregunta
