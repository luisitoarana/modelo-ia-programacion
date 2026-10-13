import Link from 'next/link';
import { useRouter } from 'next/router';
import { ReactNode, useEffect, useState } from 'react';
import {
  LayoutDashboard,
  MessageSquareCode,
  FileCode2,
  BookOpen,
  History,
  Cpu,
  Database,
  FlaskConical,
  Network,
  GraduationCap,
  ShieldCheck,
  Sparkles
} from 'lucide-react';
import { obtenerPerfil, UsuarioPerfil } from '@/services/auth';
import { getToken } from '@/services/api';
import UserMenu from '@/components/chat/UserMenu';
import { cn } from '@/lib/cn';

interface NavItem {
  href: string;
  label: string;
  icon: ReactNode;
  soloInvestigador?: boolean;
  soloAdmin?: boolean;
}

// El layout admin/investigación NO incluye /explicar — esa página usa el
// layout del chat para que el estudiante no salga del flujo del asistente.
// Tampoco incluye /explorador (se eliminó por innecesario en admin).
const NAV: { grupo: string; items: NavItem[] }[] = [
  {
    grupo: 'Aprender',
    items: [
      { href: '/', label: 'Asistente', icon: <MessageSquareCode size={18} /> },
      { href: '/panel', label: 'Panel general', icon: <LayoutDashboard size={18} /> },
      { href: '/conocimiento', label: 'Conocimiento', icon: <BookOpen size={18} />, soloInvestigador: true },
      { href: '/historial', label: 'Historial', icon: <History size={18} />, soloInvestigador: true }
    ]
  },
  {
    grupo: 'Investigación',
    items: [
      { href: '/entrenamiento', label: 'Entrenamiento', icon: <Cpu size={18} />, soloInvestigador: true },
      { href: '/dataset', label: 'Dataset & Validación', icon: <Database size={18} />, soloInvestigador: true },
      { href: '/investigacion', label: 'Reportes', icon: <FlaskConical size={18} />, soloInvestigador: true },
      { href: '/proyecto', label: 'Mapa del proyecto', icon: <Network size={18} />, soloInvestigador: true }
    ]
  },
  {
    grupo: 'Administración',
    items: [
      { href: '/admin', label: 'Panel admin', icon: <ShieldCheck size={18} />, soloAdmin: true }
    ]
  }
];

export default function AppLayout({ children }: { children: ReactNode }) {
  const router = useRouter();
  const [usuario, setUsuario] = useState<UsuarioPerfil | null>(null);

  useEffect(() => {
    if (!getToken()) {
      router.replace('/login');
      return;
    }
    obtenerPerfil()
      .then(setUsuario)
      .catch(() => router.replace('/login'));
  }, [router]);

  const esInvestigador = usuario?.rol === 'investigador' || usuario?.rol === 'administrador';
  const esAdmin = usuario?.rol === 'administrador';

  return (
    <div className="flex min-h-screen bg-bg text-text">
      {/* Sidebar */}
      <aside className="flex w-64 shrink-0 flex-col border-r bg-surface">
        <div className="flex h-16 items-center gap-2 border-b px-5">
          <div className="flex h-9 w-9 items-center justify-center rounded-lg bg-primary text-primary-foreground">
            <GraduationCap size={20} />
          </div>
          <div className="leading-tight">
            <div className="text-sm font-bold">Explicador IA</div>
            <div className="text-[11px] text-muted">Python · LLM propio</div>
          </div>
        </div>

        <nav className="flex flex-1 flex-col gap-5 overflow-y-auto p-4">
          {NAV.map((g) => {
            const items = g.items.filter(
              (i) =>
                (!i.soloInvestigador || esInvestigador) &&
                (!i.soloAdmin || esAdmin)
            );
            if (items.length === 0) return null;
            return (
              <div key={g.grupo}>
                <div className="mb-1 px-2 text-[11px] font-semibold uppercase tracking-wider text-muted">
                  {g.grupo}
                </div>
                <div className="flex flex-col gap-0.5">
                  {items.map((i) => {
                    const activo = router.pathname === i.href;
                    return (
                      <Link
                        key={i.href}
                        href={i.href}
                        className={cn(
                          'flex items-center gap-3 rounded-lg px-3 py-2 text-sm font-medium transition-colors',
                          activo
                            ? 'bg-primary-soft text-primary'
                            : 'text-muted hover:bg-surface-2 hover:text-text'
                        )}
                      >
                        {i.icon}
                        {i.label}
                      </Link>
                    );
                  })}
                </div>
              </div>
            );
          })}
        </nav>

        {/* Usuario (mismo menú que el chat, siempre abajo → no se mueve) */}
        <div className="border-t p-2">
          <UserMenu usuario={usuario} />
        </div>
      </aside>

      {/* Contenido (sin topbar, igual que el asistente → no cambia al navegar) */}
      <main className="min-w-0 flex-1 overflow-y-auto p-6">{children}</main>
    </div>
  );
}
