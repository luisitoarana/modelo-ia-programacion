import 'dart:core';

/// Modelo de una línea de código analizada y explicada en tiempo real.
class LineaExplicada {
  final int numeroLinea;
  final String codigoOriginal;
  final String tipo; // 'variable', 'condicional', 'bucle', 'funcion', 'print', 'clase', 'pregunta', 'comentario', 'otro'
  final String explicacionDidactica;
  final String? errorSintactico;
  final String? correccionSugerida;
  final bool tieneError;

  const LineaExplicada({
    required this.numeroLinea,
    required this.codigoOriginal,
    required this.tipo,
    required this.explicacionDidactica,
    this.errorSintactico,
    this.correccionSugerida,
    this.tieneError = false,
  });
}

/// Variable identificada en el código del estudiante.
class VariableDetectada {
  final String nombre;
  final String tipoDato; // 'str', 'int', 'float', 'bool', 'list', 'dict', 'desconocido'
  final String valorLiteral;
  final int linea;
  final String rolPedagogico;

  const VariableDetectada({
    required this.nombre,
    required this.tipoDato,
    required this.valorLiteral,
    required this.linea,
    required this.rolPedagogico,
  });
}

/// Estructura de control detectada (if, for, def, etc.).
class EstructuraControl {
  final String tipo;
  final int linea;
  final String condicionOParametros;
  final bool tieneDosPuntos;
  final String descripcion;

  const EstructuraControl({
    required this.tipo,
    required this.linea,
    required this.condicionOParametros,
    required this.tieneDosPuntos,
    required this.descripcion,
  });
}

/// Resultado integral del análisis automático en tiempo real.
class DiagnosticoAutomatico {
  final List<LineaExplicada> lineas;
  final List<VariableDetectada> variables;
  final List<EstructuraControl> estructuras;
  final List<String> erroresSintacticos;
  final List<String> advertencias;
  final String? salidaSimulada;
  final String? respuestaPreguntaConceptual;
  final bool esValido;
  final int totalLineas;

  const DiagnosticoAutomatico({
    required this.lineas,
    required this.variables,
    required this.estructuras,
    required this.erroresSintacticos,
    required this.advertencias,
    this.salidaSimulada,
    this.respuestaPreguntaConceptual,
    required this.esValido,
    required this.totalLineas,
  });
}

/// Motor de Explicación y Auditoría Automática en Vivo (0-latency offline).
class ExplicadorAutomatico {
  /// Descarta comentarios finales sin alterar '#' dentro de una cadena simple.
  static String _sinComentario(String linea) {
    String? comilla;
    var escape = false;
    for (var i = 0; i < linea.length; i++) {
      final c = linea[i];
      if (escape) {
        escape = false;
      } else if (c == r'\' && comilla != null) {
        escape = true;
      } else if (comilla != null) {
        if (c == comilla) comilla = null;
      } else if (c == '"' || c == "'") {
        comilla = c;
      } else if (c == '#') {
        return linea.substring(0, i);
      }
    }
    return linea;
  }

  static final RegExp _regexAsignacion =
      RegExp(r'^([a-zA-Z_][a-zA-Z0-9_]*)\s*=\s*(.+)$');

  static final RegExp _regexIf = RegExp(r'^if\s+(.+)$');
  static final RegExp _regexElif = RegExp(r'^elif\s+(.+)$');
  static final RegExp _regexFor = RegExp(r'^for\s+([a-zA-Z_][a-zA-Z0-9_]*)\s+in\s+(.+)$');
  static final RegExp _regexWhile = RegExp(r'^while\s+(.+)$');
  static final RegExp _regexDef = RegExp(r'^def\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*\((.*)\)\s*(->\s*.+)?\s*(.*)$');
  static final RegExp _regexClass = RegExp(r'^class\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*(\(.*\))?\s*(.*)$');
  static final RegExp _regexPrint = RegExp(r'^print\s*\((.*)\)\s*$');

