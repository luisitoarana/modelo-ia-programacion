import { useEffect, useState } from 'react';
import {
  Sparkles, MessageSquare, Keyboard, Palette, Mic,
  ArrowRight, Check, X, Github
} from 'lucide-react';

/**
 * Onboarding interactivo de primeros pasos.
 *
 * Se muestra automáticamente la primera vez que el usuario entra al
 * sistema. 5 slides:
 *   1. Bienvenida
 *   2. Cómo hacer preguntas
 *   3. Atajos de teclado
 *   4. Personalización (paletas)
 *   5. Voz y exportar
 *
 * Persiste el estado de "completado" en localStorage para no mostrarlo
 * de nuevo. Se puede reabrir desde Settings → Ayuda.
 */

const STORAGE_KEY = 'explicador.onboarding_v1';

const SLIDES = [
  {
    icon: <Sparkles size={36} />,
    titulo: 'Bienvenido a Explicador IA',
    subtitulo: 'Plataforma educativa para Python con tu propio LLM',
    descripcion:
      'Te voy a guiar en menos de 30 segundos por las funciones más útiles. Puedes saltarlo y siempre volver desde Configuración → Ayuda.',
    cta: 'Empezar',
  },
  {
    icon: <MessageSquare size={36} />,
    titulo: 'Pregunta lo que sea',
    subtitulo: 'En lenguaje natural, como a un profesor',
    descripcion:
      'Escribe en el chat preguntas tipo "explícame qué es una función lambda" o "genera un ejemplo de list comprehension". El sistema busca primero en su conocimiento propio y, si no encuentra, consulta una API externa.',
    cta: 'Siguiente',
  },
  {
    icon: <Keyboard size={36} />,
    titulo: 'Atajos de teclado',
    subtitulo: 'Acelera tu uso del sistema',
    descripcion: 'shortcuts',
    cta: 'Siguiente',
  },
  {
    icon: <Palette size={36} />,
    titulo: 'Personaliza el aspecto',
    subtitulo: '5 paletas + modo claro/oscuro',
    descripcion:
      'En Configuración → Apariencia puedes elegir entre 5 paletas (Terracota, Académico Azul, Verde Bosque, Púrpura Real y Minimalista) que cambian toda la app instantáneamente. Útil para la defensa de tesis.',
    cta: 'Siguiente',
  },
  {
    icon: <Mic size={36} />,
    titulo: 'Voz, web y exportación',
    subtitulo: 'Funciones avanzadas para no perder el ritmo',
    descripcion:
      'Activa el micrófono para dictar; el botón "Buscar en internet" enriquece las respuestas con fuentes actualizadas; exporta cualquier chat como Markdown o PDF para tu tesis.',
    cta: 'Terminar',
  },
];

const ATAJOS_PREVIEW = [
  { combo: 'Ctrl + K', desc: 'Búsqueda global' },
  { combo: 'Ctrl + N', desc: 'Nuevo chat' },
  { combo: 'Ctrl + ,', desc: 'Configuración' },
  { combo: 'Ctrl + /', desc: 'Ver atajos' },
];

