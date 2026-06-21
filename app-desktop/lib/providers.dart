import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'config.dart';
import 'models.dart';

const _kTokenKey = 'explicador.token';

/// Ajustes generales (idioma, URL del backend, TTS, etc.), persistidos.
class SettingsProvider extends ChangeNotifier {
  String _idioma = 'es';
  String? _apiUrlPersonalizada;
  bool _buscarWeb = false;
  bool _ttsHabilitado = false;
  double _ttsVelocidad = 0.5;
  String? _ttsVoz;
  String _proveedor = 'auto';

  String get idioma => _idioma;
  String? get apiUrlPersonalizada => _apiUrlPersonalizada;
  String get apiUrlEfectiva => AppConfig.apiBaseUrl;
  String get apiUrlAutoDetectada => AppConfig.apiBaseUrlAutoDetectado;
  bool get buscarWeb => _buscarWeb;
  bool get ttsHabilitado => _ttsHabilitado;
  double get ttsVelocidad => _ttsVelocidad;
  String? get ttsVoz => _ttsVoz;
  String get proveedor => _proveedor;

  static const _kIdiomaKey = 'explicador.idioma';
  static const _kApiUrlKey = 'explicador.api_url';
  static const _kBuscarWebKey = 'explicador.buscar_web';
  static const _kTtsKey = 'explicador.tts';
  static const _kTtsVelKey = 'explicador.tts_vel';
  static const _kTtsVozKey = 'explicador.tts_voz';
  static const _kProveedorKey = 'explicador.proveedor';

  Future<void> cargar() async {
    final prefs = await SharedPreferences.getInstance();
    _idioma = prefs.getString(_kIdiomaKey) ?? 'es';
    _apiUrlPersonalizada = prefs.getString(_kApiUrlKey);
    _buscarWeb = prefs.getBool(_kBuscarWebKey) ?? false;
    _ttsHabilitado = prefs.getBool(_kTtsKey) ?? false;
    _ttsVelocidad = prefs.getDouble(_kTtsVelKey) ?? 0.5;
    _ttsVoz = prefs.getString(_kTtsVozKey);
    _proveedor = prefs.getString(_kProveedorKey) ?? 'auto';
    AppConfig.setRuntimeApiUrl(_apiUrlPersonalizada);
    notifyListeners();
  }

  Future<void> setProveedor(String id) async {
    _proveedor = id;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kProveedorKey, id);
  }

  Future<void> setTts(bool v) async {
    _ttsHabilitado = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kTtsKey, v);
  }

  Future<void> setTtsVelocidad(double v) async {
    _ttsVelocidad = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kTtsVelKey, v);
  }

  Future<void> setTtsVoz(String? v) async {
    _ttsVoz = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (v == null) {
      await prefs.remove(_kTtsVozKey);
    } else {
      await prefs.setString(_kTtsVozKey, v);
    }
  }

  Future<void> setIdioma(String code) async {
    _idioma = code;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kIdiomaKey, code);
  }

  Future<void> setApiUrlPersonalizada(String? url) async {
    final limpia = (url == null || url.trim().isEmpty) ? null : url.trim();
    _apiUrlPersonalizada = limpia;
    AppConfig.setRuntimeApiUrl(limpia);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (limpia == null) {
      await prefs.remove(_kApiUrlKey);
    } else {
      await prefs.setString(_kApiUrlKey, limpia);
    }
  }

  Future<void> setBuscarWeb(bool v) async {
    _buscarWeb = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kBuscarWebKey, v);
  }
}

/// Estado del tema (claro/oscuro/sistema) + paleta de colores, persistidos.
class ThemeProvider extends ChangeNotifier {
  ThemeMode _mode = ThemeMode.dark;
  String _paletaId = 'terracota';

  ThemeMode get mode => _mode;
  String get paletaId => _paletaId;

  static const _kThemeKey = 'explicador.theme';
  static const _kPaletaKey = 'explicador.paleta';

  Future<void> cargar() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_kThemeKey);
    _mode = switch (v) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    _paletaId = prefs.getString(_kPaletaKey) ?? 'terracota';
    notifyListeners();
  }

  Future<void> setMode(ThemeMode mode) async {
    _mode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemeKey, mode.name);
  }

  Future<void> setPaleta(String id) async {
    _paletaId = id;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPaletaKey, id);
  }
}