  /// Analiza código Python en vivo, detecta variables, errores de sintaxis
  /// (como dos puntos o indentación) y explica cada línea de forma didáctica.
  static DiagnosticoAutomatico analizar(String codigo) {
    if (codigo.trim().isEmpty) {
      return const DiagnosticoAutomatico(
        lineas: [],
        variables: [],
        estructuras: [],
        erroresSintacticos: [],
        advertencias: [],
        esValido: true,
        totalLineas: 0,
      );
    }

    final lineasRaw = codigo.split('\n');
    final lineasExplicadas = <LineaExplicada>[];
    final variables = <VariableDetectada>[];
    final estructuras = <EstructuraControl>[];
    final errores = <String>[];
    final advertencias = <String>[];
    final salidasPrint = <String>[];
    String? preguntaConceptual;

    // Mapa de valores conocidos para simulación de print
    final valoresMemoria = <String, dynamic>{};

    bool esperaIndentacion = false;

    for (int i = 0; i < lineasRaw.length; i++) {
      final numLinea = i + 1;
      final lineaOriginal = lineasRaw[i];
      final lineaOriginalTrim = lineaOriginal.trim();
      final lineaTrim = _sinComentario(lineaOriginal).trim();
      final espaciosInicio = lineaOriginal.length - lineaOriginal.trimLeft().length;

      // Líneas vacías
      if (lineaTrim.isEmpty && !lineaOriginalTrim.startsWith('#')) {
        lineasExplicadas.add(LineaExplicada(
          numeroLinea: numLinea,
          codigoOriginal: lineaOriginal,
          tipo: 'espacio',
          explicacionDidactica: 'Línea en blanco (mejora la legibilidad del código).',
        ));
        continue;
      }

      // Verificación de indentación si la línea anterior abrió un bloque ':'
      String? errorInd;
      String? correccionInd;
      if (esperaIndentacion && espaciosInicio < 4 && !lineaTrim.startsWith('#')) {
        errorInd = 'Falta indentación (sangría de 4 espacios)';
        correccionInd = '    $lineaTrim';
        errores.add('Línea $numLinea: Debe tener al menos 4 espacios de sangría al pertenecer al bloque anterior.');
      }
      esperaIndentacion = false;

      // Comentarios y Preguntas Conceptuales
      if (lineaOriginalTrim.startsWith('#')) {
        final comentario = lineaOriginalTrim.substring(1).trim();
        final esPregunta = comentario.contains('?') ||
            comentario.toLowerCase().contains('que es') ||
            comentario.toLowerCase().contains('qué es') ||
            comentario.toLowerCase().contains('como funciona') ||
            comentario.toLowerCase().contains('cómo funciona') ||
            comentario.toLowerCase().contains('para que') ||
            comentario.toLowerCase().contains('para qué');

        String expComentario = 'Comentario explicativo: Python lo ignora durante la ejecución.';
        if (esPregunta) {
          expComentario = '❓ Pregunta conceptual del estudiante: "$comentario"';
          preguntaConceptual = _responderPreguntaConceptual(comentario);
        }

        lineasExplicadas.add(LineaExplicada(
          numeroLinea: numLinea,
          codigoOriginal: lineaOriginal,
          tipo: esPregunta ? 'pregunta' : 'comentario',
          explicacionDidactica: expComentario,
        ));
        continue;
      }

      // 1. Verificación de Condicional IF / ELIF / ELSE
      if (lineaTrim.startsWith('if ') || lineaTrim == 'if') {
        final match = _regexIf.firstMatch(lineaTrim);
        final condicionRaw = match != null ? match.group(1)!.trim() : lineaTrim.substring(2).trim();

        // Error común: un solo '=' en el condicional (ej. if nombre = "Luis")
        final tieneAsignacionError = RegExp(r'[^=!<>]=[^=]').hasMatch(condicionRaw);
        final tieneDosPuntos = condicionRaw.endsWith(':');

        String? errSintaxis = errorInd;
        String? corrSugerida = correccionInd;

        String condLimpia = condicionRaw;
        if (tieneDosPuntos) {
          condLimpia = condLimpia.substring(0, condLimpia.length - 1).trim();
        }

        if (tieneAsignacionError) {
          errSintaxis = 'Has escrito "=" (asignación) en vez de "==" (comparación de igualdad)';
          final condCorregida = condLimpia.replaceAllMapped(
              RegExp(r'(\b[a-zA-Z0-9_]+\s*)=\s*([^\s=]+)'), (m) => '${m.group(1)} == ${m.group(2)}');
          corrSugerida = '${" " * espaciosInicio}if $condCorregida:';
          errores.add('Línea $numLinea: En Python la comparación de igualdad se escribe "==", no "=".');
        } else if (!tieneDosPuntos) {
          errSintaxis = 'Falta dos puntos ":" al final del condicional';
          corrSugerida = '${" " * espaciosInicio}if $condLimpia:';
          errores.add('Línea $numLinea: Los condicionales en Python deben terminar en dos puntos ":".');
        }

        if (tieneDosPuntos || errSintaxis != null) {
          esperaIndentacion = true;
        }

        estructuras.add(EstructuraControl(
          tipo: 'if',
          linea: numLinea,
          condicionOParametros: condLimpia,
          tieneDosPuntos: tieneDosPuntos,
          descripcion: 'Evalúa si ($condLimpia) es verdadero.',
        ));

        lineasExplicadas.add(LineaExplicada(
          numeroLinea: numLinea,
          codigoOriginal: lineaOriginal,
          tipo: 'condicional',
          explicacionDidactica:
              'Condicional if: comprueba si la condición "$condLimpia" se cumple (True) para ejecutar el bloque siguiente.',
          errorSintactico: errSintaxis,
          correccionSugerida: corrSugerida,
          tieneError: errSintaxis != null,
        ));
        continue;
      }

      if (lineaTrim.startsWith('elif ') || lineaTrim == 'elif') {
        final match = _regexElif.firstMatch(lineaTrim);
        final condicionRaw = match != null ? match.group(1)!.trim() : lineaTrim.substring(4).trim();
        final tieneDosPuntos = condicionRaw.endsWith(':');
        String? errSintaxis = errorInd;
        String? corrSugerida = correccionInd;

        String condLimpia = condicionRaw;
        if (tieneDosPuntos) {
          condLimpia = condLimpia.substring(0, condLimpia.length - 1).trim();
        }

        if (!tieneDosPuntos) {
          errSintaxis = 'Falta dos puntos ":" al final de elif';
          corrSugerida = '${" " * espaciosInicio}elif $condLimpia:';
          errores.add('Línea $numLinea: La rama "elif" debe terminar con dos puntos ":".');
        }
        esperaIndentacion = true;

        estructuras.add(EstructuraControl(
          tipo: 'elif',
          linea: numLinea,
          condicionOParametros: condLimpia,
          tieneDosPuntos: tieneDosPuntos,
          descripcion: 'Condición alternativa ($condLimpia).',
        ));

        lineasExplicadas.add(LineaExplicada(
          numeroLinea: numLinea,
          codigoOriginal: lineaOriginal,
          tipo: 'condicional',
          explicacionDidactica:
              'Rama alternativa elif: si la condición previa fue falsa, evalúa si "$condLimpia" es verdadera.',
          errorSintactico: errSintaxis,
          correccionSugerida: corrSugerida,
          tieneError: errSintaxis != null,
        ));
        continue;
      }

      if (lineaTrim == 'else' || lineaTrim.startsWith('else:')) {
        final tieneDosPuntos = lineaTrim.endsWith(':');
        String? errSintaxis = errorInd;
        String? corrSugerida = correccionInd;

        if (!tieneDosPuntos) {
          errSintaxis = 'Falta dos puntos ":" después de else';
          corrSugerida = '${" " * espaciosInicio}else:';
          errores.add('Línea $numLinea: La cláusula "else" requiere dos puntos ":".');
        }
        esperaIndentacion = true;

        estructuras.add(EstructuraControl(
          tipo: 'else',
          linea: numLinea,
          condicionOParametros: 'por defecto',
          tieneDosPuntos: tieneDosPuntos,
          descripcion: 'Bloque por defecto si ninguna condición se cumplió.',
        ));

        lineasExplicadas.add(LineaExplicada(
          numeroLinea: numLinea,
          codigoOriginal: lineaOriginal,
          tipo: 'condicional',
          explicacionDidactica:
              'Cláusula else: se ejecutará únicamente si ninguna de las condiciones anteriores se cumplió.',
          errorSintactico: errSintaxis,
          correccionSugerida: corrSugerida,
          tieneError: errSintaxis != null,
        ));
        continue;
      }

      // 2. Funciones (def)
      if (lineaTrim.startsWith('def ')) {
        final match = _regexDef.firstMatch(lineaTrim);
        final tieneDosPuntos = lineaTrim.endsWith(':');
        String? errSintaxis = errorInd;
        String? corrSugerida = correccionInd;

        final nombreFn = match?.group(1) ?? 'funcion';
        final params = match?.group(2) ?? '';

        if (!tieneDosPuntos) {
          errSintaxis = 'Falta dos puntos ":" al final de la función';
          corrSugerida = '${" " * espaciosInicio}def $nombreFn($params):';
          errores.add('Línea $numLinea: Toda función "def" debe terminar con dos puntos ":".');
        }
        esperaIndentacion = true;

        estructuras.add(EstructuraControl(
          tipo: 'def',
          linea: numLinea,
          condicionOParametros: params,
          tieneDosPuntos: tieneDosPuntos,
          descripcion: 'Función $nombreFn($params).',
        ));

        lineasExplicadas.add(LineaExplicada(
          numeroLinea: numLinea,
          codigoOriginal: lineaOriginal,
          tipo: 'funcion',
          explicacionDidactica:
              'Declaración de función def: define la función reutilizable "$nombreFn"${params.isNotEmpty ? " con los parámetros ($params)" : " sin parámetros"}.',
          errorSintactico: errSintaxis,
          correccionSugerida: corrSugerida,
          tieneError: errSintaxis != null,
        ));
        continue;
      }

      // 3. Bucles (for / while)
      if (lineaTrim.startsWith('for ')) {
        final match = _regexFor.firstMatch(lineaTrim);
        final tieneDosPuntos = lineaTrim.endsWith(':');
        String? errSintaxis = errorInd;
        String? corrSugerida = correccionInd;

        final iterador = match?.group(1) ?? 'elemento';
        var coleccion = match?.group(2) ?? '';
        if (coleccion.endsWith(':')) {
          coleccion = coleccion.substring(0, coleccion.length - 1).trim();
        }

        if (!tieneDosPuntos) {
          errSintaxis = 'Falta dos puntos ":" al final del bucle for';
          corrSugerida = '${" " * espaciosInicio}for $iterador in $coleccion:';
          errores.add('Línea $numLinea: El bucle for debe terminar con dos puntos ":".');
        }
        esperaIndentacion = true;

        estructuras.add(EstructuraControl(
          tipo: 'for',
          linea: numLinea,
          condicionOParametros: '$iterador in $coleccion',
          tieneDosPuntos: tieneDosPuntos,
          descripcion: 'Bucle for que itera sobre $coleccion.',
        ));

        lineasExplicadas.add(LineaExplicada(
          numeroLinea: numLinea,
          codigoOriginal: lineaOriginal,
          tipo: 'bucle',
          explicacionDidactica:
              'Bucle for: recorre cada elemento de "$coleccion" asignándolo temporalmente a la variable "$iterador".',
          errorSintactico: errSintaxis,
          correccionSugerida: corrSugerida,
          tieneError: errSintaxis != null,
        ));
        continue;
      }

      if (lineaTrim.startsWith('while ') || lineaTrim == 'while') {
        final match = _regexWhile.firstMatch(lineaTrim);
        final tieneDosPuntos = lineaTrim.endsWith(':');
        String? errSintaxis = errorInd;
        String? corrSugerida = correccionInd;
        var cond = match?.group(1) ?? lineaTrim.substring(5).trim();
        if (cond.endsWith(':')) {
          cond = cond.substring(0, cond.length - 1).trim();
        }

        if (!tieneDosPuntos) {
          errSintaxis = 'Falta dos puntos ":" al final del bucle while';
          corrSugerida = '${" " * espaciosInicio}while $cond:';
          errores.add('Línea $numLinea: El bucle while debe terminar con dos puntos ":".');
        }
        esperaIndentacion = true;

        estructuras.add(EstructuraControl(
          tipo: 'while',
          linea: numLinea,
          condicionOParametros: cond,
          tieneDosPuntos: tieneDosPuntos,
          descripcion: 'Bucle while con condición ($cond).',
        ));

        lineasExplicadas.add(LineaExplicada(
          numeroLinea: numLinea,
          codigoOriginal: lineaOriginal,
          tipo: 'bucle',
          explicacionDidactica:
              'Bucle while: repite el bloque indentado mientras la condición "$cond" sea verdadera (True).',
          errorSintactico: errSintaxis,
          correccionSugerida: corrSugerida,
          tieneError: errSintaxis != null,
        ));
        continue;
      }

      // 4. Clases (class)
      if (lineaTrim.startsWith('class ')) {
        final match = _regexClass.firstMatch(lineaTrim);
        final tieneDosPuntos = lineaTrim.endsWith(':');
        String? errSintaxis = errorInd;
        String? corrSugerida = correccionInd;
        final nombreClase = match?.group(1) ?? 'Clase';

        if (!tieneDosPuntos) {
          errSintaxis = 'Falta dos puntos ":" al final de la clase';
          corrSugerida = '${" " * espaciosInicio}class $nombreClase:';
          errores.add('Línea $numLinea: La definición de clase debe terminar con dos puntos ":".');
        }
        esperaIndentacion = true;

        estructuras.add(EstructuraControl(
          tipo: 'class',
          linea: numLinea,
          condicionOParametros: nombreClase,
          tieneDosPuntos: tieneDosPuntos,
          descripcion: 'Clase/molde de objetos $nombreClase.',
        ));

        lineasExplicadas.add(LineaExplicada(
          numeroLinea: numLinea,
          codigoOriginal: lineaOriginal,
          tipo: 'clase',
          explicacionDidactica:
              'Definición de clase POO: crea la plantilla o molde "$nombreClase" para instanciar objetos.',
          errorSintactico: errSintaxis,
          correccionSugerida: corrSugerida,
          tieneError: errSintaxis != null,
        ));
        continue;
      }

      // 5. Invocación de print()
      if (lineaTrim.startsWith('print(') || lineaTrim.startsWith('print (')) {
        final match = _regexPrint.firstMatch(lineaTrim);
        String? errSintaxis = errorInd;
        String? corrSugerida = correccionInd;

        if (match == null && !lineaTrim.endsWith(')')) {
          errSintaxis = 'Falta cerrar paréntesis ")" en la función print';
          corrSugerida = '$lineaOriginal)';
          errores.add('Línea $numLinea: La función print requiere cerrar paréntesis al final.');
        }

        final contenidoPrint = match != null ? match.group(1)!.trim() : lineaTrim;
        final salidaSimulada = _simularPrint(contenidoPrint, valoresMemoria);
        if (salidaSimulada != null) {
          salidasPrint.add(salidaSimulada);
        }

        lineasExplicadas.add(LineaExplicada(
          numeroLinea: numLinea,
          codigoOriginal: lineaOriginal,
          tipo: 'print',
          explicacionDidactica:
              'Impresión en consola: muestra el contenido "$contenidoPrint" en la salida estándar.',
          errorSintactico: errSintaxis,
          correccionSugerida: corrSugerida,
          tieneError: errSintaxis != null,
        ));
        continue;
      }

      // 6. Asignación de Variable (ej: nombre = "Luis", edad = 20)
      final matchVar = _regexAsignacion.firstMatch(lineaTrim);
      if (matchVar != null && !lineaTrim.startsWith('return ')) {
        final nombreVar = matchVar.group(1)!.trim();
        final valorRaw = matchVar.group(2)!.trim();

        final tipoDato = _inferirTipoDato(valorRaw);
        final rol = _determinarRolVariable(nombreVar, tipoDato);

        // Almacenar en la memoria simulada
        valoresMemoria[nombreVar] = _extraerValorLiteral(valorRaw);

        variables.add(VariableDetectada(
          nombre: nombreVar,
          tipoDato: tipoDato,
          valorLiteral: valorRaw,
          linea: numLinea,
          rolPedagogico: rol,
        ));

        // Chequear errores de comillas incompletas
        String? errSintaxis = errorInd;
        String? corrSugerida = correccionInd;
        if ((valorRaw.startsWith('"') && !valorRaw.endsWith('"') && valorRaw.length > 1) ||
            (valorRaw.startsWith("'") && !valorRaw.endsWith("'") && valorRaw.length > 1)) {
          errSintaxis = 'Cadena de texto sin comilla de cierre';
          final comilla = valorRaw[0];
          corrSugerida = '${" " * espaciosInicio}$nombreVar = $valorRaw$comilla';
          errores.add('Línea $numLinea: La cadena de texto de la variable "$nombreVar" no se ha cerrado con comillas.');
        }

        lineasExplicadas.add(LineaExplicada(
          numeroLinea: numLinea,
          codigoOriginal: lineaOriginal,
          tipo: 'variable',
          explicacionDidactica:
              'Variable "$nombreVar": reserva memoria de tipo $tipoDato y le asigna el valor "$valorRaw".',
          errorSintactico: errSintaxis,
          correccionSugerida: corrSugerida,
          tieneError: errSintaxis != null,
        ));
        continue;
      }

      // Otras sentencias
      lineasExplicadas.add(LineaExplicada(
        numeroLinea: numLinea,
        codigoOriginal: lineaOriginal,
        tipo: 'otro',
        explicacionDidactica: 'Instrucción ejecutable en Python.',
        errorSintactico: errorInd,
        correccionSugerida: correccionInd,
        tieneError: errorInd != null,
      ));
    }

    String? salidaFinal;
    if (salidasPrint.isNotEmpty) {
      salidaFinal = salidasPrint.join('\n');
    }

    return DiagnosticoAutomatico(
      lineas: lineasExplicadas,
      variables: variables,
      estructuras: estructuras,
      erroresSintacticos: errores,
      advertencias: advertencias,
      salidaSimulada: salidaFinal,
      respuestaPreguntaConceptual: preguntaConceptual,
      esValido: errores.isEmpty,
      totalLineas: lineasRaw.length,
    );
  }

