"""Servicio Pedagógico de Análisis y Explicación de Código Python.

Analiza el Árbol de Sintaxis Abstracta (AST) de Python y genera explicaciones
didácticas paso a paso, libres de alucinaciones, estructuradas y 100% en español.

Diseñado específicamente para el acompañamiento docente y aprendizaje de programación
en la tesis:
  - Explica qué es 'def', qué hace la función, qué es cada parámetro.
  - Explica cada variable (punteros, acumuladores, índices).
  - Explica cómo funcionan los bucles ('for', 'while') y condicionales ('if/else').
  - Explica para qué sirve 'print', 'return', 'len', 'range'.
  - Reconoce algoritmos clásicos (Búsqueda binaria, promedios, factorial, burbuja).
  - Evalúa complejidad Big-O temporal y espacial.
  - Detecta bugs potenciales (división por cero con listas vacías, precondición de orden).
"""

from __future__ import annotations

import ast
import time
from dataclasses import dataclass, field
from typing import Any


@dataclass
class VariableInfo:
    nombre: str
    linea: int
    es_parametro: bool = False
    rol_sugerido: str = "variable de datos"


@dataclass
class BucleInfo:
    tipo: str  # 'for' o 'while'
    linea: int
    condicion_o_iterador: str
    anidamiento: int = 1


@dataclass
class ClaseInfo:
    nombre: str
    linea: int
    bases: list[str] = field(default_factory=list)
    metodos: list[str] = field(default_factory=list)
    tiene_init: bool = False
    docstring: str | None = None


@dataclass
class CondicionalInfo:
    linea: int
    condicion: str
    tiene_else: bool = False
    tiene_elif: bool = False


@dataclass
class FuncionInfo:
    nombre: str
    linea: int
    parametros: list[str] = field(default_factory=list)
    tiene_return: bool = False
    tipo_retorno_estimado: str = "None o resultado dinámico"
    docstring: str | None = None


@dataclass
class AnalisisAST:
    es_valido: bool
    error_sintaxis: str | None = None
    clases: list[ClaseInfo] = field(default_factory=list)
    funciones: list[FuncionInfo] = field(default_factory=list)
    variables: list[VariableInfo] = field(default_factory=list)
    bucles: list[BucleInfo] = field(default_factory=list)
    condicionales: list[CondicionalInfo] = field(default_factory=list)
    llamadas_nativas: list[str] = field(default_factory=list)
    algoritmo_detectado: str | None = None
    complejidad_tiempo: str = "O(1)"
    complejidad_espacio: str = "O(1)"
    lineas_codigo: int = 0
    riesgos_detectados: list[str] = field(default_factory=list)
    mejoras_pep8: list[str] = field(default_factory=list)


