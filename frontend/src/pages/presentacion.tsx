import { useEffect, useState } from 'react';
import { useRouter } from 'next/router';
import {
  Brain, Database, ShieldCheck, TrendingUp, Cpu, Zap,
  ArrowLeft, Maximize2, Minimize2, Presentation, Activity
} from 'lucide-react';
import LossChart from '@/components/LossChart';
import { getToken } from '@/services/api';
import { obtenerPerfil, UsuarioPerfil } from '@/services/auth';
import {
  estadoModelo, EstadoModelo,
  listarExperimentos, detalleExperimento,
  ExperimentoResumen, ExperimentoDetalle
} from '@/services/model';
import { estadisticasConocimiento, EstadisticasConocimiento } from '@/services/knowledgeGen';
import { formatNumber } from '@/lib/format';
import { cn } from '@/lib/cn';

/**
 * Modo presentación / kiosko — para defender la tesis frente a jurado.
 *
 * Características:
 *  - Sin sidebar, sin navegación. Solo contenido.
 *  - Métricas grandes y legibles a distancia.
 *  - Curva de pérdida prominente.
 *  - Refresh automático cada 5s.
 *  - Toggle de fullscreen.
 *  - Atajos: F = fullscreen, ESC = salir.
 *  - Carrusel de slides (idle): cambia de pantalla cada 8s para que el
 *    jurado vea todo sin que tengas que clickear.
 */