  static String _inferirTipoDato(String expr) {
    final e = expr.trim();
    if ((e.startsWith('"') && e.endsWith('"')) || (e.startsWith("'") && e.endsWith("'"))) {
      return 'str (cadena de texto)';
    }
    if (e == 'True' || e == 'False') {
      return 'bool (booleano verdadero/falso)';
    }
    if (RegExp(r'^-?[0-9]+$').hasMatch(e)) {
      return 'int (número entero)';
    }
    if (RegExp(r'^-?[0-9]+\.[0-9]+$').hasMatch(e)) {
      return 'float (número decimal)';
    }
    if (e.startsWith('[') && e.endsWith(']')) {
      return 'list (lista o colección ordenada)';
    }
    if (e.startsWith('{') && e.endsWith('}')) {
      return 'dict (diccionario clave-valor)';
    }
    if (e.startsWith('(') && e.endsWith(')')) {
      return 'tuple (tupla inmutable)';
    }
    return 'expresión calculada dinámicamente';
  }

  static String _determinarRolVariable(String nombre, String tipoDato) {
    final n = nombre.toLowerCase();
    if (n.contains('contador') || n == 'i' || n == 'c' || n == 'idx') {
      return 'Contador / Índice de iteración';
    }
    if (n.contains('total') || n.contains('suma') || n.contains('acumulador')) {
      return 'Acumulador aritmético en memoria';
    }
    if (n.contains('nombre') || n.contains('estudiante') || n.contains('user')) {
      return 'Identificador de sujeto / persona';
    }
    if (n.contains('edad') || n.contains('nota') || n.contains('precio') || n.contains('valor')) {
      return 'Magnitud cuantitativa de cálculo';
    }
    if (n.contains('lista') || n.contains('items') || n.endsWith('s')) {
      return 'Colección de datos agrupados';
    }
    return 'Almacenamiento de estado del programa';
  }

