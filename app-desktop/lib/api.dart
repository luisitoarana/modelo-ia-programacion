import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import 'config.dart';
import 'models.dart';

/// Excepción de API con mensaje legible y diagnóstico.
class ApiException implements Exception {
  final String mensaje;
  final int? status;
  final String? detalle;
  ApiException(this.mensaje, {this.status, this.detalle});
  @override
  String toString() => detalle == null ? mensaje : '$mensaje ($detalle)';
}

/// Cliente HTTP del backend. Mantiene el token en memoria.
///
/// Loggea todas las peticiones con su URL completa, status y latencia para
/// facilitar el diagnóstico ("¿por qué no entra mi app?").
class ApiClient {
  String? _token;
  static const Duration _timeout = Duration(seconds: 45);

  void setToken(String? token) => _token = token;
  String? get token => _token;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  Uri _uri(String path) => Uri.parse('${AppConfig.apiBaseUrl}$path');

  void _log(String metodo, Uri uri, int? status, int ms, [Object? error]) {
    final tag = error == null ? 'API' : 'API!';
    final linea = '[$tag] $metodo ${uri.toString()} '
        '→ ${status ?? "?"} (${ms}ms)${error == null ? "" : " · $error"}';
    developer.log(linea, name: 'explicador.api');
    // ignore: avoid_print
    print(linea);
  }

  String _extraerError(http.Response r) {
    try {
      final body = jsonDecode(r.body);
      final detail = body is Map ? body['detail'] : null;
      if (detail is String) return detail;
      if (detail is List && detail.isNotEmpty) {
        final first = detail.first;
        if (first is Map && first['msg'] != null) return first['msg'].toString();
      }
    } catch (_) {}
    return 'Error ${r.statusCode}';
  }

  /// Convierte fallos de red a un mensaje útil ("backend caído", "timeout",
  /// "URL incorrecta") en vez del genérico "no se pudo conectar".
  ApiException _envolverError(Object e, Uri uri) {
    if (e is TimeoutException) {
      return ApiException(
        'El servidor tardó demasiado en responder.',
        detalle: 'timeout en ${uri.host}:${uri.port}',
      );
    }
    if (e is http.ClientException) {
      // En Windows/Linux/Mac y Android suele venir como "Connection refused"
      // si el backend no está vivo; en web como "Failed to fetch".
      return ApiException(
        'No se pudo conectar con el backend. ¿Está corriendo?',
        detalle: '${e.message} → ${uri.host}:${uri.port}',
      );
    }
    if (e is FormatException) {
      return ApiException(
        'El servidor devolvió una respuesta no válida.',
        detalle: e.message,
      );
    }
    // Cubre SocketException y similares sin importar dart:io.
    final msg = e.toString();
    if (msg.contains('SocketException') ||
        msg.contains('Connection refused') ||
        msg.contains('Failed host lookup')) {
      return ApiException(
        'No se pudo conectar con el backend. ¿Está corriendo?',
        detalle: '$msg → ${uri.host}:${uri.port}',
      );
    }
    return ApiException('Error inesperado: $e', detalle: 'destino: $uri');
  }

  Future<dynamic> _get(String path) async {
    final uri = _uri(path);
    final t0 = DateTime.now();
    try {
      final r = await http.get(uri, headers: _headers).timeout(_timeout);
      _log('GET', uri, r.statusCode, DateTime.now().difference(t0).inMilliseconds);
      if (r.statusCode >= 400) {
        throw ApiException(_extraerError(r), status: r.statusCode);
      }
      return r.body.isEmpty ? null : jsonDecode(r.body);
    } on ApiException {
      rethrow;
    } catch (e) {
      _log('GET', uri, null, DateTime.now().difference(t0).inMilliseconds, e);
      throw _envolverError(e, uri);
    }
  }

  Future<dynamic> _post(String path, Map<String, dynamic> body,
      {Duration timeout = _timeout}) async {
    final uri = _uri(path);
    final t0 = DateTime.now();
    try {
      final r = await http
          .post(uri, headers: _headers, body: jsonEncode(body))
          .timeout(timeout);
      _log('POST', uri, r.statusCode,
          DateTime.now().difference(t0).inMilliseconds);
      if (r.statusCode >= 400) {
        throw ApiException(_extraerError(r), status: r.statusCode);
      }
      return r.body.isEmpty ? null : jsonDecode(r.body);
    } on ApiException {
      rethrow;
    } catch (e) {
      _log('POST', uri, null, DateTime.now().difference(t0).inMilliseconds, e);
      throw _envolverError(e, uri);
    }
  }

