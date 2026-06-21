import { ReactNode } from 'react';
import { Sparkles } from 'lucide-react';

/**
 * Envoltorio para páginas de auth (login, registro). Incluye:
 *  - Gradiente sutil en el fondo (terracota + cream + accent).
 *  - Grid pattern muy tenue por debajo.
 *  - Tarjeta central con sombra elevada y entrada animada.
 *  - Header con icono + título serif.
 */
export default function AuthShell({
  titulo,
  subtitulo,
  children
}: {
  titulo: string;
  subtitulo: string;
  children: ReactNode;
}) {
  return (
    <div className="relative flex min-h-screen items-center justify-center overflow-hidden bg-bg p-4">
      {/* Gradiente radial muy sutil — solo se nota un poco */}
      <div
        className="pointer-events-none absolute inset-0"
        style={{
          background:
            'radial-gradient(ellipse 80% 60% at 50% 0%, color-mix(in srgb, var(--primary) 8%, transparent), transparent), ' +
            'radial-gradient(ellipse 60% 50% at 100% 100%, color-mix(in srgb, var(--accent) 6%, transparent), transparent)'
        }}
      />

      {/* Grid pattern por debajo del gradiente, muy tenue */}
      <div className="pointer-events-none absolute inset-0 grid-pattern" />

      {/* Glow circular muy difuso detrás del card */}
      <div
        className="pointer-events-none absolute left-1/2 top-1/2 -translate-x-1/2 -translate-y-1/2"
        style={{
          width: 500,
          height: 500,
          background:
            'radial-gradient(circle, color-mix(in srgb, var(--primary) 12%, transparent), transparent 70%)',
          filter: 'blur(40px)'
        }}
      />

      {/* Contenido animado de entrada */}
      <div className="relative w-full max-w-md animate-fade-in">
        <div className="mb-7 flex flex-col items-center text-center">
          <div
            className="mb-4 flex h-14 w-14 items-center justify-center rounded-2xl bg-primary text-primary-foreground shadow-elevated"
            style={{
              boxShadow:
                '0 4px 20px -4px color-mix(in srgb, var(--primary) 50%, transparent), 0 8px 30px -10px color-mix(in srgb, var(--primary) 30%, transparent)'
            }}
          >
            <Sparkles size={26} />
          </div>
          <h1 className="font-serif text-3xl text-text">{titulo}</h1>
          <p className="mt-1.5 text-sm text-muted">{subtitulo}</p>
        </div>

        <div className="card-elevated p-7 backdrop-blur-sm">{children}</div>

        <p className="mt-6 text-center text-xs text-subtle">
          Sistema basado en un LLM propio entrenado desde cero para la
          enseñanza de Python.
        </p>
      </div>
    </div>
  );
}
