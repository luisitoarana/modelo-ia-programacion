import { useEffect, useMemo, useState } from 'react';
import Link from 'next/link';
import { useRouter } from 'next/router';
import {
  Plus, MessageSquare, Trash2, Sparkles, History,
  ShieldCheck, Database, Cpu, FlaskConical, Network, PanelLeft,
  Search, Code2, X, GripVertical
} from 'lucide-react';
import { ConversacionResumen } from '@/services/chat';
import { UsuarioPerfil } from '@/services/auth';
import UserMenu from '@/components/chat/UserMenu';
import { cn } from '@/lib/cn';
import { useT } from '@/lib/i18n';

interface Props {
  conversaciones: ConversacionResumen[];
  activaId: string | null;
  usuario: UsuarioPerfil | null;
  onNueva: () => void;
  onSeleccionar: (id: string) => void;
  onEliminar: (id: string) => void;
  colapsado?: boolean;
  onToggle?: () => void;
}

export default function ChatSidebar({
  conversaciones, activaId, usuario, onNueva, onSeleccionar, onEliminar, onToggle
}: Props) {
  const router = useRouter();
  const { t } = useT();
  const [query, setQuery] = useState('');
  const [draggingId, setDraggingId] = useState<string | null>(null);
  const [hoverDropId, setHoverDropId] = useState<string | null>(null);
  // Orden personalizado guardado en localStorage. Si el usuario reordena,
  // ese orden se respeta en la próxima carga.
  const [ordenPersonalizado, setOrdenPersonalizado] = useState<string[]>([]);
  const esInvestigador = usuario?.rol === 'investigador' || usuario?.rol === 'administrador';
  const esAdmin = usuario?.rol === 'administrador';
  const enChat = router.pathname === '/';
  const enExplicar = router.pathname === '/explicar';

  useEffect(() => {
    if (typeof window === 'undefined') return;
    try {
      const raw = window.localStorage.getItem('explicador.orden_chats');
      if (raw) setOrdenPersonalizado(JSON.parse(raw));
    } catch { /* noop */ }
  }, []);

  function guardarOrden(ids: string[]) {
    setOrdenPersonalizado(ids);
    if (typeof window !== 'undefined') {
      window.localStorage.setItem('explicador.orden_chats', JSON.stringify(ids));
    }
  }

  // Aplica el orden personalizado a las conversaciones recibidas.
  // Los chats que NO están en el orden personalizado van al final por fecha.
  const conversacionesOrdenadas = useMemo(() => {
    if (ordenPersonalizado.length === 0) return conversaciones;
    const indice = new Map(ordenPersonalizado.map((id, i) => [id, i]));
    return [...conversaciones].sort((a, b) => {
      const ia = indice.has(a.id) ? indice.get(a.id)! : Number.MAX_SAFE_INTEGER;
      const ib = indice.has(b.id) ? indice.get(b.id)! : Number.MAX_SAFE_INTEGER;
      if (ia !== ib) return ia - ib;
      return new Date(b.fecha_actualizacion).getTime() - new Date(a.fecha_actualizacion).getTime();
    });
  }, [conversaciones, ordenPersonalizado]);

  function manejarDrop(targetId: string) {
    if (!draggingId || draggingId === targetId) {
      setDraggingId(null);
      setHoverDropId(null);
      return;
    }
    const orden = conversacionesOrdenadas.map((c) => c.id);
    const from = orden.indexOf(draggingId);
    const to = orden.indexOf(targetId);
    if (from < 0 || to < 0) return;
    orden.splice(to, 0, ...orden.splice(from, 1));
    guardarOrden(orden);
    setDraggingId(null);
    setHoverDropId(null);
  }

  // Si hay orden personalizado, mostramos lista plana arrastrable (sin agrupar
  // por fecha — porque el usuario ya marcó su preferencia explícita).
  const usarListaPlana = ordenPersonalizado.length > 0;

  const grupos = useMemo(
    () => agruparPorFecha(conversaciones, query.trim().toLowerCase(), t),
    [conversaciones, query, t]
  );

  const conversacionesFiltradasPlanas = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return conversacionesOrdenadas;
    return conversacionesOrdenadas.filter((c) =>
      c.titulo?.toLowerCase().includes(q)
    );
  }, [conversacionesOrdenadas, query]);

  return (
    <aside className="flex h-full w-72 flex-col border-r border-border-soft bg-surface">
      {/* Encabezado */}
      <div className="flex items-center justify-between px-3.5 pt-3.5 pb-2">
        <div className="flex items-center gap-2">
          <div className="flex h-7 w-7 items-center justify-center rounded-lg bg-primary text-primary-foreground shadow-soft">
            <Sparkles size={14} />
          </div>
          <span className="text-[14.5px] font-semibold tracking-tight">Explicador IA</span>
        </div>
        {onToggle && (
          <button
            onClick={onToggle}
            className="rounded-md p-1.5 text-muted hover:bg-surface-2"
            title="Ocultar sidebar"
          >
            <PanelLeft size={16} />
          </button>
        )}
      </div>

      {/* Botón Nuevo chat (terracota, prominente) */}
      <div className="px-3 pt-1 pb-2">
        <button
          onClick={onNueva}
          className="flex w-full items-center justify-start gap-2 rounded-lg bg-primary px-3 py-2.5 text-[13.5px] font-semibold text-primary-foreground shadow-soft transition-colors hover:bg-primary-hover"
        >
          <Plus size={16} />
          {t('sidebar.nuevo_chat')}
        </button>
      </div>

      {/* Navegación principal */}
      <nav className="flex flex-col gap-0.5 px-2">
        {enChat ? (
          <TopItem onClick={onNueva} icon={<MessageSquare size={15} />} label="Chats" activo />
        ) : (
          <ToolItemLink href="/" icon={<MessageSquare size={15} />} label="Chats" />
        )}
        <ToolItemLink
          href="/explicar"
          icon={<Code2 size={15} />}
          label="Explicar código"
          activo={enExplicar}
        />
        {esInvestigador && (
          <ToolItemLink
            href="/proyecto"
            icon={<Network size={15} />}
            label="Mapa del proyecto"
          />
        )}
      </nav>

      {/* Búsqueda */}
      <div className="px-3 pt-3 pb-2">
        <div className="flex h-8 items-center gap-2 rounded-lg border border-border-soft bg-surface-2 px-2.5">
          <Search size={13} className="text-subtle" />
          <input
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder={t('sidebar.buscar') + '…'}
            className="flex-1 bg-transparent text-[12.5px] text-text placeholder:text-subtle focus:outline-none"
          />
          {query && (
            <button
              onClick={() => setQuery('')}
              className="text-subtle hover:text-text"
              aria-label="Limpiar búsqueda"
            >
              <X size={12} />
            </button>
          )}
        </div>
      </div>

      {/* Recientes con agrupación por fecha (o lista plana si hay orden custom) */}
      <div className="flex-1 overflow-y-auto px-2 pb-2">
        {conversaciones.length === 0 && (
          <p className="px-2 py-2 text-xs text-subtle">Aún no tienes conversaciones.</p>
        )}
        {usarListaPlana ? (
          <div className="mt-2">
            <div className="flex items-center justify-between px-2 pb-1">
              <span className="text-[10.5px] font-semibold uppercase tracking-wider text-subtle">
                Tu orden
              </span>
              <button
                onClick={() => guardarOrden([])}
                className="text-[10.5px] text-subtle hover:text-text"
                title="Volver al orden por fecha"
              >
                resetear
              </button>
            </div>
            <div className="flex flex-col gap-0.5">
              {conversacionesFiltradasPlanas.map((c) => (
                <ConversacionTile
                  key={c.id}
                  c={c}
                  activa={c.id === activaId}
                  arrastrando={draggingId === c.id}
                  hoverDrop={hoverDropId === c.id}
                  onSeleccionar={onSeleccionar}
                  onEliminar={onEliminar}
                  onDragStart={() => setDraggingId(c.id)}
                  onDragEnd={() => { setDraggingId(null); setHoverDropId(null); }}
                  onDragOver={() => setHoverDropId(c.id)}
                  onDrop={() => manejarDrop(c.id)}
                />
              ))}
            </div>
          </div>
        ) : (
          grupos.map(([etiqueta, lista]) =>
            lista.length === 0 ? null : (
              <div key={etiqueta} className="mt-2">
                <div className="px-2 pb-1 text-[10.5px] font-semibold uppercase tracking-wider text-subtle">
                  {etiqueta}
                </div>
                <div className="flex flex-col gap-0.5">
                  {lista.map((c) => (
                    <ConversacionTile
                      key={c.id}
                      c={c}
                      activa={c.id === activaId}
                      arrastrando={draggingId === c.id}
                      hoverDrop={hoverDropId === c.id}
                      onSeleccionar={onSeleccionar}
                      onEliminar={onEliminar}
                      onDragStart={() => setDraggingId(c.id)}
                      onDragEnd={() => { setDraggingId(null); setHoverDropId(null); }}
                      onDragOver={() => setHoverDropId(c.id)}
                      onDrop={() => manejarDrop(c.id)}
                    />
                  ))}
                </div>
              </div>
            )
          )
        )}
        {conversaciones.length > 0 && (
          (usarListaPlana
            ? conversacionesFiltradasPlanas.length === 0
            : grupos.every(([, l]) => l.length === 0)) && (
            <p className="px-2 py-2 text-xs text-subtle">Sin resultados para «{query}».</p>
          )
        )}
      </div>

      {/* Herramientas (investigador/admin) */}
      {esInvestigador && (
        <div className="border-t border-border-soft px-2 py-2">
          <div className="px-2 pb-1 text-[10.5px] font-semibold uppercase tracking-wider text-subtle">
            {esAdmin ? 'Administración' : 'Investigación'}
          </div>
          <Herramienta href="/historial" icon={<History size={14} />} label="Historial" />
          <Herramienta href="/entrenamiento" icon={<Cpu size={14} />} label="Entrenamiento" />
          <Herramienta href="/dataset" icon={<Database size={14} />} label="Dataset & Validación" />
          <Herramienta href="/investigacion" icon={<FlaskConical size={14} />} label="Reportes" />
          {esAdmin && (
            <Herramienta href="/admin" icon={<ShieldCheck size={14} />} label="Panel admin" />
          )}
        </div>
      )}

      {/* Usuario */}
      <div className="border-t border-border-soft p-2">
        <UserMenu usuario={usuario} />
      </div>
    </aside>
  );
}

