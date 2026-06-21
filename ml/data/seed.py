"""Corpus semilla incorporado (sin APIs).

Conjunto de ejemplos educativos escritos a mano que permite:
  - Entrenar el tokenizer y el modelo end-to-end sin gastar API.
  - Servir de "few-shot" base y de conjunto de prueba del pipeline.
  - Arrancar el corpus al que luego se suman los ejemplos generados por APIs.

No pretende ser grande: su fin es que TODO el pipeline (tokenizer → modelo →
entrenamiento → inferencia) sea ejecutable y verificable de inmediato.
"""

from __future__ import annotations

from ml.data.schema import EjemploEntrenamiento as E


def construir_semilla() -> list[E]:
    ejemplos: list[E] = [
        E(
            instruccion="Explica qué es una variable en Python",
            entrada="nombre = 'Ana'",
            salida=(
                "Una variable es un nombre que apunta a un objeto en memoria. "
                "En este caso, 'nombre' apunta al texto 'Ana'. En Python no se "
                "declara el tipo: lo determina el valor asignado. Puedes reasignar "
                "la variable a otro objeto en cualquier momento."
            ),
            nivel="basico", tema="variables", tipo="explicacion_codigo",
        ),
        E(
            instruccion="Explica qué hace este código",
            entrada="for i in range(3):\n    print(i)",
            salida=(
                "Este bucle for repite tres veces. range(3) produce los números "
                "0, 1 y 2. En cada vuelta, 'i' toma uno de esos valores y se "
                "imprime. La salida es 0, 1 y 2, cada uno en una línea."
            ),
            nivel="basico", tema="bucles", tipo="explicacion_codigo",
        ),
        E(
            instruccion="Genera una función que sume dos números y explícala",
            entrada="",
            salida=(
                "def sumar(a, b):\n    return a + b\n\n"
                "La función sumar recibe dos parámetros, a y b, y devuelve su suma "
                "con return. Es una función pura: con los mismos argumentos siempre "
                "da el mismo resultado y no modifica nada externo."
            ),
            nivel="basico", tema="funciones", tipo="generacion_codigo",
        ),
        E(
            instruccion="Explica qué es una función en Python",
            entrada="",
            salida=(
                "Una función es un bloque de código reutilizable que realiza una "
                "tarea concreta. Se define con la palabra def, puede recibir "
                "parámetros y devolver un valor con return. Sirve para organizar el "
                "programa, evitar repetición y razonar por partes."
            ),
            nivel="basico", tema="funciones", tipo="concepto",
        ),
        E(
            instruccion="Calcula el promedio de una lista de notas y explica la lógica",
            entrada="",
            salida=(
                "def promedio(notas):\n    return sum(notas) / len(notas)\n\n"
                "La función suma todas las notas con sum y divide entre la cantidad "
                "de elementos con len. Así obtiene el promedio. Conviene validar que "
                "la lista no esté vacía para evitar una división entre cero."
            ),
            nivel="basico", tema="funciones", tipo="generacion_codigo",
        ),
        E(
            instruccion="Explica el condicional if/elif/else",
            entrada="if nota >= 11:\n    print('Aprobado')\nelse:\n    print('Desaprobado')",
            salida=(
                "El if evalúa una condición booleana. Si nota es mayor o igual a 11, "
                "ejecuta la primera rama e imprime 'Aprobado'. Si no se cumple, el "
                "else ejecuta la rama alternativa e imprime 'Desaprobado'. Solo una "
                "de las ramas se ejecuta."
            ),
            nivel="basico", tema="bucles", tipo="explicacion_codigo",
        ),
        E(
            instruccion="Explica qué es una lista en Python",
            entrada="notas = [13, 14, 17]",
            salida=(
                "Una lista es una colección ordenada y mutable de elementos. Aquí "
                "'notas' contiene tres enteros. Puedes acceder por índice (notas[0] "
                "es 13), agregar con append y recorrerla con un bucle for. Permite "
                "elementos repetidos."
            ),
            nivel="basico", tema="estructuras", tipo="explicacion_codigo",
        ),
        E(
            instruccion="Explica qué es un diccionario en Python",
            entrada="estudiante = {'nombre': 'Ana', 'edad': 21}",
            salida=(
                "Un diccionario almacena pares clave-valor. Aquí la clave 'nombre' "
                "tiene el valor 'Ana' y 'edad' tiene 21. Se accede por clave, por "
                "ejemplo estudiante['nombre']. El acceso es muy rápido porque usa "
                "tablas hash."
            ),
            nivel="intermedio", tema="estructuras", tipo="explicacion_codigo",
        ),
        E(
            instruccion="Crea una clase con un método y explícala",
            entrada="",
            salida=(
                "class Estudiante:\n    def __init__(self, nombre):\n"
                "        self.nombre = nombre\n\n    def saludar(self):\n"
                "        return f'Hola, soy {self.nombre}'\n\n"
                "La clase Estudiante define un atributo nombre en el constructor "
                "__init__ y un método saludar que devuelve un saludo. Una clase "
                "separa el estado (atributos) del comportamiento (métodos)."
            ),
            nivel="intermedio", tema="oop", tipo="generacion_codigo",
        ),
        E(
            instruccion="Explica la herencia con clase padre e hija",
            entrada=(
                "class Persona:\n    def __init__(self, nombre):\n"
                "        self.nombre = nombre\n\n"
                "class Estudiante(Persona):\n    pass"
            ),
            salida=(
                "Estudiante hereda de Persona, así que reutiliza su constructor y "
                "atributos sin reescribirlos. La herencia modela una relación 'es un': "
                "un Estudiante es una Persona. Con super() la hija puede llamar al "
                "comportamiento del padre."
            ),
            nivel="avanzado", tema="oop", tipo="explicacion_codigo",
        ),
        E(
            instruccion="Implementa búsqueda binaria y explica su ventaja",
            entrada="",
            salida=(
                "def busqueda_binaria(lista, objetivo):\n    izq, der = 0, len(lista) - 1\n"
                "    while izq <= der:\n        mid = (izq + der) // 2\n"
                "        if lista[mid] == objetivo:\n            return mid\n"
                "        if lista[mid] < objetivo:\n            izq = mid + 1\n"
                "        else:\n            der = mid - 1\n    return -1\n\n"
                "La búsqueda binaria requiere una lista ordenada y divide el rango a "
                "la mitad en cada paso, logrando complejidad O(log n), mucho más "
                "rápida que la búsqueda lineal O(n)."
            ),
            nivel="intermedio", tema="algoritmos", tipo="generacion_codigo",
        ),
        E(
            instruccion="Explica la recursividad con el factorial",
            entrada="def factorial(n):\n    if n <= 1:\n        return 1\n    return n * factorial(n - 1)",
            salida=(
                "Una función recursiva se llama a sí misma. El caso base es n <= 1, "
                "que devuelve 1 y detiene la recursión. El caso recursivo multiplica "
                "n por el factorial de n-1, acercándose al caso base. Cada llamada se "
                "apila en la pila de llamadas hasta resolverse."
            ),
            nivel="avanzado", tema="algoritmos", tipo="explicacion_codigo",
        ),
        E(
            instruccion="Explica la complejidad O(n) de recorrer una lista",
            entrada="for x in lista:\n    print(x)",
            salida=(
                "El bucle visita cada elemento una vez, así que el tiempo crece de "
                "forma proporcional al tamaño de la lista: si hay n elementos, hace n "
                "operaciones. Eso es complejidad temporal O(n), lineal. La memoria "
                "adicional es O(1)."
            ),
            nivel="intermedio", tema="algoritmos", tipo="concepto",
        ),
        E(
            instruccion="Corrige el error en este código y explica",
            entrada="def dividir(a, b):\n    return a / b\n\ndividir(10, 0)",
            salida=(
                "El error es una división entre cero, que lanza ZeroDivisionError. "
                "Debes validar el divisor antes de dividir:\n\n"
                "def dividir(a, b):\n    if b == 0:\n        raise ValueError('b no puede ser 0')\n"
                "    return a / b\n\nAsí el programa falla de forma controlada y clara."
            ),
            nivel="intermedio", tema="excepciones", tipo="correccion_error",
        ),
        E(
            instruccion="Explica el manejo de excepciones con try/except",
            entrada="try:\n    n = int('abc')\nexcept ValueError:\n    print('No es un número')",
            salida=(
                "El bloque try intenta ejecutar código que podría fallar. int('abc') "
                "no se puede convertir y lanza ValueError. El except captura ese error "
                "y ejecuta su rama, imprimiendo 'No es un número', evitando que el "
                "programa se detenga abruptamente."
            ),
            nivel="intermedio", tema="excepciones", tipo="explicacion_codigo",
        ),
        E(
            instruccion="Genera una actividad de comprensión sobre bucles",
            entrada="",
            salida=(
                "Pregunta: ¿Cuál es la salida de este código?\n"
                "for i in range(1, 4):\n    print(i * 2)\n\n"
                "Opciones: a) 1 2 3  b) 2 4 6  c) 0 2 4\n"
                "Respuesta correcta: b) 2 4 6, porque i toma los valores 1, 2 y 3, y "
                "cada uno se multiplica por 2."
            ),
            nivel="basico", tema="bucles", tipo="actividad",
        ),
        E(
            instruccion="Explica qué es un bucle while",
            entrada="n = 3\nwhile n > 0:\n    print(n)\n    n -= 1",
            salida=(
                "El bucle while repite mientras la condición sea verdadera. Empieza "
                "con n=3 e imprime 3, 2 y 1. En cada vuelta resta 1 a n; cuando n "
                "llega a 0 la condición n > 0 es falsa y el bucle termina. Es clave "
                "modificar n para no crear un bucle infinito."
            ),
            nivel="basico", tema="bucles", tipo="explicacion_codigo",
        ),
        E(
            instruccion="Explica los tipos de datos básicos en Python",
            entrada="",
            salida=(
                "Los tipos básicos son: int para enteros (5), float para decimales "
                "(3.14), str para texto ('hola') y bool para verdadero/falso (True). "
                "El tipo determina qué operaciones son válidas; por ejemplo, no puedes "
                "sumar directamente un str y un int sin convertir."
            ),
            nivel="basico", tema="variables", tipo="concepto",
        ),
        E(
            instruccion="Usa una comprensión de listas y explícala",
            entrada="",
            salida=(
                "pares = [x for x in range(10) if x % 2 == 0]\n\n"
                "Una comprensión de listas construye una lista en una sola línea. "
                "Recorre range(10) y conserva solo los x cuyo resto al dividir entre 2 "
                "es 0, es decir, los pares: [0, 2, 4, 6, 8]. Es más conciso que un for "
                "con append."
            ),
            nivel="intermedio", tema="estructuras", tipo="generacion_codigo",
        ),
        E(
            instruccion="Explica el polimorfismo con un ejemplo",
            entrada="",
            salida=(
                "El polimorfismo permite que objetos de distintas clases respondan al "
                "mismo método a su manera. Si Perro y Gato tienen un método sonido(), "
                "una función que llame animal.sonido() funcionará con cualquiera, sin "
                "saber el tipo concreto. Esto favorece código flexible y extensible."
            ),
            nivel="avanzado", tema="oop", tipo="concepto",
        ),
    ]

    # Variaciones programáticas para dar volumen al corpus semilla.
    operaciones = [
        ("suma", "+", "sumar"),
        ("resta", "-", "restar"),
        ("multiplicación", "*", "multiplicar"),
    ]
    for nombre, op, verbo in operaciones:
        ejemplos.append(
            E(
                instruccion=f"Genera una función que realice la {nombre} de dos números",
                entrada="",
                salida=(
                    f"def {verbo}(a, b):\n    return a {op} b\n\n"
                    f"La función {verbo} recibe dos números y devuelve su {nombre} "
                    f"usando el operador {op}. Es breve, clara y reutilizable."
                ),
                nivel="basico", tema="funciones", tipo="generacion_codigo",
            )
        )

    return ejemplos
