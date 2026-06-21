import { useEffect, useState, useMemo } from 'react';
import Link from 'next/link';
import { useRouter } from 'next/router';
import { useTheme } from 'next-themes';
import {
  X, Search, User, Palette, Languages, ShieldCheck, HelpCircle,
  Sparkles, Bell, Lock, Sun, Moon, Monitor, Keyboard, Mic,
  Download, Brush, Volume2, Cog, AlertCircle, Check, ExternalLink,
  Github, Mail, ArrowRight, Info
} from 'lucide-react';
import { Card, CardHeader, CardBody } from '@/components/ui/Card';
import Button from '@/components/ui/Button';
import Badge from '@/components/ui/Badge';
import { getToken, setToken } from '@/services/api';
import { obtenerPerfil, UsuarioPerfil } from '@/services/auth';
import { listarConversaciones, obtenerConversacion } from '@/services/chat';
import { cn } from '@/lib/cn';
import { useT, UiLang } from '@/lib/i18n';

// ─────────────────────────── Idiomas para el asistente ───────────────────────────

const IDIOMAS: Record<string, string> = {
  'es': 'Español',
  'es-419': 'Español (Latinoamérica)',
  'es-ES': 'Español (España)',
  'es-MX': 'Español (México)',
  'es-AR': 'Español (Argentina)',
  'en': 'English',
  'en-US': 'English (US)',
  'en-GB': 'English (UK)',
  'pt': 'Português',
  'pt-BR': 'Português (Brasil)',
  'fr': 'Français',
  'it': 'Italiano',
  'de': 'Deutsch',
  'nl': 'Nederlands',
  'ru': 'Русский',
  'zh': '中文 (Mandarín simplificado)',
  'zh-TW': '繁體中文 (Mandarín tradicional)',
  'ja': '日本語',
  'ko': '한국어',
  'hi': 'हिन्दी',
  'ar': 'العربية',
  'tr': 'Türkçe',
  'pl': 'Polski',
  'vi': 'Tiếng Việt',
  'id': 'Bahasa Indonesia',
  'th': 'ภาษาไทย'
};

// ─────────────────────────── Paletas de color ───────────────────────────

const PALETAS = [
  {
    id: 'terracota',
    nombre: 'Terracota (Anthropic)',
    descripcion: 'La paleta original. Cálida, cercana, tipo papel.',
    swatches: ['#d97757', '#faf9f5', '#1f1e1b'],
    light: {
      bg: '#faf9f5', surface: '#ffffff', 'surface-2': '#f0efe7',
      'surface-3': '#e8e6da', border: '#e5e2d6', 'border-soft': '#edebe0',
      text: '#1f1e1b', muted: '#6b6a5e', subtle: '#8e8c7e',
      primary: '#d97757', 'primary-hover': '#c96644', 'primary-soft': '#f3d8c8',
      accent: '#b85c3e', 'accent-soft': '#efd5c5'
    },
    dark: {
      bg: '#262624', surface: '#30302e', 'surface-2': '#3a3a37',
      'surface-3': '#45453f', border: '#3d3d3a', 'border-soft': '#333330',
      text: '#f5f4ed', muted: '#b8b5a8', subtle: '#8a8779',
      primary: '#d97757', 'primary-hover': '#e58a6a', 'primary-soft': '#4a2e22',
      accent: '#c97052', 'accent-soft': '#3a1f15'
    }
  },
  {
    id: 'academico',
    nombre: 'Académico Azul',
    descripcion: 'Sobrio y profesional. Para defensa de tesis universitaria.',
    swatches: ['#2563eb', '#f8fafc', '#0f172a'],
    light: {
      bg: '#f8fafc', surface: '#ffffff', 'surface-2': '#f1f5f9',
      'surface-3': '#e2e8f0', border: '#e2e8f0', 'border-soft': '#eef2f8',
      text: '#0f172a', muted: '#475569', subtle: '#94a3b8',
      primary: '#2563eb', 'primary-hover': '#1d4ed8', 'primary-soft': '#dbeafe',
      accent: '#7c3aed', 'accent-soft': '#ede9fe'
    },
    dark: {
      bg: '#0a0f1d', surface: '#0f172a', 'surface-2': '#18233a',
      'surface-3': '#24324a', border: '#24324a', 'border-soft': '#1e293b',
      text: '#e6edf6', muted: '#94a3b8', subtle: '#64748b',
      primary: '#3b82f6', 'primary-hover': '#60a5fa', 'primary-soft': '#1e3a8a',
      accent: '#8b5cf6', 'accent-soft': '#2e1065'
    }
  },
  {
    id: 'bosque',
    nombre: 'Verde Bosque',
    descripcion: 'Tranquilo y natural. Tonos crema y verde profundo.',
    swatches: ['#16a34a', '#f7f5ef', '#1c2316'],
    light: {
      bg: '#f7f5ef', surface: '#ffffff', 'surface-2': '#ecebe2',
      'surface-3': '#dde0d3', border: '#dde0d3', 'border-soft': '#e8e6db',
      text: '#1c2316', muted: '#5c6b54', subtle: '#8a9684',
      primary: '#16a34a', 'primary-hover': '#15803d', 'primary-soft': '#bbf7d0',
      accent: '#d97706', 'accent-soft': '#fed7aa'
    },
    dark: {
      bg: '#1a201a', surface: '#262d24', 'surface-2': '#2f3a2d',
      'surface-3': '#3a4737', border: '#3a4737', 'border-soft': '#2f3a2d',
      text: '#eef0ea', muted: '#b8bcaf', subtle: '#7e8479',
      primary: '#22c55e', 'primary-hover': '#4ade80', 'primary-soft': '#14532d',
      accent: '#f59e0b', 'accent-soft': '#451a03'
    }
  },
  {
    id: 'purpura',
    nombre: 'Púrpura Real',
    descripcion: 'Elegante y creativo. Violetas y lavandas suaves.',
    swatches: ['#8b5cf6', '#faf8ff', '#1c1530'],
    light: {
      bg: '#faf8ff', surface: '#ffffff', 'surface-2': '#f1edfa',
      'surface-3': '#e6ddf5', border: '#e6ddf5', 'border-soft': '#f1edfa',
      text: '#1c1530', muted: '#5c5072', subtle: '#9690a8',
      primary: '#8b5cf6', 'primary-hover': '#7c3aed', 'primary-soft': '#ede9fe',
      accent: '#ec4899', 'accent-soft': '#fce7f3'
    },
    dark: {
      bg: '#1a142a', surface: '#251d3a', 'surface-2': '#322752',
      'surface-3': '#3f3266', border: '#3f3266', 'border-soft': '#322752',
      text: '#eee9f7', muted: '#b5acc9', subtle: '#7d75a0',
      primary: '#a78bfa', 'primary-hover': '#c4b5fd', 'primary-soft': '#4c1d95',
      accent: '#f472b6', 'accent-soft': '#831843'
    }
  },
  {
    id: 'mono',
    nombre: 'Minimalista',
    descripcion: 'Solo grises. Foco máximo en el contenido.',
    swatches: ['#404040', '#fafafa', '#171717'],
    light: {
      bg: '#fafafa', surface: '#ffffff', 'surface-2': '#f4f4f5',
      'surface-3': '#e4e4e7', border: '#e4e4e7', 'border-soft': '#f4f4f5',
      text: '#171717', muted: '#525252', subtle: '#a3a3a3',
      primary: '#404040', 'primary-hover': '#262626', 'primary-soft': '#d4d4d8',
      accent: '#737373', 'accent-soft': '#e5e5e5'
    },
    dark: {
      bg: '#0a0a0a', surface: '#171717', 'surface-2': '#262626',
      'surface-3': '#404040', border: '#404040', 'border-soft': '#262626',
      text: '#fafafa', muted: '#a3a3a3', subtle: '#737373',
      primary: '#e5e5e5', 'primary-hover': '#fafafa', 'primary-soft': '#404040',
      accent: '#a3a3a3', 'accent-soft': '#262626'
    }
  }
];

