import { useEffect } from 'react';
import { AlertTriangle, Trash2, LogOut, X } from 'lucide-react';
import { cn } from '@/lib/cn';

interface ConfirmDialogProps {
  abierto: boolean;
  titulo: string;
  descripcion: string;
  textoConfirmar?: string;
  textoCancelar?: string;
  tono?: 'danger' | 'warning' | 'neutral';
  icono?: 'eliminar' | 'logout' | 'warning';
  onConfirmar: () => void;
  onCancelar: () => void;
  cargando?: boolean;
}

/**
 * Diálogo de confirmación elegante con backdrop blur, animación de
 * entrada y atajos de teclado:
 *   - Enter → confirma
 *   - Esc → cancela
 *
 * Pensado para acciones destructivas (eliminar chat, cerrar sesión, etc.).
 */
export default function ConfirmDialog({
  abierto, titulo, descripcion,
  textoConfirmar = 'Confirmar',
  textoCancelar = 'Cancelar',
  tono = 'danger',
  icono = 'warning',
  onConfirmar, onCancelar, cargando = false
}: ConfirmDialogProps) {
  // Atajos de teclado.
  useEffect(() => {
    if (!abierto) return;
    function handler(e: KeyboardEvent) {
      if (e.key === 'Escape') {
        e.preventDefault();
        onCancelar();
      } else if (e.key === 'Enter') {
        e.preventDefault();
        if (!cargando) onConfirmar();
      }
    }
    window.addEventListener('keydown', handler);
    return () => window.removeEventListener('keydown', handler);
  }, [abierto, onConfirmar, onCancelar, cargando]);

  if (!abierto) return null;

  const iconoEl = {
    eliminar: <Trash2 size={20} />,
    logout: <LogOut size={20} />,
    warning: <AlertTriangle size={20} />
  }[icono];

  const tonoColors = {
    danger: {
      iconBg: 'bg-danger/15 text-danger',
      btnPrim: 'bg-danger text-white hover:opacity-90'
    },
    warning: {
      iconBg: 'bg-warning/15 text-warning',
      btnPrim: 'bg-warning text-white hover:opacity-90'
    },
    neutral: {
      iconBg: 'bg-primary-soft text-primary',
      btnPrim: 'bg-primary text-primary-foreground hover:bg-primary-hover'
    }
  }[tono];

  return (
    <div
      className="fixed inset-0 z-[60] flex items-center justify-center p-4 animate-fade-in"
      onClick={onCancelar}
    >
      {/* Backdrop */}
      <div className="absolute inset-0 bg-black/60 backdrop-blur-sm" />

      {/* Dialog */}
      <div
        className="relative w-full max-w-md rounded-2xl border border-border-soft bg-bg shadow-elevated overflow-hidden"
        onClick={(e) => e.stopPropagation()}
        style={{ animation: 'dialog-pop 200ms cubic-bezier(0.34, 1.56, 0.64, 1)' }}
      >
        <button
          onClick={onCancelar}
          className="absolute right-3 top-3 rounded-md p-1.5 text-subtle hover:bg-surface-2 hover:text-text transition-colors"
        >
          <X size={14} />
        </button>

        <div className="p-6">
          <div className={cn(
            'mb-4 inline-flex h-12 w-12 items-center justify-center rounded-2xl',
            tonoColors.iconBg
          )}>
            {iconoEl}
          </div>

          <h3 className="font-serif text-xl text-text mb-1.5">{titulo}</h3>
          <p className="text-sm text-muted leading-relaxed">{descripcion}</p>
        </div>

        <div className="flex gap-2 border-t border-border-soft bg-surface/40 px-6 py-4">
          <button
            onClick={onCancelar}
            disabled={cargando}
            className="flex-1 rounded-lg border border-border-soft bg-surface px-4 py-2 text-sm font-medium text-text hover:bg-surface-2 transition-colors disabled:opacity-50"
          >
            {textoCancelar}
          </button>
          <button
            onClick={onConfirmar}
            disabled={cargando}
            className={cn(
              'flex-1 rounded-lg px-4 py-2 text-sm font-medium transition-all disabled:opacity-50',
              tonoColors.btnPrim
            )}
          >
            {cargando ? 'Procesando…' : textoConfirmar}
          </button>
        </div>
      </div>

      <style jsx>{`
        @keyframes dialog-pop {
          from {
            opacity: 0;
            transform: scale(0.92) translateY(8px);
          }
          to {
            opacity: 1;
            transform: scale(1) translateY(0);
          }
        }
      `}</style>
    </div>
  );
}