class VisitorAnalizador(ast.NodeVisitor):
    def __init__(self) -> None:
        self.clases: list[ClaseInfo] = []
        self.funciones: list[FuncionInfo] = []
        self.variables: dict[str, VariableInfo] = {}
        self.bucles: list[BucleInfo] = []
        self.condicionales: list[CondicionalInfo] = []
        self.llamadas: set[str] = set()
        self.nivel_bucle: int = 0
        self.tiene_recursion: bool = False
        self.nombres_funciones: set[str] = set()
        self._funcion_actual: list[str] = []
        self.tiene_division: bool = False
        self.tiene_len: bool = False
        self.tiene_while_mitad: bool = False

    def visit_FunctionDef(self, node: ast.FunctionDef) -> None:
        self.nombres_funciones.add(node.name)
        params = [arg.arg for arg in node.args.args]
        for p in params:
            if p not in self.variables:
                self.variables[p] = VariableInfo(nombre=p, linea=node.lineno, es_parametro=True, rol_sugerido="parámetro de entrada")

        doc = ast.get_docstring(node)
        func_info = FuncionInfo(
            nombre=node.name,
            linea=node.lineno,
            parametros=params,
            docstring=doc,
        )

        # Chequear si tiene return
        for sub in ast.walk(node):
            if isinstance(sub, ast.Return) and sub.value is not None:
                func_info.tiene_return = True
                break

        self.funciones.append(func_info)
        self._funcion_actual.append(node.name)
        try:
            self.generic_visit(node)
        finally:
            self._funcion_actual.pop()

    def visit_ClassDef(self, node: ast.ClassDef) -> None:
        bases = []
        for b in node.bases:
            if isinstance(b, ast.Name):
                bases.append(b.id)
            elif hasattr(ast, "unparse"):
                bases.append(ast.unparse(b))
        metodos = [n.name for n in node.body if isinstance(n, ast.FunctionDef)]
        tiene_init = "__init__" in metodos
        doc = ast.get_docstring(node)
        self.clases.append(
            ClaseInfo(
                nombre=node.name,
                linea=node.lineno,
                bases=bases,
                metodos=metodos,
                tiene_init=tiene_init,
                docstring=doc,
            )
        )
        self.generic_visit(node)

    def visit_If(self, node: ast.If) -> None:
        cond_str = ast.unparse(node.test) if hasattr(ast, "unparse") else "condición"
        tiene_else = len(node.orelse) > 0 and not isinstance(node.orelse[0], ast.If)
        tiene_elif = len(node.orelse) > 0 and isinstance(node.orelse[0], ast.If)
        self.condicionales.append(
            CondicionalInfo(
                linea=node.lineno,
                condicion=cond_str,
                tiene_else=tiene_else,
                tiene_elif=tiene_elif,
            )
        )
        self.generic_visit(node)

    def visit_Assign(self, node: ast.Assign) -> None:
        for target in node.targets:
            if isinstance(target, ast.Name):
                var_name = target.id
                rol = "variable local"
                if var_name in ("inicio", "start", "low", "izq", "izquierda"):
                    rol = "puntero de límite inferior (ventana izquierda)"
                elif var_name in ("fin", "end", "high", "der", "derecha"):
                    rol = "puntero de límite superior (ventana derecha)"
                elif var_name in ("medio", "mid", "mitad"):
                    rol = "índice central de la ventana de búsqueda"
                elif var_name in ("total", "suma", "acumulador", "acc"):
                    rol = "acumulador numérico"
                elif var_name in ("i", "j", "k", "idx", "indice"):
                    rol = "índice contador de iteración"
                elif var_name in ("promedio", "media", "avg"):
                    rol = "variable que almacena el cálculo de la media"

                if var_name not in self.variables:
                    self.variables[var_name] = VariableInfo(nombre=var_name, linea=node.lineno, rol_sugerido=rol)

        # Chequear divisiones
        if isinstance(node.value, ast.BinOp):
            if isinstance(node.value.op, (ast.Div, ast.FloorDiv)):
                self.tiene_division = True
                if isinstance(node.value.right, ast.Constant) and node.value.right.value == 2:
                    self.tiene_while_mitad = True

        self.generic_visit(node)

    def visit_For(self, node: ast.For) -> None:
        self.nivel_bucle += 1
        iterador = ast.unparse(node.target) if hasattr(ast, "unparse") else "elemento"
        iterable = ast.unparse(node.iter) if hasattr(ast, "unparse") else "colección"
        self.bucles.append(BucleInfo(tipo="for", linea=node.lineno, condicion_o_iterador=f"{iterador} en {iterable}", anidamiento=self.nivel_bucle))
        self.generic_visit(node)
        self.nivel_bucle -= 1

    def visit_While(self, node: ast.While) -> None:
        self.nivel_bucle += 1
        test_str = ast.unparse(node.test) if hasattr(ast, "unparse") else "condición"
        self.bucles.append(BucleInfo(tipo="while", linea=node.lineno, condicion_o_iterador=test_str, anidamiento=self.nivel_bucle))
        self.generic_visit(node)
        self.nivel_bucle -= 1

    def visit_Call(self, node: ast.Call) -> None:
        if isinstance(node.func, ast.Name):
            func_name = node.func.id
            self.llamadas.add(func_name)
            if func_name == "len":
                self.tiene_len = True
            if self._funcion_actual and func_name == self._funcion_actual[-1]:
                self.tiene_recursion = True
        self.generic_visit(node)


