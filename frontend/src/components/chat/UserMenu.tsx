import { useEffect, useRef, useState } from 'react';
import { useRouter } from 'next/router';
import Link from 'next/link';
import { Settings, HelpCircle, ShieldCheck, LogOut, ChevronsUpDown } from 'lucide-react';
import { UsuarioPerfil, cerrarSesion } from '@/services/auth';
import ThemeToggle from '@/components/ThemeToggle';

export default function UserMenu({ usuario }: { usuario: UsuarioPerfil | null }) {
  const router = useRouter();
  const [abierto, setAbierto] = useState(false);
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    function handle(e: MouseEvent) {
      if (ref.current && !ref.current.contains(e.target as Node)) setAbierto(false);
    }
    document.addEventListener('mousedown', handle);
    return () => document.removeEventListener('mousedown', handle);
  }, []);

  function salir() {
    cerrarSesion();
    router.replace('/login');
  }

  const esAdmin = usuario?.rol === 'administrador';

  return (
    <div ref={ref} className="relative">
      {abierto && (
        <div className="absolute bottom-full left-0 mb-2 w-64 rounded-xl border bg-surface p-1.5 shadow-soft animate-fade-in">
          <div className="truncate px-3 py-2 text-xs text-muted">{usuario?.email}</div>

          <div className="flex items-center justify-between rounded-lg px-3 py-1.5 text-sm">
            <span>Tema</span>
            <ThemeToggle />
          </div>

          <div className="my-1 border-t" />

          <ItemLink href="/configuracion" icon={<Settings size={15} />} label="Configuración" onClick={() => setAbierto(false)} />
          <ItemLink href="/configuracion#ayuda" icon={<HelpCircle size={15} />} label="Obtener ayuda" onClick={() => setAbierto(false)} />

          <div className="my-1 border-t" />

          {/* Acceso de administrador — discreto */}
          <ItemLink
            href={esAdmin ? '/admin' : '/acceso-admin'}
            icon={<ShieldCheck size={15} />}
            label={esAdmin ? 'Panel de administrador' : 'Acceso administrador'}
            onClick={() => setAbierto(false)}
          />

          <button
            onClick={salir}
            className="flex w-full items-center gap-2.5 rounded-lg px-3 py-1.5 text-left text-sm text-muted transition-colors hover:bg-surface-2 hover:text-danger"
          >
            <LogOut size={15} /> Cerrar sesión
          </button>
        </div>
      )}

      <button
        onClick={() => setAbierto((v) => !v)}
        className="flex w-full items-center gap-2 rounded-lg px-2 py-2 transition-colors hover:bg-surface-2"
      >
        <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-surface-2 text-sm font-semibold uppercase">
          {usuario?.nombre?.[0] ?? '?'}
        </div>
        <div className="min-w-0 flex-1 text-left leading-tight">
          <div className="truncate text-sm font-medium">{usuario?.nombre ?? '...'}</div>
          <div className="text-[11px] capitalize text-muted">{usuario?.rol ?? ''}</div>
        </div>
        <ChevronsUpDown size={15} className="shrink-0 text-muted" />
      </button>
    </div>
  );
}

function ItemLink({
  href, icon, label, onClick
}: { href: string; icon: React.ReactNode; label: string; onClick: () => void }) {
  return (
    <Link
      href={href}
      onClick={onClick}
      className="flex items-center gap-2.5 rounded-lg px-3 py-1.5 text-sm text-muted transition-colors hover:bg-surface-2 hover:text-text"
    >
      {icon}
      {label}
    </Link>
  );
}