// Tile reutilizable con drag-and-drop nativo HTML5.
function ConversacionTile({
  c, activa, arrastrando, hoverDrop,
  onSeleccionar, onEliminar,
  onDragStart, onDragEnd, onDragOver, onDrop
}: {
  c: ConversacionResumen;
  activa: boolean;
  arrastrando: boolean;
  hoverDrop: boolean;
  onSeleccionar: (id: string) => void;
  onEliminar: (id: string) => void;
  onDragStart: () => void;
  onDragEnd: () => void;
  onDragOver: () => void;
  onDrop: () => void;
}) {
  return (
    <div
      draggable
      onDragStart={(e) => {
        e.dataTransfer.effectAllowed = 'move';
        e.dataTransfer.setData('text/plain', c.id);
        onDragStart();
      }}
      onDragEnd={onDragEnd}
      onDragOver={(e) => {
        e.preventDefault();
        e.dataTransfer.dropEffect = 'move';
        onDragOver();
      }}
      onDragLeave={() => {/* handled by next onDragOver */}}
      onDrop={(e) => { e.preventDefault(); onDrop(); }}
      className={cn(
        'group flex items-center gap-2 rounded-lg px-2.5 py-1.5 text-[13px] transition-all',
        activa
          ? 'bg-surface-2 text-text'
          : 'text-muted hover:bg-surface-2/60',
        arrastrando && 'opacity-40 scale-[0.97]',
        hoverDrop && !arrastrando && 'ring-2 ring-primary/40 ring-offset-0',
      )}
    >
      <span
        className="cursor-grab text-subtle opacity-0 group-hover:opacity-100 transition-opacity active:cursor-grabbing"
        title="Arrastra para reordenar"
      >
        <GripVertical size={11} />
      </span>
      <button
        onClick={() => onSeleccionar(c.id)}
        className={cn(
          'flex-1 truncate text-left',
          activa && 'font-medium'
        )}
        title={c.titulo}
      >
        {c.titulo || 'Conversación'}
      </button>
      <button
        onClick={(e) => { e.stopPropagation(); onEliminar(c.id); }}
        className="shrink-0 rounded p-0.5 text-subtle opacity-0 transition-opacity hover:text-danger group-hover:opacity-100"
        title="Eliminar"
      >
        <Trash2 size={12} />
      </button>
    </div>
  );
}