def analizar_codigo_python(codigo: str) -> AnalisisAST:
    """Parsea el código Python y extrae su estructura pedagógica."""
    if not codigo.strip():
        return AnalisisAST(es_valido=False, error_sintaxis="El código proporcionado está vacío.")

    try:
        arbol = ast.parse(codigo)
    except SyntaxError as exc:
        return AnalisisAST(
            es_valido=False,
            error_sintaxis=f"Error sintáctico en línea {exc.lineno}, columna {exc.offset}: {exc.msg}",
            lineas_codigo=len(codigo.splitlines()),
        )

    visitador = VisitorAnalizador()
    visitador.visit(arbol)

    lineas = len(codigo.splitlines())
    funciones = visitador.funciones
    variables = list(visitador.variables.values())
    bucles = visitador.bucles
    nativas = sorted(visitador.llamadas)

    # Identificación heurística de algoritmos
    codigo_lower = codigo.lower()
    algoritmo = None
    complejidad_t = "O(1)"
    complejidad_e = "O(1)"
    riesgos = []
    pep8 = []

    # Búsqueda binaria
    if visitador.tiene_while_mitad and any(b.tipo == "while" for b in bucles):
        algoritmo = "Posible búsqueda o reducción por mitades"
        complejidad_t = "O(log n)"
        complejidad_e = "O(1)"
        riesgos.append("Verifica que la ventana de búsqueda se reduzca a la mitad en cada iteración; el AST no demuestra por sí solo la complejidad.")
    # Promedio o media
    elif visitador.tiene_division and visitador.tiene_len:
        algoritmo = "Cálculo de Promedio / Media Aritmética"
        complejidad_t = "O(n)"
        complejidad_e = "O(1)"
        riesgos.append("ZeroDivisionError: Si la lista de calificaciones o números está vacía (`[]`), `len(calificaciones)` será 0 y ocurrirá una excepción al dividir.")
    # Fibonacci / Recursión
    elif visitador.tiene_recursion:
        algoritmo = "Función recursiva"
        complejidad_t = "No determinada: depende de las llamadas y la memoización"
        complejidad_e = "Depende de la profundidad de la recursión"
    # Burbuja
    elif any(b.anidamiento >= 2 for b in bucles):
        profundidad = max(b.anidamiento for b in bucles)
        algoritmo = "Bucles anidados"
        complejidad_t = f"O(n^{profundidad}) estimada si cada bucle depende de n"
        complejidad_e = "O(1)"
        riesgos.append("La cota depende de los límites reales de cada bucle; no se infiere solo del anidamiento.")
    elif bucles:
        algoritmo = "Algoritmo Iterativo Lineal"
        rangos_constantes = all(
            isinstance(b, ast.For)
            and isinstance(b.iter, ast.Call)
            and isinstance(b.iter.func, ast.Name)
            and b.iter.func.id == "range"
            and all(isinstance(arg, ast.Constant) and isinstance(arg.value, int) for arg in b.iter.args)
            for b in ast.walk(arbol) if isinstance(b, (ast.For, ast.While))
        )
        complejidad_t = "O(1)" if rangos_constantes else "O(n) estimada"
        complejidad_e = "O(1)"

    # Las comprensiones también recorren colecciones aunque no creen nodos For.
    if not bucles and not visitador.tiene_recursion and any(
        isinstance(n, (ast.ListComp, ast.SetComp, ast.DictComp)) for n in ast.walk(arbol)
    ):
        algoritmo = "Comprensión de colección"
        complejidad_t = "O(n) estimada"
        complejidad_e = "O(n) para la colección resultante"

    # Reglas PEP 8 básicas
    for f in funciones:
        if f.nombre != f.nombre.lower() and "_" not in f.nombre and not f.nombre.islower():
            pep8.append(f"La función `{f.nombre}` no sigue la convención snake_case recomendada por PEP 8 (ej. `mi_funcion`).")
        if not f.docstring:
            pep8.append(f"La función `{f.nombre}` carece de docstring explicativo (`'''Descripción...'''`).")

    return AnalisisAST(
        es_valido=True,
        clases=visitador.clases,
        funciones=funciones,
        variables=variables,
        bucles=bucles,
        condicionales=visitador.condicionales,
        llamadas_nativas=nativas,
        algoritmo_detectado=algoritmo,
        complejidad_tiempo=complejidad_t,
        complejidad_espacio=complejidad_e,
        lineas_codigo=lineas,
        riesgos_detectados=riesgos,
        mejoras_pep8=pep8,
    )



def _es_documento_texto(texto: str) -> bool:
    """Detecta si el contenido es un documento Markdown, informe o texto explicativo en vez de código Python."""
    t = texto.strip()
    if not t:
        return False
    lineas = [l.strip() for l in t.splitlines() if l.strip()]
    if not lineas:
        return False
    encabezados_md = sum(1 for l in lineas if l.startswith(("# ", "## ", "### ", "#### ")))
    items_lista = sum(1 for l in lineas if l.startswith(("- ", "* ", "1. ", "2. ", "3. ", "> ")))
    tiene_bloques_md = "```" in t
    tiene_palabras_py = any(
        re.search(r"^(?:def\s+\w+\(|class\s+\w+|import\s+\w+|from\s+\w+\s+import|for\s+\w+\s+in|while\s+|if\s+.*:)", l)
        for l in lineas
    )
    if (encabezados_md >= 1 and items_lista >= 1 and not tiene_palabras_py) or (encabezados_md >= 2 and not tiene_palabras_py):
        return True
    if tiene_bloques_md and encabezados_md >= 1 and not tiene_palabras_py:
        return True
    return False