// ─────────────────────────── Atajos de teclado ───────────────────────────

const ATAJOS = [
  { combo: ['Ctrl', 'K'], descripcion: 'Buscar en conversaciones' },
  { combo: ['Ctrl', 'N'], descripcion: 'Nuevo chat' },
  { combo: ['Ctrl', ','], descripcion: 'Abrir configuración' },
  { combo: ['Ctrl', '/'], descripcion: 'Mostrar atajos' },
  { combo: ['Ctrl', 'B'], descripcion: 'Colapsar/expandir sidebar' },
  { combo: ['Ctrl', 'Enter'], descripcion: 'Enviar mensaje' },
  { combo: ['Ctrl', 'Shift', 'L'], descripcion: 'Alternar tema claro/oscuro' },
  { combo: ['Shift', 'Enter'], descripcion: 'Nueva línea en composer' },
  { combo: ['Esc'], descripcion: 'Cerrar modal / volver' },
  { combo: ['↑'], descripcion: 'Mensaje anterior (en composer vacío)' },
  { combo: ['↓'], descripcion: 'Mensaje siguiente (en composer vacío)' }
];

// ─────────────────────────── Helpers de persistencia ───────────────────────────

const KEYS = {
  idioma: 'explicador.idioma',
  buscarWeb: 'explicador.buscar_web',
  paleta: 'explicador.paleta',
  ttsHabilitado: 'explicador.tts',
  ttsVoice: 'explicador.tts_voice',
  ttsRate: 'explicador.tts_rate',
  notif: 'explicador.notif'
};

function leerLocal(k: string, def: string) {
  if (typeof window === 'undefined') return def;
  return window.localStorage.getItem(k) ?? def;
}
function escribirLocal(k: string, v: string) {
  if (typeof window === 'undefined') return;
  window.localStorage.setItem(k, v);
}

// ─────────────────────────── Aplicar paleta a CSS vars ───────────────────────────

function aplicarPaleta(paletaId: string, tema: 'light' | 'dark') {
  if (typeof window === 'undefined') return;
  const paleta = PALETAS.find((p) => p.id === paletaId);
  if (!paleta) return;
  const colores = tema === 'dark' ? paleta.dark : paleta.light;
  const root = document.documentElement;
  Object.entries(colores).forEach(([key, value]) => {
    root.style.setProperty(`--${key}`, value);
  });
}

// ─────────────────────────── Secciones del menú ───────────────────────────

type SectionId =
  | 'cuenta' | 'apariencia' | 'idioma' | 'capacidades'
  | 'voz' | 'atajos' | 'exportar' | 'privacidad'
  | 'notificaciones' | 'ayuda' | 'admin' | 'mcp';

interface Section {
  id: SectionId;
  label: string;
  icon: React.ReactNode;
  group?: string;
  badge?: string;
}

// ═══════════════════════════════════════════════════════════════════════════
//                           PÁGINA PRINCIPAL
// ═══════════════════════════════════════════════════════════════════════════

