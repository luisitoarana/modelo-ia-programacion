import { FormEvent, useEffect, useRef, useState } from 'react';
import { Send, Cpu, AlertTriangle, User } from 'lucide-react';
import AppLayout from '@/layouts/AppLayout';
import { Card } from '@/components/ui/Card';
import Badge from '@/components/ui/Badge';
import Button from '@/components/ui/Button';
import { estadoModelo, EstadoModelo, preguntarModelo } from '@/services/model';
import { formatNumber } from '@/lib/format';
import { mensajeError } from '@/lib/errors';

interface Mensaje {
  rol: 'usuario' | 'modelo';
  texto: string;
  meta?: string;
}

export default function ChatPage() {
  const [estado, setEstado] = useState<EstadoModelo | null>(null);
  const [mensajes, setMensajes] = useState<Mensaje[]>([]);
  const [entrada, setEntrada] = useState('');
  const [cargando, setCargando] = useState(false);
  const finRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    estadoModelo().then(setEstado).catch(() => {});
  }, []);

  useEffect(() => {
    finRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [mensajes]);

  async function enviar(e: FormEvent) {
    e.preventDefault();
    const texto = entrada.trim();
    if (!texto || cargando) return;
    setMensajes((m) => [...m, { rol: 'usuario', texto }]);
    setEntrada('');
    setCargando(true);
    try {
      const r = await preguntarModelo({ instruccion: texto });
      setMensajes((m) => [
        ...m,
        {
          rol: 'modelo',
          texto: r.texto || '(el modelo no generó texto)',
          meta: `${r.tokens_generados} tokens · ${r.latencia_segundos}s · ${r.device}`
        }
      ]);
    } catch (err: any) {
      setMensajes((m) => [
        ...m,
        {
          rol: 'modelo',
          texto: mensajeError(err, 'El modelo propio no está disponible todavía.')
        }
      ]);
    } finally {
      setCargando(false);
    }
  }

  return (
    <AppLayout>
      <div className="mb-4 flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold">Chat con el modelo propio</h1>
          <p className="text-sm text-muted">
            Las respuestas las genera tu LLM entrenado desde cero, sin ninguna API externa.
          </p>
        </div>
        {estado &&
          (estado.disponible ? (
            <Badge tone="success">
              <Cpu size={13} /> {formatNumber(estado.num_parametros || 0)} params · {estado.device}
            </Badge>
          ) : (
            <Badge tone="warning">
              <AlertTriangle size={13} /> modelo no entrenado
            </Badge>
          ))}
      </div>

      {estado && !estado.disponible && (
        <Card className="mb-4 border-warning/40 bg-warning/5 p-4">
          <div className="flex gap-3">
            <AlertTriangle className="mt-0.5 shrink-0 text-warning" size={18} />
            <div className="text-sm">
              <p className="font-medium">El modelo propio aún no está activo.</p>
              <p className="mt-1 text-muted">{estado.motivo}</p>
              <ol className="mt-2 list-decimal space-y-1 pl-5 text-muted">
                <li>Genera dataset: <code className="rounded bg-surface-2 px-1">python -m ml.data.generator --proveedor gemini</code></li>
                <li>Entrena: <code className="rounded bg-surface-2 px-1">python -m ml.train --preset pequeno</code></li>
                <li>Activa en <code>.env</code>: <code className="rounded bg-surface-2 px-1">MODEL_ENABLED=true</code> y reinicia el backend.</li>
              </ol>
            </div>
          </div>
        </Card>
      )}

      <Card className="flex h-[64vh] flex-col p-0">
        <div className="flex-1 space-y-4 overflow-y-auto p-5">
          {mensajes.length === 0 && (
            <div className="flex h-full flex-col items-center justify-center text-center text-muted">
              <Cpu size={32} className="mb-2 opacity-50" />
              <p className="text-sm">Escribe una pregunta, p. ej. "Explica los bucles for".</p>
            </div>
          )}
          {mensajes.map((m, i) => (
            <div key={i} className={`flex gap-3 ${m.rol === 'usuario' ? 'flex-row-reverse' : ''}`}>
              <div
                className={`flex h-8 w-8 shrink-0 items-center justify-center rounded-lg ${
                  m.rol === 'usuario' ? 'bg-primary text-primary-foreground' : 'bg-accent-soft text-accent'
                }`}
              >
                {m.rol === 'usuario' ? <User size={16} /> : <Cpu size={16} />}
              </div>
              <div
                className={`max-w-[78%] rounded-xl px-4 py-2.5 text-sm ${
                  m.rol === 'usuario' ? 'bg-primary text-primary-foreground' : 'border bg-surface-2'
                }`}
              >
                <p className="whitespace-pre-wrap leading-relaxed">{m.texto}</p>
                {m.meta && <p className="mt-1 text-[11px] opacity-70">{m.meta}</p>}
              </div>
            </div>
          ))}
          {cargando && (
            <div className="flex items-center gap-2 text-sm text-muted">
              <Cpu size={16} className="animate-pulse" /> el modelo está generando…
            </div>
          )}
          <div ref={finRef} />
        </div>

        <form onSubmit={enviar} className="flex gap-2 border-t p-3">
          <input
            value={entrada}
            onChange={(e) => setEntrada(e.target.value)}
            placeholder="Escribe tu pregunta…"
            className="h-11 flex-1 rounded-lg border bg-surface px-3.5 text-sm focus-ring"
            disabled={cargando}
          />
          <Button type="submit" loading={cargando} size="icon" aria-label="Enviar">
            {!cargando && <Send size={18} />}
          </Button>
        </form>
      </Card>
    </AppLayout>
  );
}