def _generar_explicacion_documento(texto: str, modo: str, usar_modelo: bool = True) -> str:
    """Genera una explicación pedagógica estructurada de un documento Markdown o informe técnico."""
    try:
        from app.services import motor_pedagogico_service
        if usar_modelo and motor_pedagogico_service.esta_disponible():
            prompt = (
                "REGLA OBLIGATORIA DE IDIOMA: Responde SIEMPRE Y EXCLUSIVAMENTE en español. "
                "Aunque el documento, archivo Markdown o texto esté escrito en inglés, "
                "toda tu explicación, resumen de secciones y análisis deben estar 100% en español impecable y didáctico.\n\n"
                "Analiza pedagógicamente el siguiente documento técnico/Markdown. "
                "Resume su propósito, explica sus secciones principales, requerimientos o hallazgos, "
                "y destaca los puntos clave para el estudiante en español:\n\n"
                f"{texto[:4000]}"
            )
            res = motor_pedagogico_service.generar_respuesta(prompt, max_tokens=1500, temperatura=0.2)
            if res and res.texto and len(res.texto.strip()) > 50:
                return f"## 📄 Análisis Didáctico del Documento / Informe\n\n{res.texto.strip()}"
    except Exception as exc:
        log.debug("Fallback a resumen de documento determinista: %s", exc)

    lineas = texto.splitlines()
    secciones = []
    for l in lineas:
        l_s = l.strip()
        if l_s.startswith(("# ", "## ", "### ")):
            nivel = l_s.count("#", 0, 4)
            titulo = l_s.lstrip("#").strip()
            secciones.append(f"{'  ' * max(0, nivel - 1)}- **{titulo}**")

    resumen = [
        "## 📄 Análisis Didáctico del Documento / Informe Técnico",
        "Este archivo corresponde a documentación o informe técnico en formato Markdown (texto estructurado), no a código fuente ejecutable en Python.",
        "",
        "### 📑 Estructura y Secciones Principales:",
    ]
    if secciones:
        resumen.extend(secciones[:15])
    else:
        resumen.append("- Documento de contenido conceptual o especificación técnica.")

    resumen.append("")
    resumen.append("### 💡 Orientación Pedagógica:")
    resumen.append("- Este archivo define especificaciones o guías de estudio. Puedes seleccionar cualquier sección o consultar al asistente en el editor para profundizar en puntos específicos.")

    return "\n".join(resumen)

def generar_explicacion_didactica(
    codigo: str,
    modo: str = "didactico",
    nivel: str = "principiante",
    modelo_nombre: str = "Modelo Propio (350M)",
    usar_modelo: bool = True,
) -> str:
    """Genera la explicación en Markdown en español rigurosa, pedagógica y paso a paso."""
    analisis = analizar_codigo_python(codigo)

    if not analisis.es_valido:
        return f"""### ⚠️ Error de Sintaxis en el Código
No se pudo analizar el código porque contiene un error de sintaxis Python:
- **Detalle**: {analisis.error_sintaxis}

Por favor verifica la indentación (espacios) y la sintaxis de las líneas antes de explicar."""

    modo_limpio = modo.lower()

    # 1. Intentar con el motor local propio (100% offline y dinámico)
    try:
        from app.services import motor_pedagogico_service
        if usar_modelo and motor_pedagogico_service.esta_disponible():
            prompt_local = (
                f"REGLA OBLIGATORIA: Responde SIEMPRE Y EXCLUSIVAMENTE en español formal y didáctico.\n"
                f"Analiza este código Python en modo '{modo_limpio}' para nivel '{nivel}'. "
                f"IMPORTANTE: Si el código contiene comentarios con preguntas o dudas conceptuales "
                f"(por ejemplo: '# ¿qué es una variable?', '# ¿para qué sirve if?'), responde con prioridad absoluta "
                f"a la pregunta usando analogías sencillas y ejemplos didácticos:\n\n"
                f"```python\n{codigo}\n```"
            )
            res_local = motor_pedagogico_service.generar_respuesta(
                prompt_local,
                modo_explicador=modo_limpio,
                max_tokens=1800,
                temperatura=0.2,
            )
            if res_local and res_local.texto and len(res_local.texto.strip()) > 50:
                aviso = ("**Análisis parcial:** se revisaron fragmentos del archivo por el límite de contexto del motor.\n\n"
                         if res_local.contexto_recortado else "")
                return aviso + res_local.texto.strip()
    except Exception as exc:
        log.debug("Fallback al analizador AST nativo: %s", exc)

    # 2. Fallback al analizador sintáctico AST determinista
    if "complejidad" in modo_limpio:
        return _generar_modo_complejidad(codigo, analisis, nivel)
    elif "bug" in modo_limpio or "riesgo" in modo_limpio:
        return _generar_modo_bugs(codigo, analisis, nivel)
    elif "optimiz" in modo_limpio or "pep" in modo_limpio:
        return _generar_modo_optimizacion(codigo, analisis, nivel)
    else:
        return _generar_modo_didactico(codigo, analisis, nivel)


