"""Ancla la pregunta final al AST real; no califica al estudiante ni ejecuta código."""
import ast
import re


def explicar_sin_cambiar(codigo: str) -> str:
    """Respaldo estático cuando el modelo modifica un ejemplo que debía explicar.

    Describe las instrucciones visibles; no ejecuta ni inventa resultados.
    """
    arbol = ast.parse(codigo)
    pasos = []
    tipos = {str: 'str (texto)', int: 'int (entero)', float: 'float (decimal)', bool: 'bool (booleano)'}
    for nodo in arbol.body:
        if isinstance(nodo, ast.Assign):
            destino = ', '.join(ast.unparse(t) for t in nodo.targets)
            valor = ast.unparse(nodo.value)
            tipo = tipos.get(type(nodo.value.value)) if isinstance(nodo.value, ast.Constant) else None
            pasos.append(f'`{destino}` recibe `{valor}`' + (f', de tipo {tipo}.' if tipo else '. Primero se calcula la expresión de la derecha y después se asigna el resultado.'))
        elif isinstance(nodo, ast.Expr) and isinstance(nodo.value, ast.Call) and isinstance(nodo.value.func, ast.Name) and nodo.value.func.id == 'print':
            pasos.append('`print` muestra los valores de ' + ', '.join(f'`{ast.unparse(a)}`' for a in nodo.value.args) + ' en ese punto del programa. Mostrar un dato no cambia su tipo ni su valor.')
        elif isinstance(nodo, ast.If):
            pasos.append(f'`if` comprueba `{ast.unparse(nodo.test)}`. Si es verdadera ejecuta su bloque; si es falsa pasa al bloque alternativo, cuando existe. Revisa el operador y prueba un dato a cada lado de la frontera.')
        elif isinstance(nodo, ast.For):
            pasos.append(f'`for` recorre `{ast.unparse(nodo.iter)}` asignando cada elemento a `{ast.unparse(nodo.target)}` y ejecuta el cuerpo una vez por elemento. Si la colección está vacía, el cuerpo no se ejecuta.')
        elif isinstance(nodo, (ast.FunctionDef, ast.AsyncFunctionDef)):
            args = ', '.join(a.arg for a in nodo.args.args)
            pasos.append(f'`{nodo.name}({args})` define una función. Sus parámetros reciben los argumentos al llamarla. `return` devuelve un valor a quien la llama; `print` lo muestra. Definir la función no ejecuta su cuerpo.')
        else:
            pasos.append(f'Revisa la instrucción `{ast.unparse(nodo)}` en el orden en que aparece; identifica qué datos utiliza y qué cambia antes de la siguiente instrucción.')
    return ('**Explicación basada en el código original**\n'
            'La propuesta del modelo cambiaba el ejemplo; se conserva tu código y se describen sus instrucciones sin ejecutarlo.\n\n'
            '```python\n' + codigo.strip() + '\n```\n\n'
            + '\n'.join(f'{i}. {p}' for i, p in enumerate(pasos, 1))
            + '\n\nContrasta tu predicción con estos pasos. Cambia un dato y explica qué salida esperas antes de ejecutarlo; una respuesta breve es suficiente.')


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