// Agrupa conversaciones por fecha: Hoy / Ayer / Últimos 7 días / Anteriores.
function agruparPorFecha(
  conversaciones: ConversacionResumen[],
  query: string,
  t?: (k: string) => string
): Array<[string, ConversacionResumen[]]> {
  const filtradas = query
    ? conversaciones.filter((c) => c.titulo?.toLowerCase().includes(query))
    : conversaciones;

  const ahora = new Date();
  const hoy = new Date(ahora.getFullYear(), ahora.getMonth(), ahora.getDate()).getTime();
  const ayer = hoy - 86400000;
  const hace7 = hoy - 7 * 86400000;

  const T = t ?? ((k: string) => k);
  const grupos: Array<[string, ConversacionResumen[]]> = [
    [T('sidebar.hoy'), []],
    [T('sidebar.ayer'), []],
    [T('sidebar.ultima_semana'), []],
    [T('sidebar.mas_antiguas'), []]
  ];

  for (const c of filtradas) {
    const raw = (c as any).fecha_actualizacion ?? (c as any).fechaActualizacion ?? '';
    const t = raw ? new Date(raw).getTime() : NaN;
    if (Number.isNaN(t)) {
      grupos[3][1].push(c);
      continue;
    }
    const dia = new Date(new Date(t).getFullYear(), new Date(t).getMonth(), new Date(t).getDate()).getTime();
    if (dia >= hoy) grupos[0][1].push(c);
    else if (dia >= ayer) grupos[1][1].push(c);
    else if (dia >= hace7) grupos[2][1].push(c);
    else grupos[3][1].push(c);
  }
  return grupos;
}