export default function PresentacionPage() {
  const router = useRouter();
  const [usuario, setUsuario] = useState<UsuarioPerfil | null>(null);
  const [modelo, setModelo] = useState<EstadoModelo | null>(null);
  const [kb, setKb] = useState<EstadisticasConocimiento | null>(null);
  const [exps, setExps] = useState<ExperimentoResumen[]>([]);
  const [expActivo, setExpActivo] = useState<ExperimentoDetalle | null>(null);
  const [slide, setSlide] = useState<0 | 1 | 2>(0);
  const [autoSlide, setAutoSlide] = useState(true);
  const [fullscreen, setFullscreen] = useState(false);

  useEffect(() => {
    if (!getToken()) {
      router.replace('/login');
      return;
    }
    obtenerPerfil().then(setUsuario).catch(() => router.replace('/login'));

    function cargar() {
      estadoModelo().then(setModelo).catch(() => {});
      estadisticasConocimiento().then(setKb).catch(() => {});
      listarExperimentos().then(async (e) => {
        setExps(e);
        if (e.length > 0) {
          try {
            setExpActivo(await detalleExperimento(e[0].nombre));
          } catch { /* noop */ }
        }
      }).catch(() => {});
    }
    cargar();
    const id = setInterval(cargar, 5_000);
    return () => clearInterval(id);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Carrusel automático de slides cada 8s.
  useEffect(() => {
    if (!autoSlide) return;
    const id = setInterval(() => {
      setSlide((s) => ((s + 1) % 3) as 0 | 1 | 2);
    }, 8_000);
    return () => clearInterval(id);
  }, [autoSlide]);

  // Atajos: F = fullscreen, ESC = salir, flechas = slides.
  useEffect(() => {
    function handler(e: KeyboardEvent) {
      if (e.key === 'f' || e.key === 'F') toggleFullscreen();
      if (e.key === 'Escape') router.push('/panel');
      if (e.key === 'ArrowRight') setSlide((s) => ((s + 1) % 3) as 0 | 1 | 2);
      if (e.key === 'ArrowLeft') setSlide((s) => ((s + 2) % 3) as 0 | 1 | 2);
      if (e.key === ' ') {
        e.preventDefault();
        setAutoSlide((v) => !v);
      }
    }
    window.addEventListener('keydown', handler);
    return () => window.removeEventListener('keydown', handler);
  }, [router]);

  function toggleFullscreen() {
    if (!document.fullscreenElement) {
      document.documentElement.requestFullscreen().catch(() => {});
      setFullscreen(true);
    } else {
      document.exitFullscreen().catch(() => {});
      setFullscreen(false);
    }
  }

  const ultimoLoss = expActivo?.metrics[expActivo.metrics.length - 1];

  return (
    <div className="relative min-h-screen w-screen overflow-hidden bg-bg text-text">
      {/* Gradiente sutil de fondo */}
      <div
        className="pointer-events-none absolute inset-0"
        style={{
          background:
            'radial-gradient(ellipse 70% 50% at 50% 0%, color-mix(in srgb, var(--primary) 6%, transparent), transparent), ' +
            'radial-gradient(ellipse 50% 50% at 100% 100%, color-mix(in srgb, var(--accent) 5%, transparent), transparent)'
        }}
      />

      {/* Header minimalista */}
      <header className="relative flex items-center justify-between p-6">
        <div className="flex items-center gap-3">
          <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-primary text-primary-foreground shadow-soft">
            <Presentation size={18} />
          </div>
          <div>
            <h1 className="font-serif text-xl text-text leading-tight">Explicador IA</h1>
            <p className="text-[11px] text-subtle">Modo presentación</p>
          </div>
        </div>
        <div className="flex items-center gap-2">
          <button
            onClick={() => setAutoSlide(!autoSlide)}
            className={cn(
              'inline-flex items-center gap-1.5 rounded-lg px-3 py-1.5 text-xs font-medium transition-colors',
              autoSlide
                ? 'bg-success/10 text-success border border-success/30'
                : 'bg-surface border border-border-soft text-muted hover:bg-surface-2'
            )}
            title="Espacio para pausar/reanudar"
          >
            {autoSlide ? (
              <>
                <span className="h-1.5 w-1.5 rounded-full bg-success animate-pulse" />
                Auto
              </>
            ) : 'Manual'}
          </button>
          <button
            onClick={toggleFullscreen}
            className="inline-flex items-center gap-1.5 rounded-lg border border-border-soft bg-surface px-3 py-1.5 text-xs font-medium text-muted hover:bg-surface-2"
            title="F para pantalla completa"
          >
            {fullscreen ? <Minimize2 size={12} /> : <Maximize2 size={12} />}
            {fullscreen ? 'Salir FS' : 'Fullscreen'}
          </button>
          <button
            onClick={() => router.push('/panel')}
            className="inline-flex items-center gap-1.5 rounded-lg border border-border-soft bg-surface px-3 py-1.5 text-xs font-medium text-muted hover:bg-surface-2"
            title="ESC para salir"
          >
            <ArrowLeft size={12} />
            Volver
          </button>
        </div>
      </header>

      {/* Slide indicador */}
      <div className="relative flex justify-center gap-2 mb-6">
        {[0, 1, 2].map((i) => (
          <button
            key={i}
            onClick={() => setSlide(i as 0 | 1 | 2)}
            className={cn(
              'h-1.5 rounded-full transition-all',
              slide === i ? 'w-12 bg-primary' : 'w-6 bg-surface-3'
            )}
          />
        ))}
      </div>

      {/* Contenido por slide */}
      <main className="relative px-6 pb-6">
        <div className="mx-auto max-w-7xl">
          {slide === 0 && <SlideHero usuario={usuario} modelo={modelo} kb={kb} />}
          {slide === 1 && <SlideMetricas modelo={modelo} kb={kb} ultimoLoss={ultimoLoss} expActivo={expActivo} />}
          {slide === 2 && <SlideEntrenamiento expActivo={expActivo} exps={exps} />}
        </div>
      </main>

      {/* Atajos visibles abajo */}
      <footer className="absolute bottom-3 left-0 right-0 text-center text-[10px] text-subtle font-mono">
        ← → cambiar slide · espacio pausar · F fullscreen · ESC salir
      </footer>
    </div>
  );
}

// ─────────────────────────── Slide 1: Hero ───────────────────────────

function SlideHero({
  usuario, modelo, kb
}: {
  usuario: UsuarioPerfil | null;
  modelo: EstadoModelo | null;
  kb: EstadisticasConocimiento | null;
}) {
  return (
    <div className="animate-fade-in">
      <div className="text-center mb-12 mt-6">
        <h1 className="font-serif text-6xl md:text-7xl text-text mb-4">
          Explicador IA
        </h1>
        <p className="text-xl text-muted max-w-3xl mx-auto leading-relaxed">
          Plataforma educativa basada en un LLM propio entrenado desde cero
          para la enseñanza de Python en educación superior
        </p>
        <p className="mt-4 text-sm text-subtle">
          Tesis de {usuario?.nombre ?? '—'}
        </p>
      </div>

      <div className="grid gap-5 sm:grid-cols-3">
        <HeroStat
          icon={<Brain size={32} />}
          label="Modelo propio"
          value={modelo?.disponible
            ? formatNumber(modelo.num_parametros || 0)
            : 'En entrenamiento'}
          sub={modelo?.disponible ? 'parámetros' : 'aún no activo'}
          tone="primary"
        />
        <HeroStat
          icon={<Database size={32} />}
          label="Conocimiento"
          value={formatNumber(kb?.total_unidades || 0)}
          sub={`${kb?.validadas || 0} validadas`}
          tone="accent"
        />
        <HeroStat
          icon={<ShieldCheck size={32} />}
          label="Independencia API"
          value={`${kb?.tasa_independencia_api || 0}%`}
          sub="respuestas sin API externa"
          tone="success"
        />
      </div>
    </div>
  );
}

// ─────────────────────────── Slide 2: Métricas ───────────────────────────

function SlideMetricas({
  modelo, kb, ultimoLoss, expActivo
}: {
  modelo: EstadoModelo | null;
  kb: EstadisticasConocimiento | null;
  ultimoLoss?: any;
  expActivo: ExperimentoDetalle | null;
}) {
  return (
    <div className="animate-fade-in">
      <div className="mb-8 text-center">
        <h2 className="font-serif text-4xl text-text">Métricas en vivo</h2>
        <p className="text-sm text-muted mt-2">Actualización cada 5 segundos</p>
      </div>

      <div className="grid gap-5 md:grid-cols-2 lg:grid-cols-4">
        <BigMetric
          icon={<Cpu size={24} />}
          label="Estado modelo"
          value={modelo?.disponible ? 'Activo' : 'Inactivo'}
          color={modelo?.disponible ? 'text-success' : 'text-warning'}
        />
        <BigMetric
          icon={<TrendingUp size={24} />}
          label="Train loss actual"
          value={ultimoLoss?.train_loss?.toFixed(3) ?? '—'}
          mono
        />
        <BigMetric
          icon={<Zap size={24} />}
          label="Iter completada"
          value={ultimoLoss?.iter !== undefined ? String(ultimoLoss.iter) : '—'}
          mono
        />
        <BigMetric
          icon={<Database size={24} />}
          label="Reutilizaciones"
          value={formatNumber(kb?.reutilizaciones_totales || 0)}
        />
      </div>

      {expActivo && expActivo.metrics.length > 0 && (
        <div className="mt-8 rounded-2xl border border-border-soft bg-surface p-6">
          <div className="flex items-center gap-2 mb-4">
            <Activity size={16} className="text-accent" />
            <h3 className="font-semibold text-text">Curva de pérdida — {expActivo.nombre}</h3>
            <span className="inline-flex items-center gap-1 text-[10.5px] text-success ml-auto">
              <span className="h-1.5 w-1.5 rounded-full bg-success animate-pulse" />
              en vivo
            </span>
          </div>
          <LossChart metrics={expActivo.metrics} />
        </div>
      )}
    </div>
  );
}

// ─────────────────────────── Slide 3: Entrenamiento ───────────────────────────

function SlideEntrenamiento({
  expActivo, exps
}: {
  expActivo: ExperimentoDetalle | null;
  exps: ExperimentoResumen[];
}) {
  return (
    <div className="animate-fade-in">
      <div className="mb-8 text-center">
        <h2 className="font-serif text-4xl text-text">Arquitectura del modelo</h2>
        <p className="text-sm text-muted mt-2">Transformer decoder construido desde cero</p>
      </div>

      {expActivo?.config?.model && (
        <div className="grid gap-5 sm:grid-cols-3 lg:grid-cols-6 mb-8">
          <ArchStat label="Capas" value={String(expActivo.config.model.n_layer)} />
          <ArchStat label="Heads" value={String(expActivo.config.model.n_head)} />
          <ArchStat label="Embedding" value={String(expActivo.config.model.n_embd)} />
          <ArchStat label="Vocab" value={formatNumber(expActivo.config.model.vocab_size)} />
          <ArchStat label="Contexto" value={`${expActivo.config.model.block_size} tk`} />
          <ArchStat label="Params" value={formatNumber(expActivo.config.num_parametros || 0)} />
        </div>
      )}

      <div className="rounded-2xl border border-border-soft bg-code-bg p-6 max-w-4xl mx-auto">
        <pre className="text-xs text-code-text font-mono leading-relaxed">
{`# Pipeline completo (validado y reproducible)
python -m ml.data.combinar --entradas datasets/raw/*.jsonl \\
    --salida datasets/processed/train.jsonl

python -m ml.train --preset experto --iters 30000 \\
    --batch 2 --corpus datasets/processed/train.jsonl \\
    --experimento ${expActivo?.nombre || 'tesis_v1'} \\
    --tokenizer-backend sp

# Activar en el backend:
echo "MODEL_ENABLED=true" >> .env
docker compose restart backend`}
        </pre>
      </div>

      <p className="text-center text-sm text-subtle mt-8">
        {exps.length} experimento{exps.length === 1 ? '' : 's'} ejecutado{exps.length === 1 ? '' : 's'}
      </p>
    </div>
  );
}

// ─────────────────────────── Helpers ───────────────────────────

function HeroStat({
  icon, label, value, sub, tone
}: {
  icon: React.ReactNode;
  label: string;
  value: string;
  sub: string;
  tone: 'primary' | 'accent' | 'success';
}) {
  const toneClass: Record<string, string> = {
    primary: 'bg-primary-soft text-primary',
    accent: 'bg-accent-soft text-accent',
    success: 'bg-success/15 text-success'
  };
  return (
    <div className="rounded-2xl border border-border-soft bg-surface p-6">
      <div className={cn('inline-flex h-14 w-14 items-center justify-center rounded-xl mb-4', toneClass[tone])}>
        {icon}
      </div>
      <div className="text-[11px] uppercase tracking-wider text-subtle font-semibold mb-1">
        {label}
      </div>
      <div className="text-3xl font-bold text-text font-serif">{value}</div>
      <div className="text-sm text-muted mt-1">{sub}</div>
    </div>
  );
}

function BigMetric({
  icon, label, value, color = 'text-text', mono = false
}: {
  icon: React.ReactNode;
  label: string;
  value: string;
  color?: string;
  mono?: boolean;
}) {
  return (
    <div className="rounded-2xl border border-border-soft bg-surface p-5">
      <div className="inline-flex h-10 w-10 items-center justify-center rounded-xl bg-surface-2 text-muted mb-3">
        {icon}
      </div>
      <div className="text-[10.5px] uppercase tracking-wider text-subtle font-semibold mb-1">
        {label}
      </div>
      <div className={cn('text-3xl font-bold', color, mono && 'font-mono')}>
        {value}
      </div>
    </div>
  );
}

function ArchStat({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-xl border border-border-soft bg-surface p-4 text-center">
      <div className="text-[10.5px] uppercase tracking-wider text-subtle font-semibold mb-1">
        {label}
      </div>
      <div className="text-2xl font-bold font-mono text-text">{value}</div>
    </div>
  );
}

