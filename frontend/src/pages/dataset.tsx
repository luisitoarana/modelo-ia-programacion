import { useEffect, useState } from 'react';
import {
  Database, CheckCircle2, XCircle, Sparkles, Search,
  ChevronDown, ChevronUp, Award, Repeat, BookOpen, Code2,
  TrendingUp
} from 'lucide-react';
import AppLayout from '@/layouts/AppLayout';
import StatCard from '@/components/StatCard';
import { Card, CardHeader, CardBody } from '@/components/ui/Card';
import Badge from '@/components/ui/Badge';
import Button from '@/components/ui/Button';
import {
  EstadisticasConocimiento, UnidadConocimiento,
  estadisticasConocimiento, listarUnidades, validarUnidad
} from '@/services/knowledgeGen';
import { obtenerPerfil } from '@/services/auth';
import { formatNumber } from '@/lib/format';
import { cn } from '@/lib/cn';

type Filtro = 'candidato' | 'validado' | 'rechazado' | '';

const FILTROS: { id: Filtro; label: string; icon: React.ReactNode; color: string }[] = [
  { id: 'candidato', label: 'Pendientes', icon: <Sparkles size={12} />, color: 'warning' },
  { id: 'validado', label: 'Validados', icon: <CheckCircle2 size={12} />, color: 'success' },
  { id: 'rechazado', label: 'Rechazados', icon: <XCircle size={12} />, color: 'danger' },
  { id: '', label: 'Todos', icon: <Database size={12} />, color: 'neutral' }
];