  Future<void> _delete(String path) async {
    final uri = _uri(path);
    final t0 = DateTime.now();
    try {
      final r = await http.delete(uri, headers: _headers).timeout(_timeout);
      _log('DELETE', uri, r.statusCode,
          DateTime.now().difference(t0).inMilliseconds);
      if (r.statusCode >= 400) {
        throw ApiException(_extraerError(r), status: r.statusCode);
      }
    } on ApiException {
      rethrow;
    } catch (e) {
      _log('DELETE', uri, null, DateTime.now().difference(t0).inMilliseconds, e);
      throw _envolverError(e, uri);
    }
  }

  Future<dynamic> _patch(String path, Map<String, dynamic> body) async {
    final uri = _uri(path);
    final t0 = DateTime.now();
    try {
      final r = await http.patch(uri, headers: _headers, body: jsonEncode(body)).timeout(_timeout);
      _log('PATCH', uri, r.statusCode, DateTime.now().difference(t0).inMilliseconds);
      if (r.statusCode >= 400) {
        throw ApiException(_extraerError(r), status: r.statusCode);
      }
      return r.body.isEmpty ? null : jsonDecode(r.body);
    } on ApiException {
      rethrow;
    } catch (e) {
      _log('PATCH', uri, null, DateTime.now().difference(t0).inMilliseconds, e);
      throw _envolverError(e, uri);
    }
  }

  Future<dynamic> _put(String path, Map<String, dynamic> body) async {
    final uri = _uri(path);
    final t0 = DateTime.now();
    try {
      final r = await http
          .put(uri, headers: _headers, body: jsonEncode(body))
          .timeout(_timeout);
      _log('PUT', uri, r.statusCode,
          DateTime.now().difference(t0).inMilliseconds);
      if (r.statusCode >= 400) {
        throw ApiException(_extraerError(r), status: r.statusCode);
      }
      return r.body.isEmpty ? null : jsonDecode(r.body);
    } on ApiException {
      rethrow;
    } catch (e) {
      _log('PUT', uri, null, DateTime.now().difference(t0).inMilliseconds, e);
      throw _envolverError(e, uri);
    }
  }

  /// Ping rápido al backend (sin autenticación) para diagnosticar conexión
  /// desde la pantalla de configuración. Devuelve la URL probada y un
  /// resultado legible.
  Future<({bool ok, String mensaje, String url})> diagnosticar() async {
    final uri = Uri.parse('${AppConfig.apiBaseUrl}/auth/login');
    final t0 = DateTime.now();
    try {
      // Petición liviana — esperamos un 422 (body vacío) o 401 (mal pass);
      // ambos indican que el endpoint está vivo.
      final r = await http
          .post(uri, headers: {'Content-Type': 'application/json'}, body: '{}')
          .timeout(const Duration(seconds: 5));
      final ms = DateTime.now().difference(t0).inMilliseconds;
      _log('DIAG', uri, r.statusCode, ms);
      if (r.statusCode == 422 || r.statusCode == 401) {
        return (ok: true, mensaje: 'Backend OK (${ms}ms)', url: uri.toString());
      }
      return (
        ok: false,
        mensaje: 'Backend respondió pero con status ${r.statusCode}',
        url: uri.toString(),
      );
    } catch (e) {
      final ms = DateTime.now().difference(t0).inMilliseconds;
      _log('DIAG', uri, null, ms, e);
      final err = _envolverError(e, uri);
      return (ok: false, mensaje: err.toString(), url: uri.toString());
    }
  }

  // ---------------- Auth ----------------
  Future<String> login(String email, String password) async {
    final data = await _post('/auth/login', {
      'email': email,
      'password': password,
    });
    return data['access_token'] as String;
  }