/// Estado de autenticación.
class AuthProvider extends ChangeNotifier {
  final ApiClient api;
  AuthProvider(this.api);

  Usuario? _usuario;
  bool _cargando = true;
  String? _error;

  Usuario? get usuario => _usuario;
  bool get cargando => _cargando;
  bool get autenticado => _usuario != null;
  String? get error => _error;

  Future<void> cargarSesion() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_kTokenKey);
    if (token != null && token.isNotEmpty) {
      api.setToken(token);
      try {
        _usuario = await api.perfil();
      } catch (_) {
        await _limpiarToken();
      }
    }
    _cargando = false;
    notifyListeners();
  }

  Future<bool> login(String email, String password) async {
    _error = null;
    notifyListeners();
    try {
      final token = await api.login(email, password);
      api.setToken(token);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kTokenKey, token);
      _usuario = await api.perfil();
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      // Mostramos mensaje + detalle (URL, status) — clave para diagnosticar.
      _error = e.detalle == null ? e.mensaje : '${e.mensaje}\n${e.detalle}';
      notifyListeners();
      return false;
    } catch (e) {
      _error = 'Error inesperado: $e';
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    await _limpiarToken();
    _usuario = null;
    notifyListeners();
  }

  Future<void> _limpiarToken() async {
    api.setToken(null);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kTokenKey);
  }
}

/// Estado del chat conversacional.
class ChatProvider extends ChangeNotifier {
  final ApiClient api;
  ChatProvider(this.api);

  List<ConversacionResumen> conversaciones = [];
  List<Mensaje> mensajes = [];
  String? activaId;
  bool enviando = false;
  // Flags de carga para que la UI muestre skeletons en lugar de spinners.
  bool cargandoConversaciones = false;
  bool cargandoMensajes = false;
  /// Marca si ya cargamos al menos una vez (para distinguir "todavía no
  /// cargué" de "cargué y está vacío" — eso decide skeleton vs empty state).
  bool conversacionesCargadasAlgunaVez = false;
  // Orden personalizado (lista de IDs). Si está vacía, el orden por
  // fecha del backend se respeta. Si tiene contenido, los chats listados
  // aquí van en ese orden y el resto cae al final.
  List<String> ordenPersonalizado = [];

  static const _kOrdenKey = 'explicador.orden_chats';