export default function Onboarding({ forzar = false }: { forzar?: boolean }) {
  const [abierto, setAbierto] = useState(false);
  const [paso, setPaso] = useState(0);

  // Auto-abrir la primera vez.
  useEffect(() => {
    if (typeof window === 'undefined') return;
    const completado = window.localStorage.getItem(STORAGE_KEY) === 'true';
    if (!completado || forzar) {
      // Pequeño delay para que la página termine de cargar.
      const id = setTimeout(() => setAbierto(true), 600);
      return () => clearTimeout(id);
    }
  }, [forzar]);

  // Permitir reabrir vía evento global.
  useEffect(() => {
    function reabrir() {
      setPaso(0);
      setAbierto(true);
    }
    window.addEventListener('explicador:onboarding', reabrir);
    return () => window.removeEventListener('explicador:onboarding', reabrir);
  }, []);

  // Atajos: Esc cierra, ← → navegan.
  useEffect(() => {
    if (!abierto) return;
    function handler(e: KeyboardEvent) {
      if (e.key === 'Escape') { e.preventDefault(); cerrar(); }
      else if (e.key === 'ArrowLeft') { e.preventDefault(); setPaso((p) => Math.max(0, p - 1)); }
      else if (e.key === 'ArrowRight' || e.key === 'Enter') {
        e.preventDefault();
        if (paso < SLIDES.length - 1) setPaso(paso + 1);
        else cerrar();
      }
    }
    window.addEventListener('keydown', handler);
    return () => window.removeEventListener('keydown', handler);
  }, [abierto, paso]);

  function cerrar() {
    if (typeof window !== 'undefined') {
      window.localStorage.setItem(STORAGE_KEY, 'true');
    }
    setAbierto(false);
  }

  if (!abierto) return null;
  const slide = SLIDES[paso];

  return (
    <div
      className="fixed inset-0 z-[80] flex items-center justify-center p-4 animate-fade-in"
      onClick={cerrar}
    >
      <div className="absolute inset-0 bg-black/65 backdrop-blur-md" />

      <div
        className="relative w-full max-w-lg rounded-2xl border border-border-soft bg-bg shadow-elevated overflow-hidden"
        onClick={(e) => e.stopPropagation()}
        style={{ animation: 'onboard-pop 280ms cubic-bezier(0.34, 1.56, 0.64, 1)' }}
      >
        {/* Botón cerrar */}
        <button
          onClick={cerrar}
          className="absolute right-3 top-3 z-10 rounded-md p-1.5 text-subtle hover:bg-surface-2 hover:text-text transition-colors"
          aria-label="Saltar tutorial"
        >
          <X size={14} />
        </button>

        {/* Contenido */}
        <div className="px-8 pt-12 pb-6">
          <div className="flex items-center justify-center mb-6">
            <div className="flex h-16 w-16 items-center justify-center rounded-2xl bg-primary-soft text-primary shadow-soft">
              {slide.icon}
            </div>
          </div>

          <h2 className="font-serif text-2xl text-text text-center mb-1">
            {slide.titulo}
          </h2>
          <p className="text-sm text-primary text-center font-medium mb-4">
            {slide.subtitulo}
          </p>

          {/* Cuerpo: texto o atajos */}
          {slide.descripcion === 'shortcuts' ? (
            <div className="mb-6 rounded-xl border border-border-soft bg-surface/50 p-3 space-y-2">
              {ATAJOS_PREVIEW.map((a) => (
                <div key={a.combo} className="flex items-center justify-between">
                  <span className="text-sm text-text">{a.desc}</span>
                  <kbd className="px-2 py-0.5 text-[11px] font-mono font-semibold border border-border-soft bg-surface-2 rounded">
                    {a.combo}
                  </kbd>
                </div>
              ))}
              <p className="text-[11px] text-subtle text-center pt-1.5 border-t border-border-soft">
                Mira la lista completa con <kbd className="px-1 py-0.5 text-[10px] font-mono border border-border-soft bg-surface-2 rounded">Ctrl+/</kbd>
              </p>
            </div>
          ) : (
            <p className="text-sm text-muted text-center leading-relaxed mb-6 max-w-md mx-auto">
              {slide.descripcion}
            </p>
          )}
        </div>

        {/* Footer con dots + botón */}
        <div className="flex items-center justify-between border-t border-border-soft bg-surface/40 px-6 py-4">
          {/* Dots */}
          <div className="flex gap-1.5">
            {SLIDES.map((_, i) => (
              <button
                key={i}
                onClick={() => setPaso(i)}
                className={
                  'h-1.5 rounded-full transition-all ' +
                  (i === paso
                    ? 'w-6 bg-primary'
                    : i < paso
                      ? 'w-1.5 bg-primary/40'
                      : 'w-1.5 bg-border')
                }
                aria-label={`Ir al paso ${i + 1}`}
              />
            ))}
          </div>

          <div className="flex gap-2">
            {paso > 0 && (
              <button
                onClick={() => setPaso(paso - 1)}
                className="rounded-lg border border-border-soft bg-surface px-3 py-1.5 text-xs font-medium text-text hover:bg-surface-2 transition-colors"
              >
                Atrás
              </button>
            )}
            <button
              onClick={() => {
                if (paso < SLIDES.length - 1) setPaso(paso + 1);
                else cerrar();
              }}
              className="inline-flex items-center gap-1.5 rounded-lg bg-primary px-4 py-1.5 text-xs font-semibold text-primary-foreground hover:bg-primary-hover transition-colors"
            >
              {slide.cta}
              {paso === SLIDES.length - 1 ? (
                <Check size={12} />
              ) : (
                <ArrowRight size={12} />
              )}
            </button>
          </div>
        </div>
      </div>

      <style jsx>{`
        @keyframes onboard-pop {
          from { opacity: 0; transform: scale(0.94) translateY(12px); }
          to { opacity: 1; transform: scale(1) translateY(0); }
        }
      `}</style>
    </div>
  );
}
