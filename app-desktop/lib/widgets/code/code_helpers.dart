import 'package:flutter/material.dart';

/// Icono para representar un lenguaje en tabs, árbol de archivos y toolbar.
IconData iconoLenguaje(String l) => switch (l) {
  'python' => Icons.terminal,
  'dart' => Icons.flutter_dash,
  'javascript' || 'typescript' => Icons.javascript,
  'json' || 'yaml' => Icons.data_object,
  'markdown' => Icons.article_outlined,
  'html' || 'css' => Icons.web,
  _ => Icons.description_outlined,
};

/// Mapea una extensión de archivo (sin el punto) al identificador de
/// lenguaje que usa el resto del editor.
String lenguajeDeExtension(String ext) => switch (ext.toLowerCase()) {
  'py' => 'python',
  'dart' => 'dart',
  'js' || 'mjs' || 'cjs' => 'javascript',
  'jsx' => 'javascript',
  'ts' || 'tsx' => 'typescript',
  'json' => 'json',
  'md' => 'markdown',
  'yaml' || 'yml' => 'yaml',
  'java' => 'java',
  'kt' => 'kotlin',
  'rs' => 'rust',
  'go' => 'go',
  'c' || 'h' => 'c',
  'cpp' || 'hpp' || 'cc' => 'cpp',
  'cs' => 'csharp',
  'rb' => 'ruby',
  'php' => 'php',
  'sh' => 'bash',
  'html' => 'html',
  'css' => 'css',
  _ => 'texto',
};

/// Devuelve el runtime del sandbox para ejecutar código de este lenguaje,
/// o null si no está soportado.
String? lenguajeEjecutable(String l) => switch (l) {
  'python' => 'python',
  'javascript' => 'javascript',
  'typescript' => 'javascript', // Node acepta transpilados
  'bash' || 'shell' => 'bash',
  _ => null,
};

class ArchivoPropuesto {
  final String rutaRelativa;
  final String contenido;
  const ArchivoPropuesto(this.rutaRelativa, this.contenido);
}

/// Formato explícito para propuestas de varios archivos del asistente.
List<ArchivoPropuesto> extraerArchivosPropuestos(String texto) {
  final patron = RegExp(
    r'(?:^|\n)ARCHIVO:[ \t]*([^\r\n]+)(?:\r?\n[ \t]*)+```[^\r\n]*\r?\n([\s\S]*?)```',
    caseSensitive: false,
  );
  return [
    for (final m in patron.allMatches(texto))
      ArchivoPropuesto(
        m.group(1)!.trim().replaceAll('`', ''),
        m.group(2)!.trimRight(),
      ),
  ];
}

bool rutaPropuestaSegura(String ruta) {
  final partes = ruta.replaceAll('\\', '/').split('/');
  return partes.isNotEmpty &&
      partes.every(
        (parte) =>
            parte.isNotEmpty &&
            parte != '.' &&
            parte != '..' &&
            !RegExp(r'[<>:"|?*]').hasMatch(parte),
      );
}

/// Un editor sin foco puede tener selección (-1, -1). No es código seleccionado.
String textoSeleccionadoSeguro(TextEditingController controller) {
  final rango = controller.selection;
  if (!rango.isValid || rango.start < 0 || rango.end > controller.text.length) {
    return '';
  }
  return rango.textInside(controller.text);
}

bool esPeticionDeCambio(String texto) => RegExp(
  r'\b(cambia\w*|modifica\w*|corr[íi][jg]\w*|correg\w*|actualiza\w*|reemplaza\w*|agrega\w*|añade\w*|arregla\w*|aplica\w*|pon\w*|quita\w*|remueve\w*|elimina\w*|ya no quiero|solo con|sin input|valores fijos|fij[oa]s?|haz que|deja de|sustituye\w*)\b',
  caseSensitive: false,
).hasMatch(texto);

bool esConfirmacionDeCambio(String texto) => RegExp(
  r'^\s*(sí|si|ok|vale|adelante|hazlo|de acuerdo)(?:\s*[,!.]?\s*(corrígelo|corrigelo|hazlo|aplícalo|aplicalo))?\s*[.!]?\s*$',
  caseSensitive: false,
).hasMatch(texto);
