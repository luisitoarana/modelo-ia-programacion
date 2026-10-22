import 'dart:convert';
import 'dart:io';

/// Proceso con salida en vivo y stdin abierto hasta que el usuario lo detenga.
class ProcesoInteractivo {
  final Process _proceso;
  final Directory? _temporal;
  ProcesoInteractivo._(this._proceso, [this._temporal]);

  Stream<String> get salida => _proceso.stdout.transform(utf8.decoder);
  Stream<String> get errores => _proceso.stderr.transform(utf8.decoder);
  Future<int> get finalizado => _proceso.exitCode;

  void enviar(String texto) => _proceso.stdin.writeln(texto);
  void cerrarEntrada() => _proceso.stdin.close();
  void detener() => _proceso.kill();

  Future<void> limpiar() async {
    // Solo se borra el directorio temporal creado por esta misma instancia.
    if (_temporal != null && await _temporal.exists()) {
      await _temporal.delete(recursive: true);
    }
  }

  static Future<ProcesoInteractivo> python(String codigo, {String? cwd}) async {
    final temporal = await Directory.systemTemp.createTemp(
      'pythonia_terminal_',
    );
    final archivo = File(
      '${temporal.path}${Platform.pathSeparator}programa.py',
    );
    try {
      await archivo.writeAsString(codigo, encoding: utf8);
      final candidatos = Platform.isWindows
          ? ['python', 'py']
          : ['python3', 'python'];
      for (final ejecutable in candidatos) {
        try {
          final proceso = await Process.start(
            ejecutable,
            ['-u', archivo.path],
            workingDirectory: cwd,
            environment: {
              'PYTHONIOENCODING': 'utf-8',
              'PYTHONUTF8': '1',
              if (cwd != null) 'PYTHONPATH': cwd,
            },
          );
          return ProcesoInteractivo._(proceso, temporal);
        } on ProcessException {
          if (ejecutable == candidatos.last) rethrow;
        }
      }
      throw StateError('No se encontró Python instalado.');
    } catch (_) {
      await temporal.delete(recursive: true);
      rethrow;
    }
  }

  static Future<ProcesoInteractivo> comando(
    String comando, {
    String? cwd,
  }) async {
    final proceso = await Process.start(
      Platform.isWindows ? 'powershell' : '/bin/bash',
      Platform.isWindows
          ? ['-NoProfile', '-Command', comando]
          : ['-c', comando],
      workingDirectory: cwd,
      environment: {'PYTHONIOENCODING': 'utf-8', 'PYTHONUNBUFFERED': '1'},
    );
    return ProcesoInteractivo._(proceso);
  }
}