export default function ConfiguracionPage() {
  const router = useRouter();
  const { theme, resolvedTheme } = useTheme();
  const [usuario, setUsuario] = useState<UsuarioPerfil | null>(null);
  const [activa, setActiva] = useState<SectionId>('cuenta');
  const [busqueda, setBusqueda] = useState('');

  useEffect(() => {
    if (!getToken()) {
      router.replace('/login');
      return;
    }
    obtenerPerfil().then(setUsuario).catch(() => router.replace('/login'));
  }, [router]);

  // Abrir sección específica via ?seccion=apariencia
  useEffect(() => {
    const s = router.query.seccion;
    if (typeof s === 'string') {
      setActiva(s as SectionId);
    }
  }, [router.query.seccion]);

  // Aplicar paleta guardada al cargar.
  useEffect(() => {
    const paletaId = leerLocal(KEYS.paleta, 'terracota');
    const t = (resolvedTheme === 'dark' ? 'dark' : 'light') as 'light' | 'dark';
    aplicarPaleta(paletaId, t);
  }, [resolvedTheme]);

  const esAdmin = usuario?.rol === 'administrador';

  const SECCIONES: Section[] = useMemo(() => ([
    { id: 'cuenta', label: 'Cuenta', icon: <User size={15} />, group: 'Configuración' },
    { id: 'apariencia', label: 'Apariencia', icon: <Palette size={15} />, group: 'Configuración' },
    { id: 'idioma', label: 'Idioma', icon: <Languages size={15} />, group: 'Configuración' },
    { id: 'capacidades', label: 'Capacidades', icon: <Sparkles size={15} />, group: 'Configuración' },
    { id: 'voz', label: 'Voz', icon: <Mic size={15} />, group: 'Configuración' },
    { id: 'privacidad', label: 'Privacidad y seguridad', icon: <Lock size={15} />, group: 'Configuración' },
    { id: 'notificaciones', label: 'Notificaciones', icon: <Bell size={15} />, group: 'Configuración' },

    { id: 'atajos', label: 'Atajos de teclado', icon: <Keyboard size={15} />, group: 'Aplicación' },
    { id: 'exportar', label: 'Exportar', icon: <Download size={15} />, group: 'Aplicación' },
    { id: 'ayuda', label: 'Ayuda', icon: <HelpCircle size={15} />, group: 'Aplicación' },
    ...(esAdmin ? [
      { id: 'mcp' as SectionId, label: 'MCP (Tools del sistema)', icon: <Cog size={15} />, group: 'Avanzado', badge: 'BETA' },
      { id: 'admin' as SectionId, label: 'Acceso administrador', icon: <ShieldCheck size={15} />, group: 'Avanzado' },
    ] : [])
  ]), [esAdmin]);

  const seccionesFiltradas = useMemo(() => {
    if (!busqueda.trim()) return SECCIONES;
    const q = busqueda.toLowerCase();
    return SECCIONES.filter((s) => s.label.toLowerCase().includes(q));
  }, [busqueda, SECCIONES]);

  const grupos = useMemo(() => {
    const map = new Map<string, Section[]>();
    seccionesFiltradas.forEach((s) => {
      const g = s.group ?? 'Otros';
      if (!map.has(g)) map.set(g, []);
      map.get(g)!.push(s);
    });
    return Array.from(map.entries());
  }, [seccionesFiltradas]);

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 backdrop-blur-sm animate-fade-in">
      <div
        className="relative flex h-[88vh] max-h-[760px] w-[94vw] max-w-[1200px] overflow-hidden rounded-2xl border border-border-soft bg-bg shadow-elevated"
        onClick={(e) => e.stopPropagation()}
      >
        {/* Sidebar */}
        <aside className="flex w-64 shrink-0 flex-col border-r border-border-soft bg-surface">
          {/* Búsqueda */}
          <div className="p-3">
            <div className="flex items-center gap-2 rounded-lg border border-border-soft bg-surface-2 px-3 py-2">
              <Search size={13} className="text-subtle" />
              <input
                value={busqueda}
                onChange={(e) => setBusqueda(e.target.value)}
                placeholder="Buscar"
                className="flex-1 bg-transparent text-sm text-text placeholder:text-subtle focus:outline-none"
              />
              {busqueda && (
                <button onClick={() => setBusqueda('')} className="text-subtle hover:text-text">
                  <X size={12} />
                </button>
              )}
            </div>
          </div>

          {/* Grupos de secciones */}
          <nav className="flex-1 overflow-y-auto px-2 pb-2">
            {grupos.map(([grupo, items]) => (
              <div key={grupo} className="mb-3">
                <div className="px-2 pb-1 text-[10.5px] font-semibold uppercase tracking-wider text-subtle">
                  {grupo}
                </div>
                <div className="flex flex-col gap-0.5">
                  {items.map((s) => (
                    <button
                      key={s.id}
                      onClick={() => setActiva(s.id)}
                      className={cn(
                        'flex items-center gap-2.5 rounded-lg px-2.5 py-2 text-[13px] text-left transition-colors',
                        activa === s.id
                          ? 'bg-surface-2 text-text font-medium'
                          : 'text-muted hover:bg-surface-2/60 hover:text-text'
                      )}
                    >
                      <span className={activa === s.id ? 'text-primary' : 'text-muted'}>
                        {s.icon}
                      </span>
                      <span className="flex-1">{s.label}</span>
                      {s.badge && (
                        <span className="text-[10px] text-subtle uppercase tracking-wider">
                          {s.badge}
                        </span>
                      )}
                    </button>
                  ))}
                </div>
              </div>
            ))}
          </nav>
        </aside>

        {/* Contenido */}
        <main className="relative flex-1 overflow-y-auto">
          {/* Botón cerrar */}
          <button
            onClick={() => router.back()}
            className="absolute right-4 top-4 z-10 rounded-lg p-2 text-muted hover:bg-surface-2 hover:text-text transition-colors"
          >
            <X size={18} />
          </button>

          <div className="px-10 py-8 max-w-3xl">
            {activa === 'cuenta' && <SeccionCuenta usuario={usuario} onLogout={() => {
              setToken(null);
              router.replace('/login');
            }} />}
            {activa === 'apariencia' && <SeccionApariencia />}
            {activa === 'idioma' && <SeccionIdioma />}
            {activa === 'capacidades' && <SeccionCapacidades />}
            {activa === 'voz' && <SeccionVoz />}
            {activa === 'privacidad' && <SeccionPrivacidad />}
            {activa === 'notificaciones' && <SeccionNotificaciones />}
            {activa === 'atajos' && <SeccionAtajos />}
            {activa === 'exportar' && <SeccionExportar />}
            {activa === 'ayuda' && <SeccionAyuda usuario={usuario} />}
            {activa === 'admin' && esAdmin && <SeccionAdmin />}
            {activa === 'mcp' && esAdmin && <SeccionMcp />}
          </div>
        </main>
      </div>
    </div>
  );
}

// ═══════════════════════════════════════════════════════════════════════════
//                           SECCIONES
// ═══════════════════════════════════════════════════════════════════════════

function TituloSeccion({ titulo, descripcion }: { titulo: string; descripcion?: string }) {
  return (
    <div className="mb-8">
      <h2 className="font-serif text-2xl text-text">{titulo}</h2>
      {descripcion && <p className="mt-1 text-sm text-muted">{descripcion}</p>}
    </div>
  );
}

function SubTitulo({ titulo }: { titulo: string }) {
  return (
    <h3 className="text-base font-semibold text-text mt-6 mb-3 first:mt-0">{titulo}</h3>
  );
}

function Fila({
  etiqueta, descripcion, children
}: {
  etiqueta: string;
  descripcion?: string;
  children: React.ReactNode;
}) {
  return (
    <div className="flex items-start justify-between gap-4 py-3 border-b border-border-soft last:border-0">
      <div className="flex-1 min-w-0">
        <div className="text-sm font-medium text-text">{etiqueta}</div>
        {descripcion && <div className="text-xs text-muted mt-0.5 leading-relaxed">{descripcion}</div>}
      </div>
      <div className="shrink-0">{children}</div>
    </div>
  );
}