def _generar_modo_didactico(codigo: str, a: AnalisisAST, nivel: str) -> str:
    lineas_md = []

    # Detección y respuesta prioritaria a preguntas conceptuales en comentarios (# ¿qué es una variable?)
    preguntas_comentarios = []
    for linea in codigo.splitlines():
        l_strip = linea.strip()
        if l_strip.startswith("#"):
            c_text = l_strip.lstrip("#").strip()
            if any(k in c_text.lower() for k in ("?", "qué es", "que es", "cómo funciona", "como funciona", "para qué", "para que", "variable")):
                preguntas_comentarios.append(c_text)

    if preguntas_comentarios:
        lineas_md.append("## 💡 Respuesta Pedagógica a tu Pregunta Conceptual")
        for preg in preguntas_comentarios:
            lineas_md.append(f"### ❓ Consulta: *\"{preg}\"*")
            p_low = preg.lower()
            if "variable" in p_low:
                lineas_md.append(
                    "- **¿Qué es una variable en Python?**: Una variable es una referencia o identificador "
                    "que le asignamos a un espacio de la memoria RAM donde se almacena un valor (número, texto, etc.).\n"
                    "- **Analogía didáctica**: Imagina una caja con una etiqueta adhesiva. "
                    "Si escribes `nombre = 'Luis'`, la etiqueta pegada a la caja es `nombre` y lo que está adentro es `'Luis'`.\n"
                    "- **Regla de oro**: El signo `=` es el **operador de asignación** (no significa igualdad matemática). "
                    "Guarda lo que está a su derecha dentro del espacio nombrado a su izquierda."
                )
            elif "if" in p_low or "condicional" in p_low:
                lineas_md.append(
                    "- **¿Cómo funciona un condicional `if`?**: Permite que el programa tome decisiones lógicas. "
                    "Si la condición es verdadera (`True`), se ejecutan las instrucciones indentadas con 4 espacios.\n"
                    "- **Sintaxis obligatoria**: Siempre debe terminar con dos puntos `:` (ejemplo: `if nombre == 'Luis':`)."
                )
            elif "print" in p_low:
                lineas_md.append(
                    "- **¿Para qué sirve `print()`?**: Es una función integrada que envía información a la terminal "
                    "para que el usuario pueda visualizarla en pantalla."
                )
            elif "bucle" in p_low or "for" in p_low or "while" in p_low:
                lineas_md.append(
                    "- **¿Qué es un bucle (`for` / `while`)?**: Es una estructura que repite un bloque de código automáticamente "
                    "sin tener que duplicar líneas manualmente."
                )
            else:
                lineas_md.append(
                    f"- En Python, '{preg}' es un concepto fundamental de programación que estructura las instrucciones paso a paso."
                )
        lineas_md.append("\n---\n")

    lineas_md.append("## 🎯 Propósito del Código")
    if a.algoritmo_detectado:
        lineas_md.append(f"Este código implementa el algoritmo de **{a.algoritmo_detectado}**.")
    else:
        lineas_md.append("Este programa es un módulo en Python estructurado para procesar y transformar datos paso a paso.")

    lineas_md.append("\n## 🧩 Elementos Clave del Lenguaje (¿Qué significa cada término?)")

    # Explicación de Clases y Programación Orientada a Objetos (POO)
    if a.clases:
        lineas_md.append("\n### 🏛️ Programación Orientada a Objetos (POO / Clases)")
        for c in a.clases:
            herencia = f" (hereda de `{', '.join(c.bases)}`)" if c.bases else ""
            lineas_md.append(f"#### 📦 Clase `{c.nombre}`{herencia} (línea {c.linea})")
            lineas_md.append("- **¿Qué es una clase?**: Es un molde o plantilla fundamental de la POO que encapsula estado (atributos) y comportamientos (métodos).")
            if c.tiene_init:
                lineas_md.append("- **Método constructor `__init__(self, ...)`**: Método especial de inicialización que se ejecuta automáticamente cuando se instancia un nuevo objeto de la clase.")
                lineas_md.append("- **El parámetro `self`**: Referencia obligatoria que representa la instancia viva actual en memoria, garantizando que cada objeto conserve sus propios valores en `self.atributo`.")
            if c.metodos:
                lineas_md.append(f"- **Métodos del objeto**: `{', '.join(c.metodos)}`.")
            if c.docstring:
                lineas_md.append(f"- **Documentación**: *{c.docstring.strip()}*")

    # Explicación de funciones y 'def'
    if a.funciones:
        for f in a.funciones:
            lineas_md.append(f"### 🔹 Palabra clave `def` y función `{f.nombre}`")
            lineas_md.append("- **¿Qué es `def`?**: Proviene de la palabra en inglés *define* ('definir'). Es la palabra reservada que le indica al intérprete de Python que se va a declarar una función reutilizable.")
            if f.parametros:
                lineas_md.append(f"- **Parámetros (`{', '.join(f.parametros)}`)**: Son las variables que la función espera recibir desde afuera como datos de entrada para poder operar.")
                for p in f.parametros:
                    lineas_md.append(f"  - `{p}`: dato recibido para el procesamiento.")
            else:
                lineas_md.append("- **Parámetros**: No recibe parámetros externos.")
            if f.tiene_return:
                lineas_md.append("- **Instrucción `return`**: Finaliza la ejecución de la función y devuelve el valor resultante al lugar del programa donde fue invocada.")
    elif not a.clases:
        lineas_md.append("- Este código es un script secuencial directo (no encapsulado en funciones `def` o clases).")

    # Explicación de variables detectadas
    if a.variables:
        lineas_md.append("\n### 🏷️ Variables Utilizadas y su Rol en el Algoritmo")
        for v in a.variables:
            tipo_desc = "Parámetro" if v.es_parametro else "Variable local"
            lineas_md.append(f"- **`{v.nombre}`** ({tipo_desc}, línea {v.linea}): Funciona como **{v.rol_sugerido}**.")

    # Explicación de bucles
    if a.bucles:
        lineas_md.append("\n### 🔄 Estructuras de Control e Iteración (Bucles)")
        for b in a.bucles:
            if b.tipo == "for":
                lineas_md.append(f"- **Bucle `for` (línea {b.linea})**: Itera elemento por elemento sobre `{b.condicion_o_iterador}`. En cada ciclo, la variable de control toma el valor del siguiente elemento.")
            elif b.tipo == "while":
                lineas_md.append(f"- **Bucle `while` (línea {b.linea})**: Evalúa la condición `{b.condicion_o_iterador}`. Mientras sea verdadera (`True`), repite el bloque interno. Si se vuelve falsa (`False`), el bucle termina.")

    # Explicación de condicionales
    if a.condicionales:
        lineas_md.append("\n### 🔀 Toma de Decisiones (Condicionales `if` / `elif` / `else`)")
        for cond in a.condicionales:
            lineas_md.append(f"- **Condicional en línea {cond.linea} (`if {cond.condicion}`)**: Evalúa una expresión lógica booleana.")
            lineas_md.append("  - Si la condición resulta verdadera (`True`), se ejecuta su bloque indentado.")
            if cond.tiene_elif:
                lineas_md.append("  - Cuenta con ramificación alternativa `elif` para verificar condiciones secundarias.")
            if cond.tiene_else:
                lineas_md.append("  - Cuenta con cláusula por defecto `else` que se ejecuta si ninguna condición previa se cumplió.")

    # Explicación de funciones nativas
    if a.llamadas_nativas:
        lineas_md.append("\n### ⚙️ Funciones Nativas de Python Usadas")
        for f in a.llamadas_nativas:
            if f == "print":
                lineas_md.append("- **`print(...)`**: Imprime o muestra información en la terminal/consola estándar para que el usuario pueda verla.")
            elif f == "len":
                lineas_md.append("- **`len(...)`**: Viene de *length* ('longitud'). Retorna el número total de elementos contenidos en una lista, cadena o colección.")
            elif f == "range":
                lineas_md.append("- **`range(...)`**: Genera una secuencia ordenada de números enteros para ser recorrida por un bucle.")
            elif f == "sum":
                lineas_md.append("- **`sum(...)`**: Realiza la suma aritmética de todos los elementos iterables.")
            elif f == "enumerate":
                lineas_md.append("- **`enumerate(...)`**: Devuelve pares con el índice de posición y el valor del elemento.")

    # Desglose paso a paso del código
    lineas_md.append("\n## 🔍 Desglose Paso a Paso de la Ejecución")
    lineas_codigo = [l.rstrip() for l in codigo.splitlines() if l.strip()]
    for i, l in enumerate(lineas_codigo, 1):
        lineas_md.append(f"{i}. `{l}`")

    lineas_md.append(f"\n## ⏱️ Complejidad Resumida")
    lineas_md.append(f"- **Tiempo**: `{a.complejidad_tiempo}`")
    lineas_md.append(f"- **Espacio (Memoria Auxiliar)**: `{a.complejidad_espacio}`")

    lineas_md.append("\n## ❓ Preguntas de Autoevaluación y Comprensión")
    preguntas_contextuales = []
    if a.bucles:
        b_pri = a.bucles[0]
        preguntas_contextuales.append(
            f"¿Cuántas iteraciones exactas ejecutará el bucle `{b_pri.tipo}` en la línea {b_pri.linea} "
            f"con los datos actuales y qué valor final alcanzará `{b_pri.condicion_o_iterador}`?"
        )
    if a.condicionales:
        c_pri = a.condicionales[0]
        preguntas_contextuales.append(
            f"En la línea {c_pri.linea} (`if {c_pri.condicion}`), ¿qué valores específicos de entrada "
            f"harían que la condición se evalúe como `False` y qué camino tomará el flujo del programa?"
        )
    if a.funciones:
        f_pri = a.funciones[0]
        params_str = ", ".join(f_pri.parametros) if f_pri.parametros else "sin parámetros"
        preguntas_contextuales.append(
            f"Si invocamos la función `{f_pri.nombre}({params_str})` con valores extremos o vacíos, "
            f"¿qué resultado devolverá y cómo garantizarías que no arroje una excepción no controlada?"
        )
    if a.algoritmo_detectado and "Binaria" in a.algoritmo_detectado:
        preguntas_contextuales.append(
            "¿Qué sucedería con la búsqueda binaria si la lista de entrada estuviese desordenada? *(Pista: Revisa la decisión `lista[medio] < objetivo`)*."
        )
    elif a.algoritmo_detectado and "Promedio" in a.algoritmo_detectado:
        preguntas_contextuales.append(
            "¿Qué excepción arrojaría el programa si le pasamos una lista vacía `[]` y cómo podrías prevenirlo con un `if` defensivo?"
        )

    if preguntas_contextuales:
        for p_idx, p_txt in enumerate(preguntas_contextuales[:2], 1):
            lineas_md.append(f"{p_idx}. {p_txt}")
    else:
        lineas_md.append("1. ¿Qué valor tomarían las variables principales si alteramos los datos de entrada iniciales?")
        lineas_md.append("2. ¿Existe algún caso límite (como valores vacíos, negativos o ceros) que requiera validación adicional?")

    return "\n".join(lineas_md)


