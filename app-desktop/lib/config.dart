import 'package:flutter/foundation.dart';
import 'dart:io' show Platform;

/// Configuración de la aplicación.
class AppConfig {
  /// Permite sobreescribir la URL del backend al compilar:
  ///   flutter run --dart-define=API_URL=http://192.168.1.50:8000/api/v1
  static const String _overrideUrl =
      String.fromEnvironment('API_URL', defaultValue: '');

  /// Override en runtime (lo guarda Settings). Tiene precedencia sobre
  /// la detección automática.
  static String? _runtimeOverride;
  static void setRuntimeApiUrl(String? url) {
    _runtimeOverride = (url == null || url.trim().isEmpty) ? null : url.trim();
  }

  static String get apiBaseUrlAutoDetectado {
    if (_overrideUrl.isNotEmpty) return _overrideUrl;
    if (kIsWeb) return 'http://localhost:8765/api/v1';
    try {
      if (Platform.isAndroid) return 'http://10.0.2.2:8765/api/v1';
    } catch (_) {}
    return 'http://localhost:8765/api/v1';
  }

  /// URL base del backend efectiva (override runtime → compile-time → auto).
  ///
  /// Detección automática por plataforma:
  ///  - Web        → http://localhost:8000
  ///  - Windows / macOS / Linux desktop → http://localhost:8000
  ///  - Android emulator → http://10.0.2.2:8000   (alias al host)
  ///  - iOS simulator   → http://localhost:8000
  ///  - Móvil físico    → cambia en Settings de la app
  static String get apiBaseUrl {
    return _runtimeOverride ?? apiBaseUrlAutoDetectado;
  }

  static const String appName = 'Explicador Python IA';
}

/// Idiomas soportados por el asistente.
///
/// Cualquier idioma listado aquí puede usarse: la app simplemente le pide
/// al LLM que responda en ese idioma. La calidad depende del modelo.
class Idiomas {
  static const Map<String, String> opciones = {
    // Español
    'es': 'Español',
    'es-419': 'Español (Latinoamérica)',
    'es-ES': 'Español (España)',
    'es-MX': 'Español (México)',
    'es-AR': 'Español (Argentina)',
    'es-CO': 'Español (Colombia)',
    'es-PE': 'Español (Perú)',
    'es-CL': 'Español (Chile)',
    // Inglés
    'en': 'English',
    'en-US': 'English (US)',
    'en-GB': 'English (UK)',
    // Lenguas romances
    'pt': 'Português',
    'pt-BR': 'Português (Brasil)',
    'fr': 'Français',
    'it': 'Italiano',
    'ca': 'Català',
    'ro': 'Română',
    // Germánicas
    'de': 'Deutsch',
    'nl': 'Nederlands',
    'sv': 'Svenska',
    'no': 'Norsk',
    'da': 'Dansk',
    // Eslavas
    'ru': 'Русский (Ruso)',
    'pl': 'Polski',
    'uk': 'Українська (Ucraniano)',
    'cs': 'Čeština',
    // Asiáticas
    'zh': '中文 (Mandarín simplificado)',
    'zh-TW': '繁體中文 (Mandarín tradicional)',
    'ja': '日本語 (Japonés)',
    'ko': '한국어 (Coreano)',
    'hi': 'हिन्दी (Hindi)',
    'th': 'ภาษาไทย (Tailandés)',
    'vi': 'Tiếng Việt (Vietnamita)',
    'id': 'Bahasa Indonesia',
    'ms': 'Bahasa Melayu',
    // Otras
    'ar': 'العربية (Árabe)',
    'tr': 'Türkçe (Turco)',
    'he': 'עברית (Hebreo)',
    'el': 'Ελληνικά (Griego)',
    'fa': 'فارسی (Persa)',
  };

  static String label(String code) => opciones[code] ?? code;

  static bool esEspanol(String code) => code.startsWith('es');

  /// Mapea el código de idioma al locale para reconocimiento de voz.
  static String localeVoz(String code) {
    if (code.startsWith('es')) return 'es_ES';
    if (code.startsWith('en')) return 'en_US';
    if (code.startsWith('pt')) return 'pt_BR';
    if (code.startsWith('zh')) return 'zh_CN';
    return switch (code) {
      'fr' => 'fr_FR',
      'it' => 'it_IT',
      'de' => 'de_DE',
      'ja' => 'ja_JP',
      'ko' => 'ko_KR',
      'ru' => 'ru_RU',
      'ar' => 'ar_SA',
      'hi' => 'hi_IN',
      'tr' => 'tr_TR',
      'nl' => 'nl_NL',
      'pl' => 'pl_PL',
      'id' => 'id_ID',
      'th' => 'th_TH',
      'vi' => 'vi_VN',
      _ => 'es_ES',
    };
  }
}