  static dynamic _extraerValorLiteral(String expr) {
    final e = expr.trim();
    if ((e.startsWith('"') && e.endsWith('"')) || (e.startsWith("'") && e.endsWith("'"))) {
      return e.substring(1, e.length - 1);
    }
    if (e == 'True') return true;
    if (e == 'False') return false;
    if (int.tryParse(e) != null) return int.parse(e);
    if (double.tryParse(e) != null) return double.parse(e);
    return e;
  }

  static String? _simularPrint(String contenido, Map<String, dynamic> memoria) {
    if (contenido.isEmpty) return '';

    // print(f"...")
    if (contenido.startsWith('f"') && contenido.endsWith('"') ||
        contenido.startsWith("f'") && contenido.endsWith("'")) {
      var texto = contenido.substring(2, contenido.length - 1);
      for (final entry in memoria.entries) {
        texto = texto.replaceAll('{${entry.key}}', '${entry.value}');
      }
      return texto;
    }

    // print("literal")
    if ((contenido.startsWith('"') && contenido.endsWith('"')) ||
        (contenido.startsWith("'") && contenido.endsWith("'"))) {
      return contenido.substring(1, contenido.length - 1);
    }

    // print(variable)
    if (memoria.containsKey(contenido)) {
      return '${memoria[contenido]}';
    }

    // Concatenación simple: "Hola " + nombre o f-string
    if (contenido.contains('+')) {
      final partes = contenido.split('+');
      final buffer = StringBuffer();
      for (final p in partes) {
        final pTrim = p.trim();
        if ((pTrim.startsWith('"') && pTrim.endsWith('"')) ||
            (pTrim.startsWith("'") && pTrim.endsWith("'"))) {
          buffer.write(pTrim.substring(1, pTrim.length - 1));
        } else if (memoria.containsKey(pTrim)) {
          buffer.write(memoria[pTrim]);
        } else {
          buffer.write(pTrim);
        }
      }
      return buffer.toString();
    }

    return null;
  }

