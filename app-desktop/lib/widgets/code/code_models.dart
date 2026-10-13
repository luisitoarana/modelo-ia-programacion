import 'package:flutter/material.dart';

import '../../services/curriculum_catalog.dart';
import '../../theme.dart';
import 'code_controller.dart';

/// Un archivo abierto en el editor. Guarda el contenido, la ruta (si está
/// persistido), el idioma detectado y el `CodeController` que aplica el
/// syntax-highlight inline en el TextField.
///
/// `original` sirve para detectar cambios sin guardar (`contenido != original`).
class TabArchivo {
  String nombre;
  String? ruta;
  String contenido;
  String original;
  String lenguaje;
  LeccionCurricular? leccionCurricular;
  CodeController? _controller;

  TabArchivo({
    required this.nombre,
    required this.ruta,
    required this.contenido,
    required this.original,
    required this.lenguaje,
    this.leccionCurricular,
    AppPalette? palette,
  }) {
    if (palette != null) {
      _controller = CodeController(
        text: contenido,
        lenguaje: lenguaje,
        palette: palette,
      );
    }
  }

  /// Devuelve el controller. Se inicializa lazy en el primer build con la
  /// paleta real (se requiere `p` la primera vez).
  CodeController controller([AppPalette? p]) {
    if (_controller == null) {
      assert(p != null,
          'Se requiere paleta al primer acceso al controller');
      _controller = CodeController(
        text: contenido,
        lenguaje: lenguaje,
        palette: p!,
      );
    }
    return _controller!;
  }

  void dispose() => _controller?.dispose();
}

/// Resultado de una ejecución en el sandbox del backend.
class ResultadoEjecucion {
  final String stdout;
  final String stderr;
  final int exitCode;
  final double duracion;
  final bool timeout;
  final String lenguaje;
  ResultadoEjecucion({
    required this.stdout,
    required this.stderr,
    required this.exitCode,
    required this.duracion,
    required this.timeout,
    required this.lenguaje,
  });
}

/// Pestaña activa del panel inferior del editor.
enum PanelInferior { output, terminal, problemas, ia }

/// Intent para el atajo Ctrl+S / Cmd+S.
class GuardarIntent extends Intent {
  const GuardarIntent();
}

/// Intent para el atajo F5 / Ctrl+R / Cmd+R.
class EjecutarIntent extends Intent {
  const EjecutarIntent();
}

/// Entrada del árbol del explorador — archivo o carpeta.
class NodoArchivo {
  final String nombre;
  final String ruta;
  final bool esCarpeta;
  final String? lenguaje; // solo archivos
  bool expandido; // solo carpetas
  List<NodoArchivo>? hijos; // null = aún no se cargaron (lazy)

  NodoArchivo._({
    required this.nombre,
    required this.ruta,
    required this.esCarpeta,
    this.lenguaje,
    this.expandido = false,
    this.hijos,
  });

  factory NodoArchivo.archivo({
    required String nombre,
    required String ruta,
    required String lenguaje,
  }) =>
      NodoArchivo._(
        nombre: nombre,
        ruta: ruta,
        esCarpeta: false,
        lenguaje: lenguaje,
      );

  factory NodoArchivo.carpeta({
    required String nombre,
    required String ruta,
  }) =>
      NodoArchivo._(
        nombre: nombre,
        ruta: ruta,
        esCarpeta: true,
      );
}

/// Raíz de un árbol de archivos (una carpeta abierta como proyecto).
class NodoCarpeta {
  final String nombre;
  final String ruta;
  final List<NodoArchivo> hijos;
  NodoCarpeta({
    required this.nombre,
    required this.ruta,
    required this.hijos,
  });
}

/// Mensaje en el historial de interacción con la IA dentro del editor de código.
class MensajeEditorIa {
  final bool esUsuario;
  final String texto;
  final DateTime fecha;
  final String? codigoExtraido;

  MensajeEditorIa({
    required this.esUsuario,
    required this.texto,
    DateTime? fecha,
    this.codigoExtraido,
  }) : fecha = fecha ?? DateTime.now();
}
