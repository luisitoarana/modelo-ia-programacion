import { useEffect, useState } from 'react';
import {
  Cpu, Activity, Terminal, RefreshCw, TrendingDown,
  Zap, Clock, Hash, Layers, Box, CheckCircle2, AlertCircle,
  Play, Pause
} from 'lucide-react';
import AppLayout from '@/layouts/AppLayout';
import { Card, CardHeader, CardBody } from '@/components/ui/Card';
import Badge from '@/components/ui/Badge';
import Button from '@/components/ui/Button';
import LossChart from '@/components/LossChart';
import {
  EstadoModelo, ExperimentoResumen, ExperimentoDetalle,
  estadoModelo, listarExperimentos, detalleExperimento
} from '@/services/model';
import { formatNumber } from '@/lib/format';
import { cn } from '@/lib/cn';

export default function EntrenamientoPage() {
  const [modelo, setModelo] = useState<EstadoModelo | null>(null);
  const [exps, setExps] = useState<ExperimentoResumen[]>([]);
  const [sel, setSel] = useState<ExperimentoDetalle | null>(null);
  const [cargando, setCargando] = useState(false);
  const [autoRefresh, setAutoRefresh] = useState(true);
  const [ultimoRefresh, setUltimoRefresh] = useState<Date>(new Date());

  async function refrescar(mantenerSel = false) {
    setCargando(true);
    try {
      const [m, e] = await Promise.all([estadoModelo(), listarExperimentos()]);
      setModelo(m);
      setExps(e);
      // Si hay selección, refrescar SU detalle. Si no, auto-elegir el más reciente.
      if (sel && mantenerSel) {
        const detalle = await detalleExperimento(sel.nombre);
        setSel(detalle);
      } else if (e[0] && !sel) {
        setSel(await detalleExperimento(e[0].nombre));
      }
      setUltimoRefresh(new Date());
    } catch {
      /* silencioso */
    } finally {
      setCargando(false);
    }
  }

  useEffect(() => {
    refrescar();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Auto-refresh cada 5s mientras esté activo.
  useEffect(() => {
    if (!autoRefresh) return;
    const id = setInterval(() => refrescar(true), 5_000);
    return () => clearInterval(id);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [autoRefresh, sel]);

  async function abrir(nombre: string) {
    setSel(await detalleExperimento(nombre));
  }

  // Calcular métricas derivadas del experimento activo.
  const ultimaMetric = sel?.metrics[sel.metrics.length - 1];
  const primeraMetric = sel?.metrics[0];
  const tendencia = ultimaMetric && primeraMetric && primeraMetric.train_loss && ultimaMetric.train_loss
    ? ((primeraMetric.train_loss - ultimaMetric.train_loss) / primeraMetric.train_loss * 100)
    : 0;
  const segundosAtras = Math.round((Date.now() - ultimoRefresh.getTime()) / 1000);

  return (
    <AppLayout>
      <div className="mb-6 flex items-start justify-between gap-3 flex-wrap animate-fade-in">
        <div className="flex items-start gap-3">
          <div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-xl bg-primary-soft text-primary">
            <Cpu size={22} />
          </div>
          <div>
            <h1 className="font-serif text-3xl text-text">Entrenamiento del modelo propio</h1>
            <p className="mt-1 text-sm text-muted">
              Métricas en tiempo real del LLM educativo entrenado desde cero con tu GPU.
            </p>
          </div>
        </div>
        <div className="flex items-center gap-2">
          <button
            onClick={() => setAutoRefresh(!autoRefresh)}
            className={cn(
              'inline-flex items-center gap-1.5 rounded-lg px-3 py-1.5 text-xs font-medium transition-colors',
              autoRefresh
                ? 'bg-success/10 text-success border border-success/30'
                : 'bg-surface border border-border-soft text-muted hover:bg-surface-2'
            )}
          >
            {autoRefresh ? (
              <>
                <span className="h-1.5 w-1.5 rounded-full bg-success animate-pulse" />
                Auto-refresh
              </>
            ) : (
              <>
                <Pause size={11} />
                Manual
              </>
            )}
          </button>
          <Button variant="outline" size="sm" onClick={() => refrescar(true)} loading={cargando}>
            {!cargando && <RefreshCw size={14} />}
            Refrescar
          </Button>
        </div>
      </div>

      {/* Estado del modelo en producción */}
      <div className="mb-6 rounded-2xl border border-border-soft bg-surface p-5 animate-fade-in">
        <div className="flex items-start justify-between flex-wrap gap-3">
          <div className="flex items-start gap-3">
            <div className={cn(
              'flex h-11 w-11 items-center justify-center rounded-xl',
              modelo?.disponible ? 'bg-success/15 text-success' : 'bg-warning/15 text-warning'
            )}>
              {modelo?.disponible ? <CheckCircle2 size={20} /> : <AlertCircle size={20} />}
            </div>
            <div>
              <div className="flex items-center gap-2 flex-wrap">
                <h2 className="font-semibold text-text">Modelo en producción</h2>
                {modelo?.disponible ? (
                  <Badge tone="success">
                    <CheckCircle2 size={11} /> activo
                  </Badge>
                ) : (
                  <Badge tone="warning">no activo</Badge>
                )}
              </div>
              <p className="mt-0.5 text-sm text-muted">
                {modelo?.disponible
                  ? `${formatNumber(modelo.num_parametros || 0)} parámetros · ${modelo.device}`
                  : modelo?.motivo || 'Entrena con python -m ml.train y activa en .env'}
              </p>
              {modelo?.checkpoint && (
                <p className="mt-1 text-[11px] text-subtle font-mono break-all">
                  {modelo.checkpoint}
                </p>
              )}
            </div>
          </div>
        </div>
      </div>

      {/* Curva + métricas */}
      {sel && (
        <div className="mb-6 rounded-2xl border border-border-soft bg-surface p-5 animate-fade-in">
          <div className="flex items-start justify-between flex-wrap gap-3 mb-4">
            <div className="flex items-start gap-3">
              <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-accent-soft text-accent">
                <Activity size={18} />
              </div>
              <div>
                <h3 className="font-semibold text-text flex items-center gap-2 flex-wrap">
                  Curva de pérdida
                  <Badge tone="primary">{sel.nombre}</Badge>
                  {autoRefresh && (
                    <span className="inline-flex items-center gap-1 text-[10.5px] text-success">
                      <span className="h-1.5 w-1.5 rounded-full bg-success animate-pulse" />
                      en vivo
                    </span>
                  )}
                </h3>
                <p className="text-xs text-subtle mt-0.5">
                  {sel.metrics.length} puntos · refrescado hace {segundosAtras}s
                </p>
              </div>
            </div>
            {tendencia > 0 && (
              <div className="inline-flex items-center gap-1.5 rounded-lg border border-success/30 bg-success/5 px-3 py-1.5 text-xs">
                <TrendingDown size={12} className="text-success" />
                <span className="font-semibold text-success">{tendencia.toFixed(1)}%</span>
                <span className="text-success/70">de mejora</span>
              </div>
            )}
          </div>

          <LossChart metrics={sel.metrics} />

          {/* Tarjetas de métricas en tiempo real */}
          {ultimaMetric && (
            <div className="mt-4 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
              <MetricaCard
                icon={<TrendingDown size={14} />}
                label="Train loss"
                value={ultimaMetric.train_loss?.toFixed(4) ?? '—'}
                tone="primary"
              />
              <MetricaCard
                icon={<TrendingDown size={14} />}
                label="Val loss"
                value={ultimaMetric.val_loss?.toFixed(4) ?? '—'}
                tone="accent"
              />
              <MetricaCard
                icon={<Zap size={14} />}
                label="Learning rate"
                value={ultimaMetric.lr?.toExponential(2) ?? '—'}
                tone="warning"
              />
              <MetricaCard
                icon={<Hash size={14} />}
                label="Iter actual"
                value={String(ultimaMetric.iter)}
                tone="muted"
              />
            </div>
          )}

          {/* Config del modelo */}
          {sel.config && (
            <div className="mt-4 flex flex-wrap gap-1.5 pt-4 border-t border-border-soft">
              {sel.config.num_parametros && (
                <Badge tone="primary">
                  <Box size={10} />
                  {formatNumber(sel.config.num_parametros)} params
                </Badge>
              )}
              {sel.config.device && (
                <Badge tone="neutral">
                  <Cpu size={10} />
                  {sel.config.device}
                </Badge>
              )}
              {sel.config.model?.n_layer && (
                <Badge tone="accent">
                  <Layers size={10} />
                  {sel.config.model.n_layer} capas
                </Badge>
              )}
              {sel.config.model?.n_embd && (
                <Badge tone="accent">n_embd {sel.config.model.n_embd}</Badge>
              )}
              {sel.config.model?.block_size && (
                <Badge tone="neutral">ctx {sel.config.model.block_size}</Badge>
              )}
              {sel.config.model?.n_head && (
                <Badge tone="neutral">{sel.config.model.n_head} heads</Badge>
              )}
              {sel.config.model?.vocab_size && (
                <Badge tone="neutral">vocab {sel.config.model.vocab_size}</Badge>
              )}
            </div>
          )}
        </div>
      )}

      {/* Lista de experimentos */}
      <div className="grid gap-4 lg:grid-cols-2">
        <Card>
          <CardHeader title="Experimentos" icon={<Activity size={18} />} />
          <CardBody className="space-y-2 pt-3">
            {exps.length === 0 ? (
              <div className="text-center py-6">
                <Activity size={28} className="mx-auto text-subtle mb-2" />
                <p className="text-sm text-text font-medium">Sin experimentos aún</p>
                <p className="text-xs text-subtle mt-0.5">
                  Lanza uno con <code className="rounded bg-surface-2 px-1 text-[10.5px]">python -m ml.train</code>
                </p>
              </div>
            ) : (
              exps.map((e) => (
                <button
                  key={e.nombre}
                  onClick={() => abrir(e.nombre)}
                  className={cn(
                    'w-full rounded-xl border p-3 text-left text-sm transition-all hover:shadow-soft',
                    sel?.nombre === e.nombre
                      ? 'border-primary bg-primary-soft/30'
                      : 'border-border-soft bg-surface hover:border-border'
                  )}
                >
                  <div className="flex items-start justify-between gap-2 mb-1">
                    <span className="font-semibold text-text truncate">{e.nombre}</span>
                    <Badge tone="neutral">{e.iteraciones} it</Badge>
                  </div>
                  <div className="text-xs text-muted flex items-center gap-2 flex-wrap">
                    <span>{formatNumber(e.num_parametros || 0)} params</span>
                    {e.ultimo_val_loss && (
                      <>
                        <span>·</span>
                        <span>val {e.ultimo_val_loss.toFixed(3)}</span>
                      </>
                    )}
                    {e.device && (
                      <>
                        <span>·</span>
                        <span>{e.device}</span>
                      </>
                    )}
                  </div>
                </button>
              ))
            )}
          </CardBody>
        </Card>

        <Card>
          <CardHeader title="Cómo entrenar" icon={<Terminal size={18} />} />
          <CardBody className="pt-3">
            <pre className="overflow-x-auto rounded-xl bg-code-bg p-4 text-[11.5px] text-code-text leading-relaxed">
{`# 1) Generar dataset con APIs
python -m ml.data.generator \\
    --proveedor deepseek \\
    --por-objetivo 30 \\
    --salida datasets/raw/exp.jsonl

# 2) Combinar corpus
python -m ml.data.combinar \\
    --entradas datasets/raw/*.jsonl \\
    --salida datasets/processed/train.jsonl

# 3) Entrenar (usa tu GPU)
python -m ml.train \\
    --preset experto \\
    --iters 30000 \\
    --batch 2 \\
    --corpus datasets/processed/train.jsonl \\
    --experimento tesis_v1 \\
    --tokenizer-backend sp

# 4) Activar en .env y reiniciar
# MODEL_ENABLED=true
# MODEL_CHECKPOINT_PATH=training/checkpoints/tesis_v1_best.pt
docker compose restart backend`}
            </pre>
          </CardBody>
        </Card>
      </div>
    </AppLayout>
  );
}

function MetricaCard({
  icon, label, value, tone
}: {
  icon: React.ReactNode;
  label: string;
  value: string;
  tone: 'primary' | 'accent' | 'warning' | 'muted';
}) {
  const toneIcon: Record<string, string> = {
    primary: 'bg-primary-soft text-primary',
    accent: 'bg-accent-soft text-accent',
    warning: 'bg-warning/10 text-warning',
    muted: 'bg-surface-2 text-muted'
  };
  return (
    <div className="rounded-xl border border-border-soft bg-surface p-3 transition-all hover:border-border">
      <div className="flex items-center gap-2 mb-1.5">
        <div className={cn('flex h-6 w-6 items-center justify-center rounded-lg', toneIcon[tone])}>
          {icon}
        </div>
        <span className="text-[10.5px] uppercase tracking-wider text-subtle font-semibold">
          {label}
        </span>
      </div>
      <div className="text-lg font-bold font-mono text-text">{value}</div>
    </div>
  );
}
