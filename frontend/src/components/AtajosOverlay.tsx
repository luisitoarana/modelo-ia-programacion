import { useEffect, useState } from 'react';
import { Keyboard, X } from 'lucide-react';

const ATAJOS = [
  { combo: ['Ctrl', 'K'], descripcion: 'Abrir command palette (buscar/ejecutar)' },
  { combo: ['Ctrl', '/'], descripcion: 'Mostrar este overlay de atajos' },
  { combo: ['Ctrl', 'N'], descripcion: 'Nuevo chat' },
  { combo: ['Ctrl', ','], descripcion: 'Abrir configuración' },
  { combo: ['Ctrl', 'B'], descripcion: 'Colapsar/expandir sidebar' },
  { combo: ['Ctrl', 'Shift', 'L'], descripcion: 'Alternar tema claro/oscuro' },
  { combo: ['Enter'], descripcion: 'Enviar mensaje' },
  { combo: ['Shift', 'Enter'], descripcion: 'Nueva línea en composer' },
  { combo: ['Esc'], descripcion: 'Cerrar modal / overlay' },
];

/**
 * Overlay flotante con atajos. Se abre con Ctrl+/ y se cierra con Esc o
 * click fuera. Más rápido que navegar a Settings.
 */
export default function AtajosOverlay() {
  const [abierto, setAbierto] = useState(false);

  useEffect(() => {
    function handler(e: KeyboardEvent) {
      const mod = e.ctrlKey || e.metaKey;
      if (mod && e.key === '/') {
        const tag = (e.target as HTMLElement)?.tagName;
        if (tag !== 'INPUT' && tag !== 'TEXTAREA') {
          e.preventDefault();
          setAbierto((v) => !v);
        }
      }
      if (e.key === 'Escape' && abierto) {
        e.preventDefault();
        setAbierto(false);
      }
    }
    window.addEventListener('keydown', handler);
    return () => window.removeEventListener('keydown', handler);
  }, [abierto]);

  if (!abierto) return null;

  return (
    <div
      className="fixed inset-0 z-[60] flex items-center justify-center p-4 animate-fade-in"
      onClick={() => setAbierto(false)}
    >
      <div className="absolute inset-0 bg-black/50 backdrop-blur-sm" />

      <div
        className="relative w-full max-w-md rounded-2xl border border-border-soft bg-bg shadow-elevated overflow-hidden"
        onClick={(e) => e.stopPropagation()}
        style={{ animation: 'pop 200ms cubic-bezier(0.34, 1.56, 0.64, 1)' }}
      >
        <div className="flex items-center justify-between border-b border-border-soft px-4 py-3">
          <div className="flex items-center gap-2">
            <Keyboard size={15} className="text-primary" />
            <h3 className="text-sm font-semibold text-text">Atajos de teclado</h3>
          </div>
          <button
            onClick={() => setAbierto(false)}
            className="rounded p-1 text-subtle hover:bg-surface-2 hover:text-text"
          >
            <X size={14} />
          </button>
        </div>

        <div className="max-h-[60vh] overflow-y-auto py-1">
          {ATAJOS.map((a) => (
            <div
              key={a.descripcion}
              className="flex items-center justify-between px-4 py-2.5 hover:bg-surface-2/50"
            >
              <span className="text-sm text-text">{a.descripcion}</span>
              <div className="flex items-center gap-1">
                {a.combo.map((tecla, i) => (
                  <span key={i} className="inline-flex items-center">
                    <kbd className="inline-flex items-center justify-center min-w-[24px] h-[22px] rounded border border-border-soft bg-surface-2 px-1.5 text-[10.5px] font-mono font-semibold text-text">
                      {tecla}
                    </kbd>
                    {i < a.combo.length - 1 && (
                      <span className="text-subtle text-[10px] mx-0.5">+</span>
                    )}
                  </span>
                ))}
              </div>
            </div>
          ))}
        </div>

        <div className="border-t border-border-soft bg-surface/40 px-4 py-2 text-[10.5px] text-subtle text-center">
          En macOS usa <kbd className="px-1 py-0.5 border border-border-soft rounded font-mono">⌘</kbd> en lugar de <kbd className="px-1 py-0.5 border border-border-soft rounded font-mono">Ctrl</kbd>
        </div>
      </div>

      <style jsx>{`
        @keyframes pop {
          from { opacity: 0; transform: scale(0.94); }
          to { opacity: 1; transform: scale(1); }
        }
      `}</style>
    </div>
  );
}