function ToggleSwitch({ value, onChange }: { value: boolean; onChange: (v: boolean) => void }) {
  const [pressed, setPressed] = useState(false);
  return (
    <button
      type="button"
      role="switch"
      aria-checked={value}
      onClick={() => onChange(!value)}
      onMouseDown={() => setPressed(true)}
      onMouseUp={() => setPressed(false)}
      onMouseLeave={() => setPressed(false)}
      className={cn(
        'relative inline-flex h-7 w-12 shrink-0 cursor-pointer rounded-full transition-all duration-200',
        value
          ? 'bg-primary shadow-[0_2px_8px_-2px_color-mix(in_srgb,var(--primary)_50%,transparent)]'
          : 'bg-surface-3'
      )}
    >
      <span
        className={cn(
          'absolute top-1/2 -translate-y-1/2 h-[22px] w-[22px] rounded-full bg-white shadow-md transition-all duration-300',
          pressed && 'scale-[0.85]'
        )}
        style={{
          left: value ? '22px' : '3px',
          transitionTimingFunction: 'cubic-bezier(0.34, 1.56, 0.64, 1)'
        }}
      />
    </button>
  );
}

// ─────────────────────────── Cuenta ───────────────────────────

function SeccionCuenta({ usuario, onLogout }: { usuario: UsuarioPerfil | null; onLogout: () => void }) {
  const inicial = usuario?.nombre?.charAt(0)?.toUpperCase() ?? '?';
  return (
    <div>
      <TituloSeccion titulo="Cuenta" descripcion="Información de tu sesión activa." />

      <div className="flex items-center gap-4 pb-6 mb-2 border-b border-border-soft">
        <div className="flex h-14 w-14 items-center justify-center rounded-2xl bg-primary text-primary-foreground text-xl font-semibold shadow-soft">
          {inicial}
        </div>
        <div className="flex-1 min-w-0">
          <div className="text-base font-semibold text-text">{usuario?.nombre ?? '—'}</div>
          <div className="text-sm text-muted">{usuario?.email ?? '—'}</div>
          <div className="mt-1">
            <Badge tone={usuario?.rol === 'administrador' ? 'accent' : 'neutral'}>
              {usuario?.rol ?? '—'}
            </Badge>
          </div>
        </div>
      </div>

      {usuario?.institucion && (
        <Fila etiqueta="Institución">
          <span className="text-sm text-text">{usuario.institucion}</span>
        </Fila>
      )}

      <SubTitulo titulo="Sesión" />
      <Fila etiqueta="Estado de la sesión" descripcion="Estás autenticado con un JWT válido.">
        <span className="inline-flex items-center gap-1.5 text-xs text-success">
          <span className="h-1.5 w-1.5 rounded-full bg-success" />
          Activa
        </span>
      </Fila>
      <div className="mt-6">
        <button
          onClick={onLogout}
          className="inline-flex items-center gap-2 rounded-lg border border-danger/40 bg-danger/5 px-4 py-2 text-sm font-medium text-danger hover:bg-danger/10 transition-colors"
        >
          <ExternalLink size={14} />
          Cerrar sesión
        </button>
      </div>
    </div>
  );
}

// ─────────────────────────── Apariencia ───────────────────────────

function SeccionApariencia() {
  const { theme, setTheme, resolvedTheme } = useTheme();
  const [paletaActual, setPaletaActual] = useState('terracota');

  useEffect(() => {
    setPaletaActual(leerLocal(KEYS.paleta, 'terracota'));
  }, []);

  function cambiarPaleta(id: string) {
    setPaletaActual(id);
    escribirLocal(KEYS.paleta, id);
    const t = (resolvedTheme === 'dark' ? 'dark' : 'light') as 'light' | 'dark';
    aplicarPaleta(id, t);
  }

  return (
    <div>
      <TituloSeccion titulo="Apariencia" descripcion="Personaliza cómo se ve el sistema." />

      <SubTitulo titulo="Tema" />
      <Fila
        etiqueta="Modo de color"
        descripcion="Claro y Oscuro son fijos. Auto sigue el tema del sistema operativo."
      >
        <div className="flex gap-1.5">
          {([
            { v: 'light', l: 'Claro', i: <Sun size={13} /> },
            { v: 'dark', l: 'Oscuro', i: <Moon size={13} /> },
            { v: 'system', l: 'Auto', i: <Monitor size={13} /> }
          ] as const).map((o) => (
            <button
              key={o.v}
              onClick={() => setTheme(o.v)}
              className={cn(
                'inline-flex items-center gap-1.5 rounded-lg px-3 py-1.5 text-xs font-medium transition-colors',
                theme === o.v
                  ? 'bg-primary text-primary-foreground'
                  : 'border border-border-soft bg-surface text-muted hover:bg-surface-2'
              )}
            >
              {o.i}
              {o.l}
            </button>
          ))}
        </div>
      </Fila>

      <SubTitulo titulo="Paleta de colores" />
      <p className="text-xs text-muted mb-3 leading-relaxed">
        Cada paleta cambia toda la app: bordes, fondos, sombras, acentos. La paleta se aplica a ambos modos (claro y oscuro).
      </p>
      <div className="grid gap-3 sm:grid-cols-2">
        {PALETAS.map((p) => (
          <button
            key={p.id}
            onClick={() => cambiarPaleta(p.id)}
            className={cn(
              'group rounded-xl border p-4 text-left transition-all hover:shadow-soft',
              paletaActual === p.id
                ? 'border-primary bg-primary-soft/20'
                : 'border-border-soft bg-surface hover:border-border'
            )}
          >
            <div className="flex items-center gap-3 mb-2">
              <div className="flex">
                {p.swatches.map((c, i) => (
                  <span
                    key={i}
                    className="h-7 w-7 rounded-full border-2 border-surface -ml-2 first:ml-0 transition-transform group-hover:translate-x-0"
                    style={{ background: c }}
                  />
                ))}
              </div>
              {paletaActual === p.id && (
                <Check size={14} className="text-primary ml-auto" />
              )}
            </div>
            <div className="text-sm font-semibold text-text">{p.nombre}</div>
            <div className="text-xs text-subtle mt-0.5 leading-relaxed">{p.descripcion}</div>
          </button>
        ))}
      </div>
    </div>
  );
}

// ─────────────────────────── Idioma ───────────────────────────

