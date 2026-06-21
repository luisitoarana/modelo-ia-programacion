import { useEffect, useState } from 'react';
import Link from 'next/link';
import {
  Cpu, Database, ShieldCheck, Gauge, BookOpen, Network,
  History, FlaskConical, Sparkles, CheckCircle2, AlertCircle,
  ArrowRight, Brain, FileSearch, MessagesSquare, TrendingUp,
  Activity, Zap, Presentation
} from 'lucide-react';
import AppLayout from '@/layouts/AppLayout';
import StatCard from '@/components/StatCard';
import { Card } from '@/components/ui/Card';
import Badge from '@/components/ui/Badge';
import LossChart from '@/components/LossChart';
import { obtenerPerfil, UsuarioPerfil } from '@/services/auth';
import {
  estadoModelo, EstadoModelo,
  listarExperimentos, detalleExperimento,
  ExperimentoResumen, ExperimentoDetalle
} from '@/services/model';
import { estadisticasConocimiento, EstadisticasConocimiento } from '@/services/knowledgeGen';
import { formatNumber } from '@/lib/format';
import { cn } from '@/lib/cn';

export default function PanelPage() {
  const [usuario, setUsuario] = useState<UsuarioPerfil | null>(null);
  const [modelo, setModelo] = useState<EstadoModelo | null>(null);
  const [kb, setKb] = useState<EstadisticasConocimiento | null>(null);
  const [experimentos, setExperimentos] = useState<ExperimentoResumen[]>([]);
  const [expActivo, setExpActivo] = useState<ExperimentoDetalle | null>(null);
  const [ultimoRefresh, setUltimoRefresh] = useState<Date>(new Date());

  // Carga inicial + refresco automático cada 30s para métricas live.
  useEffect(() => {
    obtenerPerfil().then(setUsuario).catch(() => {});

    function cargar() {
      estadoModelo().then(setModelo).catch(() => {});
      estadisticasConocimiento().then(setKb).catch(() => {});
      listarExperimentos().then(async (exps) => {
        setExperimentos(exps);
        if (exps.length > 0) {
          // Auto-elegir el más reciente para mostrar su curva.
          try {
            const detalle = await detalleExperimento(exps[0].nombre);
            setExpActivo(detalle);
          } catch { /* noop */ }
        }
      }).catch(() => {});
      setUltimoRefresh(new Date());
    }
    cargar();
    const id = setInterval(cargar, 30_000);
    return () => clearInterval(id);
  }, []);

  const esInvestigador = usuario?.rol === 'investigador' || usuario?.rol === 'administrador';
  const esAdmin = usuario?.rol === 'administrador';

  return (
    <AppLayout>
      <div className="mb-6">
        <h1 className="font-serif text-3xl text-text">Panel general</h1>
        <p className="text-sm text-muted mt-1">
          Estado del sistema, modelo propio y herramientas disponibles para investigación.
        </p>
      </div>

      {/* Estado del modelo */}
      <Card className="mb-6 p-5">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div className="flex items-center gap-3">
            <div className="flex h-11 w-11 items-center justify-center rounded-xl bg-primary-soft text-primary">
              <Brain size={22} />
            </div>
            <div>
              <div className="flex items-center gap-2">
                <h2 className="font-semibold">Modelo propio (LLM desde cero)</h2>
                {modelo?.disponible ? (
                  <Badge tone="success">
                    <CheckCircle2 size={11} /> activo
                  </Badge>
                ) : (
                  <Badge tone="warning">
                    <AlertCircle size={11} /> no entrenado
                  </Badge>
                )}
              </div>
              <p className="text-sm text-muted mt-0.5">
                {modelo?.disponible
                  ? `${formatNumber(modelo.num_parametros || 0)} parámetros · ${modelo.device}`
                  : modelo?.motivo || 'Entrena el modelo con python -m ml.train y actívalo en .env'}
              </p>
            </div>
          </div>
          <Link
            href="/"
            className="inline-flex items-center gap-1.5 rounded-lg bg-primary px-4 py-2 text-sm font-medium text-primary-foreground hover:bg-primary-hover"
          >
            Ir al asistente
            <ArrowRight size={14} />
          </Link>
        </div>
      </Card>

      {/* Curva de entrenamiento — en vivo */}
      {esInvestigador && expActivo && expActivo.metrics.length > 0 && (
        <Card className="mb-6 p-5 animate-fade-in">
          <div className="mb-3 flex items-start justify-between gap-3 flex-wrap">
            <div className="flex items-start gap-3">
              <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-accent-soft text-accent">
                <Activity size={18} />
              </div>
              <div>
                <h3 className="font-semibold text-text flex items-center gap-2 flex-wrap">
                  Curva de entrenamiento
                  <Badge tone="primary">{expActivo.nombre}</Badge>
                  <span className="inline-flex items-center gap-1 text-[10.5px] text-success">
                    <span className="h-1.5 w-1.5 rounded-full bg-success animate-pulse" />
                    en vivo
                  </span>
                </h3>
                <p className="text-xs text-subtle mt-0.5">
                  {expActivo.metrics.length} puntos · última iter {expActivo.metrics[expActivo.metrics.length - 1].iter}
                  {' · '}
                  refrescado {Math.round((Date.now() - ultimoRefresh.getTime()) / 1000)}s atrás
                </p>
              </div>
            </div>
            {experimentos.length > 1 && (
              <select
                value={expActivo.nombre}
                onChange={async (e) => {
                  try {
                    const d = await detalleExperimento(e.target.value);
                    setExpActivo(d);
                  } catch { /* noop */ }
                }}
                className="h-9 rounded-lg border border-border-soft bg-surface-2 px-3 text-xs text-text"
              >
                {experimentos.map((e) => (
                  <option key={e.nombre} value={e.nombre}>{e.nombre}</option>
                ))}
              </select>
            )}
          </div>
          <LossChart metrics={expActivo.metrics} />
          <div className="mt-3 grid gap-3 sm:grid-cols-4">
            <MiniMetric
              label="Train loss"
              value={expActivo.metrics[expActivo.metrics.length - 1].train_loss?.toFixed(3) ?? '—'}
              tone="primary"
            />
            <MiniMetric
              label="Val loss"
              value={expActivo.metrics[expActivo.metrics.length - 1].val_loss?.toFixed(3) ?? '—'}
              tone="accent"
            />
            <MiniMetric
              label="Learning rate"
              value={expActivo.metrics[expActivo.metrics.length - 1].lr?.toExponential(2) ?? '—'}
              tone="muted"
            />
            <MiniMetric
              label="Iter actual"
              value={String(expActivo.metrics[expActivo.metrics.length - 1].iter)}
              tone="muted"
            />
          </div>
        </Card>
      )}

      {/* Métricas del conocimiento */}
      {esInvestigador && kb && (
        <div className="mb-8 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          <StatCard
            label="Independencia de APIs"
            value={`${kb.tasa_independencia_api}%`}
            hint="respuestas sin API"
            icon={<ShieldCheck size={22} />}
            tone="success"
          />
          <StatCard
            label="Unidades de conocimiento"
            value={formatNumber(kb.total_unidades)}
            hint={`${kb.validadas} validadas`}
            icon={<Database size={22} />}
            tone="primary"
          />
          <StatCard
            label="Reutilizaciones"
            value={formatNumber(kb.reutilizaciones_totales)}
            icon={<Gauge size={22} />}
            tone="accent"
          />
          <StatCard
            label="Cobertura del currículo"
            value={`${kb.cobertura_curriculo}%`}
            icon={<BookOpen size={22} />}
            tone="warning"
          />
        </div>
      )}

      {/* Herramientas — la parte importante: cada tarjeta explica para qué sirve */}
      {esInvestigador && (
        <>
          <div className="mb-3 flex items-baseline justify-between">
            <h2 className="text-lg font-semibold text-text">Herramientas de investigación</h2>
            <span className="text-xs text-subtle">
              Solo visibles para investigador/administrador
            </span>
          </div>

          <div className="grid gap-3 sm:grid-cols-2">
            <ToolCard
              href="/conocimiento"
              icon={<Database size={18} />}
              titulo="Base de conocimiento"
              descripcion="Las unidades de conocimiento que el sistema reutiliza para responder sin APIs. Cuanto más validadas, más independiente es la IA. Aquí ves cuáles fueron generadas, cuáles aprobadas y cuáles se reutilizan más."
              tone="primary"
            />
            <ToolCard
              href="/dataset"
              icon={<FileSearch size={18} />}
              titulo="Dataset & Validación"
              descripcion="Los ejemplos que se usan para entrenar el modelo propio. Aquí validas la calidad de cada uno: si está aprobado pasa al set de entrenamiento. Mientras más ejemplos validados, mejor aprende el modelo."
              tone="accent"
            />
            <ToolCard
              href="/entrenamiento"
              icon={<Cpu size={18} />}
              titulo="Entrenamiento"
              descripcion="Lanza el entrenamiento del LLM propio sobre el dataset validado y mira la curva de pérdida en vivo. Cada época mejora la comprensión del modelo."
              tone="success"
            />
            <ToolCard
              href="/historial"
              icon={<History size={18} />}
              titulo="Historial"
              descripcion="Todas las consultas pedagógicas que el sistema ha respondido. Útil para analizar qué temas son más demandados y dónde el modelo flaquea."
              tone="warning"
            />
            <ToolCard
              href="/investigacion"
              icon={<FlaskConical size={18} />}
              titulo="Reportes de investigación"
              descripcion="Métricas listas para tu tesis: comprensión algorítmica, satisfacción del estudiante, reutilización de conocimiento, independencia de APIs. Exportables."
              tone="primary"
            />
            <ToolCard
              href="/proyecto"
              icon={<Network size={18} />}
              titulo="Mapa del proyecto"
              descripcion="Visualización de toda la arquitectura: backend, frontend, modelos, datasets, training. Útil para entender cómo se conectan las piezas o explicar el sistema en tu defensa de tesis."
              tone="accent"
            />
            {esAdmin && (
              <ToolCard
                href="/admin"
                icon={<Sparkles size={18} />}
                titulo="Panel admin"
                descripcion="Configurar API keys (Gemini, DeepSeek) cifradas en BD, generar dataset desde currículo, y ver resumen general de usuarios/consultas. Solo para administrador."
                tone="danger"
              />
            )}
            <ToolCard
              href="/chat"
              icon={<MessagesSquare size={18} />}
              titulo="Chat con el modelo propio"
              descripcion="Habla directamente con el LLM entrenado, sin pasar por APIs externas. Sirve para probar la calidad del modelo después de cada entrenamiento."
              tone="primary"
            />
            <ToolCard
              href="/presentacion"
              icon={<Presentation size={18} />}
              titulo="Modo presentación"
              descripcion="Pantalla limpia con métricas grandes, carrusel automático de slides y atajos de teclado. Pensado para defender tu tesis frente al jurado."
              tone="accent"
            />
          </div>
        </>
      )}
    </AppLayout>
  );
}