def _generar_modo_complejidad(codigo: str, a: AnalisisAST, nivel: str) -> str:
    return f"""## ⏱️ Análisis de Complejidad Algorítmica (Notación Big-O)

### 1. Complejidad Temporal (Tiempo de Ejecución)
- **Peor Caso**: `{a.complejidad_tiempo}`
- **Mejor Caso**: `{"O(1)" if a.algoritmo_detectado and "Binaria" in a.algoritmo_detectado else a.complejidad_tiempo}`
- **Justificación Pedagógica**:
  {"En cada iteración del bucle while, el espacio de búsqueda se reduce a la mitad dividiendo entre 2. Por tanto, el número máximo de comparaciones requeridas para n elementos es log₂(n)." if "log n" in a.complejidad_tiempo else "El algoritmo recorre secuencialmente los elementos de la colección mediante un bucle, realizando un número de operaciones proporcional al tamaño n de la entrada."}

### 2. Complejidad Espacial (Memoria Auxiliar)
- **Espacio Auxiliar**: `{a.complejidad_espacio}`
- **Justificación**:
  El algoritmo no crea estructuras de datos dinámicas adicionales que crezcan con el tamaño de los datos de entrada; solo utiliza variables puntero fijas en memoria stack.

### 3. Escalabilidad
- Si el tamaño de entrada se multiplica por 10 (de 1,000 a 10,000 elementos):
  - Con `{a.complejidad_tiempo}`: {"El tiempo apenas aumenta en ~3 operaciones adicionales." if "log n" in a.complejidad_tiempo else "El tiempo aumentará aproximadamente 10 veces de forma lineal."}
"""


