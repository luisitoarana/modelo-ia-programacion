"""Servicio Curricular de Aprendizaje de Python Basado en Módulos y Retos.

Estructura formativa inspirada en "El Libro de Python" y diseñada para
la investigación cuasiexperimental sobre comprensión algorítmica.

Organiza el conocimiento en 3 Módulos Progresivos:
1. Principiante: Variables, tipos primitivos, palabras reservadas (keyword.kwlist) y print/input.
2. Intermedio: Control de flujo (if/elif/else), bucles (for/while), acumuladores y defensiva (ZeroDivisionError).
3. Avanzado: Modularización con def, complejidad Big-O, estructuras dinámicas y POO (clases).
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Literal


NivelModulo = Literal["principiante", "intermedio", "avanzado"]


@dataclass(slots=True)
class LeccionReto:
    id: str
    modulo_id: NivelModulo
    modulo_titulo: str
    numero: str
    titulo: str
    concepto_clave: str
    palabras_reservadas: list[str]
    descripcion_pedagogica: str
    codigo_inicial: str
    guia_docente: str
    pistas_andamiaje: list[str]
    pregunta_autoevaluacion: str
    codigo_solucion: str


@dataclass(slots=True)
class ModuloInfo:
    id: NivelModulo
    numero: int
    titulo: str
    descripcion: str
    icono: str
    color_hex: str
    temas_principales: list[str]
    lecciones: list[LeccionReto] = field(default_factory=list)


# ─────────────────────────────────────────────────────────────────────────────
# CATÁLOGO OFICIAL DE LECCIONES Y RETOS DE APRENDIZAJE
# ─────────────────────────────────────────────────────────────────────────────

LECCIONES_CURRICULO: list[LeccionReto] = [
    # ── MÓDULO 1: PRINCIPIANTE ──
    LeccionReto(
        id="m1_l1_variables",
        modulo_id="principiante",
        modulo_titulo="Módulo 1: Fundamentos y Palabras Reservadas",
        numero="1.1",
        titulo="Variables y Salida por Consola",
        concepto_clave="Variables en memoria, tipos str e int, función print()",
        palabras_reservadas=[],
        descripcion_pedagogica=(
            "Aprender a reservar un espacio en memoria con un nombre descriptivo "
            "(ej. nombre = 'Luis') y visualizarlo con print(). Comprender que una "
            "variable no necesita declaración de tipo explícita en Python."
        ),
        codigo_inicial=(
            "# Lección 1.1: Tu primera variable en Python\n"
            "# 1. Guarda tu nombre en la variable 'estudiante'\n"
            "estudiante = 'Luis'\n\n"
            "# 2. Guarda tu edad en la variable 'edad'\n"
            "edad = 20\n\n"
            "# 3. Muestra el saludo en pantalla con print()\n"
            "print('Hola, mi nombre es ' + estudiante)\n"
            "print(f'Tengo {edad} años y estoy aprendiendo Python.')\n"
        ),
        guia_docente=(
            "Pregunte al alumno qué ocurre si cambia 'Luis' por otro nombre o si "
            "intenta sumar edad + estudiante directamente sin convertir a texto."
        ),
        pistas_andamiaje=[
            "Una variable es como una caja con una etiqueta donde guardas un dato.",
            "Para texto usamos comillas ('Luis' o \"Luis\"). Para números escribimos el número directo (20).",
            "La función print() envía el texto a la terminal inferior.",
        ],
        pregunta_autoevaluacion=(
            "Observa estudiante y edad en el código. ¿Qué valor guarda cada variable y qué mostrará cada print()? Explica con tus palabras."
        ),
        codigo_solucion=(
            "estudiante = 'Luis'\n"
            "edad = 20\n"
            "print(f'Estudiante: {estudiante}, Edad: {edad}')\n"
        ),
    ),
    LeccionReto(
        id="m1_l2_tipos_datos",
        modulo_id="principiante",
        modulo_titulo="Módulo 1: Fundamentos y Palabras Reservadas",
        numero="1.2",
        titulo="Tipos Primitivos y type()",
        concepto_clave="int, float, str, bool y función type()",
        palabras_reservadas=["True", "False"],
        descripcion_pedagogica=(
            "Diferenciar entre enteros (int), decimales (float), cadenas de texto (str) "
            "y valores booleanos (True / False). Comprender la importancia del tipo "
            "de dato en operaciones aritméticas."
        ),
        codigo_inicial=(
            "# Lección 1.2: Tipos primitivos de Python\n"
            "precio = 19.99       # float (decimal)\n"
            "cantidad = 3         # int (entero)\n"
            "producto = 'Cuaderno' # str (texto)\n"
            "disponible = True    # bool (booleano: True o False)\n\n"
            "# Inspeccionamos los tipos con type():\n"
            "print('Tipo de precio:', type(precio))\n"
            "print('Tipo de cantidad:', type(cantidad))\n"
            "print('Tipo de producto:', type(producto))\n"
            "print('Tipo de disponible:', type(disponible))\n\n"
            "total = precio * cantidad\n"
            "print(f'Total a pagar por {cantidad} {producto}s: ${total:.2f}')\n"
        ),
        guia_docente=(
            "Pídale al estudiante que intente cambiar disponible por 'true' (con minúscula) "
            "para evidenciar que Python distingue mayúsculas en palabras reservadas."
        ),
        pistas_andamiaje=[
            "int son enteros sin coma (1, 2, 100). float tienen punto decimal (3.14).",
            "bool solo acepta exactamente True o False con la primera letra en MAYÚSCULA.",
            "La función type(variable) te dice qué tipo de dato tiene asignado.",
        ],
        pregunta_autoevaluacion=(
            "¿Qué tipo de dato tiene precio y qué tipo tiene producto? ¿Qué crees que ocurre al ejecutar producto + cantidad?"
        ),
        codigo_solucion=(
            "precio = 19.99\n"
            "cantidad = 3\n"
            "total = precio * cantidad\n"
            "print(f'Total: ${total}')\n"
        ),
    ),
    LeccionReto(
        id="m1_l3_palabras_reservadas",
        modulo_id="principiante",
        modulo_titulo="Módulo 1: Fundamentos y Palabras Reservadas",
        numero="1.3",
        titulo="Palabras Reservadas (keyword.kwlist)",
        concepto_clave="Palabras clave del lenguaje, sintaxis reservada",
        palabras_reservadas=["def", "if", "else", "for", "while", "return", "import"],
        descripcion_pedagogica=(
            "Descubrir por qué ciertas palabras como def, for, if, class están reservadas "
            "por el motor de Python y no pueden ser utilizadas como identificadores "
            "de variables. Estudio de keyword.kwlist."
        ),
        codigo_inicial=(
            "# Lección 1.3: Palabras reservadas en Python (El Libro de Python)\n"
            "import keyword\n\n"
            "# 1. Vemos cuántas palabras reservadas tiene Python:\n"
            "palabras = keyword.kwlist\n"
            "print(f'Python tiene {len(palabras)} palabras reservadas oficiales:')\n"
            "print(palabras[:12])  # Mostramos las primeras 12\n\n"
            "# 2. EXPERIMENTO:\n"
            "# Si descomentas la siguiente línea, verás un SyntaxError:\n"
            "# for = 10  # ¡Error! 'for' está reservada para bucles\n\n"
            "# La forma correcta es usar un nombre válido:\n"
            "repeticiones = 10\n"
            "print(f'Variable válida creada con éxito: repeticiones = {repeticiones}')\n"
        ),
        guia_docente=(
            "Haga que el estudiante intente asignar valores a 'def = 5' o 'if = True'. "
            "Al ver el SyntaxError, pregunte qué mensaje muestra la terminal."
        ),
        pistas_andamiaje=[
            "Python tiene una lista de ~35 palabras que son órdenes directas del lenguaje.",
            "Ninguna palabra reservada puede usarse como nombre de variable o función.",
            "Si una palabra cambia de color en el editor (sintaxis resaltada), probablemente sea reservada.",
        ],
        pregunta_autoevaluacion=(
            "¿Qué ocurre si usas for como nombre de una variable, por ejemplo for = 10? Explica por qué Python reserva esa palabra."
        ),
        codigo_solucion=(
            "import keyword\n"
            "print(keyword.kwlist)\n"
        ),
    ),
    LeccionReto(
        id="m1_l4_indentacion_reglas",
        modulo_id="principiante",
        modulo_titulo="Módulo 1: Fundamentos y Palabras Reservadas",
        numero="1.4",
        titulo="Indentación y Dos Puntos (:)",
        concepto_clave="Indentación de 4 espacios, bloque de código, sintaxis con :",
        palabras_reservadas=["if", "else"],
        descripcion_pedagogica=(
            "Comprender la regla estructural más importante de Python: la indentación. "
            "A diferencia de otros lenguajes con llaves {}, Python usa sangría consistente; se recomiendan 4 espacios "
            "y dos puntos (:) para delimitar qué código pertenece a un bloque."
        ),
        codigo_inicial=(
            "# Lección 1.4: La regla de oro de Python: Indentación\n"
            "nota = 8.5\n\n"
            "# Los dos puntos ':' abren el bloque. Las siguientes líneas llevan 4 espacios:\n"
            "if nota >= 7.0:\n"
            "    print('¡Felicidades!')\n"
            "    print('Has aprobado la materia.')\n"
            "else:\n"
            "    print('Debes prepararte para el examen de recuperación.')\n\n"
            "print('Fin de la evaluación.')  # Fuera del bloque if/else\n"
        ),
        guia_docente=(
            "Pídale al estudiante que quite los 4 espacios antes de print('¡Felicidades!') "
            "para que experimente el error IndentationError: expected an indented block."
        ),
        pistas_andamiaje=[
            "Siempre que una línea termine en dos puntos ':', la siguiente debe tener sangría (se recomiendan 4 espacios).",
            "Si el código no tiene sangría, Python no sabe si pertenece al condicional o si va después.",
            "Para salir del bloque, simplemente vuelves a escribir alineado al margen izquierdo.",
        ],
        pregunta_autoevaluacion=(
            "Con nota = 8.5, ¿qué mensajes se mostrarán? Explica cómo los espacios al inicio de una línea indican qué instrucciones pertenecen al if."
        ),
        codigo_solucion=(
            "nota = 8.5\n"
            "if nota >= 7.0:\n"
            "    print('Aprobado')\n"
            "else:\n"
            "    print('Reprobado')\n"
        ),
    ),

    # ── MÓDULO 2: INTERMEDIO ──
    LeccionReto(
        id="m2_l1_condicionales",
        modulo_id="intermedio",
        modulo_titulo="Módulo 2: Control de Flujo y Colecciones",
        numero="2.1",
        titulo="Condicionales Múltiples (if, elif, else)",
        concepto_clave="Bifurcaciones lógicas, operadores relacionales and/or/not",
        palabras_reservadas=["if", "elif", "else", "and", "or"],
        descripcion_pedagogica=(
            "Dominar la toma de decisiones con múltiples caminos usando elif. "
            "Comprender el orden secuencial de evaluación de condiciones "
            "y cómo evitar condiciones redundantes."
        ),
        codigo_inicial=(
            "# Lección 2.1: Clasificación de calificaciones con if / elif / else\n"
            "calificacion = 82\n\n"
            "if calificacion >= 90:\n"
            "    nivel = 'Excelente'\n"
            "elif calificacion >= 80:\n"
            "    nivel = 'Muy Bueno'\n"
            "elif calificacion >= 70:\n"
            "    nivel = 'Aprobado'\n"
            "else:\n"
            "    nivel = 'Reprobado'\n\n"
            "print(f'Calificación {calificacion} -> Nivel: {nivel}')\n"
        ),
        guia_docente=(
            "Pregunte qué pasaría si cambiáramos el orden y pusiéramos 'if calificacion >= 70:' al principio. "
            "Demuestre cómo el orden de las ramas altera el resultado algorítmico."
        ),
        pistas_andamiaje=[
            "Python evalúa las condiciones de arriba hacia abajo.",
            "En cuanto una condición es Verdadera (True), ejecuta ese bloque y salta el resto de ramas.",
            "La rama 'else' es la red de seguridad: se ejecuta solo si ninguna condición anterior fue cierta.",
        ],
        pregunta_autoevaluacion=(
            "Si cambias calificacion a 95, ¿qué valor tendrá nivel? Explica por qué se elige esa rama y no la siguiente."
        ),
        codigo_solucion=(
            "calificacion = 82\n"
            "if calificacion >= 90:\n"
            "    print('A')\n"
            "elif calificacion >= 80:\n"
            "    print('B')\n"
            "else:\n"
            "    print('C')\n"
        ),
    ),
    LeccionReto(
        id="m2_l2_bucles_acumuladores",
        modulo_id="intermedio",
        modulo_titulo="Módulo 2: Control de Flujo y Colecciones",
        numero="2.2",
        titulo="Bucles for y Variables Acumuladoras",
        concepto_clave="Bucle for, iterador range(), patrón acumulador total += x",
        palabras_reservadas=["for", "in"],
        descripcion_pedagogica=(
            "Comprender el patrón algorítmico fundamental del acumulador: una variable "
            "que mantiene el estado sumatorio de las iteraciones de un bucle for."
        ),
        codigo_inicial=(
            "# Lección 2.2: Patrón Acumulador con bucle for\n"
            "# Queremos calcular la suma de los números del 1 al 5:\n"
            "acumulador_suma = 0  # Inicia en el elemento neutro de la suma\n\n"
            "print('Traza paso a paso:')\n"
            "for numero in range(1, 6):  # Genera: 1, 2, 3, 4, 5\n"
            "    acumulador_suma = acumulador_suma + numero\n"
            "    print(f'  Paso: sumamos {numero} -> Total parcial: {acumulador_suma}')\n\n"
            "print(f'Suma total final: {acumulador_suma}')\n"
        ),
        guia_docente=(
            "Haga que el estudiante trace a mano el valor de acumulador_suma en cada paso. "
            "Luego pregunte qué ocurriría si iniciáramos acumulador_suma en 10 en lugar de 0."
        ),
        pistas_andamiaje=[
            "Un acumulador siempre debe inicializarse FUERA del bucle.",
            "En cada ciclo, la variable 'numero' toma el siguiente valor de range().",
            "La operación acumulador_suma += numero actualiza el valor anterior sumándole el nuevo.",
        ],
        pregunta_autoevaluacion=(
            "¿Qué números recorre range(1, 6) y cuál será la suma final? Describe cómo cambia acumulador_suma en el bucle."
        ),
        codigo_solucion=(
            "total = sum(range(1, 6))\n"
            "print(f'Total: {total}')\n"
        ),
    ),
    LeccionReto(
        id="m2_l3_listas_colecciones",
        modulo_id="intermedio",
        modulo_titulo="Módulo 2: Control de Flujo y Colecciones",
        numero="2.3",
        titulo="Listas Dinámicas e Indexación",
        concepto_clave="Listas [], índice 0, len(), append(), recorrido for-in",
        palabras_reservadas=["for", "in"],
        descripcion_pedagogica=(
            "Aprender a agrupar múltiples datos en una sola estructura lineal. "
            "Entender que los índices en Python comienzan en cero (0) y cómo "
            "calcular el tamaño con len()."
        ),
        codigo_inicial=(
            "# Lección 2.3: Manipulación de listas en Python\n"
            "lenguajes = ['Python', 'JavaScript', 'C++', 'Java']\n\n"
            "# Acceso por índice (base cero):\n"
            "print(f'Primer lenguaje (índice 0): {lenguajes[0]}')\n"
            "print(f'Último lenguaje (índice -1): {lenguajes[-1]}')\n"
            "print(f'Total de elementos: {len(lenguajes)}')\n\n"
            "# Recorrido de la lista con bucle for:\n"
            "print('\\nLista completa:')\n"
            "for i, item in enumerate(lenguajes, start=1):\n"
            "    print(f'  {i}. {item}')\n"
        ),
        guia_docente=(
            "Pida que intenten acceder a lenguajes[10] para que experimenten el error IndexError: list index out of range."
        ),
        pistas_andamiaje=[
            "El primer elemento de una lista está en la posición 0, no en 1.",
            "El último elemento se puede acceder cómodamente con el índice negativo -1.",
            "len(lista) te da cuántos elementos hay dentro.",
        ],
        pregunta_autoevaluacion=(
            "¿Qué muestran lenguajes[0] y lenguajes[-1]? Explica qué ocurre si intentas acceder a lenguajes[4] en esta lista."
        ),
        codigo_solucion=(
            "items = ['a', 'b', 'c']\n"
            "print(items[0], items[-1])\n"
        ),
    ),
    LeccionReto(
        id="m2_l4_defensiva_zerodivision",
        modulo_id="intermedio",
        modulo_titulo="Módulo 2: Control de Flujo y Colecciones",
        numero="2.4",
        titulo="Programación Defensiva (ZeroDivisionError)",
        concepto_clave="Casos límite, lista vacía [], prevención de división entre cero",
        palabras_reservadas=["if", "not", "return", "try", "except"],
        descripcion_pedagogica=(
            "Aprender a programar con blindaje ante casos límite. Si una lista viene vacía, "
            "su longitud es cero y dividir la suma entre len(lista) causa un colapso "
            "del sistema por ZeroDivisionError. Aprender a validar antes de operar."
        ),
        codigo_inicial=(
            "# Lección 2.4: Blindaje ante ZeroDivisionError\n"
            "def calcular_promedio_seguro(notas):\n"
            "    # VALIDACIÓN DEFENSIVA:\n"
            "    # Si la lista está vacía, evitamos dividir entre 0:\n"
            "    if not notas:  # Equivalente a: if len(notas) == 0\n"
            "        print('⚠️ Advertencia: Lista vacía recibida. Promedio es 0.0')\n"
            "        return 0.0\n"
            "    \n"
            "    # Si llegamos aquí, es 100% seguro dividir:\n"
            "    suma = sum(notas)\n"
            "    return suma / len(notas)\n\n"
            "# Prueba 1: Con notas reales\n"
            "notas_luis = [8.0, 9.5, 7.0]\n"
            "print('Promedio Luis:', calcular_promedio_seguro(notas_luis))\n\n"
            "# Prueba 2: Caso límite peligroso (lista vacía)\n"
            "notas_vacias = []\n"
            "print('Promedio Lista Vacía:', calcular_promedio_seguro(notas_vacias))\n"
        ),
        guia_docente=(
            "Demuestre a los alumnos qué pasa si quitan el 'if not notas:'. "
            "El programa se detiene de golpe con ZeroDivisionError: division by zero. "
            "Este es el núcleo de la comprensión algorítmica defensiva."
        ),
        pistas_andamiaje=[
            "En matemáticas y en computación, dividir entre cero es una operación indefinida que detiene el programa.",
            "Una lista vacía [] tiene len == 0. Por tanto, notas / len(notas) causará error si no se valida.",
            "La instrucción 'if not lista:' comprueba limpiamente si una colección está vacía.",
        ],
        pregunta_autoevaluacion=(
            "¿Qué devuelve calcular_promedio_seguro([])? Explica qué error evita if not notas cuando la lista está vacía."
        ),
        codigo_solucion=(
            "def promedio(lista):\n"
            "    return sum(lista) / len(lista) if lista else 0.0\n"
        ),
    ),

    # ── MÓDULO 3: AVANZADO ──
    LeccionReto(
        id="m3_l1_funciones_puras",
        modulo_id="avanzado",
        modulo_titulo="Módulo 3: Algoritmos, Big-O y POO",
        numero="3.1",
        titulo="Funciones Puras y Modularización (def)",
        concepto_clave="def, parámetros, return, anotaciones de tipo (type hints), funciones puras",
        palabras_reservadas=["def", "return"],
        descripcion_pedagogica=(
            "Diseño de funciones profesionales con anotaciones de tipo (type hints) y docstrings. "
            "Comprender la diferencia entre funciones con efectos secundarios (print) "
            "y funciones puras que retornan valores reutilizables (return)."
        ),
        codigo_inicial=(
            "# Lección 3.1: Modularización profesional con funciones\n"
            "def calcular_estadisticas(numeros: list[float]) -> dict[str, float]:\n"
            "    \"\"\"Calcula el valor mínimo, máximo y media de una colección numérica.\"\"\"\n"
            "    if not numeros:\n"
            "        return {'min': 0.0, 'max': 0.0, 'media': 0.0}\n"
            "    \n"
            "    return {\n"
            "        'min': min(numeros),\n"
            "        'max': max(numeros),\n"
            "        'media': round(sum(numeros) / len(numeros), 2),\n"
            "    }\n\n"
            "datos = [12.5, 45.0, 78.2, 33.1, 9.8]\n"
            "resumen = calcular_estadisticas(datos)\n"
            "print('Resultados estadísticos:', resumen)\n"
        ),
        guia_docente=(
            "Explique la diferencia entre 'print()' (que solo muestra en consola) y 'return' "
            "(que entrega el dato a otra parte del sistema para seguir computando)."
        ),
        pistas_andamiaje=[
            "Una función es un bloque de código reutilizable que recibe entradas (parámetros) y produce una salida (return).",
            "Los type hints (list[float] -> dict) ayudan a documentar qué datos espera recibir y qué devuelve.",
            "Una función pura siempre devuelve el mismo resultado para las mismas entradas.",
        ],
        pregunta_autoevaluacion=(
            "¿Qué devuelve calcular_estadisticas(datos)? Explica cómo podrías usar ese resultado en otra parte del programa y qué cambiaría si la función solo lo imprimiera."
        ),
        codigo_solucion=(
            "def stats(datos: list[float]) -> dict:\n"
            "    return {'min': min(datos), 'max': max(datos), 'avg': sum(datos)/len(datos)} if datos else {}\n"
        ),
    ),
    LeccionReto(
        id="m3_l2_busqueda_binaria_bigo",
        modulo_id="avanzado",
        modulo_titulo="Módulo 3: Algoritmos, Big-O y POO",
        numero="3.2",
        titulo="Búsqueda Binaria y Complejidad O(log n)",
        concepto_clave="Notación Big-O, complejidad temporal O(log n), búsqueda binaria",
        palabras_reservadas=["def", "while", "if", "elif", "else", "return"],
        descripcion_pedagogica=(
            "Análisis formal de algoritmos y eficiencia Big-O. Demostración de por qué "
            "la búsqueda binaria divide el espacio a la mitad en cada ciclo, logrando "
            "un tiempo de ejecución O(log n) frente al O(n) de la búsqueda secuencial."
        ),
        codigo_inicial=(
            "# Lección 3.2: Búsqueda Binaria - O(log n)\n"
            "def busqueda_binaria(coleccion: list[int], objetivo: int) -> int:\n"
            "    \"\"\"Retorna el índice del objetivo o -1 si no existe. Precondición: lista ordenada.\"\"\"\n"
            "    inicio = 0\n"
            "    fin = len(coleccion) - 1\n"
            "    pasos = 0\n"
            "    \n"
            "    while inicio <= fin:\n"
            "        pasos += 1\n"
            "        medio = (inicio + fin) // 2\n"
            "        if coleccion[medio] == objetivo:\n"
            "            print(f'-> Encontrado en {pasos} comparaciones (O(log n))')\n"
            "            return medio\n"
            "        elif coleccion[medio] < objetivo:\n"
            "            inicio = medio + 1\n"
            "        else:\n"
            "            fin = medio - 1\n"
            "            \n"
            "    return -1\n\n"
            "datos_ordenados = [2, 5, 8, 12, 16, 23, 38, 56, 72, 91]\n"
            "pos = busqueda_binaria(datos_ordenados, 23)\n"
            "print(f'Elemento 23 ubicado en índice: {pos}')\n"
        ),
        guia_docente=(
            "Haga notar a los alumnos que para 1,000 elementos la búsqueda binaria requiere máximo 10 pasos, "
            "mientras la búsqueda secuencial requeriría hasta 1,000 pasos."
        ),
        pistas_andamiaje=[
            "Precondición indispensable: la lista DEBE estar previamente ordenada.",
            "En cada ciclo, descartamos la mitad de los elementos dividiendo por dos.",
            "Complejidad temporal: Peor caso O(log n), Mejor caso O(1) si está en el centro.",
        ],
        pregunta_autoevaluacion=(
            "¿Qué posición devuelve la búsqueda del número 23? Explica por qué la lista debe estar ordenada para descartar la mitad de los elementos."
        ),
        codigo_solucion=(
            "def bin_search(arr, target):\n"
            "    lo, hi = 0, len(arr) - 1\n"
            "    while lo <= hi:\n"
            "        mid = (lo + hi) // 2\n"
            "        if arr[mid] == target: return mid\n"
            "        elif arr[mid] < target: lo = mid + 1\n"
            "        else: hi = mid - 1\n"
            "    return -1\n"
        ),
    ),
    LeccionReto(
        id="m3_l3_poo_clases",
        modulo_id="avanzado",
        modulo_titulo="Módulo 3: Algoritmos, Big-O y POO",
        numero="3.3",
        titulo="Programación Orientada a Objetos (POO)",
        concepto_clave="class, constructor __init__, métodos de instancia, parámetro self",
        palabras_reservadas=["class", "def", "return"],
        descripcion_pedagogica=(
            "Introducción al paradigma de objetos: empaquetar estado (atributos) y "
            "comportamiento (métodos) dentro de una clase reutilizable. "
            "Comprender el rol del constructor __init__ y la referencia self."
        ),
        codigo_inicial=(
            "# Lección 3.3: Clases y Objetos en Python\n"
            "class Estudiante:\n"
            "    def __init__(self, nombre: str, carrera: str):\n"
            "        self.nombre = nombre\n"
            "        self.carrera = carrera\n"
            "        self.calificaciones: list[float] = []\n"
            "    \n"
            "    def agregar_nota(self, nota: float) -> None:\n"
            "        if 0.0 <= nota <= 10.0:\n"
            "            self.calificaciones.append(nota)\n"
            "            \n"
            "    def promedio(self) -> float:\n"
            "        if not self.calificaciones:\n"
            "            return 0.0\n"
            "        return round(sum(self.calificaciones) / len(self.calificaciones), 2)\n\n"
            "# Instanciación y uso del objeto:\n"
            "luis = Estudiante('Luis', 'Ingeniería en Sistemas')\n"
            "luis.agregar_nota(9.5)\n"
            "luis.agregar_nota(8.0)\n"
            "print(f'Estudiante: {luis.nombre} ({luis.carrera})')\n"
            "print(f'Promedio acumulado: {luis.promedio()}')\n"
        ),
        guia_docente=(
            "Explique la analogía del plano arquitectónico (la clase) y la casa construida (el objeto o instancia). "
            "Detalle por qué 'self' representa a la instancia particular que ejecuta el método."
        ),
        pistas_andamiaje=[
            "Una clase es un molde que define qué datos y qué acciones tiene una entidad.",
            "__init__ es el método constructor que se ejecuta automáticamente al crear un nuevo objeto.",
            "'self' hace referencia al objeto específico con el que estamos trabajando.",
        ],
        pregunta_autoevaluacion=(
            "¿Qué promedio tendrá luis después de agregar las dos notas? Explica cómo self permite que cada estudiante conserve sus propios datos."
        ),
        codigo_solucion=(
            "class Alumno:\n"
            "    def __init__(self, nombre):\n"
            "        self.nombre = nombre\n"
        ),
    ),
]


MODULOS_DEFINICION: list[ModuloInfo] = [
    ModuloInfo(
        id="principiante",
        numero=1,
        titulo="Módulo 1: Fundamentos y Palabras Reservadas",
        descripcion=(
            "Sintaxis elemental de Python, asignación de variables (ej. Luis = 1), "
            "tipos primitivos (int, float, str, bool), palabras reservadas oficiales "
            "(keyword.kwlist) y reglas de indentación de 4 espacios."
        ),
        icono="menu_book_rounded",
        color_hex="#2196F3",
        temas_principales=[
            "Variables y Asignación",
            "Tipos Primitivos (str, int, float, bool)",
            "Palabras Reservadas de Python",
            "Indentación y Reglas de Sintaxis (:)",
        ],
        lecciones=[l for l in LECCIONES_CURRICULO if l.modulo_id == "principiante"],
    ),
    ModuloInfo(
        id="intermedio",
        numero=2,
        titulo="Módulo 2: Control de Flujo y Colecciones",
        descripcion=(
            "Bifurcaciones lógicas (if/elif/else), bucles iterativos (for/while con range), "
            "variables con rol algorítmico (acumuladores y contadores), listas y programación "
            "defensiva para prevenir ZeroDivisionError e IndexError."
        ),
        icono="alt_route_rounded",
        color_hex="#FFA000",
        temas_principales=[
            "Condicionales (if / elif / else)",
            "Bucles for y Patrón Acumulador",
            "Listas Dinámicas y Colecciones",
            "Programación Defensiva (ZeroDivisionError)",
        ],
        lecciones=[l for l in LECCIONES_CURRICULO if l.modulo_id == "intermedio"],
    ),
    ModuloInfo(
        id="avanzado",
        numero=3,
        titulo="Módulo 3: Algoritmos, Big-O y POO",
        descripcion=(
            "Modularización con funciones puras (def), análisis formal de complejidad "
            "algorítmica Big-O (tiempo y memoria), Programación Orientada a Objetos "
            "(clases, métodos, __init__) y buenas prácticas PEP 8."
        ),
        icono="psychology_rounded",
        color_hex="#9C27B0",
        temas_principales=[
            "Funciones Puras y Tipado Estático",
            "Búsqueda Binaria y Complejidad O(log n)",
            "Clases y Objetos (POO)",
            "Estándares PEP 8 y Código Limpio",
        ],
        lecciones=[l for l in LECCIONES_CURRICULO if l.modulo_id == "avanzado"],
    ),
]


class CurriculumService:
    """Gestiona el catálogo curricular y construye instrucciones pedagógicas adaptadas."""

    @staticmethod
    def listar_modulos() -> list[dict]:
        return [
            {
                "id": m.id,
                "numero": m.numero,
                "titulo": m.titulo,
                "descripcion": m.descripcion,
                "icono": m.icono,
                "color_hex": m.color_hex,
                "temas_principales": m.temas_principales,
                "total_lecciones": len(m.lecciones),
            }
            for m in MODULOS_DEFINICION
        ]

    @staticmethod
    def obtener_modulo(modulo_id: str) -> dict | None:
        mid = modulo_id.lower().strip()
        alias = {
            "modulo_1": "principiante",
            "modulo_2": "intermedio",
            "modulo_3": "avanzado",
            "1": "principiante",
            "2": "intermedio",
            "3": "avanzado",
        }
        mid = alias.get(mid, mid)
        mod = next((m for m in MODULOS_DEFINICION if m.id == mid), None)
        if not mod:
            return None
        return {
            "id": mod.id,
            "numero": mod.numero,
            "titulo": mod.titulo,
            "descripcion": mod.descripcion,
            "icono": mod.icono,
            "color_hex": mod.color_hex,
            "temas_principales": mod.temas_principales,
            "lecciones": [
                {
                    "id": l.id,
                    "numero": l.numero,
                    "titulo": l.titulo,
                    "concepto_clave": l.concepto_clave,
                    "palabras_reservadas": l.palabras_reservadas,
                    "descripcion_pedagogica": l.descripcion_pedagogica,
                    "codigo_inicial": l.codigo_inicial,
                    "guia_docente": l.guia_docente,
                    "pistas_andamiaje": l.pistas_andamiaje,
                    "pregunta_autoevaluacion": l.pregunta_autoevaluacion,
                }
                for l in mod.lecciones
            ],
        }

    @staticmethod
    def obtener_leccion(leccion_id: str) -> LeccionReto | None:
        # La app de escritorio publicó estos dos identificadores abreviados.
        # Mantener ambos permite registrar sus intentos y consultar registros web.
        aliases = {
            "m1_l4_indentacion": "m1_l4_indentacion_reglas",
            "m2_l3_listas_indexacion": "m2_l3_listas_colecciones",
        }
        identificador = leccion_id.strip()
        identificador = aliases.get(identificador, identificador)
        return next((l for l in LECCIONES_CURRICULO if l.id == identificador), None)

    @staticmethod
    def construir_prompt_tutor_leccion(
        leccion: LeccionReto,
        codigo_estudiante: str,
        duda_estudiante: str | None = None,
    ) -> str:
        """Genera el prompt para que la IA actúe como tutor de una lección específica."""
        duda = duda_estudiante.strip() if duda_estudiante else "El estudiante solicita explicación didáctica de este código."
        return (
            f"[CONTEXTO DE APRENDIZAJE CURRICULAR]\n"
            f"Módulo: {leccion.modulo_titulo}\n"
            f"Lección {leccion.numero}: {leccion.titulo}\n"
            f"Concepto Central: {leccion.concepto_clave}\n"
            f"Palabras Reservadas Clave: {', '.join(leccion.palabras_reservadas)}\n\n"
            f"Consulta / Estado del Estudiante: {duda}\n\n"
            f"Código en el editor:\n```python\n{codigo_estudiante}\n```\n\n"
            f"Instrucción para el Tutor IA: Explica pedagógicamente conectando con los conceptos de la lección "
            f"'{leccion.titulo}'. No entregues solo el código final; desglosa los pasos, señala cómo influyen las "
            f"palabras clave y termina planteando la pregunta de reflexión: '{leccion.pregunta_autoevaluacion}'."
        )
