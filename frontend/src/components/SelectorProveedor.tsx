import { useEffect, useRef, useState } from 'react';
import { ChevronDown, Brain, Cloud, Zap, CheckCircle2, AlertCircle } from 'lucide-react';
import { cn } from '@/lib/cn';
import { listarProveedores, ProveedorIA } from '@/services/chat';

/**
 * Selector de proveedor de IA en el composer del chat.
 *
 * Permite al usuario decidir, por mensaje, qué motor responde:
 *   - Automático (modelo propio si está, si no API).
 *   - Modelo propio (forzar el LLM entrenado desde cero).
 *   - Gemini / DeepSeek (APIs externas, si hay credenciales).
 *
 * Persiste la última elección en localStorage para que sobreviva al recargar.
 */

const STORAGE_KEY = 'explicador.proveedor';

interface Props {
  value: string;
  onChange: (id: string) => void;
  compact?: boolean;
}

function iconoTipo(tipo: ProveedorIA['tipo']) {
  if (tipo === 'auto') return <Zap size={13} />;
  if (tipo === 'propio') return <Brain size={13} />;
  return <Cloud size={13} />;
}

export default function SelectorProveedor({ value, onChange, compact = false }: Props) {
  const [proveedores, setProveedores] = useState<ProveedorIA[]>([]);
  const [abierto, setAbierto] = useState(false);
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    listarProveedores()
      .then(setProveedores)
      .catch(() => {
        // Sin backend: dejamos opciones por defecto.
        setProveedores([
          { id: 'auto', nombre: 'Automático', descripcion: '', tipo: 'auto', disponible: true },
        ]);
      });
  }, []);

  useEffect(() => {
    function handler(e: MouseEvent) {
      if (ref.current && !ref.current.contains(e.target as Node)) {
        setAbierto(false);
      }
    }
    document.addEventListener('mousedown', handler);
    return () => document.removeEventListener('mousedown', handler);
  }, []);

  const actual = proveedores.find((p) => p.id === value) ?? proveedores[0];

  function elegir(id: string) {
    onChange(id);
    try { localStorage.setItem(STORAGE_KEY, id); } catch {}
    setAbierto(false);
  }

  if (!actual) return null;

  const hayVarios = proveedores.length > 1;

  return (
    <div ref={ref} className="relative">
      <button
        type="button"
        onClick={() => hayVarios && setAbierto((v) => !v)}
        className={cn(
          'flex items-center gap-1.5 rounded-lg border border-border-soft bg-surface text-xs font-semibold transition-colors',
          hayVarios ? 'hover:bg-surface-2 cursor-pointer' : 'cursor-default',
          compact ? 'px-2 py-1' : 'px-2.5 py-1.5',
        )}
        title={actual.descripcion || 'Motor neural de la tesis (100% offline)'}
      >
        <span className="text-primary">{iconoTipo(actual.tipo)}</span>
        <span className="text-text">{actual.nombre}</span>
        {hayVarios && <ChevronDown size={11} className="text-muted" />}
      </button>

      {abierto && hayVarios && (
        <div className="absolute bottom-full left-0 z-40 mb-2 w-64 rounded-xl border border-border-soft bg-surface p-1 shadow-elevated">
          {proveedores.map((p) => (
            <button
              key={p.id}
              type="button"
              onClick={() => p.disponible && elegir(p.id)}
              disabled={!p.disponible}
              className={cn(
                'flex w-full items-start gap-2 rounded-lg px-2 py-2 text-left transition-colors',
                p.disponible
                  ? 'hover:bg-surface-2'
                  : 'cursor-not-allowed opacity-50',
                value === p.id && 'bg-primary/10',
              )}
            >
              <span
                className={cn(
                  'mt-0.5 flex h-7 w-7 shrink-0 items-center justify-center rounded-md',
                  p.tipo === 'propio' && 'bg-primary/15 text-primary',
                  p.tipo === 'auto' && 'bg-accent/15 text-accent',
                  p.tipo === 'api' && 'bg-surface-2 text-muted',
                )}
              >
                {iconoTipo(p.tipo)}
              </span>
              <span className="min-w-0 flex-1">
                <span className="flex items-center gap-1.5">
                  <span className="text-xs font-medium text-text">{p.nombre}</span>
                  {value === p.id && (
                    <CheckCircle2 size={11} className="text-primary" />
                  )}
                  {!p.disponible && (
                    <span className="rounded-full bg-warning/15 px-1.5 py-0.5 text-[9px] font-semibold text-warning">
                      no disponible
                    </span>
                  )}
                </span>
                <span className="block text-[11px] leading-snug text-muted">
                  {p.descripcion}
                </span>
              </span>
            </button>
          ))}
          <div className="mt-1 flex items-start gap-1.5 border-t border-border-soft px-2 py-1.5 text-[10px] text-subtle">
            <AlertCircle size={10} className="mt-0.5 shrink-0" />
            <span>
              "Modelo propio" usa tu IA entrenada desde cero. Las APIs externas
              son andamio temporal.
            </span>
          </div>
        </div>
      )}
    </div>
  );
}

export function recuperarProveedorGuardado(): string {
  if (typeof window === 'undefined') return 'auto';
  try {
    return localStorage.getItem(STORAGE_KEY) || 'auto';
  } catch {
    return 'auto';
  }
}
