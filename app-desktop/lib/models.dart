// Modelos de datos de la aplicación.

class Usuario {
  final String id;
  final String nombre;
  final String email;
  final String rol;
  final String? institucion;

  Usuario({
    required this.id,
    required this.nombre,
    required this.email,
    required this.rol,
    this.institucion,
  });

  factory Usuario.fromJson(Map<String, dynamic> j) => Usuario(
        id: j['id']?.toString() ?? '',
        nombre: j['nombre'] ?? '',
        email: j['email'] ?? '',
        rol: j['rol'] ?? 'estudiante',
        institucion: j['institucion'],
      );

  bool get esAdmin => rol == 'administrador';
  bool get esInvestigador => rol == 'investigador' || rol == 'administrador';
}

class ConversacionResumen {
  final String id;
  final String titulo;
  final String fechaActualizacion;

  ConversacionResumen({
    required this.id,
    required this.titulo,
    required this.fechaActualizacion,
  });

  factory ConversacionResumen.fromJson(Map<String, dynamic> j) =>
      ConversacionResumen(
        id: j['id']?.toString() ?? '',
        titulo: j['titulo'] ?? 'Conversación',
        fechaActualizacion: j['fecha_actualizacion'] ?? '',
      );
}

/// Fuente RAG citada por una respuesta del asistente.
class FuenteRag {
  final String docId;
  final String titulo;
  final double score;
  final String chunkId;

  FuenteRag({
    required this.docId,
    required this.titulo,
    required this.score,
    required this.chunkId,
  });

  factory FuenteRag.fromJson(Map<String, dynamic> j) => FuenteRag(
        docId: j['doc_id']?.toString() ?? '',
        titulo: j['titulo']?.toString() ?? '(sin título)',
        score: (j['score'] ?? 0).toDouble(),
        chunkId: j['chunk_id']?.toString() ?? '',
      );
}

/// Fuente web consultada por la respuesta del asistente.
class FuenteWeb {
  final String? titulo;
  final String? url;
  final String? snippet;

  FuenteWeb({this.titulo, this.url, this.snippet});

  factory FuenteWeb.fromJson(Map<String, dynamic> j) => FuenteWeb(
        titulo: j['titulo']?.toString(),
        url: j['url']?.toString(),
        snippet: j['snippet']?.toString(),
      );
}

class Mensaje {
  final String id;
  final String rol; // usuario | asistente
  final String contenido;
  final String? origenRespuesta;
  final double latenciaSegundos;
  final List<FuenteRag> fuentesRag;
  final List<FuenteWeb> fuentesWeb;
  final int? nImagenes;
  final String? proveedorUsado;

  Mensaje({
    required this.id,
    required this.rol,
    required this.contenido,
    this.origenRespuesta,
    this.latenciaSegundos = 0,
    this.fuentesRag = const [],
    this.fuentesWeb = const [],
    this.nImagenes,
    this.proveedorUsado,
  });

  bool get esUsuario => rol == 'usuario';

  factory Mensaje.fromJson(Map<String, dynamic> j) {
    final meta = j['metadata_json'];
    final ragRaw = (meta is Map ? meta['fuentes_rag'] : null) as List? ?? const [];
    final webRaw = (meta is Map ? meta['fuentes_web'] : null) as List? ?? const [];
    return Mensaje(
      id: j['id']?.toString() ?? '',
      rol: j['rol'] ?? 'asistente',
      contenido: j['contenido'] ?? '',
      origenRespuesta: j['origen_respuesta'],
      latenciaSegundos: (j['latencia_segundos'] ?? 0).toDouble(),
      fuentesRag: ragRaw
          .whereType<Map<String, dynamic>>()
          .map(FuenteRag.fromJson)
          .toList(),
      fuentesWeb: webRaw
          .whereType<Map<String, dynamic>>()
          .map(FuenteWeb.fromJson)
          .toList(),
      nImagenes: meta is Map ? meta['n_imagenes'] as int? : null,
      proveedorUsado: meta is Map ? meta['proveedor'] as String? : null,
    );
  }
}

/// Proveedor de IA disponible para el selector multi-IA del composer.
class ProveedorIA {
  final String id;
  final String nombre;
  final String descripcion;
  final String tipo; // auto | propio | api
  final bool disponible;

  const ProveedorIA({
    required this.id,
    required this.nombre,
    required this.descripcion,
    required this.tipo,
    required this.disponible,
  });

  factory ProveedorIA.fromJson(Map<String, dynamic> j) => ProveedorIA(
        id: j['id']?.toString() ?? '',
        nombre: j['nombre']?.toString() ?? '',
        descripcion: j['descripcion']?.toString() ?? '',
        tipo: j['tipo']?.toString() ?? 'api',
        disponible: j['disponible'] == true,
      );
}

/// Documento indexado en el sistema RAG.
class DocumentoRag {
  final String id;
  final String titulo;
  final String fuente;
  final int nChunks;
  final String fecha;
  final List<String> tags;

  DocumentoRag({
    required this.id,
    required this.titulo,
    required this.fuente,
    required this.nChunks,
    required this.fecha,
    this.tags = const [],
  });

  factory DocumentoRag.fromJson(Map<String, dynamic> j) => DocumentoRag(
        id: j['id']?.toString() ?? '',
        titulo: j['titulo']?.toString() ?? '',
        fuente: j['fuente']?.toString() ?? '',
        nChunks: (j['n_chunks'] ?? 0) as int,
        fecha: j['fecha']?.toString() ?? '',
        tags: (j['tags'] as List?)?.cast<String>() ?? const [],
      );
}

/// Estado global del sistema RAG.
class EstadoRag {
  final bool disponible;
  final int nDocumentos;
  final int nChunks;
  final int dim;
  final String backend;
  final String? motivo;

  EstadoRag({
    required this.disponible,
    this.nDocumentos = 0,
    this.nChunks = 0,
    this.dim = 0,
    this.backend = 'none',
    this.motivo,
  });

  factory EstadoRag.fromJson(Map<String, dynamic> j) => EstadoRag(
        disponible: j['disponible'] == true,
        nDocumentos: (j['n_documentos'] ?? 0) as int,
        nChunks: (j['n_chunks'] ?? 0) as int,
        dim: (j['dim'] ?? 0) as int,
        backend: j['backend']?.toString() ?? 'none',
        motivo: j['motivo']?.toString(),
      );
}