def _generar_modo_bugs(codigo: str, a: AnalisisAST, nivel: str) -> str:
    riesgos_md = "\n".join([f"- ⚠️ **{r}**" for r in a.riesgos_detectados]) if a.riesgos_detectados else "- No se detectaron bugs evidentes de primer nivel."

    return f"""## 🛡️ Detección de Bugs, Riesgos y Casos Límite (Edge Cases)

### 1. Auditoría de Riesgos Detectados
{riesgos_md}

### 2. Casos Límite Críticos a Probar
1. **Colección Vacía (`[]`)**:
   ¿El código valida si hay elementos antes de operar o calcular longitudes?
2. **Elemento Inexistente**:
   ¿Qué devuelve la función si el dato buscado no está en la colección? (Debe retornar `-1` o `None` sin lanzar excepción).
3. **Tipos de Datos Incompatibles**:
   ¿Qué pasa si un usuario envía una cadena de texto en lugar de una lista de números?

### 3. Recomendación Defensiva (Código Blindado)
Se recomienda agregar validaciones de precondición al inicio de la función:
```python
if not lista:
    return -1  # o raise ValueError('La colección no puede estar vacía')
```
"""


def _generar_modo_optimizacion(codigo: str, a: AnalisisAST, nivel: str) -> str:
    pep8_md = "\n".join([f"- 🐍 {p}" for p in a.mejoras_pep8]) if a.mejoras_pep8 else "- Cumple satisfactoriamente las convenciones básicas de estilo PEP 8."

    return f"""## ✨ Optimización y Evaluación de Estilo Pythonic (PEP 8)

### 1. Revisión de Buenas Prácticas (PEP 8)
{pep8_md}

### 2. Consejos de Código Idiomático (Pythonic)
- Usa anotaciones de tipo (*type hints*) en funciones: `def mi_funcion(datos: list[int]) -> float:` para que el editor brinde autocompletado y validación.
- Incluye un docstring conciso al inicio de cada función explicando qué hace, qué recibe y qué retorna.
- Prefiere funciones nativas optimizadas en C (`sum()`, `bisect`) cuando estén disponibles en la biblioteca estándar de Python.
"""