function Herramienta({ href, icon, label }: { href: string; icon: React.ReactNode; label: string }) {
  return (
    <Link
      href={href}
      className="flex items-center gap-2 rounded-lg px-2.5 py-1.5 text-[12.5px] text-muted transition-colors hover:bg-surface-2 hover:text-text"
    >
      {icon}
      {label}
    </Link>
  );
}

function ToolItemLink({
  href, icon, label, activo = false
}: {
  href: string;
  icon: React.ReactNode;
  label: string;
  activo?: boolean;
}) {
  return (
    <Link
      href={href}
      className={cn(
        'flex items-center gap-2 rounded-lg px-2.5 py-1.5 text-[13px] transition-colors',
        activo
          ? 'bg-surface-2 text-text font-medium'
          : 'text-muted hover:bg-surface-2 hover:text-text'
      )}
    >
      {icon}
      {label}
    </Link>
  );
}

function TopItem({
  icon, label, onClick, activo
}: {
  icon: React.ReactNode;
  label: string;
  onClick?: () => void;
  activo?: boolean;
}) {
  return (
    <button
      onClick={onClick}
      className={cn(
        'flex w-full items-center gap-2 rounded-lg px-2.5 py-1.5 text-[13px] transition-colors',
        activo
          ? 'bg-surface-2 text-text'
          : 'text-muted hover:bg-surface-2 hover:text-text'
      )}
    >
      {icon}
      {label}
    </button>
  );
}
