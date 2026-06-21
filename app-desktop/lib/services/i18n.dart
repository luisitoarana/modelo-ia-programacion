import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Sistema de internacionalización ligero, sin paquetes externos.
///
/// Diseño:
///   - Singleton con `ValueNotifier<UiLang>` para que cualquier widget
///     pueda rerenderizar al cambiar idioma.
///   - 2 idiomas: 'es' (default) y 'en'.
///   - `t(key)` devuelve la traducción del idioma actual, o cae a español
///     si la clave falta. Esto hace que añadir claves sea incremental
///     y nunca rompa.
///   - Persistido en SharedPreferences.
///
/// Uso en widgets:
///   ```dart
///   ValueListenableBuilder<UiLang>(
///     valueListenable: I18n.instance.idioma,
///     builder: (_, lang, __) => Text(I18n.t('sidebar.nuevo_chat')),
///   );
///   ```
/// Para una página entera sólo necesitas el ValueListenableBuilder
/// arriba del subtree que quieres re-renderizar.

enum UiLang { es, en }

const _kKey = 'explicador.ui_lang';

class I18n {
  I18n._();
  static final I18n instance = I18n._();

  final ValueNotifier<UiLang> idioma = ValueNotifier<UiLang>(UiLang.es);

  Future<void> cargar() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_kKey);
    idioma.value = v == 'en' ? UiLang.en : UiLang.es;
  }

  Future<void> setIdioma(UiLang lang) async {
    idioma.value = lang;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kKey, lang == UiLang.en ? 'en' : 'es');
  }

  /// Traduce una clave usando el idioma actual.
  /// Si la clave no existe en el idioma actual cae al español.
  static String t(String key) {
    final lang = instance.idioma.value;
    final dict = lang == UiLang.en ? _EN : _ES;
    return dict[key] ?? _ES[key] ?? key;
  }
}