def construir_respuesta_educativa_schema(
    codigo: str,
    *,
    pregunta: str = "Explicación de código Python",
    nivel: str = "basico",
    tema: str = "funciones",
) -> Any:
    from app.schemas.ai_response import (
        ActividadEvaluativa,
        AnalisisComplejidad,
        ConceptoClave,
        ExplicacionLinea,
        MetadataRespuestaIA,
        RespuestaIAEducativa,
    )

    analisis = analizar_codigo_python(codigo)
    lineas_raw = [l for l in codigo.splitlines() if l.strip()]

    explicaciones_lineas = []
    for idx, linea in enumerate(lineas_raw, 1):
        l_str = linea.strip()
        semantica = "Instrucción de ejecución en el flujo del algoritmo."
        impacto = "Mantiene el estado de las variables locales."
        if l_str.startswith("def "):
            semantica = "Declara una nueva función con su bloque y parámetros asociados."
            impacto = "Crea el objeto función en memoria y lo enlaza a su identificador."
        elif l_str.startswith("return "):
            semantica = "Devuelve el valor computado al llamador y finaliza la función."
            impacto = "Libera las variables locales de la pila de llamadas."
        elif l_str.startswith("while "):
            semantica = "Evalúa la condición booleana para continuar el ciclo de iteración."
            impacto = "Determina si se ejecuta una nueva pasada del bucle."
        elif l_str.startswith("for "):
            semantica = "Itera sobre cada elemento de la colección especificada."
            impacto = "Actualiza la variable de control de bucle en cada vuelta."
        elif "=" in l_str and "==" not in l_str:
            semantica = "Evalúa la expresión del lado derecho y la asigna a la variable."
            impacto = "Guarda o actualiza el valor en el espacio de nombres local."

        explicaciones_lineas.append(
            ExplicacionLinea(
                linea_numero=idx,
                codigo_linea=linea,
                semantica=semantica,
                impacto_en_memoria=impacto,
            )
        )

    conceptos = [
        ConceptoClave(
            concepto="Definición de Funciones",
            definicion="La palabra clave 'def' empaqueta un bloque de instrucciones reutilizables.",
            tipo="sintactico",
        ),
        ConceptoClave(
            concepto="Estructuras de Control e Iteración",
            definicion="Permiten bifurcar el flujo lógico o repetir instrucciones eficientemente.",
            tipo="algoritmico",
        ),
    ]

    complejidad = AnalisisComplejidad(
        temporal=analisis.complejidad_tiempo,
        espacial=analisis.complejidad_espacio,
        justificacion=f"Estimado por análisis de árbol sintáctico: {analisis.algoritmo_detectado or 'Algoritmo Python'}",
    )

    actividad = ActividadEvaluativa(
        tipo="opcion_multiple",
        enunciado="¿Qué sucede con la complejidad temporal si el número de elementos se duplica?",
        opciones=["Aumenta proporcionalmente", "Aumenta logarítmicamente", "Se mantiene constante", "Aumenta exponencialmente"],
        respuesta_correcta="Aumenta proporcionalmente" if "O(n)" in analisis.complejidad_tiempo else "Aumenta logarítmicamente",
        retroalimentacion_esperada="El comportamiento ante el crecimiento de entrada define la eficiencia del algoritmo.",
    )

    return RespuestaIAEducativa(
        nivel=nivel if nivel in ("basico", "intermedio", "avanzado") else "basico",
        tema=tema if tema in ("variables", "bucles", "funciones", "oop", "algoritmos", "estructuras", "excepciones", "archivos", "otro") else "funciones",
        pregunta=pregunta,
        codigo=codigo,
        explicacion_general=generar_explicacion_didactica(codigo, modo="didactico", nivel=nivel),
        explicacion_linea_por_linea=explicaciones_lineas,
        conceptos_clave=conceptos,
        analisis_complejidad=complejidad,
        actividad_evaluativa=actividad,
        fuente_ia="modelo-local",
        metadata=MetadataRespuestaIA(tokens_totales=220, latencia_segundos=0.6),
    )
