import { useEffect, useState } from 'react';
import { useRouter } from 'next/router';
import {
  KeyRound, ShieldCheck, Database, Users, MessageSquare, CheckCircle2,
  XCircle, Loader2, Sparkles, Cpu, AlertCircle, Eye, EyeOff,
  RefreshCw, ChevronRight, Zap
} from 'lucide-react';
import AppLayout from '@/layouts/AppLayout';
import { Card, CardHeader, CardBody } from '@/components/ui/Card';
import StatCard from '@/components/StatCard';
import Badge from '@/components/ui/Badge';
import Button from '@/components/ui/Button';
import Input from '@/components/ui/Input';
import Select from '@/components/ui/Select';
import { obtenerPerfil } from '@/services/auth';
import {
  EstadoAPIKey, ResumenAdmin, estadoAPIKeys, guardarAPIKey, probarAPIKey,
  resumenAdmin, generarCurriculo
} from '@/services/admin';
import { formatNumber } from '@/lib/format';
import { mensajeError } from '@/lib/errors';
import { cn } from '@/lib/cn';

type Proveedor = 'gemini' | 'deepseek';

export default function AdminPage() {
  const router = useRouter();
  const [autorizado, setAutorizado] = useState<boolean | null>(null);
  const [keys, setKeys] = useState<Record<string, EstadoAPIKey>>({});
  const [resumen, setResumen] = useState<ResumenAdmin | null>(null);

  useEffect(() => {
    obtenerPerfil()
      .then((p) => {
        if (p.rol !== 'administrador') {
          setAutorizado(false);
          router.replace('/');
        } else {
          setAutorizado(true);
          cargar();
        }
      })
      .catch(() => router.replace('/login'));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  async function cargar() {
    try {
      const [k, r] = await Promise.all([estadoAPIKeys(), resumenAdmin()]);
      setKeys(k);
      setResumen(r);
    } catch {
      /* noop */
    }
  }

  if (autorizado === null) {
    return (
      <AppLayout>
        <div className="flex h-64 items-center justify-center text-muted">
          <Loader2 className="animate-spin" />
        </div>
      </AppLayout>
    );
  }

  const algunaConfigurada = Object.values(keys).some((k) => k?.configurada);

  return (
    <AppLayout>
      <div className="mb-6 animate-fade-in">
        <div className="flex items-start gap-3">
          <div
            className="flex h-12 w-12 shrink-0 items-center justify-center rounded-xl bg-accent-soft text-accent shadow-soft"
            style={{ boxShadow: '0 8px 20px -10px color-mix(in srgb, var(--accent) 35%, transparent)' }}
          >
            <ShieldCheck size={22} />
          </div>
          <div>
            <h1 className="font-serif text-3xl text-text">Panel de administrador</h1>
            <p className="mt-1 text-sm text-muted">
              Configura las API keys (cifradas) y controla la generación de datos de entrenamiento.
            </p>
          </div>
        </div>
      </div>

      {/* Banner si no hay ninguna API configurada */}
      {Object.keys(keys).length > 0 && !algunaConfigurada && (
        <div className="mb-6 rounded-2xl border border-warning/40 bg-warning/5 p-4 animate-fade-in">
          <div className="flex items-start gap-3">
            <AlertCircle className="mt-0.5 shrink-0 text-warning" size={18} />
            <div className="flex-1">
              <p className="text-sm font-semibold text-text">
                Aún no hay ninguna API configurada
              </p>
              <p className="mt-0.5 text-xs text-muted leading-relaxed">
                Sin una API, el chat responderá con un aviso para los usuarios.
                Configura al menos Gemini o DeepSeek aquí abajo para que el sistema
                tenga "cerebro" mientras entrenas tu modelo propio.
              </p>
            </div>
          </div>
        </div>
      )}

      {/* Métricas */}
      {resumen && (
        <div className="mb-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          <StatCardAnimada delay={0} label="Usuarios" value={formatNumber(resumen.usuarios)} icon={<Users size={20} />} />
          <StatCardAnimada delay={80} label="Consultas" value={formatNumber(resumen.consultas)} tone="primary" icon={<MessageSquare size={20} />} />
          <StatCardAnimada delay={160} label="Dataset" value={formatNumber(resumen.dataset)} tone="accent" icon={<Database size={20} />} />
          <StatCardAnimada
            delay={240}
            label="Conocimiento validado"
            value={`${resumen.unidades_validadas}/${resumen.unidades_conocimiento}`}
            tone="success"
            icon={<CheckCircle2 size={20} />}
          />
        </div>
      )}

      <div className="grid gap-4 lg:grid-cols-2">
        <TarjetaAPIKey proveedor="gemini" estado={keys.gemini_api_key} onCambio={cargar} delay={0} />
        <TarjetaAPIKey proveedor="deepseek" estado={keys.deepseek_api_key} onCambio={cargar} delay={120} />
      </div>

      <div className="mt-6 animate-fade-in" style={{ animationDelay: '300ms' }}>
        <GeneracionDataset />
      </div>
    </AppLayout>
  );
}

// ─────────────────────────── StatCard con animación de entrada ───────────────────────────

function StatCardAnimada({
  delay, ...props
}: React.ComponentProps<typeof StatCard> & { delay: number }) {
  return (
    <div className="animate-fade-in" style={{ animationDelay: `${delay}ms` }}>
      <StatCard {...props} />
    </div>
  );
}

// ─────────────────────────── Tarjeta de API Key ───────────────────────────

function TarjetaAPIKey({
  proveedor, estado, onCambio, delay
}: { proveedor: Proveedor; estado?: EstadoAPIKey; onCambio: () => void; delay: number }) {
  const [valor, setValor] = useState('');
  const [verClave, setVerClave] = useState(false);
  const [guardando, setGuardando] = useState(false);
  const [probando, setProbando] = useState(false);
  const [resultado, setResultado] = useState<string | null>(null);
  const [ok, setOk] = useState<boolean | null>(null);

  const nombre = proveedor === 'gemini' ? 'Google Gemini' : 'DeepSeek';
  const descripcion = proveedor === 'gemini'
    ? 'Modelos Gemini 1.5/2.0 — fuerte en código, multimodal, gratis hasta cuota generosa.'
    : 'DeepSeek-V2/R1 — razonamiento step-by-step y código de primer nivel.';
  const linkObtenerKey = proveedor === 'gemini'
    ? 'https://aistudio.google.com/apikey'
    : 'https://platform.deepseek.com/api_keys';

  async function guardar() {
    if (!valor.trim()) return;
    setGuardando(true);
    setResultado(null);
    try {
      await guardarAPIKey(proveedor, valor.trim());
      setValor('');
      setResultado('Guardada y cifrada correctamente.');
      setOk(true);
      onCambio();
    } catch (e: any) {
      setResultado(mensajeError(e, 'No se pudo guardar.'));
      setOk(false);
    } finally {
      setGuardando(false);
    }
  }

  async function probar() {
    setProbando(true);
    setResultado(null);
    try {
      const r = await probarAPIKey(proveedor);
      setOk(r.ok);
      setResultado(
        r.ok
          ? `Conexión OK · respuesta: "${r.respuesta}" (${r.latencia_segundos}s)`
          : `Falló: ${r.detalle}`
      );
    } catch (e: any) {
      setOk(false);
      setResultado(mensajeError(e, 'Error al probar.'));
    } finally {
      setProbando(false);
    }
  }

  const configurada = estado?.configurada === true;

  return (
    <div
      className={cn(
        'group rounded-2xl border p-5 transition-all animate-fade-in',
        configurada
          ? 'border-success/30 bg-success/[0.03] hover:border-success/50'
          : 'border-border-soft bg-surface hover:border-border'
      )}
      style={{ animationDelay: `${delay}ms` }}
    >
      {/* Header con icono y estado */}
      <div className="flex items-start gap-3 mb-3">
        <div className={cn(
          'flex h-10 w-10 shrink-0 items-center justify-center rounded-xl transition-transform group-hover:scale-105',
          configurada ? 'bg-success/15 text-success' : 'bg-primary-soft text-primary'
        )}>
          <KeyRound size={18} />
        </div>
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 flex-wrap">
            <h3 className="font-semibold text-text">{nombre}</h3>
            {configurada ? (
              <Badge tone="success">
                <CheckCircle2 size={11} />
                activa
              </Badge>
            ) : (
              <Badge tone="warning">
                <AlertCircle size={11} />
                sin configurar
              </Badge>
            )}
          </div>
          <p className="mt-0.5 text-xs text-subtle leading-relaxed">{descripcion}</p>
        </div>
      </div>

      {/* Mostrar máscara si está configurada */}
      {configurada && estado?.vista && (
        <div className="mb-3 rounded-lg border border-border-soft bg-surface-2 px-3 py-2">
          <div className="flex items-center justify-between gap-2">
            <code className="font-mono text-xs text-muted truncate">
              {estado.vista}
            </code>
            {estado.actualizado_por && (
              <span className="text-[10.5px] text-subtle whitespace-nowrap">
                por {estado.actualizado_por}
              </span>
            )}
          </div>
        </div>
      )}

      {/* Input para guardar nueva clave */}
      <div className="space-y-2.5">
        <div className="relative">
          <Input
            type={verClave ? 'text' : 'password'}
            placeholder={`Pega aquí tu API key de ${nombre}`}
            value={valor}
            onChange={(e) => setValor(e.target.value)}
            className="pr-10"
          />
          {valor.length > 0 && (
            <button
              type="button"
              onClick={() => setVerClave(!verClave)}
              className="absolute right-3 top-1/2 -translate-y-1/2 text-subtle hover:text-text"
              title={verClave ? 'Ocultar' : 'Mostrar'}
            >
              {verClave ? <EyeOff size={14} /> : <Eye size={14} />}
            </button>
          )}
        </div>

        <div className="flex flex-wrap gap-2">
          <Button onClick={guardar} loading={guardando} disabled={!valor.trim()}>
            Guardar (cifrada)
          </Button>
          <Button
            variant="outline"
            onClick={probar}
            loading={probando}
            disabled={!configurada}
          >
            <Zap size={13} />
            Probar
          </Button>
          <a
            href={linkObtenerKey}
            target="_blank"
            rel="noreferrer"
            className="inline-flex items-center gap-1 text-xs text-primary hover:underline self-center ml-auto"
          >
            Obtener clave <ChevronRight size={11} />
          </a>
        </div>

        {resultado && (
          <div
            className={cn(
              'flex items-start gap-2 rounded-lg border p-2.5 text-xs animate-fade-in',
              ok
                ? 'border-success/30 bg-success/5 text-success'
                : 'border-danger/30 bg-danger/5 text-danger'
            )}
          >
            {ok ? <CheckCircle2 size={13} className="mt-0.5 shrink-0" /> : <XCircle size={13} className="mt-0.5 shrink-0" />}
            <span className="break-words">{resultado}</span>
          </div>
        )}
      </div>
    </div>
  );
}

// ─────────────────────────── Generación de Dataset ───────────────────────────

function GeneracionDataset() {
  const [proveedor, setProveedor] = useState<Proveedor>('gemini');
  const [nivel, setNivel] = useState('');
  const [limite, setLimite] = useState('4');
  const [cargando, setCargando] = useState(false);
  const [resultado, setResultado] = useState<any>(null);
  const [error, setError] = useState<string | null>(null);

  async function generar() {
    setCargando(true);
    setError(null);
    setResultado(null);
    try {
      const r = await generarCurriculo({
        proveedor,
        nivel: nivel || null,
        limite: limite ? parseInt(limite, 10) : null
      });
      setResultado(r);
    } catch (e: any) {
      setError(mensajeError(e, 'No se pudo generar. ¿Configuraste la API key?'));
    } finally {
      setCargando(false);
    }
  }

  return (
    <div className="rounded-2xl border border-border-soft bg-surface p-5">
      <div className="flex items-start gap-3 mb-4">
        <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-primary-soft text-primary">
          <Sparkles size={18} />
        </div>
        <div>
          <h3 className="font-semibold text-text">Generar dataset de entrenamiento</h3>
          <p className="mt-0.5 text-xs text-subtle leading-relaxed">
            Usa la API (solo aquí) para crear ejemplos educativos. Estos ejemplos entrenan tu modelo propio.
          </p>
        </div>
      </div>

      <div className="grid gap-3 sm:grid-cols-4 mb-3">
        <Select
          value={proveedor}
          onChange={(e) => setProveedor(e.target.value as Proveedor)}
          options={[
            { value: 'gemini', label: 'Proveedor: Gemini' },
            { value: 'deepseek', label: 'Proveedor: DeepSeek' }
          ]}
        />
        <Select
          value={nivel}
          onChange={(e) => setNivel(e.target.value)}
          options={[
            { value: '', label: 'Todos los niveles' },
            { value: 'basico', label: 'Básico' },
            { value: 'intermedio', label: 'Intermedio' },
            { value: 'avanzado', label: 'Avanzado' }
          ]}
        />
        <Input
          type="number"
          min={1}
          max={50}
          value={limite}
          onChange={(e) => setLimite(e.target.value)}
          placeholder="Límite por objetivo"
        />
        <Button onClick={generar} loading={cargando}>
          {!cargando && <Cpu size={16} />} Generar
        </Button>
      </div>

      <p className="text-[11.5px] text-subtle leading-relaxed mb-3">
        Genera conocimiento por currículo, valida su calidad automáticamente y lo guarda como
        candidato. Luego se valida en <span className="text-text font-medium">Dataset & Validación</span> y se
        exporta para entrenar.
      </p>

      {error && (
        <div className="flex items-start gap-2 rounded-lg border border-danger/30 bg-danger/5 p-3 text-xs text-danger animate-fade-in">
          <XCircle size={13} className="mt-0.5 shrink-0" />
          <span>{error}</span>
        </div>
      )}

      {resultado && (
        <div className="rounded-xl border border-border-soft bg-surface-2/40 p-4 animate-fade-in">
          <p className="text-xs font-semibold text-muted uppercase tracking-wider mb-2">Resultado</p>
          <div className="flex flex-wrap gap-2">
            <Badge tone="primary">items {resultado.total_items}</Badge>
            <Badge tone="success">aprobados {resultado.aprobados}</Badge>
            <Badge tone="accent">almacenados {resultado.almacenados}</Badge>
            <Badge tone={resultado.fallidos ? 'danger' : 'neutral'}>
              fallidos {resultado.fallidos}
            </Badge>
          </div>
        </div>
      )}
    </div>
  );
}