  Future<void> cargarOrden() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kOrdenKey);
    if (raw != null) {
      try {
        ordenPersonalizado = raw.split('\n').where((s) => s.isNotEmpty).toList();
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<void> guardarOrden(List<String> ids) async {
    ordenPersonalizado = ids;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (ids.isEmpty) {
      await prefs.remove(_kOrdenKey);
    } else {
      await prefs.setString(_kOrdenKey, ids.join('\n'));
    }
  }

  /// Reordena: mueve [draggedId] a la posición de [targetId].
  Future<void> reordenar(String draggedId, String targetId) async {
    if (draggedId == targetId) return;
    final actual = conversaciones.map((c) => c.id).toList();
    final from = actual.indexOf(draggedId);
    final to = actual.indexOf(targetId);
    if (from < 0 || to < 0) return;
    actual.insert(to, actual.removeAt(from));
    await guardarOrden(actual);
  }

  /// Devuelve conversaciones ordenadas según ordenPersonalizado (si hay).
  List<ConversacionResumen> get conversacionesOrdenadas {
    if (ordenPersonalizado.isEmpty) return conversaciones;
    final indice = <String, int>{
      for (var i = 0; i < ordenPersonalizado.length; i++)
        ordenPersonalizado[i]: i
    };
    final copia = List<ConversacionResumen>.from(conversaciones);
    copia.sort((a, b) {
      final ia = indice[a.id] ?? 1 << 30;
      final ib = indice[b.id] ?? 1 << 30;
      if (ia != ib) return ia.compareTo(ib);
      // Empate: por fecha descendente.
      final fa = DateTime.tryParse(a.fechaActualizacion) ?? DateTime(2000);
      final fb = DateTime.tryParse(b.fechaActualizacion) ?? DateTime(2000);
      return fb.compareTo(fa);
    });
    return copia;
  }

  Future<void> cargarConversaciones() async {
    cargandoConversaciones = true;
    notifyListeners();
    try {
      conversaciones = await api.listarConversaciones();
    } catch (_) {
      // mantenemos la lista anterior; el error se muestra a nivel UI si aplica
    } finally {
      cargandoConversaciones = false;
      conversacionesCargadasAlgunaVez = true;
      notifyListeners();
    }
  }

  void nueva() {
    activaId = null;
    mensajes = [];
    notifyListeners();
  }

  Future<void> seleccionar(String id) async {
    activaId = id;
    mensajes = [];
    cargandoMensajes = true;
    notifyListeners();
    try {
      mensajes = await api.obtenerMensajes(id);
    } catch (_) {
      mensajes = [];
    } finally {
      cargandoMensajes = false;
      notifyListeners();
    }
  }

  Future<void> eliminar(String id) async {
    try {
      await api.eliminarConversacion(id);
    } catch (_) {}
    if (id == activaId) nueva();
    await cargarConversaciones();
  }

  /// Envía un mensaje "ligado a un contexto" (archivo, carpeta, snippet).
  ///
  /// Estrategia anti-explosión de chats:
  ///   - Antes: cada archivo creaba SU chat → 20 archivos = 20 chats.
  ///   - Ahora: una conversación POR CONTEXTO BASE (carpeta o snippet).
  ///     Múltiples archivos de la misma carpeta se acumulan en un chat
  ///     único, distinguidos por el primer mensaje (que indica el archivo).
  ///
  /// El match es por prefijo: si pasas `📁 src/` y existe una conversación
  /// con título que empieza por `📁 src/`, se reutiliza.
  Future<void> enviarParaContexto(
    String texto, {
    required String contexto,
    String idioma = 'es',
    bool buscarWeb = false,
  }) async {
    if (texto.trim().isEmpty || enviando) return;

    // Busca conversación cuyo título coincide exacto o por prefijo.
    // Esto cubre dos escenarios:
    //   1. Contexto pasado por el caller es exactamente el título existente.
    //   2. El caller pasa "📁 src" y existe "📁 src · 3 archivos" → reusa.
    ConversacionResumen? existente;
    for (final c in conversaciones) {
      if (c.titulo == contexto || c.titulo.startsWith('$contexto · ')) {
        existente = c;
        break;
      }
    }

    if (existente != null) {
      await seleccionar(existente.id);
      await enviar(texto, idioma: idioma, buscarWeb: buscarWeb);
      return;
    }

    try {
      final nuevoId = await api.crearConversacion(contexto);
      activaId = nuevoId;
      mensajes = [];
      notifyListeners();
      await enviar(texto, idioma: idioma, buscarWeb: buscarWeb);
    } on ApiException catch (e) {
      mensajes = [
        ...mensajes,
        Mensaje(id: 'err', rol: 'asistente', contenido: 'Error: ${e.mensaje}'),
      ];
      notifyListeners();
    }
  }

  Future<void> enviar(
    String texto, {
    String idioma = 'es',
    bool buscarWeb = false,
    String proveedor = 'auto',
  }) async {
    if (texto.trim().isEmpty || enviando) return;
    enviando = true;
    mensajes = [
      ...mensajes,
      Mensaje(id: 'tmp', rol: 'usuario', contenido: texto.trim()),
    ];
    notifyListeners();

    try {
      final RespuestaEnvio resp = activaId == null
          ? await api.mensajeRapido(
              texto.trim(),
              idioma: idioma,
              buscarWeb: buscarWeb,
              proveedor: proveedor,
            )
          : await api.enviarMensaje(
              activaId!,
              texto.trim(),
              idioma: idioma,
              buscarWeb: buscarWeb,
              proveedor: proveedor,
            );
      activaId = resp.conversacionId;
      mensajes = [
        ...mensajes.where((m) => m.id != 'tmp'),
        resp.mensajeUsuario,
        resp.mensajeAsistente,
      ];
      await cargarConversaciones();
    } on ApiException catch (e) {
      mensajes = [
        ...mensajes,
        Mensaje(id: 'err', rol: 'asistente', contenido: 'Error: ${e.mensaje}'),
      ];
    } catch (e) {
      mensajes = [
        ...mensajes,
        Mensaje(
          id: 'err',
          rol: 'asistente',
          contenido: 'No se pudo conectar con el servidor.',
        ),
      ];
    } finally {
      enviando = false;
      notifyListeners();
    }
  }

  void limpiar() {
    conversaciones = [];
    mensajes = [];
    activaId = null;
    enviando = false;
  }
}
