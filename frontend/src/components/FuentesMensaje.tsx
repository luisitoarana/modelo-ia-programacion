import { useState } from 'react';
import { BookText, Globe, ChevronDown, ChevronUp } from 'lucide-react';
import { cn } from '@/lib/cn';
import type { FuenteRag, FuenteWeb } from '@/services/chat';

/**
 * Chips de fuentes mostrados debajo de una respuesta del asistente.
 *
 * - `fuentes_rag`: documentos del usuario consultados (anti-alucinación).
 * - `fuentes_web`: páginas web consultadas en tiempo real.
 *
 * Al hacer click sobre un chip se expande el texto / la URL para que el
 * usuario pueda verificar de dónde sale cada afirmación.
 */
interface Props {
  rag?: FuenteRag[];
  web?: FuenteWeb[];
}

export default function FuentesMensaje({ rag = [], web = [] }: Props) {
  const [expandido, setExpandido] = useState(false);
  const total = rag.length + web.length;
  if (total === 0) return null;

  return (
    <div className="mt-3 rounded-lg border border-border-soft bg-surface-2/40 p-2.5">
      <button
        onClick={() => setExpandido((v) => !v)}
        className="flex w-full items-center justify-between gap-2 text-[12px] font-medium text-muted hover:text-text"
      >
        <span className="flex items-center gap-1.5">
          <BookText size={13} />
          {total} {total === 1 ? 'fuente consultada' : 'fuentes consultadas'}
          {rag.length > 0 && (
            <span className="ml-1 rounded-full bg-primary/15 px-1.5 py-0.5 text-[10px] font-semibold text-primary">
              {rag.length} doc{rag.length !== 1 ? 's' : ''}
            </span>
          )}
          {web.length > 0 && (
            <span className="rounded-full bg-accent/15 px-1.5 py-0.5 text-[10px] font-semibold text-accent">
              {web.length} web
            </span>
          )}
        </span>
        {expandido ? <ChevronUp size={13} /> : <ChevronDown size={13} />}
      </button>

      {expandido && (
        <div className="mt-2.5 flex flex-col gap-1.5">
          {rag.map((f) => (
            <ChipRag key={f.chunk_id} fuente={f} />
          ))}
          {web.map((f, i) => (
            <ChipWeb key={`web-${i}`} fuente={f} />
          ))}
        </div>
      )}
    </div>
  );
}

function ChipRag({ fuente }: { fuente: FuenteRag }) {
  return (
    <div className="flex items-center gap-2 rounded-md border border-border-soft bg-surface px-2.5 py-1.5">
      <BookText size={12} className="shrink-0 text-primary" />
      <span className="min-w-0 flex-1 truncate text-[12px] text-text">
        {fuente.titulo}
      </span>
      <span
        className={cn(
          'shrink-0 rounded-full px-1.5 py-0.5 text-[10px] font-semibold',
          fuente.score >= 0.5
            ? 'bg-success/15 text-success'
            : fuente.score >= 0.3
            ? 'bg-warning/15 text-warning'
            : 'bg-muted/15 text-muted',
        )}
        title={`Similitud coseno: ${fuente.score.toFixed(3)}`}
      >
        {(fuente.score * 100).toFixed(0)}%
      </span>
    </div>
  );
}

function ChipWeb({ fuente }: { fuente: FuenteWeb }) {
  const dominio = (() => {
    try {
      return fuente.url ? new URL(fuente.url).hostname : '';
    } catch {
      return '';
    }
  })();
  return (
    <a
      href={fuente.url}
      target="_blank"
      rel="noopener noreferrer"
      className="flex items-center gap-2 rounded-md border border-border-soft bg-surface px-2.5 py-1.5 hover:border-accent"
    >
      <Globe size={12} className="shrink-0 text-accent" />
      <span className="min-w-0 flex-1 truncate text-[12px] text-text">
        {fuente.titulo || dominio || 'Resultado web'}
      </span>
      {dominio && (
        <span className="shrink-0 text-[10px] text-subtle">{dominio}</span>
      )}
    </a>
  );
}
