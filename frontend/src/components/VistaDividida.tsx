import dynamic from 'next/dynamic';
import { useTheme } from 'next-themes';
import { ReactNode } from 'react';
import { Lightbulb, ListOrdered, Gauge, ClipboardCheck } from 'lucide-react';
import { RespuestaIAEducativa } from '@/services/ai';
import Badge from '@/components/ui/Badge';
import { Card } from '@/components/ui/Card';
import EmptyState from '@/components/ui/EmptyState';

const Editor = dynamic(() => import('@monaco-editor/react'), { ssr: false });

export default function VistaDividida({
  respuesta,
  cabecera
}: {
  respuesta: RespuestaIAEducativa | null;
  cabecera?: ReactNode;
}) {
  const { resolvedTheme } = useTheme();

  if (!respuesta) {
    return (
      <EmptyState
        icon={<Lightbulb size={22} />}
        title="Aún no hay respuesta"
        description="Escribe una solicitud para generar código y su explicación pedagógica."
      />
    );
  }

  return (
    <div className="space-y-4">
      {cabecera}
      <div className="grid gap-4 lg:grid-cols-2">
        <Card className="overflow-hidden">
          <div className="flex items-center justify-between border-b px-4 py-3">
            <h3 className="text-sm font-semibold">Código Python</h3>
            <Badge tone="primary">{respuesta.tema}</Badge>
          </div>
          <Editor
            height="440px"
            defaultLanguage="python"
            value={respuesta.codigo}
            theme={resolvedTheme === 'light' ? 'vs' : 'vs-dark'}
            options={{
              minimap: { enabled: false },
              fontSize: 14,
              automaticLayout: true,
              wordWrap: 'on',
              scrollBeyondLastLine: false
            }}
          />
        </Card>

        <Card className="max-h-[70vh] overflow-y-auto p-5">
          <h3 className="mb-2 text-sm font-semibold">Explicación pedagógica</h3>
          <p className="text-sm leading-relaxed text-muted">{respuesta.explicacion_general}</p>

          {respuesta.conceptos_clave?.length > 0 && (
            <section className="mt-5">
              <h4 className="mb-2 flex items-center gap-2 text-sm font-semibold">
                <Lightbulb size={15} className="text-warning" /> Conceptos clave
              </h4>
              <ul className="space-y-2">
                {respuesta.conceptos_clave.map((c, i) => (
                  <li key={i} className="rounded-lg border bg-surface-2/50 p-3">
                    <div className="flex items-center gap-2">
                      <span className="text-sm font-semibold">{c.concepto}</span>
                      <Badge tone="accent">{c.tipo}</Badge>
                    </div>
                    <p className="mt-1 text-xs text-muted">{c.definicion}</p>
                  </li>
                ))}
              </ul>
            </section>
          )}

          {respuesta.explicacion_linea_por_linea?.length > 0 && (
            <section className="mt-5">
              <h4 className="mb-2 flex items-center gap-2 text-sm font-semibold">
                <ListOrdered size={15} className="text-primary" /> Línea por línea
              </h4>
              <ol className="space-y-2">
                {respuesta.explicacion_linea_por_linea.map((l) => (
                  <li key={l.linea_numero} className="text-sm">
                    <code className="rounded bg-surface-2 px-1.5 py-0.5 font-mono text-xs">
                      {l.codigo_linea}
                    </code>
                    <p className="mt-1 text-muted">{l.semantica}</p>
                  </li>
                ))}
              </ol>
            </section>
          )}

          {respuesta.analisis_complejidad && (
            <section className="mt-5">
              <h4 className="mb-2 flex items-center gap-2 text-sm font-semibold">
                <Gauge size={15} className="text-success" /> Complejidad
              </h4>
              <div className="flex gap-2">
                <Badge tone="primary">Temporal {respuesta.analisis_complejidad.temporal}</Badge>
                <Badge tone="accent">Espacial {respuesta.analisis_complejidad.espacial}</Badge>
              </div>
              <p className="mt-2 text-xs text-muted">
                {respuesta.analisis_complejidad.justificacion}
              </p>
            </section>
          )}

          {respuesta.actividad_evaluativa && (
            <section className="mt-5">
              <h4 className="mb-2 flex items-center gap-2 text-sm font-semibold">
                <ClipboardCheck size={15} className="text-accent" /> Actividad de comprensión
              </h4>
              <div className="rounded-lg border bg-surface-2/50 p-3">
                <Badge tone="neutral">{respuesta.actividad_evaluativa.tipo}</Badge>
                <p className="mt-2 text-sm">{respuesta.actividad_evaluativa.enunciado}</p>
                {respuesta.actividad_evaluativa.opciones?.length > 0 && (
                  <ul className="mt-2 space-y-1 text-sm text-muted">
                    {respuesta.actividad_evaluativa.opciones.map((o, i) => (
                      <li key={i}>{o}</li>
                    ))}
                  </ul>
                )}
              </div>
            </section>
          )}
        </Card>
      </div>
    </div>
  );
}
