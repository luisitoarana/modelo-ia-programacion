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
          "# Lección 1.1: Tu primera variable en Python\n"
          "# 1. Guarda tu nombre en la variable 'estudiante'\n"
          "estudiante = 'Luis'\n\n"
          "# 2. Guarda tu edad en la variable 'edad'\n"
          "edad = 20\n\n"
          "# 3. Muestra el saludo en pantalla con print()\n"
          "print('Hola, mi nombre es ' + estudiante)\n"
          "print(f'Tengo {edad} años y estoy aprendiendo Python.')\n",
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
          "# Lección 1.2: Tipos primitivos en Python\n"
          "precio = 19.99         # float (decimal)\n"
          "cantidad = 3           # int (entero)\n"
          "producto = 'Cuaderno'   # str (texto)\n"
          "disponible = True      # bool (True o False)\n\n"
          "# Inspección de tipos en tiempo de ejecución:\n"
          "print('Tipo de precio:', type(precio))\n"
          "print('Tipo de cantidad:', type(cantidad))\n"
          "print('Tipo de producto:', type(producto))\n"
          "print('Tipo de disponible:', type(disponible))\n\n"
          "total = precio * cantidad\n"
          "print(f'Total a pagar por {cantidad} {producto}s: \${total:.2f}')\n",
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
          "# Lección 1.3: Palabras reservadas en Python (El Libro de Python)\n"
          "import keyword\n\n"
          "# 1. Lista oficial de palabras reservadas:\n"
          "palabras = keyword.kwlist\n"
          "print(f'Python tiene {len(palabras)} palabras reservadas oficiales:')\n"
          "print(palabras[:12])  # Mostramos las primeras 12\n\n"
          "# 2. EXPERIMENTO:\n"
          "# Si descomentas la siguiente línea verás un SyntaxError:\n"
          "# for = 10  # ¡Error! 'for' está reservada para bucles\n\n"
          "# La forma correcta con un nombre válido:\n"
          "repeticiones = 10\n"
          "print(f'Variable válida creada con éxito: repeticiones = {repeticiones}')\n",
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
          "# Lección 1.4: La regla de oro de Python: Indentación\n"
          "nota = 8.5\n\n"
          "# Los dos puntos ':' abren el bloque; las siguientes líneas llevan sangría:\n"
          "if nota >= 7.0:\n"
          "    print('¡Felicidades!')\n"
          "    print('Has aprobado la materia.')\n"
          "else:\n"
          "    print('Debes prepararte para el examen de recuperación.')\n\n"
          "print('Fin del programa.')  # Fuera del bloque condicional\n",
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
          "# Lección 2.1: Clasificación de calificaciones\n"
          "calificacion = 82\n\n"
          "if calificacion >= 90:\n"
          "    nivel = 'Excelente'\n"
          "elif calificacion >= 80:\n"
          "    nivel = 'Muy Bueno'\n"
          "elif calificacion >= 70:\n"
          "    nivel = 'Aprobado'\n"
          "else:\n"
          "    nivel = 'Reprobado'\n\n"
          "print(f'Calificación {calificacion} -> Nivel: {nivel}')\n",
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
          "# Lección 2.2: Patrón Acumulador con bucle for\n"
          "acumulador_suma = 0  # Inicia en el elemento neutro de la suma\n\n"
          "print('Traza paso a paso:')\n"
          "for numero in range(1, 6):  # Genera 1, 2, 3, 4, 5\n"
          "    acumulador_suma = acumulador_suma + numero\n"
          "    print(f'  Paso: sumamos {numero} -> Total parcial: {acumulador_suma}')\n\n"
          "print(f'Suma total acumulada: {acumulador_suma}')\n",
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
          "# Lección 2.3: Listas e indexación en Python\n"
          "lenguajes = ['Python', 'JavaScript', 'C++', 'Java']\n\n"
          "print(f'Primer elemento (índice 0): {lenguajes[0]}')\n"
          "print(f'Último elemento (índice -1): {lenguajes[-1]}')\n"
          "print(f'Longitud total: {len(lenguajes)}')\n\n"
          "print('\\nRecorrido con bucle for:')\n"
          "for i, item in enumerate(lenguajes, start=1):\n"
          "    print(f'  {i}. {item}')\n",
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
          "# Lección 2.4: Blindaje defensivo de promedios\n"
          "def calcular_promedio_seguro(notas):\n"
          "    # VALIDACIÓN DEFENSIVA:\n"
          "    if not notas:  # Comprueba si la lista está vacía\n"
          "        print('⚠️ Advertencia: Lista vacía recibida. Promedio es 0.0')\n"
          "        return 0.0\n"
          "    \n"
          "    return sum(notas) / len(notas)\n\n"
          "# Caso normal:\n"
          "print('Promedio con notas:', calcular_promedio_seguro([8.0, 9.5, 7.0]))\n\n"
          "# Caso límite peligroso:\n"
          "print('Promedio lista vacía:', calcular_promedio_seguro([]))\n",
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
          "# Lección 3.1: Funciones modulares con anotaciones de tipo\n"
          "def calcular_estadisticas(numeros: list[float]) -> dict[str, float]:\n"
          "    \"\"\"Calcula min, max y promedio de una colección numérica.\"\"\"\n"
          "    if not numeros:\n"
          "        return {'min': 0.0, 'max': 0.0, 'media': 0.0}\n"
          "    \n"
          "    return {\n"
          "        'min': min(numeros),\n"
          "        'max': max(numeros),\n"
          "        'media': round(sum(numeros) / len(numeros), 2),\n"
          "    }\n\n"
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
          "# Lección 3.2: Búsqueda Binaria - Complejidad O(log n)\n"
          "def busqueda_binaria(coleccion: list[int], objetivo: int) -> int:\n"
          "    \"\"\"Retorna índice o -1 si no existe. Precondición: lista ordenada.\"\"\"\n"
          "    inicio = 0\n"
          "    fin = len(coleccion) - 1\n"
          "    pasos = 0\n"
          "    \n"
          "    while inicio <= fin:\n"
          "        pasos += 1\n"
          "        medio = (inicio + fin) // 2\n"
          "        if coleccion[medio] == objetivo:\n"
          "            print(f'-> Encontrado en solo {pasos} pasos (O(log n))')\n"
          "            return medio\n"
          "        elif coleccion[medio] < objetivo:\n"
          "            inicio = medio + 1\n"
          "        else:\n"
          "            fin = medio - 1\n"
          "            \n"
          "    return -1\n\n"
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
          "luis = Estudiante('Luis', 'Ingeniería en Sistemas')\n"
          "luis.agregar_nota(9.5)\n"
          "luis.agregar_nota(8.0)\n"
          "print(f'Estudiante: {luis.nombre} ({luis.carrera})')\n"
          "print(f'Promedio acumulado: {luis.promedio()}')\n",
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