function SeccionIdioma() {
  const [idioma, setIdioma] = useState('es');
  const { lang: uiLang, setLang: setUiLang } = useT();
  useEffect(() => { setIdioma(leerLocal(KEYS.idioma, 'es')); }, []);
  function cambiar(v: string) {
    setIdioma(v);
    escribirLocal(KEYS.idioma, v);
  }
  return (
    <div>
      <TituloSeccion
        titulo="Idioma"
        descripcion="Idioma de las respuestas del asistente y de la interfaz del sistema."
      />

      <div className="rounded-xl border border-info/30 bg-info/5 p-3 mb-6 flex gap-2 items-start">
        <Info size={14} className="mt-0.5 shrink-0 text-info" />
        <div className="text-xs text-muted leading-relaxed">
          Hay dos idiomas independientes: el del <span className="font-medium text-text">asistente</span> (idioma de las respuestas que recibes) y el de la <span className="font-medium text-text">interfaz</span> (botones, menús). Puedes mezclarlos.
        </div>
      </div>

      <Fila
        etiqueta="Idioma del asistente"
        descripcion="El chat te responderá siempre en este idioma, sin importar en cuál preguntes."
      >
        <select
          value={idioma}
          onChange={(e) => cambiar(e.target.value)}
          className="h-9 rounded-lg border border-border-soft bg-surface-2 px-3 text-sm text-text focus-ring min-w-[200px]"
        >
          {Object.entries(IDIOMAS).map(([code, nombre]) => (
            <option key={code} value={code}>{nombre}</option>
          ))}
        </select>
      </Fila>

      <Fila
        etiqueta="Idioma de la interfaz"
        descripcion="Cambia labels, botones y menús del sistema. Cobertura parcial — el resto seguirá en español hasta completar el diccionario."
      >
        <select
          value={uiLang}
          onChange={(e) => setUiLang(e.target.value as UiLang)}
          className="h-9 rounded-lg border border-border-soft bg-surface-2 px-3 text-sm text-text focus-ring min-w-[200px]"
        >
          <option value="es">Español</option>
          <option value="en">English</option>
        </select>
      </Fila>
    </div>
  );
}

// ─────────────────────────── Capacidades ───────────────────────────

function SeccionCapacidades() {
  const [buscarWeb, setBuscarWeb] = useState(false);
  useEffect(() => {
    setBuscarWeb(leerLocal(KEYS.buscarWeb, 'false') === 'true');
  }, []);
  function cambiar(v: boolean) {
    setBuscarWeb(v);
    escribirLocal(KEYS.buscarWeb, v.toString());
  }
  return (
    <div>
      <TituloSeccion
        titulo="Capacidades del asistente"
        descripcion="Activa funciones avanzadas para enriquecer las respuestas."
      />
      <Fila
        etiqueta="Búsqueda en internet"
        descripcion="Permite al asistente buscar documentación, frameworks y errores en la web cuando la pregunta lo amerite. Las fuentes se citan en la respuesta."
      >
        <ToggleSwitch value={buscarWeb} onChange={cambiar} />
      </Fila>
    </div>
  );
}

// ─────────────────────────── Voz ───────────────────────────

function SeccionVoz() {
  const [tts, setTts] = useState(false);
  const [voice, setVoice] = useState('');
  const [rate, setRate] = useState(1.0);
  const [voices, setVoices] = useState<SpeechSynthesisVoice[]>([]);

  useEffect(() => {
    setTts(leerLocal(KEYS.ttsHabilitado, 'false') === 'true');
    setVoice(leerLocal(KEYS.ttsVoice, ''));
    setRate(parseFloat(leerLocal(KEYS.ttsRate, '1.0')));

    function cargarVoces() {
      if (typeof window === 'undefined') return;
      setVoices(window.speechSynthesis?.getVoices() || []);
    }
    cargarVoces();
    if (typeof window !== 'undefined' && window.speechSynthesis) {
      window.speechSynthesis.onvoiceschanged = cargarVoces;
    }
  }, []);

  function probarVoz() {
    if (typeof window === 'undefined' || !window.speechSynthesis) return;
    const u = new SpeechSynthesisUtterance('Hola, soy tu asistente. Esta es una prueba de voz.');
    if (voice) {
      const v = voices.find((vc) => vc.name === voice);
      if (v) u.voice = v;
    }
    u.rate = rate;
    window.speechSynthesis.speak(u);
  }

  const soportado = typeof window !== 'undefined' && 'speechSynthesis' in window;

  return (
    <div>
      <TituloSeccion
        titulo="Voz"
        descripcion="Configura el dictado por voz (entrada) y la lectura de respuestas (salida)."
      />

      {!soportado && (
        <div className="rounded-xl border border-warning/30 bg-warning/5 p-3 mb-4 flex gap-2 items-start">
          <AlertCircle size={14} className="mt-0.5 shrink-0 text-warning" />
          <div className="text-xs text-muted">
            Tu navegador no soporta la API de síntesis de voz. Usa Chrome o Edge para esta función.
          </div>
        </div>
      )}

      <SubTitulo titulo="Dictado por voz (entrada)" />
      <Fila
        etiqueta="Dictado por voz"
        descripcion="Activa el micrófono en el composer para dictar en vez de teclear. El locale viene del idioma del asistente."
      >
        <Badge tone="success">
          <Check size={11} />
          Disponible
        </Badge>
      </Fila>

      <SubTitulo titulo="Síntesis de voz (salida)" />
      <Fila
        etiqueta="Leer respuestas en voz alta"
        descripcion="Cuando el asistente responde, también lo lee con la voz seleccionada abajo."
      >
        <ToggleSwitch
          value={tts}
          onChange={(v) => {
            setTts(v);
            escribirLocal(KEYS.ttsHabilitado, v.toString());
          }}
        />
      </Fila>

      <Fila etiqueta="Voz" descripcion={`${voices.length} voces disponibles en tu navegador.`}>
        <select
          value={voice}
          onChange={(e) => {
            setVoice(e.target.value);
            escribirLocal(KEYS.ttsVoice, e.target.value);
          }}
          disabled={!soportado || voices.length === 0}
          className="h-9 rounded-lg border border-border-soft bg-surface-2 px-3 text-sm text-text focus-ring min-w-[200px] disabled:opacity-50"
        >
          <option value="">Predeterminada del sistema</option>
          {voices.map((v) => (
            <option key={v.name} value={v.name}>
              {v.name} ({v.lang})
            </option>
          ))}
        </select>
      </Fila>

      <Fila etiqueta="Velocidad de lectura" descripcion={`${rate.toFixed(1)}× — más bajo = más lento.`}>
        <input
          type="range"
          min="0.5"
          max="2"
          step="0.1"
          value={rate}
          onChange={(e) => {
            const v = parseFloat(e.target.value);
            setRate(v);
            escribirLocal(KEYS.ttsRate, v.toString());
          }}
          className="w-40 accent-[var(--primary)]"
        />
      </Fila>

      <div className="mt-6">
        <Button onClick={probarVoz} variant="outline" size="sm" disabled={!soportado}>
          <Volume2 size={14} />
          Probar voz
        </Button>
      </div>
    </div>
  );
}

