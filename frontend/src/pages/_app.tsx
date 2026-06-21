import type { AppProps } from 'next/app';
import { useEffect } from 'react';
import { useRouter } from 'next/router';
import { useTheme } from 'next-themes';
import ThemeProvider from '@/components/ThemeProvider';
import CommandPalette from '@/components/CommandPalette';
import AtajosOverlay from '@/components/AtajosOverlay';
import Onboarding from '@/components/Onboarding';
import { getToken } from '@/services/api';
import '@/styles/globals.css';

// Paletas duplicadas aquí para que se apliquen al cargar cualquier página.
const PALETAS: Record<string, { light: Record<string, string>; dark: Record<string, string> }> = {
  terracota: {
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
  academico: {
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
  bosque: {
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
  purpura: {
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
  mono: {
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
};

function aplicarPaletaGuardada(tema: 'light' | 'dark') {
  if (typeof window === 'undefined') return;
  const id = window.localStorage.getItem('explicador.paleta') ?? 'terracota';
  const p = PALETAS[id];
  if (!p) return;
  const colores = tema === 'dark' ? p.dark : p.light;
  const root = document.documentElement;
  Object.entries(colores).forEach(([key, value]) => {
    root.style.setProperty(`--${key}`, value);
  });
}

/** Componente que escucha atajos globales y aplica la paleta. */
function GlobalShortcutsAndPalette() {
  const router = useRouter();
  const { theme, setTheme, resolvedTheme } = useTheme();

  useEffect(() => {
    aplicarPaletaGuardada(resolvedTheme === 'dark' ? 'dark' : 'light');
  }, [resolvedTheme]);

  useEffect(() => {
    function handler(e: KeyboardEvent) {
      // Ignorar si el foco está en un input/textarea (excepto Esc).
      const tag = (e.target as HTMLElement)?.tagName;
      const enInput = tag === 'INPUT' || tag === 'TEXTAREA' ||
                     (e.target as HTMLElement)?.isContentEditable;

      // Esc — siempre funciona (vuelve atrás)
      if (e.key === 'Escape' && router.pathname !== '/') {
        // Solo si no es input — para no romper composer
        if (!enInput) {
          e.preventDefault();
          router.back();
          return;
        }
      }

      // El resto de atajos no deben dispararse si está en input.
      if (enInput) return;

      const mod = e.ctrlKey || e.metaKey;

      // Cmd/Ctrl + K — el CommandPalette se abre por sí solo
      // (escucha el mismo evento). No hacemos nada aquí para no duplicar.

      // Cmd/Ctrl + N — nuevo chat
      if (mod && e.key.toLowerCase() === 'n' && !e.shiftKey) {
        e.preventDefault();
        if (router.pathname !== '/') {
          router.push('/');
        } else {
          // disparar evento custom que la página del asistente captura
          window.dispatchEvent(new CustomEvent('explicador:nuevo-chat'));
        }
        return;
      }

      // Cmd/Ctrl + , — configuración
      if (mod && e.key === ',') {
        e.preventDefault();
        router.push('/configuracion');
        return;
      }

      // Cmd/Ctrl + / — el AtajosOverlay se abre solo

      // Cmd/Ctrl + Shift + L — alternar tema
      if (mod && e.shiftKey && e.key.toLowerCase() === 'l') {
        e.preventDefault();
        setTheme(resolvedTheme === 'dark' ? 'light' : 'dark');
        return;
      }
    }

    window.addEventListener('keydown', handler);
    return () => window.removeEventListener('keydown', handler);
  }, [router, setTheme, resolvedTheme]);

  return null;
}

function OnboardingGate() {
  // Solo mostrar onboarding cuando el usuario está autenticado
  // (no en /login ni en SSR). Evita que aparezca antes de tener acceso.
  if (typeof window === 'undefined') return null;
  if (!getToken()) return null;
  if (window.location.pathname === '/login') return null;
  return <Onboarding />;
}

export default function App({ Component, pageProps }: AppProps) {
  return (
    <ThemeProvider>
      <GlobalShortcutsAndPalette />
      <Component {...pageProps} />
      <CommandPalette />
      <AtajosOverlay />
      <OnboardingGate />
    </ThemeProvider>
  );
}
