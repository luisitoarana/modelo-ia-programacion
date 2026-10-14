import 'package:flutter/material.dart';

/// Modelo de una lección o reto curricular en el cliente.
class LeccionCurricular {
  final String id;
  final String moduloId;
  final String moduloTitulo;
  final String numero;
  final String titulo;
  final String conceptoClave;
  final List<String> palabrasReservadas;
  final String descripcionPedagogica;
  final String codigoInicial;
  final String guiaDocente;
  final List<String> pistas;
  final String preguntaAutoevaluacion;
  final IconData icono;

  List<String> get pistasAndamiaje => pistas;

  const LeccionCurricular({
    required this.id,
    required this.moduloId,
    required this.moduloTitulo,
    required this.numero,
    required this.titulo,
    required this.conceptoClave,
    required this.palabrasReservadas,
    required this.descripcionPedagogica,
    required this.codigoInicial,
    required this.guiaDocente,
    required this.pistas,
    required this.preguntaAutoevaluacion,
    required this.icono,
  });
}

/// Catálogo local de lecciones curriculares de Python (offline first).
class CurriculumCatalog {
  static const List<LeccionCurricular> lecciones = [
    // ── MÓDULO 1: PRINCIPIANTE ──
    LeccionCurricular(
      id: 'm1_l1_variables',
      moduloId: 'principiante',
      moduloTitulo: 'Módulo 1: Fundamentos y Palabras Reservadas',
      numero: '1.1',
      titulo: 'Variables y print()',
      conceptoClave: 'Variables en memoria, asignación, texto e impresión',
      palabrasReservadas: [],
      descripcionPedagogica:
          'Aprende a reservar un espacio en memoria con un nombre descriptivo y visualizarlo en la consola usando print().',
      codigoInicial:
          "# Reto 1.1: Tu primera variable en Python\n"
          "# ==============================================================\n"
          "# INSTRUCCIONES:\n"
          "# 1. Guarda tu nombre en la variable 'estudiante'.\n"
          "# 2. Guarda tu edad en la variable 'edad'.\n"
          "# 3. Muestra en pantalla el saludo usando print().\n"
          "# ==============================================================\n\n"
          "# 1. Crea la variable estudiante:\n"
          "estudiante = 'Tu Nombre'\n\n"
          "# 2. Crea la variable edad:\n"
          "edad = 0\n\n"
          "# 3. Muestra el saludo con print():\n"
          "# Escribe aquí tu print...\n",
      guiaDocente:
          'Pregunte al estudiante qué ocurre si cambia el nombre o intenta sumar un texto con un número.',
      pistas: [
        'Una variable es como una caja con nombre donde guardas un dato.',
        'Para texto usamos comillas y para números los escribimos directo.',
        'print() envía el resultado a la terminal inferior.',
      ],
      preguntaAutoevaluacion:
          'Observa estudiante y edad en el código. ¿Qué valor guarda cada variable y qué mostrará cada print()? Explica con tus palabras.',
      icono: Icons.edit_note_rounded,
    ),
    LeccionCurricular(
      id: 'm1_l2_tipos_datos',
      moduloId: 'principiante',
      moduloTitulo: 'Módulo 1: Fundamentos y Palabras Reservadas',
      numero: '1.2',
      titulo: 'Tipos Primitivos y type()',
      conceptoClave: 'int, float, str, bool y comprobación con type()',
      palabrasReservadas: ['True', 'False'],
      descripcionPedagogica:
          'Comprende las diferencias entre números enteros (int), decimales (float), texto (str) y valores booleanos (True/False).',
      codigoInicial:
          "# Reto 1.2: Tipos primitivos en Python\n"
          "# ==============================================================\n"
          "# INSTRUCCIONES:\n"
          "# 1. Declara 'precio' con un número decimal (float), ej: 19.99.\n"
          "# 2. Declara 'cantidad' con un número entero (int), ej: 3.\n"
          "# 3. Declara 'producto' con texto (str), ej: 'Cuaderno'.\n"
          "# 4. Declara 'disponible' con un booleano (bool): True o False.\n"
          "# 5. Imprime el tipo de cada variable usando la función type().\n"
          "# 6. Calcula el total (precio * cantidad) e imprímelo.\n"
          "# ==============================================================\n\n"
          "# Escribe aquí tus variables y prints:\n\n",
      guiaDocente:
          'Pídale al estudiante que intente escribir true en minúscula para observar NameError: ese nombre no está definido.',
      pistas: [
        'int no tiene decimales; float tiene punto decimal.',
        'True y False se escriben obligatoriamente con la primera letra en mayúscula.',
        'type(x) te devuelve el tipo actual de la variable.',
      ],
      preguntaAutoevaluacion:
          '¿Qué tipo de dato tiene precio y qué tipo tiene producto? ¿Qué crees que ocurre al ejecutar producto + cantidad?',
      icono: Icons.data_object_rounded,
    ),
    LeccionCurricular(
      id: 'm1_l3_palabras_reservadas',
      moduloId: 'principiante',
      moduloTitulo: 'Módulo 1: Fundamentos y Palabras Reservadas',
      numero: '1.3',
      titulo: 'Palabras Reservadas (keyword.kwlist)',
      conceptoClave:
          'Palabras protegidas del lenguaje que no pueden ser variables',
      palabrasReservadas: ['def', 'if', 'for', 'while', 'return', 'class'],
      descripcionPedagogica:
          'Descubre las 35 palabras reservadas oficiales de Python y por qué intentar usarlas como variables causa SyntaxError.',
      codigoInicial:
          "# Reto 1.3: Palabras reservadas en Python\n"
          "# ==============================================================\n"
          "# INSTRUCCIONES:\n"
          "# 1. Importa el módulo 'keyword'.\n"
          "# 2. Imprime la cantidad total de palabras reservadas (len).\n"
          "# 3. Imprime una lista con las primeras 12 palabras reservadas.\n"
          "# 4. Crea una variable con un nombre válido (ej: repeticiones = 10).\n"
          "# ==============================================================\n\n"
          "# Escribe tu código aquí:\n\n",
      guiaDocente:
          'Haga que el estudiante intente asignar valores a def o if para que entienda el rol del intérprete.',
      pistas: [
        'Las palabras reservadas son instrucciones del sistema.',
        'No puedes llamar a una variable con el mismo nombre que una instrucción de Python.',
        'keyword.kwlist contiene el listado completo de palabras protegidas.',
      ],
      preguntaAutoevaluacion:
          '¿Qué ocurre si usas for como nombre de una variable, por ejemplo for = 10? Explica por qué Python reserva esa palabra.',
      icono: Icons.lock_outline_rounded,
    ),
    LeccionCurricular(
      id: 'm1_l4_indentacion',
      moduloId: 'principiante',
      moduloTitulo: 'Módulo 1: Fundamentos y Palabras Reservadas',
      numero: '1.4',
      titulo: 'Indentación y Dos Puntos (:)',
      conceptoClave: 'Estructura por sangría de 4 espacios y operador :',
      palabrasReservadas: ['if', 'else'],
      descripcionPedagogica:
          'Aprende la regla estructural más importante de Python: los bloques se definen con sangría consistente y dos puntos (:); se recomiendan 4 espacios.',
      codigoInicial:
          "# Reto 1.4: La regla de oro de Python: Indentación\n"
          "# ==============================================================\n"
          "# INSTRUCCIONES:\n"
          "# 1. Crea una variable 'nota' con una calificación numérica.\n"
          "# 2. Escribe una estructura 'if' y 'else' con dos puntos (:).\n"
          "# 3. Recuerda indentar (4 espacios) las instrucciones dentro del bloque.\n"
          "# 4. Si la nota >= 7.0 imprime 'Aprobado', de lo contrario 'Reprobado'.\n"
          "# ==============================================================\n\n"
          "nota = 8.5\n\n"
          "# Completa la condición if/else aquí:\n\n",
      guiaDocente:
          'Pídale al estudiante que borre los espacios antes de print y observe el IndentationError.',
      pistas: [
        'Toda línea que termine en dos puntos (:) exige que la siguiente tenga sangría; se recomiendan 4 espacios.',
        'Para salir del bloque, vuelve a escribir alineado al margen izquierdo.',
        'Python no usa llaves {} como Java o C++; la sangría es la estructura.',
      ],
      preguntaAutoevaluacion:
          'Con nota = 8.5, ¿qué mensajes se mostrarán? Explica cómo los espacios al inicio de una línea indican qué instrucciones pertenecen al if.',
      icono: Icons.format_indent_increase_rounded,
    ),

    // ── MÓDULO 2: INTERMEDIO ──
    LeccionCurricular(
      id: 'm2_l1_condicionales',
      moduloId: 'intermedio',
      moduloTitulo: 'Módulo 2: Control de Flujo y Colecciones',
      numero: '2.1',
      titulo: 'Condicionales if / elif / else',
      conceptoClave: 'Bifurcaciones lógicas y evaluación en cascada',
      palabrasReservadas: ['if', 'elif', 'else'],
      descripcionPedagogica:
          'Domina la toma de decisiones con múltiples alternativas y aprende por qué el orden de las condiciones es vital.',
      codigoInicial:
          "# Reto 2.1: Clasificación de calificaciones (if / elif / else)\n"
          "# ==============================================================\n"
          "# INSTRUCCIONES:\n"
          "# 1. Dada la variable 'calificacion', clasifícala en una variable 'nivel':\n"
          "#    - Si calificacion >= 90: nivel = 'Excelente'\n"
          "#    - Si calificacion >= 80: nivel = 'Muy Bueno'\n"
          "#    - Si calificacion >= 70: nivel = 'Aprobado'\n"
          "#    - De lo contrario: nivel = 'Reprobado'\n"
          "# 2. Imprime el nivel resultante con print().\n"
          "# ==============================================================\n\n"
          "calificacion = 82\n\n"
          "# Escribe aquí la estructura if / elif / else:\n\n",
      guiaDocente:
          'Pregunte qué pasaría si invertimos el orden de las ramas comprobando primero >= 70.',
      pistas: [
        'Python evalúa de arriba a abajo y se detiene en la primera condición que sea True.',
        'elif te permite evaluar una nueva condición si la anterior fue False.',
        'else es el caso por descarte si ninguna rama anterior se cumplió.',
      ],
      preguntaAutoevaluacion:
          'Si cambias calificacion a 95, ¿qué valor tendrá nivel? Explica por qué se elige esa rama y no la siguiente.',
      icono: Icons.alt_route_rounded,
    ),
    LeccionCurricular(
      id: 'm2_l2_bucles_acumuladores',
      moduloId: 'intermedio',
      moduloTitulo: 'Módulo 2: Control de Flujo y Colecciones',
      numero: '2.2',
      titulo: 'Bucles for y Acumuladores',
      conceptoClave: 'Iteración con range() y patrón acumulador suma += x',
      palabrasReservadas: ['for', 'in'],
      descripcionPedagogica:
          'Comprende el patrón algorítmico del acumulador para sumar elementos a través de ciclos repetitivos.',
      codigoInicial:
          "# Reto 2.2: Patrón Acumulador con bucle for\n"
          "# ==============================================================\n"
          "# INSTRUCCIONES:\n"
          "# 1. Inicializa un acumulador: suma_total = 0.\n"
          "# 2. Usa un bucle 'for' con range(1, 6) para iterar del 1 al 5.\n"
          "# 3. En cada paso, suma el número al acumulador y muestra la traza.\n"
          "# 4. Al salir del bucle, imprime la suma final acumulada.\n"
          "# ==============================================================\n\n"
          "# Escribe tu solución aquí:\n\n",
      guiaDocente:
          'Trace con el alumno cómo cambia el valor de acumulador_suma en la memoria RAM paso a paso.',
      pistas: [
        'El acumulador debe inicializarse ANTES del bucle.',
        'range(1, 6) genera valores desde 1 hasta 5 inclusive.',
        'acumulador += x es la forma abreviada de acumulador = acumulador + x.',
      ],
      preguntaAutoevaluacion:
          '¿Qué números recorre range(1, 6) y cuál será la suma final? Describe cómo cambia acumulador_suma en el bucle.',
      icono: Icons.repeat_rounded,
    ),
    LeccionCurricular(
      id: 'm2_l3_listas_indexacion',
      moduloId: 'intermedio',
      moduloTitulo: 'Módulo 2: Control de Flujo y Colecciones',
      numero: '2.3',
      titulo: 'Listas Dinámicas e Índices',
      conceptoClave: 'Listas [], índice 0, len(), índices negativos -1',
      palabrasReservadas: ['for', 'in'],
      descripcionPedagogica:
          'Aprende a almacenar colecciones ordenadas de datos y recorrerlas eficientemente en Python.',
      codigoInicial:
          "# Reto 2.3: Listas e indexación en Python\n"
          "# ==============================================================\n"
          "# INSTRUCCIONES:\n"
          "# 1. Crea una lista 'lenguajes' con al menos 4 nombres de tecnologías.\n"
          "# 2. Imprime el primer elemento usando el índice [0].\n"
          "# 3. Imprime el último elemento usando el índice negativo [-1].\n"
          "# 4. Recorre la lista con un bucle 'for' e imprime cada elemento.\n"
          "# ==============================================================\n\n"
          "# Escribe tu solución aquí:\n\n",
      guiaDocente:
          'Provoque un IndexError pidiéndole al alumno acceder a lenguajes[10].',
      pistas: [
        'El primer índice siempre es 0.',
        'El índice -1 accede limpiamente al último elemento.',
        'len(lista) devuelve la cantidad de elementos contenidos.',
      ],
      preguntaAutoevaluacion:
          '¿Qué muestran lenguajes[0] y lenguajes[-1]? Explica qué ocurre si intentas acceder a lenguajes[4] en esta lista.',
      icono: Icons.list_alt_rounded,
    ),
    LeccionCurricular(
      id: 'm2_l4_defensiva_zerodivision',
      moduloId: 'intermedio',
      moduloTitulo: 'Módulo 2: Control de Flujo y Colecciones',
      numero: '2.4',
      titulo: 'Blindaje ante ZeroDivisionError',
      conceptoClave:
          'Programación defensiva ante listas vacías y división entre cero',
      palabrasReservadas: ['if', 'not', 'return', 'def'],
      descripcionPedagogica:
          'Aprende a proteger algoritmos contra entradas vacías que provocan ZeroDivisionError en cálculos de promedios.',
      codigoInicial:
          "# Reto 2.4: Blindaje defensivo de promedios\n"
          "# ==============================================================\n"
          "# INSTRUCCIONES:\n"
          "# 1. Completa la función 'calcular_promedio_seguro(notas)'.\n"
          "# 2. Si 'notas' está vacía (if not notas), retorna 0.0 con una advertencia.\n"
          "# 3. Si tiene notas, retorna la suma dividida para la longitud.\n"
          "# 4. Prueba con una lista con datos y con una lista vacía.\n"
          "# ==============================================================\n\n"
          "def calcular_promedio_seguro(notas):\n"
          "    # Escribe aquí la validación defensiva:\n"
          "    pass\n\n"
          "# Pruebas:\n"
          "print('Con notas:', calcular_promedio_seguro([8.0, 9.5, 7.0]))\n"
          "print('Lista vacía:', calcular_promedio_seguro([]))\n",
      guiaDocente:
          'Muestre qué sucede al eliminar la validación if not notas: el sistema colapsa de inmediato.',
      pistas: [
        'len([]) es igual a cero. Cualquier división entre cero detiene el programa.',
        'if not lista verifica de forma pythónica si una colección está vacía.',
        'El código blindado anticipa el fallo antes de operar matemáticamente.',
      ],
      preguntaAutoevaluacion:
          '¿Qué devuelve calcular_promedio_seguro([])? Explica qué error evita if not notas cuando la lista está vacía.',
      icono: Icons.shield_outlined,
    ),

    // ── MÓDULO 3: AVANZADO ──
    LeccionCurricular(
      id: 'm3_l1_funciones_puras',
      moduloId: 'avanzado',
      moduloTitulo: 'Módulo 3: Algoritmos, Big-O y POO',
      numero: '3.1',
      titulo: 'Funciones Puras y Type Hints (def)',
      conceptoClave:
          'def, return, anotaciones de tipo (type hints), funciones puras',
      palabrasReservadas: ['def', 'return'],
      descripcionPedagogica:
          'Diseña funciones modulares con anotaciones de tipo y retorno explícito para arquitectura de software profesional.',
      codigoInicial:
          "# Reto 3.1: Funciones modulares con retorno (def / return)\n"
          "# ==============================================================\n"
          "# INSTRUCCIONES:\n"
          "# 1. Completa 'calcular_estadisticas(numeros: list[float]) -> dict'.\n"
          "# 2. Debe calcular y retornar un diccionario con: 'min', 'max' y 'media'.\n"
          "# 3. Si la lista viene vacía, retorna ceros para todos los valores.\n"
          "# 4. Prueba tu función con la lista 'datos'.\n"
          "# ==============================================================\n\n"
          "def calcular_estadisticas(numeros: list[float]) -> dict[str, float]:\n"
          "    # Escribe tu lógica de cálculo aquí:\n"
          "    pass\n\n"
          "datos = [12.5, 45.0, 78.2, 33.1, 9.8]\n"
          "print('Resumen estadístico:', calcular_estadisticas(datos))\n",
      guiaDocente:
          'Explique el contraste entre return (entrega del dato a la memoria) y print() (solo salida por pantalla).',
      pistas: [
        'return permite que el resultado de la función sea reutilizado por otra función.',
        'Los type hints (list[float] -> dict) documentan formalmente los contratos de la función.',
        'Una función pura no altera variables globales fuera de su propio alcance.',
      ],
      preguntaAutoevaluacion:
          '¿Qué devuelve calcular_estadisticas(datos)? Explica cómo podrías usar ese resultado en otra parte del programa y qué cambiaría si la función solo lo imprimiera.',
      icono: Icons.functions_rounded,
    ),
    LeccionCurricular(
      id: 'm3_l2_busqueda_binaria_bigo',
      moduloId: 'avanzado',
      moduloTitulo: 'Módulo 3: Algoritmos, Big-O y POO',
      numero: '3.2',
      titulo: 'Búsqueda Binaria y Complejidad O(log n)',
      conceptoClave:
          'Notación Big-O, tiempo logarítmico O(log n), búsqueda binaria',
      palabrasReservadas: ['def', 'while', 'if', 'return'],
      descripcionPedagogica:
          'Análisis riguroso de complejidad algorítmica: comprende por qué dividir el espacio a la mitad reduce comparaciones de O(n) a O(log n).',
      codigoInicial:
          "# Reto 3.2: Búsqueda Binaria - Complejidad O(log n)\n"
          "# ==============================================================\n"
          "# INSTRUCCIONES:\n"
          "# 1. Completa la función 'busqueda_binaria(coleccion, objetivo)'.\n"
          "# 2. Usa punteros 'inicio = 0' y 'fin = len(coleccion) - 1'.\n"
          "# 3. En un bucle while, calcula 'medio = (inicio + fin) // 2'.\n"
          "# 4. Si coleccion[medio] == objetivo, retorna 'medio'.\n"
          "# 5. Ajusta 'inicio' o 'fin' según corresponda.\n"
          "# 6. Si no existe, retorna -1.\n"
          "# ==============================================================\n\n"
          "def busqueda_binaria(coleccion: list[int], objetivo: int) -> int:\n"
          "    # Escribe tu algoritmo aquí:\n"
          "    pass\n\n"
          "numeros = [2, 5, 8, 12, 16, 23, 38, 56, 72, 91]\n"
          "pos = busqueda_binaria(numeros, 23)\n"
          "print(f'Objetivo 23 ubicado en índice: {pos}')\n",
      guiaDocente:
          'Demuestre matemáticamente que para 1,000,000 de elementos la búsqueda binaria requiere máximo ~20 pasos.',
      pistas: [
        'La lista debe estar obligatoriamente ordenada.',
        'En cada iteración se descarta la mitad del arreglo.',
        'La complejidad espacial es O(1) ya que no consume memoria adicional.',
      ],
      preguntaAutoevaluacion:
          '¿Qué posición devuelve la búsqueda del número 23? Explica por qué la lista debe estar ordenada para descartar la mitad de los elementos.',
      icono: Icons.speed_rounded,
    ),
    LeccionCurricular(
      id: 'm3_l3_poo_clases',
      moduloId: 'avanzado',
      moduloTitulo: 'Módulo 3: Algoritmos, Big-O y POO',
      numero: '3.3',
      titulo: 'Programación Orientada a Objetos (POO)',
      conceptoClave: 'class, constructor __init__, métodos y referencia self',
      palabrasReservadas: ['class', 'def', 'return'],
      descripcionPedagogica:
          'Empaqueta datos y lógica dentro de clases reutilizables. Comprende el constructor __init__ y el rol de self.',
      codigoInicial:
          "# Reto 3.3: Clases y Objetos en Python\n"
          "# ==============================================================\n"
          "# INSTRUCCIONES:\n"
          "# 1. Define la clase 'Estudiante' con constructor __init__(self, nombre, carrera).\n"
          "# 2. Inicializa self.calificaciones = [] en el constructor.\n"
          "# 3. Implementa el método 'agregar_nota(self, nota: float)'.\n"
          "# 4. Implementa el método 'promedio(self) -> float'.\n"
          "# 5. Instancia un objeto, agrega 2 notas y muestra el promedio.\n"
          "# ==============================================================\n\n"
          "class Estudiante:\n"
          "    # Escribe el constructor y métodos de la clase:\n"
          "    pass\n\n"
          "# Prueba instanciando un estudiante aquí:\n\n",
      guiaDocente:
          'Explique la analogía del molde de galletas (la clase) y las galletas horneadas (las instancias).',
      pistas: [
        'class define la plantilla; la instancia es el objeto concreto en memoria.',
        '__init__ se ejecuta automáticamente al instanciar el objeto.',
        'self representa la instancia particular sobre la que se opera.',
      ],
      preguntaAutoevaluacion:
          '¿Qué promedio tendrá luis después de agregar las dos notas? Explica cómo self permite que cada estudiante conserve sus propios datos.',
      icono: Icons.psychology_rounded,
    ),
  ];

  static List<LeccionCurricular> leccionesPorModulo(String moduloId) {
    final m = moduloId.toLowerCase().trim();
    if (m == 'modulo_1' || m == 'principiante') {
      return lecciones.where((l) => l.moduloId == 'principiante').toList();
    }
    if (m == 'modulo_2' || m == 'intermedio') {
      return lecciones.where((l) => l.moduloId == 'intermedio').toList();
    }
    if (m == 'modulo_3' || m == 'avanzado') {
      return lecciones.where((l) => l.moduloId == 'avanzado').toList();
    }
    return lecciones;
  }

  static String nombreNivel(String nivel) {
    final m = nivel.toLowerCase().trim();
    if (m == 'modulo_1' || m == 'principiante') return 'Módulo 1: Principiante';
    if (m == 'modulo_2' || m == 'intermedio') return 'Módulo 2: Intermedio';
    if (m == 'modulo_3' || m == 'avanzado') return 'Módulo 3: Avanzado';
    return 'Módulo Curricular';
  }

  static LeccionCurricular? obtenerPorId(String id) {
    return lecciones.firstWhere(
      (l) => l.id == id,
      orElse: () => lecciones.first,
    );
  }
}