  static String _responderPreguntaConceptual(String pregunta) {
    final p = pregunta.toLowerCase();
    if (p.contains('variable')) {
      return '📌 **¿Qué es una variable en Python?**\n\n'
          'Una variable es un nombre que le asignas a una "caja" o espacio en la memoria de la computadora '
          'para guardar un dato (como un texto `"Luis"` o un número `20`).\n\n'
          '• **Sintaxis**: `nombre_variable = valor`\n'
          '• **Ejemplo**: `nombre = "Luis"` guarda `"Luis"` en la variable `nombre`.\n'
          '• **Regla de oro**: El operador `=` significa *asignar* (guardar), no comparar.';
    }
    if (p.contains('print')) {
      return '📌 **¿Para qué sirve print()?**\n\n'
          '`print()` es una función nativa de Python que muestra información en la pantalla o consola '
          'para que el usuario o el programador puedan verla.\n\n'
          '• **Ejemplo**: `print("Hola mundo")`\n'
          '• Puedes imprimir variables: `print(nombre)` o texto con formato: `print(f"Hola {nombre}")`.';
    }
    if (p.contains('if') || p.contains('condicional')) {
      return '📌 **¿Cómo funciona un condicional (if)?**\n\n'
          'El `if` permite que tu programa tome decisiones. Evalúa una condición y, si es verdadera (`True`), '
          'ejecuta el bloque de código que está debajo con 4 espacios de sangría (indentación).\n\n'
          '• **Sintaxis**:\n```python\nif edad >= 18:\n    print("Mayor de edad")\n```\n'
          '• Recuerda siempre colocar dos puntos `:` al final del `if`.';
    }
    if (p.contains('bucle') || p.contains('for') || p.contains('while')) {
      return '📌 **¿Qué es un bucle (for / while)?**\n\n'
          'Un bucle permite repetir una o más instrucciones múltiples veces sin tener que reescribir el código.\n\n'
          '• **for**: Se usa cuando sabes cuántas veces o sobre qué colección quieres repetir (ej. una lista).\n'
          '• **while**: Se repite mientras una condición lógica sea verdadera (`True`).';
    }
    if (p.contains('dos puntos') || p.contains('indentacion') || p.contains('sangria')) {
      return '📌 **¿Por qué son obligatorios los dos puntos (:) y la indentación?**\n\n'
          'En Python no se usan llaves `{}` para abrir bloques de código como en Java o C. '
          'Los dos puntos `:` le avisan al intérprete que a continuación comienza un bloque, y '
          'la sangría (4 espacios) le indica qué líneas pertenecen a ese bloque.';
    }
    return '📌 **Concepto de Programación Python**:\n\n'
        'Has realizado una consulta en los comentarios. En Python, la estructura se basa en legibilidad, '
        'variables dinámicamente tipadas, y bloques delimitados con dos puntos `:` y 4 espacios de indentación.';
  }
}
