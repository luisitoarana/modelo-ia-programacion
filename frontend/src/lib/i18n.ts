/**
 * Sistema i18n ligero sin dependencias.
 *
 * Cómo funciona:
 *   - 2 idiomas de UI: 'es' (por defecto) y 'en'.
 *   - El idioma se guarda en localStorage como `explicador.ui_lang`.
 *   - Hook useT() devuelve { t, lang, setLang } y rerenderiza al cambiar.
 *   - Si una clave no existe en el idioma actual, cae al español.
 *
 * Limitaciones honestas: cubre la UI más visible (sidebar, header,
 * settings, bienvenida). El resto sigue en español hasta completar el
 * diccionario. Es 100% incremental — añadir una clave nueva nunca rompe.
 */
import { useEffect, useState, useCallback } from 'react';

export type UiLang = 'es' | 'en';

type Dict = Record<string, string>;

const ES: Dict = {
  // Sidebar y navegación
  'sidebar.nuevo_chat': 'Nuevo chat',
  'sidebar.buscar': 'Buscar',
  'sidebar.sin_chats': 'Aún no hay conversaciones',
  'sidebar.hoy': 'Hoy',
  'sidebar.ayer': 'Ayer',
  'sidebar.ultima_semana': 'Última semana',
  'sidebar.ultimo_mes': 'Último mes',
  'sidebar.mas_antiguas': 'Más antiguas',

  // Bienvenida
  'bienvenida.titulo': '¿En qué puedo ayudarte hoy?',
  'bienvenida.subtitulo': 'Hazme una pregunta sobre Python y te explico paso a paso.',
  'bienvenida.sugerencia.1': 'Explícame qué es una función lambda',
  'bienvenida.sugerencia.2': 'Genera un ejemplo de list comprehension',
  'bienvenida.sugerencia.3': 'Diferencia entre lista y tupla',

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
  'common.guardar': 'Guardar',
  'common.cerrar': 'Cerrar',
  'common.cerrar_sesion': 'Cerrar sesión',
  'common.exportar': 'Exportar',
  'common.cargando': 'Cargando…',

  // Configuración (top-level)
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
  'config.admin': 'Acceso administrador',
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

  // Header del chat
  'chat.nueva': 'Nueva conversación',
  'chat.exportar': 'Exportar',
};

const EN: Dict = {
  'sidebar.nuevo_chat': 'New chat',
  'sidebar.buscar': 'Search',
  'sidebar.sin_chats': 'No conversations yet',
  'sidebar.hoy': 'Today',
  'sidebar.ayer': 'Yesterday',
  'sidebar.ultima_semana': 'Last week',
  'sidebar.ultimo_mes': 'Last month',
  'sidebar.mas_antiguas': 'Older',

  'bienvenida.titulo': 'How can I help you today?',
  'bienvenida.subtitulo': 'Ask me anything about Python and I’ll walk you through it.',
  'bienvenida.sugerencia.1': 'Explain what a lambda function is',
  'bienvenida.sugerencia.2': 'Show me a list comprehension example',
  'bienvenida.sugerencia.3': 'Difference between list and tuple',

  'composer.placeholder': 'Type your question…',
  'composer.enviar': 'Send',
  'composer.adjuntar': 'Attach file',
  'composer.mic': 'Voice dictation',
  'composer.web': 'Search the web',

  'common.cancelar': 'Cancel',
  'common.confirmar': 'Confirm',
  'common.eliminar': 'Delete',
  'common.guardar': 'Save',
  'common.cerrar': 'Close',
  'common.cerrar_sesion': 'Log out',
  'common.exportar': 'Export',
  'common.cargando': 'Loading…',

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
  'config.admin': 'Admin access',
  'config.grupo.configuracion': 'Settings',
  'config.grupo.aplicacion': 'Application',
  'config.grupo.avanzado': 'Advanced',

  'apariencia.tema': 'Theme',
  'apariencia.modo': 'Color mode',
  'apariencia.claro': 'Light',
  'apariencia.oscuro': 'Dark',
  'apariencia.auto': 'Auto',
  'apariencia.paleta': 'Color palette',

  'chat.nueva': 'New conversation',
  'chat.exportar': 'Export',
};

const DICTS: Record<UiLang, Dict> = { es: ES, en: EN };

const STORAGE_KEY = 'explicador.ui_lang';

/** Lee el idioma guardado o devuelve 'es' por defecto. */
export function getUiLang(): UiLang {
  if (typeof window === 'undefined') return 'es';
  const v = window.localStorage.getItem(STORAGE_KEY);
  return v === 'en' ? 'en' : 'es';
}

/** Cambia el idioma y notifica al resto de la app. */
export function setUiLang(lang: UiLang) {
  if (typeof window === 'undefined') return;
  window.localStorage.setItem(STORAGE_KEY, lang);
  window.dispatchEvent(new CustomEvent('explicador:ui-lang-changed', { detail: lang }));
}

/** Traduce una clave usando el idioma actual. */
export function t(key: string, lang?: UiLang): string {
  const l = lang ?? getUiLang();
  return DICTS[l][key] ?? ES[key] ?? key;
}

/**
 * Hook que devuelve { t, lang, setLang } y rerenderiza al cambiar el
 * idioma vía evento custom. Úsalo en cualquier componente para que
 * las traducciones se actualicen instantáneamente al cambiar.
 */
export function useT() {
  const [lang, setLang] = useState<UiLang>('es');

  useEffect(() => {
    setLang(getUiLang());
    function onChange(e: Event) {
      const detail = (e as CustomEvent).detail as UiLang;
      setLang(detail);
    }
    window.addEventListener('explicador:ui-lang-changed', onChange);
    return () => window.removeEventListener('explicador:ui-lang-changed', onChange);
  }, []);

  const translate = useCallback((key: string) => t(key, lang), [lang]);

  return {
    t: translate,
    lang,
    setLang: (l: UiLang) => setUiLang(l),
  };
}
