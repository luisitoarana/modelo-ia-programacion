import 'package:flutter_tts/flutter_tts.dart';

/// Servicio de Text-to-Speech para leer las respuestas del asistente
/// cuando el usuario tenga TTS activado.
///
/// Diseño:
///   - Singleton (1 sola instancia en toda la app).
///   - `speak(texto)` se puede llamar siempre — si TTS no está habilitado,
///     no hace nada (decisión en el caller).
///   - Limpia markdown antes de leer (no lee asteriscos, backticks, etc.).
///   - Si llega un nuevo texto mientras se lee el anterior, cancela y
///     empieza el nuevo (igual que la web).
class TtsService {
  TtsService._();
  static final TtsService instance = TtsService._();

  final FlutterTts _tts = FlutterTts();
  bool _inicializado = false;

  Future<void> _asegurar() async {
    if (_inicializado) return;
    try {
      await _tts.awaitSpeakCompletion(false);
    } catch (_) {}
    _inicializado = true;
  }

  Future<List<Map<String, String>>> voicesDisponibles() async {
    await _asegurar();
    try {
      final raw = await _tts.getVoices;
      if (raw is List) {
        return raw.map((v) {
          final m = (v as Map);
          return <String, String>{
            'name': (m['name'] ?? '').toString(),
            'locale': (m['locale'] ?? '').toString(),
          };
        }).where((v) => v['name']!.isNotEmpty).toList();
      }
    } catch (_) {}
    return [];
  }

  Future<void> speak(
    String texto, {
    required double velocidad,
    String? voz,
    String idioma = 'es-ES',
  }) async {
    await _asegurar();
    final limpio = _limpiarMarkdown(texto);
    if (limpio.isEmpty) return;
    try {
      await _tts.stop();
      await _tts.setLanguage(idioma);
      // velocidad: 0.0 (lento) a 1.0 (rápido) en flutter_tts.
      await _tts.setSpeechRate(velocidad.clamp(0.0, 1.0));
      if (voz != null && voz.isNotEmpty) {
        try {
          await _tts.setVoice({'name': voz, 'locale': idioma});
        } catch (_) {}
      }
      await _tts.speak(limpio.length > 1000 ? limpio.substring(0, 1000) : limpio);
    } catch (_) {
      // Silencioso — TTS es "nice to have", no debe romper el chat.
    }
  }

  Future<void> stop() async {
    if (!_inicializado) return;
    try {
      await _tts.stop();
    } catch (_) {}
  }

  /// Limpia markdown para que la voz no lea símbolos como "asterisco".
  String _limpiarMarkdown(String s) {
    return s
        .replaceAll(RegExp(r'```[\s\S]*?```'), '. Bloque de código. ')
        .replaceAll(RegExp(r'`[^`]+`'), '')
        .replaceAll(RegExp(r'[*_#>]+'), '')
        .replaceAll(RegExp(r'\[([^\]]+)\]\([^)]+\)'), r'$1')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