export default function DatasetPage() {
  const [stats, setStats] = useState<EstadisticasConocimiento | null>(null);
  const [unidades, setUnidades] = useState<UnidadConocimiento[]>([]);
  const [filtro, setFiltro] = useState<Filtro>('candidato');
  const [nombre, setNombre] = useState('investigador');
  const [busqueda, setBusqueda] = useState('');
  const [cargando, setCargando] = useState(false);

  async function cargar() {
    setCargando(true);
    try {
      const [s, u, perfil] = await Promise.all([
        estadisticasConocimiento(),
        listarUnidades(filtro || undefined),
        obtenerPerfil().catch(() => null)
      ]);
      setStats(s);
      setUnidades(u);
      if (perfil) setNombre(perfil.nombre);
    } catch {
      /* noop */
    } finally {
      setCargando(false);
    }
  }

  useEffect(() => {
    cargar();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [filtro]);

  async function validar(id: string, aprobar: boolean) {
    await validarUnidad(id, { aprobar, validado_por: nombre });
    cargar();
  }

  const unidadesFiltradas = busqueda.trim().length === 0
    ? unidades
    : unidades.filter((u) =>
        u.pregunta_canonica.toLowerCase().includes(busqueda.toLowerCase()) ||
        u.tema.toLowerCase().includes(busqueda.toLowerCase()) ||
        u.explicacion_general.toLowerCase().includes(busqueda.toLowerCase())
      );

  return (
    <AppLayout>
      <div className="mb-6 animate-fade-in">
        <div className="flex items-start gap-3">
          <div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-xl bg-accent-soft text-accent">
            <Database size={22} />
          </div>
          <div>
            <h1 className="font-serif text-3xl text-text">Dataset & Validación</h1>
            <p className="mt-1 text-sm text-muted">
              El conocimiento generado se valida aquí antes de reutilizarse y
              exportarse para el entrenamiento de tu modelo propio.
            </p>
          </div>
        </div>
      </div>

      {stats && (
        <div className="mb-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          <StatCard label="Total" value={formatNumber(stats.total_unidades)} icon={<Database size={20} />} />
          <StatCard label="Validadas" value={formatNumber(stats.validadas)} tone="success" icon={<CheckCircle2 size={20} />} />
          <StatCard label="Pendientes" value={formatNumber(stats.candidatas)} tone="warning" icon={<Sparkles size={20} />} />
          <StatCard label="Independencia API" value={`${stats.tasa_independencia_api}%`} tone="accent" icon={<TrendingUp size={20} />} />
        </div>
      )}

      {/* Filtros + búsqueda */}
      <div className="mb-5 flex flex-col sm:flex-row gap-3">
        <div className="flex flex-wrap gap-1.5">
          {FILTROS.map((f) => (
            <button
              key={f.id || 'todos'}
              onClick={() => setFiltro(f.id)}
              className={cn(
                'inline-flex items-center gap-1.5 rounded-lg px-3.5 py-1.5 text-xs font-medium transition-all',
                filtro === f.id
                  ? 'bg-primary text-primary-foreground shadow-soft'
                  : 'border border-border-soft bg-surface text-muted hover:bg-surface-2'
              )}
            >
              {f.icon}
              {f.label}
            </button>
          ))}
        </div>
        <div className="flex-1 relative">
          <Search size={14} className="absolute left-3 top-1/2 -translate-y-1/2 text-subtle" />
          <input
            value={busqueda}
            onChange={(e) => setBusqueda(e.target.value)}
            placeholder="Buscar por pregunta, tema o contenido…"
            className="w-full h-9 rounded-lg border border-border-soft bg-surface-2 pl-9 pr-3 text-sm text-text focus-ring"
          />
        </div>
      </div>

      {/* Grid de cards */}
      {unidadesFiltradas.length === 0 ? (
        <div className="rounded-2xl border border-dashed border-border-soft bg-surface/50 p-12 text-center">
          <Database size={36} className="mx-auto text-subtle mb-3" />
          <p className="text-sm font-medium text-text">
            No hay unidades {filtro === 'candidato' ? 'pendientes' : filtro || ''}.
          </p>
          <p className="text-xs text-subtle mt-1">
            Genera conocimiento desde el panel admin o deja que las consultas alimenten la base.
          </p>
        </div>
      ) : (
        <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
          {unidadesFiltradas.map((u, i) => (
            <UnidadCard
              key={u.id}
              unidad={u}
              onValidar={validar}
              delay={i * 50}
            />
          ))}
        </div>
      )}
    </AppLayout>
  );
}

// ─────────────────────────── Card de unidad ───────────────────────────

function UnidadCard({
  unidad: u, onValidar, delay
}: {
  unidad: UnidadConocimiento;
  onValidar: (id: string, aprobar: boolean) => void;
  delay: number;
}) {
  const [abierta, setAbierta] = useState(false);
  const esCandidata = u.estado === 'candidato';
  const esValidada = u.estado === 'validado';
  const esRechazada = u.estado === 'rechazado';

  return (
    <div
      className={cn(
        'rounded-2xl border p-4 transition-all animate-fade-in hover:shadow-soft',
        esValidada && 'border-success/30 bg-success/[0.03]',
        esRechazada && 'border-danger/30 bg-danger/[0.03]',
        esCandidata && 'border-border-soft bg-surface hover:border-border'
      )}
      style={{ animationDelay: `${delay}ms` }}
    >
      {/* Badges metadata */}
      <div className="mb-2 flex flex-wrap items-center gap-1.5">
        <Badge tone="primary">{u.nivel}</Badge>
        <Badge tone="accent">
          <BookOpen size={10} />
          {u.tema}
        </Badge>
        <Badge tone="neutral">{u.origen}</Badge>
        <Badge tone={u.puntaje_calidad >= 9 ? 'success' : u.puntaje_calidad >= 6 ? 'warning' : 'danger'}>
          <Award size={10} />
          {u.puntaje_calidad}/12
        </Badge>
        {u.veces_reutilizada > 0 && (
          <Badge tone="primary">
            <Repeat size={10} />
            {u.veces_reutilizada}×
          </Badge>
        )}
      </div>

      {/* Pregunta */}
      <h3 className="text-sm font-semibold text-text leading-snug mb-1.5 line-clamp-2">
        {u.pregunta_canonica}
      </h3>

      {/* Explicación: colapsable */}
      <div className="text-xs text-muted leading-relaxed">
        <p className={abierta ? '' : 'line-clamp-3'}>{u.explicacion_general}</p>
        {u.explicacion_general.length > 200 && (
          <button
            onClick={() => setAbierta(!abierta)}
            className="mt-1.5 inline-flex items-center gap-0.5 text-primary hover:underline text-[11px]"
          >
            {abierta ? (
              <>menos <ChevronUp size={11} /></>
            ) : (
              <>leer más <ChevronDown size={11} /></>
            )}
          </button>
        )}
      </div>

      {/* Mostrar código si existe */}
      {abierta && u.codigo_ejemplo && (
        <div className="mt-3 rounded-lg bg-code-bg p-2.5">
          <div className="flex items-center gap-1.5 mb-1.5">
            <Code2 size={10} className="text-code-text/60" />
            <span className="text-[10px] uppercase tracking-wider text-code-text/60 font-mono">
              Código de ejemplo
            </span>
          </div>
          <pre className="overflow-x-auto text-[11px] leading-relaxed text-code-text font-mono whitespace-pre-wrap">
            {u.codigo_ejemplo}
          </pre>
        </div>
      )}

      {/* Acciones */}
      {esCandidata && (
        <div className="mt-3 flex gap-2 pt-3 border-t border-border-soft">
          <button
            onClick={() => onValidar(u.id, true)}
            className="flex-1 inline-flex items-center justify-center gap-1 rounded-lg bg-success px-3 py-1.5 text-xs font-medium text-white hover:opacity-90 transition-opacity"
          >
            <CheckCircle2 size={13} /> Validar
          </button>
          <button
            onClick={() => onValidar(u.id, false)}
            className="flex-1 inline-flex items-center justify-center gap-1 rounded-lg border border-danger/40 bg-danger/10 px-3 py-1.5 text-xs font-medium text-danger hover:bg-danger/20 transition-colors"
          >
            <XCircle size={13} /> Rechazar
          </button>
        </div>
      )}
      {esValidada && (
        <div className="mt-3 flex items-center gap-1.5 pt-3 border-t border-success/20 text-[11px] text-success font-medium">
          <CheckCircle2 size={12} /> Aprobada para entrenamiento
        </div>
      )}
      {esRechazada && (
        <div className="mt-3 flex items-center gap-1.5 pt-3 border-t border-danger/20 text-[11px] text-danger font-medium">
          <XCircle size={12} /> Excluida del corpus
        </div>
      )}
    </div>
  );
}