const Map<String, String> _ES = {
  // Sidebar
  'sidebar.nuevo_chat': 'Nuevo chat',
  'sidebar.buscar': 'Buscar',
  'sidebar.chat': 'Chat',
  'sidebar.explicar': 'Explicar código',
  'sidebar.explorador': 'Mi PC',
  'sidebar.terminal': 'Terminal',
  'sidebar.recientes': 'Recientes',
  'sidebar.hoy': 'Hoy',
  'sidebar.ayer': 'Ayer',
  'sidebar.ultima_semana': 'Últimos 7 días',
  'sidebar.mas_antiguas': 'Anteriores',

  // Header del chat
  'chat.nueva': 'Nueva conversación',
  'chat.exportar': 'Exportar',

  // Bienvenida
  'bienvenida.titulo': '¿En qué puedo ayudarte hoy?',
  'bienvenida.subtitulo': 'Hazme una pregunta sobre Python y te explico paso a paso.',

  // Composer
  'composer.placeholder': 'Escribe tu pregunta…',
  'composer.enviar': 'Enviar',
  'composer.adjuntar': 'Adjuntar archivo',
  'composer.mic': 'Dictar por voz',
  'composer.web': 'Buscar en internet',

  // Common
  'common.cancelar': 'Cancelar',
  'common.confirmar': 'Confirmar',
  'common.eliminar': 'Eliminar',
  'common.cerrar': 'Cerrar',
  'common.cerrar_sesion': 'Cerrar sesión',
  'common.exportar': 'Exportar',
  'common.cargando': 'Cargando…',
  'common.guardar': 'Guardar',

  // Configuración
  'config.titulo': 'Configuración',
  'config.cuenta': 'Cuenta',
  'config.apariencia': 'Apariencia',
  'config.idioma': 'Idioma',
  'config.capacidades': 'Capacidades',
  'config.voz': 'Voz',
  'config.privacidad': 'Privacidad y seguridad',
  'config.notificaciones': 'Notificaciones',
  'config.atajos': 'Atajos de teclado',
  'config.exportar': 'Exportar',
  'config.ayuda': 'Ayuda',
  'config.avanzado': 'Avanzado',
  'config.grupo.configuracion': 'Configuración',
  'config.grupo.aplicacion': 'Aplicación',
  'config.grupo.avanzado': 'Avanzado',

  // Apariencia
  'apariencia.tema': 'Tema',
  'apariencia.modo': 'Modo de color',
  'apariencia.claro': 'Claro',
  'apariencia.oscuro': 'Oscuro',
  'apariencia.auto': 'Auto',
  'apariencia.paleta': 'Paleta de colores',

  // Command palette
  'palette.placeholder': 'Buscar acciones, páginas y conversaciones…',
  'palette.sin_resultados': 'Sin resultados',
  'palette.navegar': 'navegar',
  'palette.seleccionar': 'seleccionar',
  'palette.resultados': 'resultados',
  'palette.s_acciones': 'Acciones',
  'palette.s_navegacion': 'Navegación',
  'palette.s_configuracion': 'Configuración',
  'palette.s_conversaciones': 'Conversaciones',

  // Comandos
  'cmd.nuevo_chat': 'Nuevo chat',
  'cmd.tema_claro': 'Cambiar a tema claro',
  'cmd.tema_oscuro': 'Cambiar a tema oscuro',
  'cmd.exportar_chat': 'Exportar conversación actual',
  'cmd.ir_chat': 'Ir al chat',
  'cmd.ir_explicar': 'Explicar código',
  'cmd.ir_explorador': 'Explorador (Mi PC)',
  'cmd.ir_terminal': 'Terminal',
  'cmd.configuracion': 'Abrir configuración',
  'cmd.apariencia': 'Cambiar paleta de colores',
  'cmd.atajos': 'Ver atajos de teclado',
  'cmd.cerrar_sesion': 'Cerrar sesión',
  'cmd.abrir_conv': 'Abrir conversación',

  // Onboarding
  'tour.empezar': 'Empezar',
  'tour.siguiente': 'Siguiente',
  'tour.atras': 'Atrás',
  'tour.terminar': 'Terminar',
  'tour.saltar': 'Saltar tutorial',
  'tour.1.titulo': 'Bienvenido a Explicador IA',
  'tour.1.subtitulo': 'Plataforma educativa para Python con tu propio LLM',
  'tour.1.desc': 'Te voy a guiar en menos de 30 segundos por las funciones más útiles. Puedes saltarlo y siempre volver desde Configuración → Ayuda.',
  'tour.2.titulo': 'Pregunta lo que sea',
  'tour.2.subtitulo': 'En lenguaje natural, como a un profesor',
  'tour.2.desc': 'Escribe en el chat preguntas tipo "explícame qué es una función lambda". El sistema busca primero en su conocimiento propio y, si no encuentra, consulta una API.',
  'tour.3.titulo': 'Atajos de teclado',
  'tour.3.subtitulo': 'Acelera tu uso del sistema',
  'tour.4.titulo': 'Personaliza el aspecto',
  'tour.4.subtitulo': '5 paletas + modo claro/oscuro',
  'tour.4.desc': 'En Configuración → Apariencia puedes elegir entre 5 paletas que cambian toda la app instantáneamente. Útil para tu defensa de tesis.',
  'tour.5.titulo': 'Voz, archivos y vistas',
  'tour.5.subtitulo': 'Funciones avanzadas',
  'tour.5.desc': 'Activa el micrófono para dictar; explora tu PC desde la vista Explorador; usa la terminal integrada para correr scripts.',

  // Atajos
  'atajos.titulo': 'Atajos de teclado',
  'atajos.macos_hint': 'En macOS usa ⌘ en lugar de Ctrl.',
};