// ──────── Tarjeta de herramienta con descripción clara ────────

const TONES: Record<string, string> = {
  primary: 'text-primary bg-primary-soft',
  accent: 'text-accent bg-accent-soft',
  success: 'text-success bg-success/10',
  warning: 'text-warning bg-warning/10',
  danger: 'text-danger bg-danger/10',
  neutral: 'text-muted bg-surface-2'
};

function MiniMetric({
  label, value, tone = 'muted'
}: {
  label: string;
  value: string;
  tone?: 'primary' | 'accent' | 'muted';
}) {
  const toneClass: Record<string, string> = {
    primary: 'text-primary',
    accent: 'text-accent',
    muted: 'text-text'
  };
  return (
    <div className="rounded-lg border border-border-soft bg-surface-2/40 px-3 py-2.5">
      <div className="text-[10.5px] uppercase tracking-wider text-subtle font-semibold mb-0.5">
        {label}
      </div>
      <div className={cn('text-base font-bold font-mono', toneClass[tone])}>
        {value}
      </div>
    </div>
  );
}

function ToolCard({
  href, icon, titulo, descripcion, tone = 'primary'
}: {
  href: string;
  icon: React.ReactNode;
  titulo: string;
  descripcion: string;
  tone?: keyof typeof TONES;
}) {
  return (
    <Link
      href={href}
      className="group flex gap-3 rounded-xl border border-border-soft bg-surface p-4 transition-all hover:border-border hover:shadow-soft"
    >
      <div
        className={cn(
          'flex h-10 w-10 shrink-0 items-center justify-center rounded-lg',
          TONES[tone]
        )}
      >
        {icon}
      </div>
      <div className="min-w-0 flex-1">
        <div className="flex items-center gap-1.5">
          <h3 className="font-semibold text-text text-sm">{titulo}</h3>
          <ArrowRight
            size={12}
            className="text-subtle opacity-0 -translate-x-1 transition-all group-hover:opacity-100 group-hover:translate-x-0"
          />
        </div>
        <p className="mt-1 text-xs text-muted leading-relaxed">{descripcion}</p>
      </div>
    </Link>
  );
}
