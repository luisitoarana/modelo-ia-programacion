// Implementación STUB para web: el disco local no está disponible.

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

/// Indica si el acceso a disco local está soportado en esta plataforma.
const bool soportaDiscoLocal = false;

Future<List<EntradaLocal>> listarLocal(String ruta) async => const [];

Future<String> leerLocal(String ruta) async =>
    'El acceso al disco local solo está disponible en la app de escritorio nativa.';

Future<bool> escribirLocal(String ruta, String contenido) async => false;

/// Resultado de ejecutar un comando en la terminal.
class ResultadoComando {
  final String salida;
  final int codigo;
  const ResultadoComando(this.salida, this.codigo);
}

Future<ResultadoComando> ejecutarComandoLocal(String comando, {String? cwd}) async =>
    const ResultadoComando(
      'La terminal solo está disponible en la app de escritorio nativa '
      '(Windows/Linux/Mac).',
      -1,
    );