  Future<void> registrarEstudiante({
    required String nombre,
    required String email,
    required String password,
    String? nivelAcademico,
  }) async {
    await _post('/auth/registro', {
      'nombre': nombre,
      'email': email,
      'password': password,
      'rol': 'estudiante',
      if (nivelAcademico != null && nivelAcademico.trim().isNotEmpty)
        'nivel_academico': nivelAcademico.trim(),
    });
  }

  Future<Usuario> perfil() async {
    final data = await _get('/auth/yo');
    return Usuario.fromJson(data as Map<String, dynamic>);
  }

  // ---------------- Chat ----------------
  Future<List<ConversacionResumen>> listarConversaciones() async {
    final data = await _get('/chat/conversaciones') as List;
    return data
        .map((e) => ConversacionResumen.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Crea una conversación vacía con el título dado y devuelve su id.
  /// Útil cuando queremos un chat dedicado a un contexto (archivo, carpeta).
  Future<String> crearConversacion(String titulo) async {
    final data =
        await _post('/chat/conversaciones', {'titulo': titulo}) as Map;
    return data['id'].toString();
  }

  Future<List<Mensaje>> obtenerMensajes(String convId) async {
    final data = await _get('/chat/conversaciones/$convId') as Map<String, dynamic>;
    final mensajes = (data['mensajes'] as List?) ?? [];
    return mensajes
        .map((e) => Mensaje.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<RespuestaEnvio> mensajeRapido(
    String contenido, {
    String idioma = 'es',
    bool buscarWeb = false,
    String proveedor = 'auto',
    String? modoAcompanamiento,
    String? nivelModulo,
  }) async {
    final data = await _post(
      '/chat/mensaje-rapido',
      {
        'contenido': contenido,
        'idioma': idioma,
        'buscar_web': buscarWeb,
        'proveedor': proveedor,
        if (modoAcompanamiento != null)
          'modo_acompanamiento': modoAcompanamiento,
        if (nivelModulo != null)
          'nivel_modulo': nivelModulo,
      },
      timeout: const Duration(seconds: 120),
    );
    return RespuestaEnvio.fromJson(data as Map<String, dynamic>);
  }

  /// Guarda la predicción y la explicación redactadas por el estudiante.
  /// La API no asigna una nota: esta evidencia requiere revisión docente.
  Future<Map<String, dynamic>> registrarIntentoAprendizaje({
    required String? leccionId,
    String? pregunta,
    required String modo,
    required String codigoInicial,
    required String codigoFinal,
    required String prediccion,
    required String explicacionPropia,
    required int pistasUsadas,
    required int duracionSegundos,
  }) async {
    final data = await _post('/aprendizaje/intentos', {
      'leccion_id': leccionId,
      'pregunta': pregunta,
      'modo': modo,
      'codigo_inicial': codigoInicial,
      'codigo_final': codigoFinal,
      'prediccion': prediccion,
      'explicacion_propia': explicacionPropia,
      'pistas_usadas': pistasUsadas,
      'duracion_segundos': duracionSegundos,
    });
    return data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> obtenerAsignacionEstudio() async {
    final data = await _get('/aprendizaje/asignacion');
    return data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> estudioActual() async =>
      (await _get('/estudio/actual')) as Map<String, dynamic>;
  Future<Map<String, dynamic>> tareasEstudio() async =>
      (await _get('/estudio/tareas')) as Map<String, dynamic>;
  Future<Map<String, dynamic>> vistaPreviaEvaluacion(String fase) async =>
      (await _get('/estudio/docente/vista-previa/$fase')) as Map<String, dynamic>;
  Future<Map<String, dynamic>> iniciarEvaluacion() async =>
      (await _post('/estudio/iniciar', {})) as Map<String, dynamic>;
  Future<Map<String, dynamic>> guardarEvaluacion(String id, Map<String, dynamic> respuestas, int revision, {bool finalizar = false}) async =>
      (await _put('/estudio/entregas/$id', {'respuestas': respuestas, 'revision': revision, 'finalizar': finalizar})) as Map<String, dynamic>;
  Future<Map<String, dynamic>> configuracionEstudio() async =>
      (await _get('/estudio/configuracion')) as Map<String, dynamic>;
  Future<void> configurarEstudio(Map<String, dynamic> datos) async {
    await _put('/estudio/configuracion', datos);
  }
  Future<Map<String, dynamic>> resumenEstudio() async =>
      (await _get('/estudio/docente/resumen')) as Map<String, dynamic>;
  Future<void> autorizarDocente(String id) async {
    await _put('/estudio/docente/autorizar/$id', {});
  }
  Future<void> revisarEvaluacion(String id, String pregunta, Map<String, dynamic> rubrica) async {
    await _put('/estudio/docente/entregas/$id/preguntas/$pregunta', rubrica);
  }

  Future<Map<String, dynamic>> resumenAdmin() async =>
      (await _get('/admin/resumen')) as Map<String, dynamic>;

  Future<void> cambiarClave(String actual, String nueva) async {
    await _put('/auth/clave', {'actual': actual, 'nueva': nueva});
  }

  Future<List<Map<String, dynamic>>> usuariosAdmin() async =>
      (await _get('/admin/usuarios') as List).cast<Map<String, dynamic>>();

  Future<List<Map<String, dynamic>>> intentosDocente({int offset = 0}) async =>
      (await _get('/aprendizaje/investigacion/intentos?offset=$offset') as List)
          .cast<Map<String, dynamic>>();

  Future<void> asignarEstudio(String usuarioId, String condicion, String fase) async {
    await _put('/aprendizaje/asignaciones/$usuarioId', {
      'condicion': condicion, 'fase': fase,
    });
  }

  Future<void> revisarIntento(String intentoId, {
    required int comprension,
    required int codigo,
    required int casosLimite,
    required String observaciones,
  }) async {
    await _put('/aprendizaje/investigacion/intentos/$intentoId/revision', {
      'comprension': comprension,
      'codigo': codigo,
      'casos_limite': casosLimite,
      'observaciones': observaciones,
    });
  }

  Future<void> cambiarEstadoEstudiante(String usuarioId, bool activo) async {
    await _patch('/admin/usuarios/$usuarioId/estado', {'activo': activo});
  }

  Future<Map<String, dynamic>> validarSintaxisPython(String codigo) async {
    final data = await _post('/herramientas/validar-sintaxis', {
      'codigo': codigo,
    });
    return data as Map<String, dynamic>;
  }

  Future<RespuestaEnvio> enviarMensaje(
    String convId,
    String contenido, {
    String idioma = 'es',
    bool buscarWeb = false,
    String proveedor = 'auto',
    String? modoAcompanamiento,
    String? nivelModulo,
  }) async {
    final data = await _post(
      '/chat/conversaciones/$convId/mensajes',
      {
        'contenido': contenido,
        'idioma': idioma,
        'buscar_web': buscarWeb,
        'proveedor': proveedor,
        if (modoAcompanamiento != null)
          'modo_acompanamiento': modoAcompanamiento,
        if (nivelModulo != null)
          'nivel_modulo': nivelModulo,
      },
      timeout: const Duration(seconds: 120),
    );
    return RespuestaEnvio.fromJson(data as Map<String, dynamic>);
  }

  Future<void> eliminarConversacion(String convId) async {
    await _delete('/chat/conversaciones/$convId');
  }

  // ---------------- Selector multi-IA ----------------

  Future<List<ProveedorIA>> listarProveedores() async {
    final data = await _get('/chat/proveedores') as Map<String, dynamic>;
    final lista = (data['proveedores'] as List?) ?? const [];
    return lista
        .whereType<Map<String, dynamic>>()
        .map(ProveedorIA.fromJson)
        .toList();
  }

  // ---------------- RAG (Retrieval-Augmented Generation) ----------------

  Future<EstadoRag> estadoRag() async {
    final data = await _get('/rag/estado') as Map<String, dynamic>;
    return EstadoRag.fromJson(data);
  }

  Future<List<DocumentoRag>> listarDocumentosRag() async {
    final data = await _get('/rag/documentos') as List;
    return data
        .whereType<Map<String, dynamic>>()
        .map(DocumentoRag.fromJson)
        .toList();
  }

  Future<DocumentoRag> subirTextoRag({
    required String titulo,
    required String texto,
    String fuente = 'subido',
    List<String> tags = const [],
  }) async {
    final data = await _post('/rag/subir', {
      'titulo': titulo,
      'texto': texto,
      'fuente': fuente,
      'tags': tags,
    }) as Map<String, dynamic>;
    return DocumentoRag.fromJson(data);
  }

  /// Sube un archivo (txt, md, py, etc.) usando multipart/form-data.
  Future<DocumentoRag> subirArchivoRag({
    required String nombreArchivo,
    required List<int> bytes,
    String? titulo,
    String tags = '',
  }) async {
    final inicio = DateTime.now();
    final uri = _uri('/rag/subir-archivo');
    try {
      final req = http.MultipartRequest('POST', uri);
      if (_token != null) req.headers['Authorization'] = 'Bearer $_token';
      req.files.add(http.MultipartFile.fromBytes(
        'archivo', bytes,
        filename: nombreArchivo,
      ));
      if (titulo != null && titulo.isNotEmpty) req.fields['titulo'] = titulo;
      if (tags.isNotEmpty) req.fields['tags'] = tags;
      final streamed = await req.send().timeout(_timeout);
      final r = await http.Response.fromStream(streamed);
      final ms = DateTime.now().difference(inicio).inMilliseconds;
      _log('POST', uri, r.statusCode, ms);
      if (r.statusCode >= 200 && r.statusCode < 300) {
        return DocumentoRag.fromJson(
          jsonDecode(r.body) as Map<String, dynamic>,
        );
      }
      throw ApiException(_extraerError(r), status: r.statusCode);
    } catch (e) {
      final ms = DateTime.now().difference(inicio).inMilliseconds;
      _log('POST', uri, null, ms, e);
      if (e is ApiException) rethrow;
      throw _envolverError(e, uri);
    }
  }

  Future<void> eliminarDocumentoRag(String id) async {
    await _delete('/rag/documentos/$id');
  }

  // ---------------- Ejecutar Python en sandbox del backend ----------------
  /// Ejecuta un snippet de código en el sandbox del backend.
  /// Devuelve stdout, stderr, exit_code y duración. Soporta varios
  /// lenguajes — el nombre del método es histórico (empezó solo con Python).
  Future<Map<String, dynamic>> ejecutarPython(
    String codigo, {
    int timeout = 10,
    String lenguaje = 'python',
    String? stdinTexto,
  }) async {
    final data = await _post('/herramientas/ejecutar-python', {
      'codigo': codigo,
      'timeout': timeout,
      'lenguaje': lenguaje,
      if (stdinTexto != null) 'stdin_texto': stdinTexto,
    });
    return data as Map<String, dynamic>;
  }

  // ---------------- Feedback (RLHF) ----------------
  /// Envía un voto (+1 / -1) sobre una respuesta del asistente al backend.
  /// El voto se persiste en la tabla `feedbacks` y luego se usa para
  /// construir el dataset DPO. Ver docs/RLHF_PLAN.md.
  Future<Map<String, dynamic>> enviarFeedback({
    required String mensajeId,
    required int voto,
    String? razon,
    String? comentario,
  }) async {
    final data = await _post('/feedback', {
      'mensaje_id': mensajeId,
      'voto': voto,
      if (razon != null) 'razon': razon,
      if (comentario != null) 'comentario': comentario,
    });
    return data as Map<String, dynamic>;
  }

  // ---------------- Admin: API keys de proveedores IA ----------------
  /// Devuelve el estado de las API keys (enmascaradas) para cada proveedor.
  /// Requiere rol administrador.
  Future<List<Map<String, dynamic>>> estadoApiKeys() async {
    final data = await _get('/admin/config/api-keys') as Map<String, dynamic>;
    final lista = (data['keys'] as List?) ?? [];
    return lista.cast<Map<String, dynamic>>();
  }

  /// Guarda/actualiza una API key (cifrada en BD). Solo admin.
  Future<void> guardarApiKey(String proveedor, String apiKey) async {
    await _put(
      '/admin/config/api-keys',
      {'proveedor': proveedor, 'api_key': apiKey},
    );
  }

  /// Hace una llamada real al proveedor para validar la key. Solo admin.
  Future<({bool ok, String detalle})> probarApiKey(String proveedor) async {
    try {
      final data = await _post('/admin/config/probar/$proveedor', {}) as Map;
      return (
        ok: data['ok'] == true,
        detalle: data['detalle']?.toString() ?? 'sin detalle',
      );
    } on ApiException catch (e) {
      return (ok: false, detalle: e.mensaje);
    }
  }

  // ---------------- Estado del modelo ----------------
  Future<Map<String, dynamic>> estadoModelo() async {
    final data = await _get('/ai/modelo-estado');
    return data as Map<String, dynamic>;
  }

  // ---------------- Explorador de proyecto (backend) ----------------
  Future<List<NodoProyecto>> arbolProyecto(String ruta) async {
    final data = await _get('/proyecto/arbol?ruta=${Uri.encodeComponent(ruta)}')
        as Map<String, dynamic>;
    final elementos = (data['elementos'] as List?) ?? [];
    return elementos
        .map((e) => NodoProyecto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<ArchivoProyecto> leerArchivoProyecto(String ruta) async {
    final data = await _get('/proyecto/archivo?ruta=${Uri.encodeComponent(ruta)}')
        as Map<String, dynamic>;
    return ArchivoProyecto.fromJson(data);
  }

  /// Audita la arquitectura completa del proyecto mediante AST sintáctico.
  Future<Map<String, dynamic>> auditarProyectoAST({
    bool conAuditoriaIa = true,
    String proveedor = 'auto',
  }) async {
    final data = await _post(
      '/proyecto/auditoria-ast?con_auditoria_ia=$conAuditoriaIa&proveedor=$proveedor',
      {},
    );
    return data as Map<String, dynamic>;
  }

  // ── Currículo Curricular y Retos de Aprendizaje ──

  Future<List<dynamic>> listarModulosCurriculo() async {
    final data = await _get('/curriculo/modulos');
    return (data as List<dynamic>?) ?? [];
  }

  Future<Map<String, dynamic>> obtenerModuloCurriculo(String moduloId) async {
    final data = await _get('/curriculo/modulos/$moduloId');
    return data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> obtenerLeccionCurriculo(String leccionId) async {
    final data = await _get('/curriculo/leccion/$leccionId');
    return data as Map<String, dynamic>;
  }
}

class NodoProyecto {
  final String nombre;
  final String ruta;
  final String tipo; // carpeta | archivo
  final bool esTexto;

  NodoProyecto({
    required this.nombre,
    required this.ruta,
    required this.tipo,
    required this.esTexto,
  });

  bool get esCarpeta => tipo == 'carpeta';

  factory NodoProyecto.fromJson(Map<String, dynamic> j) => NodoProyecto(
        nombre: j['nombre'] ?? '',
        ruta: j['ruta'] ?? '',
        tipo: j['tipo'] ?? 'archivo',
        esTexto: j['es_texto'] ?? false,
      );
}

class ArchivoProyecto {
  final String ruta;
  final String nombre;
  final String lenguaje;
  final String contenido;

  ArchivoProyecto({
    required this.ruta,
    required this.nombre,
    required this.lenguaje,
    required this.contenido,
  });

  factory ArchivoProyecto.fromJson(Map<String, dynamic> j) => ArchivoProyecto(
        ruta: j['ruta'] ?? '',
        nombre: j['nombre'] ?? '',
        lenguaje: j['lenguaje'] ?? 'texto',
        contenido: j['contenido'] ?? '',
      );
}

class RespuestaEnvio {
  final String conversacionId;
  final String titulo;
  final Mensaje mensajeUsuario;
  final Mensaje mensajeAsistente;

  RespuestaEnvio({
    required this.conversacionId,
    required this.titulo,
    required this.mensajeUsuario,
    required this.mensajeAsistente,
  });

  factory RespuestaEnvio.fromJson(Map<String, dynamic> j) => RespuestaEnvio(
        conversacionId: j['conversacion_id']?.toString() ?? '',
        titulo: j['titulo'] ?? '',
        mensajeUsuario:
            Mensaje.fromJson(j['mensaje_usuario'] as Map<String, dynamic>),
        mensajeAsistente:
            Mensaje.fromJson(j['mensaje_asistente'] as Map<String, dynamic>),
      );
}
