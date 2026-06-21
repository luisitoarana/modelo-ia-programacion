import { useEffect, useMemo, useRef, useState } from 'react';
import { useRouter } from 'next/router';
import { useTheme } from 'next-themes';
import {
  Search, MessageSquare, Settings, Palette, Plus, FileCode2,
  Network, ShieldCheck, Sun, Moon, ArrowRight, Sparkles, Keyboard,
  Download, Brain, FlaskConical
} from 'lucide-react';
import { ConversacionResumen, listarConversaciones } from '@/services/chat';
import { obtenerPerfil, UsuarioPerfil } from '@/services/auth';
import { cn } from '@/lib/cn';

interface Comando {
  id: string;
  titulo: string;
  subtitulo?: string;
  seccion: 'Acciones' | 'Navegación' | 'Configuración' | 'Conversaciones';
  icon: React.ReactNode;
  ejecutar: () => void;
  soloAdmin?: boolean;
}

/**
 * Command Palette estilo VS Code / Spotlight:
 *   - Se abre con Cmd/Ctrl + K
 *   - Lista acciones globales + conversaciones recientes
 *   - Búsqueda fuzzy básica (substring match)
 *   - Navegación con flechas, Enter para ejecutar, Esc para cerrar
 */
export default function CommandPalette() {
  const router = useRouter();
  const { setTheme, resolvedTheme } = useTheme();
  const [abierto, setAbierto] = useState(false);
  const [query, setQuery] = useState('');
  const [seleccionado, setSeleccionado] = useState(0);
  const [conversaciones, setConversaciones] = useState<ConversacionResumen[]>([]);
  const [usuario, setUsuario] = useState<UsuarioPerfil | null>(null);
  const inputRef = useRef<HTMLInputElement>(null);

  // Escuchar Ctrl+K para abrir.
  useEffect(() => {
    function handler(e: KeyboardEvent) {
      const mod = e.ctrlKey || e.metaKey;
      if (mod && e.key.toLowerCase() === 'k') {
        const tag = (e.target as HTMLElement)?.tagName;
        // Solo si no está en input/textarea (excepto el palette mismo).
        if (tag !== 'INPUT' && tag !== 'TEXTAREA') {
          e.preventDefault();
          setAbierto(true);
        }
      }
    }
    window.addEventListener('keydown', handler);
    return () => window.removeEventListener('keydown', handler);
  }, []);

  // Cargar datos al abrir.
  useEffect(() => {
    if (!abierto) return;
    listarConversaciones().then(setConversaciones).catch(() => {});
    obtenerPerfil().then(setUsuario).catch(() => {});
    setTimeout(() => inputRef.current?.focus(), 50);
    setQuery('');
    setSeleccionado(0);
  }, [abierto]);

  // Construir lista de comandos.
  const comandos: Comando[] = useMemo(() => {
    const acciones: Comando[] = [
      {
        id: 'nuevo',
        titulo: 'Nuevo chat',
        seccion: 'Acciones',
        icon: <Plus size={14} />,
        ejecutar: () => {
          router.push('/');
          window.dispatchEvent(new CustomEvent('explicador:nuevo-chat'));
        },
      },
      {
        id: 'tema',
        titulo: resolvedTheme === 'dark' ? 'Cambiar a tema claro' : 'Cambiar a tema oscuro',
        seccion: 'Acciones',
        icon: resolvedTheme === 'dark' ? <Sun size={14} /> : <Moon size={14} />,
        ejecutar: () => setTheme(resolvedTheme === 'dark' ? 'light' : 'dark'),
      },
      {
        id: 'exportar',
        titulo: 'Exportar conversación actual',
        seccion: 'Acciones',
        icon: <Download size={14} />,
        ejecutar: () => {
          router.push('/');
          window.dispatchEvent(new CustomEvent('explicador:exportar'));
        },
      },
    ];
    const navegacion: Comando[] = [
      { id: 'chat', titulo: 'Ir al chat', seccion: 'Navegación', icon: <MessageSquare size={14} />, ejecutar: () => router.push('/') },
      { id: 'explicar', titulo: 'Explicar código', seccion: 'Navegación', icon: <FileCode2 size={14} />, ejecutar: () => router.push('/explicar') },
      { id: 'panel', titulo: 'Panel general', seccion: 'Navegación', icon: <Sparkles size={14} />, ejecutar: () => router.push('/panel') },
      { id: 'dataset', titulo: 'Dataset & Validación', seccion: 'Navegación', icon: <Brain size={14} />, ejecutar: () => router.push('/dataset') },
      { id: 'entren', titulo: 'Entrenamiento', seccion: 'Navegación', icon: <FlaskConical size={14} />, ejecutar: () => router.push('/entrenamiento') },
      { id: 'mapa', titulo: 'Mapa del proyecto', seccion: 'Navegación', icon: <Network size={14} />, ejecutar: () => router.push('/proyecto') },
      { id: 'presentacion', titulo: 'Modo presentación', seccion: 'Navegación', icon: <Sparkles size={14} />, ejecutar: () => router.push('/presentacion') },
      { id: 'admin', titulo: 'Panel admin', seccion: 'Navegación', icon: <ShieldCheck size={14} />, ejecutar: () => router.push('/admin'), soloAdmin: true },
    ];
    const config: Comando[] = [
      { id: 'settings', titulo: 'Configuración', seccion: 'Configuración', icon: <Settings size={14} />, ejecutar: () => router.push('/configuracion') },
      { id: 'apariencia', titulo: 'Cambiar paleta de colores', seccion: 'Configuración', icon: <Palette size={14} />, ejecutar: () => router.push('/configuracion?seccion=apariencia') },
      { id: 'atajos', titulo: 'Ver atajos de teclado', seccion: 'Configuración', icon: <Keyboard size={14} />, ejecutar: () => router.push('/configuracion?seccion=atajos') },
    ];

    const convs: Comando[] = conversaciones.slice(0, 10).map((c) => ({
      id: `conv-${c.id}`,
      titulo: c.titulo || 'Conversación',
      subtitulo: 'Abrir conversación',
      seccion: 'Conversaciones',
      icon: <MessageSquare size={14} />,
      ejecutar: () => router.push(`/?c=${c.id}`),
    }));

    const esAdmin = usuario?.rol === 'administrador';
    return [...acciones, ...navegacion, ...config, ...convs]
      .filter((c) => !c.soloAdmin || esAdmin);
  }, [conversaciones, usuario, router, setTheme, resolvedTheme]);

  const filtrados = useMemo(() => {
    if (!query.trim()) return comandos;
    const q = query.toLowerCase();
    return comandos.filter((c) =>
      c.titulo.toLowerCase().includes(q) ||
      c.seccion.toLowerCase().includes(q)
    );
  }, [comandos, query]);

  // Agrupar por sección.
  const grupos = useMemo(() => {
    const map = new Map<string, Comando[]>();
    filtrados.forEach((c) => {
      if (!map.has(c.seccion)) map.set(c.seccion, []);
      map.get(c.seccion)!.push(c);
    });
    return Array.from(map.entries());
  }, [filtrados]);

  // Aplanar para navegación con flechas.
  const planos = useMemo(() => filtrados, [filtrados]);

  function ejecutarSeleccionado() {
    const cmd = planos[seleccionado];
    if (!cmd) return;
    setAbierto(false);
    cmd.ejecutar();
  }

  // Atajos dentro del palette.
  useEffect(() => {
    if (!abierto) return;
    function handler(e: KeyboardEvent) {
      if (e.key === 'Escape') {
        e.preventDefault();
        setAbierto(false);
      } else if (e.key === 'ArrowDown') {
        e.preventDefault();
        setSeleccionado((s) => Math.min(s + 1, planos.length - 1));
      } else if (e.key === 'ArrowUp') {
        e.preventDefault();
        setSeleccionado((s) => Math.max(s - 1, 0));
      } else if (e.key === 'Enter') {
        e.preventDefault();
        ejecutarSeleccionado();
      }
    }
    window.addEventListener('keydown', handler);
    return () => window.removeEventListener('keydown', handler);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [abierto, seleccionado, planos]);

  useEffect(() => {
    setSeleccionado(0);
  }, [query]);

  if (!abierto) return null;

  return (
    <div
      className="fixed inset-0 z-[70] flex items-start justify-center p-4 pt-[15vh] animate-fade-in"
      onClick={() => setAbierto(false)}
    >
      <div className="absolute inset-0 bg-black/50 backdrop-blur-sm" />

      <div
        className="relative w-full max-w-xl rounded-2xl border border-border-soft bg-bg shadow-elevated overflow-hidden"
        onClick={(e) => e.stopPropagation()}
        style={{ animation: 'palette-pop 200ms cubic-bezier(0.34, 1.56, 0.64, 1)' }}
      >
        {/* Input */}
        <div className="flex items-center gap-3 border-b border-border-soft px-4 py-3">
          <Search size={16} className="text-subtle" />
          <input
            ref={inputRef}
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Buscar acciones, páginas y conversaciones…"
            className="flex-1 bg-transparent text-[14.5px] text-text placeholder:text-subtle focus:outline-none"
          />
          <kbd className="px-1.5 py-0.5 text-[10.5px] font-mono text-subtle border border-border-soft rounded">
            esc
          </kbd>
        </div>

        {/* Resultados */}
        <div className="max-h-[50vh] overflow-y-auto py-2">
          {grupos.length === 0 ? (
            <div className="px-4 py-10 text-center">
              <Search size={24} className="mx-auto text-subtle mb-2" />
              <p className="text-sm text-muted">
                Sin resultados para «{query}»
              </p>
            </div>
          ) : (
            grupos.map(([seccion, items]) => (
              <div key={seccion} className="mb-1">
                <div className="px-4 py-1 text-[10px] font-semibold uppercase tracking-wider text-subtle">
                  {seccion}
                </div>
                {items.map((c) => {
                  const idx = planos.indexOf(c);
                  const activo = idx === seleccionado;
                  return (
                    <button
                      key={c.id}
                      onClick={() => {
                        setSeleccionado(idx);
                        ejecutarSeleccionado();
                      }}
                      onMouseEnter={() => setSeleccionado(idx)}
                      className={cn(
                        'flex w-full items-center gap-3 px-4 py-2 text-left transition-colors',
                        activo ? 'bg-surface-2' : 'hover:bg-surface-2/50'
                      )}
                    >
                      <span className={activo ? 'text-primary' : 'text-muted'}>
                        {c.icon}
                      </span>
                      <span className="flex-1 min-w-0">
                        <span className="text-sm text-text truncate block">{c.titulo}</span>
                        {c.subtitulo && (
                          <span className="text-[11px] text-subtle">{c.subtitulo}</span>
                        )}
                      </span>
                      {activo && <ArrowRight size={11} className="text-subtle" />}
                    </button>
                  );
                })}
              </div>
            ))
          )}
        </div>

        {/* Footer con shortcuts */}
        <div className="flex items-center justify-between border-t border-border-soft bg-surface/40 px-4 py-2 text-[10.5px] text-subtle">
          <div className="flex items-center gap-3">
            <span className="inline-flex items-center gap-1">
              <kbd className="px-1 py-0.5 border border-border-soft rounded font-mono">↑↓</kbd>
              navegar
            </span>
            <span className="inline-flex items-center gap-1">
              <kbd className="px-1 py-0.5 border border-border-soft rounded font-mono">↵</kbd>
              seleccionar
            </span>
          </div>
          <div>{filtrados.length} resultados</div>
        </div>
      </div>

      <style jsx>{`
        @keyframes palette-pop {
          from { opacity: 0; transform: scale(0.96) translateY(-8px); }
          to { opacity: 1; transform: scale(1) translateY(0); }
        }
      `}</style>
    </div>
  );
}
