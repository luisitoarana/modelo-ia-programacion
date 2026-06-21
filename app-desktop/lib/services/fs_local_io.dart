// Implementación NATIVA (escritorio/móvil) con dart:io: accede al disco real.

import 'dart:convert';
import 'dart:io';

/// Entrada del sistema de archivos (carpeta o archivo).
class EntradaLocal {
  final String nombre;
  final String ruta;
  final bool esCarpeta;
  final int tamano;

  const EntradaLocal({
    required this.nombre,
    required this.ruta,
    required this.esCarpeta,
    this.tamano = 0,
  });
}

const bool soportaDiscoLocal = true;

const int _maxBytes = 200000;

const Set<String> _excluir = {
  '.git', 'node_modules', '.next', 'build', '__pycache__', '.venv', 'venv',
  '.dart_tool', '.idea', '.gradle',
};

Future<List<EntradaLocal>> listarLocal(String ruta) async {
  final dir = Directory(ruta);
  if (!await dir.exists()) return const [];
  final entradas = <EntradaLocal>[];
  try {
    await for (final e in dir.list(followLinks: false)) {
      final nombre = e.path.split(Platform.pathSeparator).last;
      if (_excluir.contains(nombre)) continue;
      final esDir = e is Directory;
      int tam = 0;
      if (e is File) {
        try {
          tam = await e.length();
        } catch (_) {}
      }
      entradas.add(EntradaLocal(
        nombre: nombre,
        ruta: e.path,
        esCarpeta: esDir,
        tamano: tam,
      ));
    }
  } catch (_) {
    // permisos u otros errores: devolvemos lo que se haya podido leer
  }
  entradas.sort((a, b) {
    if (a.esCarpeta != b.esCarpeta) return a.esCarpeta ? -1 : 1;
    return a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase());
  });
  return entradas;
}

Future<String> leerLocal(String ruta) async {
  final f = File(ruta);
  if (!await f.exists()) return 'Archivo no encontrado.';
  try {
    final len = await f.length();
    final raf = await f.open();
    final data = await raf.read(len > _maxBytes ? _maxBytes : len);
    await raf.close();
    final texto = utf8.decode(data, allowMalformed: true);
    return len > _maxBytes ? '$texto\n\n… (archivo truncado)' : texto;
  } catch (e) {
    return 'No se pudo leer el archivo: $e';
  }
}

/// Escribe (crea o sobrescribe) un archivo en el disco.
Future<bool> escribirLocal(String ruta, String contenido) async {
  try {
    await File(ruta).writeAsString(contenido);
    return true;
  } catch (_) {
    return false;
  }
}

/// Resultado de ejecutar un comando en la terminal.
class ResultadoComando {
  final String salida;
  final int codigo;
  const ResultadoComando(this.salida, this.codigo);
}

/// Ejecuta un comando en la PC (terminal real).
Future<ResultadoComando> ejecutarComandoLocal(String comando, {String? cwd}) async {
  try {
    final res = Platform.isWindows
        ? await Process.run('cmd', ['/c', comando],
            workingDirectory: cwd, runInShell: true)
        : await Process.run('/bin/sh', ['-c', comando],
            workingDirectory: cwd, runInShell: true);
    final out =
        '${res.stdout?.toString() ?? ''}${res.stderr?.toString() ?? ''}';
    return ResultadoComando(out.trimRight(), res.exitCode);
  } catch (e) {
    return ResultadoComando('Error al ejecutar: $e', -1);
  }
}