// ─────────────────────────── Atajos ───────────────────────────

function SeccionAtajos() {
  return (
    <div>
      <TituloSeccion
        titulo="Atajos de teclado"
        descripcion="Acelera tu navegación. En Mac usa ⌘ en lugar de Ctrl."
      />

      <div className="rounded-xl border border-border-soft bg-surface overflow-hidden">
        {ATAJOS.map((a, i) => (
          <div
            key={a.descripcion}
            className={cn(
              'flex items-center justify-between px-4 py-3',
              i !== ATAJOS.length - 1 && 'border-b border-border-soft'
            )}
          >
            <span className="text-sm text-text">{a.descripcion}</span>
            <div className="flex items-center gap-1.5">
              {a.combo.map((tecla, j) => (
                <span key={j} className="inline-flex items-center">
                  <kbd className="inline-flex items-center justify-center min-w-[28px] h-[26px] rounded border border-border-soft bg-surface-2 px-2 text-[11px] font-mono font-semibold text-text shadow-sm">
                    {tecla}
                  </kbd>
                  {j < a.combo.length - 1 && (
                    <span className="text-subtle text-xs mx-0.5">+</span>
                  )}
                </span>
              ))}
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

// ─────────────────────────── Exportar ───────────────────────────

function SeccionExportar() {
  const [conversaciones, setConversaciones] = useState<{ id: string; titulo: string }[]>([]);
  const [exportando, setExportando] = useState(false);

  useEffect(() => {
    listarConversaciones()
      .then((cs) => setConversaciones(cs.map((c) => ({ id: c.id, titulo: c.titulo }))))
      .catch(() => {});
  }, []);

  async function exportarMarkdown(id: string, titulo: string) {
    setExportando(true);
    try {
      const detalle = await obtenerConversacion(id);
      const lineas: string[] = [
        `# ${titulo || 'Conversación'}`,
        '',
        `_Exportado: ${new Date().toLocaleString()}_`,
        '',
        '---',
        ''
      ];
      for (const m of detalle.mensajes) {
        const rol = m.rol === 'usuario' ? 'Tú' : 'Asistente';
        lineas.push(`### ${rol}`);
        lineas.push('');
        lineas.push(m.contenido);
        lineas.push('');
      }
      const blob = new Blob([lineas.join('\n')], { type: 'text/markdown;charset=utf-8' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `${titulo.replace(/[^a-z0-9]+/gi, '_').slice(0, 60) || 'chat'}.md`;
      document.body.appendChild(a);
      a.click();
      a.remove();
      URL.revokeObjectURL(url);
    } finally {
      setExportando(false);
    }
  }

  async function exportarTodas() {
    setExportando(true);
    try {
      for (const c of conversaciones) {
        await exportarMarkdown(c.id, c.titulo);
        // Pequeña pausa para que el browser pueda iniciar cada descarga.
        await new Promise((r) => setTimeout(r, 200));
      }
    } finally {
      setExportando(false);
    }
  }

  return (
    <div>
      <TituloSeccion
        titulo="Exportar"
        descripcion="Descarga tus conversaciones como Markdown para guardar o citar en tu tesis."
      />

      <div className="mb-6 flex flex-wrap gap-2">
        <Button onClick={exportarTodas} loading={exportando} disabled={conversaciones.length === 0}>
          <Download size={14} />
          Exportar todas ({conversaciones.length})
        </Button>
      </div>

      <SubTitulo titulo="Exportar una conversación" />
      {conversaciones.length === 0 ? (
        <p className="text-sm text-muted">Aún no tienes conversaciones para exportar.</p>
      ) : (
        <div className="rounded-xl border border-border-soft bg-surface divide-y divide-border-soft">
          {conversaciones.slice(0, 20).map((c) => (
            <div key={c.id} className="flex items-center justify-between px-4 py-2.5 hover:bg-surface-2/30">
              <span className="text-sm text-text truncate flex-1 mr-3">
                {c.titulo || 'Conversación'}
              </span>
              <button
                onClick={() => exportarMarkdown(c.id, c.titulo)}
                disabled={exportando}
                className="inline-flex items-center gap-1 rounded-md border border-border-soft bg-surface-2 px-2.5 py-1 text-xs text-text hover:bg-surface-3 disabled:opacity-50"
              >
                <Download size={11} />
                .md
              </button>
            </div>
          ))}
          {conversaciones.length > 20 && (
            <div className="px-4 py-2 text-[11px] text-subtle text-center">
              … y {conversaciones.length - 20} más. Usa "Exportar todas" para descargarlas.
            </div>
          )}
        </div>
      )}
    </div>
  );
}

// ─────────────────────────── Privacidad ───────────────────────────

function SeccionPrivacidad() {
  return (
    <div>
      <TituloSeccion titulo="Privacidad y seguridad" descripcion="Control de tus datos y sesión." />
      <Fila
        etiqueta="Conversaciones"
        descripcion="Tus conversaciones están guardadas en la base de datos y solo tú las ves."
      >
        <Badge tone="success">Privadas</Badge>
      </Fila>
      <Fila
        etiqueta="Cifrado de API keys"
        descripcion="Si configuraste APIs, sus claves están cifradas en la BD con AES-256."
      >
        <Badge tone="success">Activo</Badge>
      </Fila>
      <Fila
        etiqueta="Filtro de contenido"
        descripcion="El sistema bloquea consultas con intención claramente maliciosa (malware, robo de credenciales, etc.)."
      >
        <Badge tone="success">Activado</Badge>
      </Fila>
    </div>
  );
}

// ─────────────────────────── Notificaciones ───────────────────────────

function SeccionNotificaciones() {
  const [notif, setNotif] = useState(false);
  useEffect(() => { setNotif(leerLocal(KEYS.notif, 'false') === 'true'); }, []);
  return (
    <div>
      <TituloSeccion titulo="Notificaciones" descripcion="Cuándo y cómo te avisamos." />
      <Fila
        etiqueta="Notificaciones del navegador"
        descripcion="Aviso cuando termine un entrenamiento o una generación de dataset (próximamente)."
      >
        <ToggleSwitch
          value={notif}
          onChange={(v) => {
            setNotif(v);
            escribirLocal(KEYS.notif, v.toString());
          }}
        />
      </Fila>
    </div>
  );
}

// ─────────────────────────── Ayuda ───────────────────────────

function SeccionAyuda({ usuario }: { usuario: UsuarioPerfil | null }) {
  return (
    <div>
      <TituloSeccion titulo="Ayuda" descripcion="Recursos para aprovechar al máximo el sistema." />
      <div className="space-y-2">
        <button
          onClick={() => window.dispatchEvent(new CustomEvent('explicador:onboarding'))}
          className="flex w-full items-start gap-3 rounded-xl border border-primary/30 bg-primary-soft/30 px-4 py-3 transition-all hover:border-primary hover:bg-primary-soft/50 text-left"
        >
          <div className="mt-0.5 text-primary">
            <Sparkles size={14} />
          </div>
          <div className="min-w-0 flex-1">
            <div className="text-sm font-medium text-text">Ver el tour de bienvenida</div>
            <div className="text-xs text-muted leading-relaxed">5 slides con las funciones clave. 30 segundos.</div>
          </div>
          <ArrowRight size={11} className="text-subtle mt-1" />
        </button>
        <Tarjeta
          href="/"
          titulo="Guía del asistente"
          descripcion="Cómo hacer mejores preguntas, modo profesor, adjuntos, dictado por voz."
        />
        <Tarjeta
          href="/proyecto"
          titulo="Mapa del proyecto"
          descripcion="Diagrama de cómo se conectan backend, frontend, modelos y datasets."
        />
        <Tarjeta
          href={`mailto:${usuario?.email ?? ''}?subject=Explicador IA — Reporte`}
          externo
          icono={<Mail size={14} />}
          titulo="Reportar un problema"
          descripcion="Envía un correo describiendo qué pasó."
        />
        <Tarjeta
          href="https://github.com"
          externo
          icono={<Github size={14} />}
          titulo="Sobre Explicador IA"
          descripcion="LLM educativo entrenado desde cero para la enseñanza de Python."
        />
      </div>
    </div>
  );
}

function Tarjeta({
  href, titulo, descripcion, externo = false, icono
}: {
  href: string;
  titulo: string;
  descripcion: string;
  externo?: boolean;
  icono?: React.ReactNode;
}) {
  const props = externo
    ? { href, target: '_blank', rel: 'noreferrer' }
    : { href };
  const Wrap: any = externo ? 'a' : Link;
  return (
    <Wrap
      {...props}
      className="flex items-start gap-3 rounded-xl border border-border-soft bg-surface px-4 py-3 transition-all hover:border-border hover:bg-surface-2"
    >
      <div className="mt-0.5 text-muted">
        {icono ?? <ArrowRight size={14} />}
      </div>
      <div className="min-w-0 flex-1">
        <div className="text-sm font-medium text-text">{titulo}</div>
        <div className="text-xs text-muted leading-relaxed">{descripcion}</div>
      </div>
      {externo && <ExternalLink size={11} className="text-subtle mt-1" />}
    </Wrap>
  );
}

// ─────────────────────────── Admin ───────────────────────────

function SeccionAdmin() {
  return (
    <div>
      <TituloSeccion titulo="Acceso administrador" descripcion="Acceso a funciones avanzadas del sistema." />
      <Tarjeta
        href="/admin"
        titulo="Panel de administrador"
        descripcion="Configurar API keys, ver métricas del sistema, generar datasets."
        icono={<ShieldCheck size={14} />}
      />
      <div className="mt-2">
        <Tarjeta
          href="/panel"
          titulo="Panel general"
          descripcion="Dashboard con métricas del modelo propio y curvas de entrenamiento."
          icono={<Cog size={14} />}
        />
      </div>
    </div>
  );
}

// ─────────────────────────── MCP ───────────────────────────

function SeccionMcp() {
  const [estado, setEstado] = useState<import('@/services/mcp').EstadoMcp | null>(null);
  const [cargando, setCargando] = useState(true);
  const [guardando, setGuardando] = useState(false);
  const [nuevoDir, setNuevoDir] = useState('');
  const [error, setError] = useState<string | null>(null);

  async function recargar() {
    setCargando(true);
    setError(null);
    try {
      const { obtenerEstadoMcp } = await import('@/services/mcp');
      const e = await obtenerEstadoMcp();
      setEstado(e);
    } catch (err: any) {
      setError(err?.message ?? 'No se pudo cargar MCP');
    } finally {
      setCargando(false);
    }
  }

  useEffect(() => {
    recargar();
  }, []);

  async function actualizar(parcial: Partial<import('@/services/mcp').PermisosMcp>) {
    if (!estado) return;
    setGuardando(true);
    setError(null);
    try {
      const { actualizarPermisosMcp } = await import('@/services/mcp');
      const nuevos = await actualizarPermisosMcp({ ...estado.permisos, ...parcial });
      setEstado({ ...estado, permisos: nuevos });
    } catch (err: any) {
      setError(err?.message ?? 'No se pudo guardar');
    } finally {
      setGuardando(false);
    }
  }

  function agregarDir() {
    const d = nuevoDir.trim();
    if (!d || !estado) return;
    if (estado.permisos.directorios_permitidos.includes(d)) return;
    actualizar({ directorios_permitidos: [...estado.permisos.directorios_permitidos, d] });
    setNuevoDir('');
  }

  function quitarDir(d: string) {
    if (!estado) return;
    actualizar({
      directorios_permitidos: estado.permisos.directorios_permitidos.filter((x) => x !== d),
    });
  }

  function toggleTool(name: string) {
    if (!estado) return;
    const habilitadas = estado.permisos.tools_habilitadas.includes(name)
      ? estado.permisos.tools_habilitadas.filter((t) => t !== name)
      : [...estado.permisos.tools_habilitadas, name];
    actualizar({ tools_habilitadas: habilitadas });
  }

  return (
    <div>
      <TituloSeccion
        titulo="MCP — Tools del sistema"
        descripcion="Permite al asistente leer archivos, ejecutar Python y otras acciones en tu PC, con los permisos que tú definas."
      />

      {/* Estado */}
      <div className="mb-6 rounded-xl border border-border-soft bg-surface p-4">
        <div className="flex items-center gap-2 mb-3">
          <span
            className={cn(
              'h-2 w-2 rounded-full',
              estado?.activo ? 'bg-success' : 'bg-subtle',
            )}
          />
          <span className="text-sm font-medium text-text">
            {cargando
              ? 'Verificando…'
              : estado?.activo
                ? 'MCP server activo'
                : 'MCP server inactivo'}
          </span>
          <button
            onClick={recargar}
            disabled={cargando}
            className="ml-auto text-xs text-muted hover:text-text underline"
          >
            recargar
          </button>
        </div>
        {error && (
          <div className="text-xs text-danger flex items-start gap-2">
            <AlertCircle size={13} className="mt-0.5 shrink-0" />
            {error}
          </div>
        )}
      </div>

      {estado && (
        <>
          <SubTitulo titulo="Tools disponibles" />
          <p className="text-xs text-muted mb-3 leading-relaxed">
            Activa o desactiva cada tool. Una tool desactivada nunca puede
            ser invocada por el asistente, ni siquiera si éste lo pide.
          </p>
          <div className="space-y-2 mb-4">
            {estado.tools.map((t) => {
              const habilitada = estado.permisos.tools_habilitadas.includes(t.name);
              return (
                <div
                  key={t.name}
                  className={cn(
                    'rounded-xl border p-3 flex items-start gap-3 transition-colors',
                    habilitada
                      ? 'border-success/40 bg-success/5'
                      : 'border-border-soft bg-surface',
                  )}
                >
                  <ToggleSwitch
                    value={habilitada}
                    onChange={() => toggleTool(t.name)}
                  />
                  <div className="flex-1 min-w-0">
                    <div className="text-sm font-mono text-text">{t.name}</div>
                    <div className="text-xs text-muted leading-relaxed mt-0.5">
                      {t.description}
                    </div>
                  </div>
                </div>
              );
            })}
          </div>

          <SubTitulo titulo="Directorios permitidos" />
          <p className="text-xs text-muted mb-3 leading-relaxed">
            El asistente solo puede leer/escribir/listar bajo estas rutas.
            Cualquier intento fuera de aquí se rechaza automáticamente.
          </p>
          <div className="rounded-xl border border-border-soft bg-surface mb-3">
            {estado.permisos.directorios_permitidos.length === 0 ? (
              <div className="p-3 text-sm text-muted italic">
                Sin directorios permitidos. El asistente no puede acceder a
                ningún archivo hasta que añadas al menos uno.
              </div>
            ) : (
              estado.permisos.directorios_permitidos.map((d, i) => (
                <div
                  key={d}
                  className={cn(
                    'flex items-center gap-2 px-3 py-2',
                    i > 0 && 'border-t border-border-soft',
                  )}
                >
                  <span className="text-xs font-mono text-text flex-1 truncate">{d}</span>
                  <button
                    onClick={() => quitarDir(d)}
                    disabled={guardando}
                    className="text-xs text-danger hover:underline"
                  >
                    quitar
                  </button>
                </div>
              ))
            )}
          </div>
          <div className="flex gap-2 mb-6">
            <input
              value={nuevoDir}
              onChange={(e) => setNuevoDir(e.target.value)}
              onKeyDown={(e) => e.key === 'Enter' && agregarDir()}
              placeholder="C:/Users/tu/Proyectos"
              className="flex-1 h-9 rounded-lg border border-border-soft bg-surface-2 px-3 text-sm text-text focus-ring font-mono"
            />
            <button
              onClick={agregarDir}
              disabled={!nuevoDir.trim() || guardando}
              className="rounded-lg bg-primary text-primary-foreground px-4 text-sm font-medium hover:bg-primary-hover disabled:opacity-50"
            >
              Añadir
            </button>
          </div>

          <SubTitulo titulo="Acciones destructivas" />
          <Fila
            etiqueta="Escribir archivos"
            descripcion="bloquear: nunca · confirmar: pide aprobación del usuario · auto: permite sin preguntar"
          >
            <select
              value={estado.permisos.modo_escribir}
              onChange={(e) => actualizar({ modo_escribir: e.target.value as any })}
              className="h-9 rounded-lg border border-border-soft bg-surface-2 px-3 text-sm text-text focus-ring"
            >
              <option value="bloquear">bloquear</option>
              <option value="confirmar">confirmar</option>
              <option value="auto">auto</option>
            </select>
          </Fila>
          <Fila
            etiqueta="Ejecutar Python"
            descripcion="El sandbox tiene timeout y env aislado, pero la ejecución puede tener efectos secundarios."
          >
            <select
              value={estado.permisos.modo_ejecutar}
              onChange={(e) => actualizar({ modo_ejecutar: e.target.value as any })}
              className="h-9 rounded-lg border border-border-soft bg-surface-2 px-3 text-sm text-text focus-ring"
            >
              <option value="bloquear">bloquear</option>
              <option value="confirmar">confirmar</option>
              <option value="auto">auto</option>
            </select>
          </Fila>

          <SubTitulo titulo="Límites" />
          <Fila etiqueta="Tamaño máximo de lectura" descripcion={`${Math.round(estado.permisos.max_bytes_lectura / 1024)} KB`}>
            <input
              type="number"
              value={estado.permisos.max_bytes_lectura}
              onChange={(e) => actualizar({ max_bytes_lectura: parseInt(e.target.value) || 0 })}
              className="h-9 w-32 rounded-lg border border-border-soft bg-surface-2 px-3 text-sm text-text focus-ring"
            />
          </Fila>
          <Fila etiqueta="Timeout de ejecución (segundos)">
            <input
              type="number"
              value={estado.permisos.timeout_ejecucion_segundos}
              onChange={(e) => actualizar({ timeout_ejecucion_segundos: parseInt(e.target.value) || 1 })}
              className="h-9 w-24 rounded-lg border border-border-soft bg-surface-2 px-3 text-sm text-text focus-ring"
            />
          </Fila>
        </>
      )}
    </div>
  );
}