const Map<String, String> _EN = {
  // Sidebar
  'sidebar.nuevo_chat': 'New chat',
  'sidebar.buscar': 'Search',
  'sidebar.chat': 'Chat',
  'sidebar.explicar': 'Explain code',
  'sidebar.explorador': 'My PC',
  'sidebar.terminal': 'Terminal',
  'sidebar.recientes': 'Recent',
  'sidebar.hoy': 'Today',
  'sidebar.ayer': 'Yesterday',
  'sidebar.ultima_semana': 'Last 7 days',
  'sidebar.mas_antiguas': 'Older',

  // Header del chat
  'chat.nueva': 'New conversation',
  'chat.exportar': 'Export',

  // Bienvenida
  'bienvenida.titulo': 'How can I help you today?',
  'bienvenida.subtitulo': 'Ask me anything about Python and I’ll walk you through it.',

  // Composer
  'composer.placeholder': 'Type your question…',
  'composer.enviar': 'Send',
  'composer.adjuntar': 'Attach file',
  'composer.mic': 'Voice dictation',
  'composer.web': 'Search the web',

  // Common
  'common.cancelar': 'Cancel',
  'common.confirmar': 'Confirm',
  'common.eliminar': 'Delete',
  'common.cerrar': 'Close',
  'common.cerrar_sesion': 'Log out',
  'common.exportar': 'Export',
  'common.cargando': 'Loading…',
  'common.guardar': 'Save',

  // Configuración
  'config.titulo': 'Settings',
  'config.cuenta': 'Account',
  'config.apariencia': 'Appearance',
  'config.idioma': 'Language',
  'config.capacidades': 'Capabilities',
  'config.voz': 'Voice',
  'config.privacidad': 'Privacy & security',
  'config.notificaciones': 'Notifications',
  'config.atajos': 'Keyboard shortcuts',
  'config.exportar': 'Export',
  'config.ayuda': 'Help',
  'config.avanzado': 'Advanced',
  'config.grupo.configuracion': 'Settings',
  'config.grupo.aplicacion': 'Application',
  'config.grupo.avanzado': 'Advanced',

  // Apariencia
  'apariencia.tema': 'Theme',
  'apariencia.modo': 'Color mode',
  'apariencia.claro': 'Light',
  'apariencia.oscuro': 'Dark',
  'apariencia.auto': 'Auto',
  'apariencia.paleta': 'Color palette',

  // Command palette
  'palette.placeholder': 'Search actions, pages and conversations…',
  'palette.sin_resultados': 'No results',
  'palette.navegar': 'navigate',
  'palette.seleccionar': 'select',
  'palette.resultados': 'results',
  'palette.s_acciones': 'Actions',
  'palette.s_navegacion': 'Navigation',
  'palette.s_configuracion': 'Settings',
  'palette.s_conversaciones': 'Conversations',

  // Comandos
  'cmd.nuevo_chat': 'New chat',
  'cmd.tema_claro': 'Switch to light theme',
  'cmd.tema_oscuro': 'Switch to dark theme',
  'cmd.exportar_chat': 'Export current conversation',
  'cmd.ir_chat': 'Go to chat',
  'cmd.ir_explicar': 'Explain code',
  'cmd.ir_explorador': 'Explorer (My PC)',
  'cmd.ir_terminal': 'Terminal',
  'cmd.configuracion': 'Open settings',
  'cmd.apariencia': 'Change color palette',
  'cmd.atajos': 'View keyboard shortcuts',
  'cmd.cerrar_sesion': 'Log out',
  'cmd.abrir_conv': 'Open conversation',

  // Onboarding
  'tour.empezar': 'Start',
  'tour.siguiente': 'Next',
  'tour.atras': 'Back',
  'tour.terminar': 'Finish',
  'tour.saltar': 'Skip tutorial',
  'tour.1.titulo': 'Welcome to Explicador IA',
  'tour.1.subtitulo': 'Educational platform for Python with your own LLM',
  'tour.1.desc': 'I\'ll walk you through the most useful features in under 30 seconds. You can skip it and reopen it anytime from Settings → Help.',
  'tour.2.titulo': 'Ask anything',
  'tour.2.subtitulo': 'In natural language, like to a teacher',
  'tour.2.desc': 'Type questions like "explain what a lambda function is". The system first searches its own knowledge base; if nothing matches, it queries an API.',
  'tour.3.titulo': 'Keyboard shortcuts',
  'tour.3.subtitulo': 'Speed up how you use the system',
  'tour.4.titulo': 'Make it yours',
  'tour.4.subtitulo': '5 palettes + light/dark mode',
  'tour.4.desc': 'In Settings → Appearance you can pick from 5 palettes that instantly change the whole app. Great for your thesis defense.',
  'tour.5.titulo': 'Voice, files & views',
  'tour.5.subtitulo': 'Advanced features',
  'tour.5.desc': 'Enable the mic to dictate; browse your PC from the Explorer view; use the built-in terminal to run scripts.',

  // Atajos
  'atajos.titulo': 'Keyboard shortcuts',
  'atajos.macos_hint': 'On macOS use ⌘ instead of Ctrl.',
};
