import { FormEvent, useState } from 'react';
import { useRouter } from 'next/router';
import Link from 'next/link';
import { ShieldCheck, Mail, Lock, ArrowLeft } from 'lucide-react';
import AuthShell from '@/components/AuthShell';
import Input from '@/components/ui/Input';
import Button from '@/components/ui/Button';
import { login, obtenerPerfil, cerrarSesion } from '@/services/auth';
import { mensajeError } from '@/lib/errors';

export default function AccesoAdminPage() {
  const router = useRouter();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [cargando, setCargando] = useState(false);

  async function enviar(e: FormEvent) {
    e.preventDefault();
    setError(null);
    setCargando(true);
    try {
      await login(email, password);
      const perfil = await obtenerPerfil();
      if (perfil.rol !== 'administrador') {
        cerrarSesion();
        setError('Esta cuenta no tiene permisos de administrador.');
        return;
      }
      router.replace('/admin');
    } catch (err) {
      setError(mensajeError(err, 'Credenciales inválidas'));
    } finally {
      setCargando(false);
    }
  }

  return (
    <AuthShell titulo="Acceso de administrador" subtitulo="Control del sistema y entrenamiento">
      <form onSubmit={enviar} className="flex flex-col gap-4">
        <div className="flex items-center justify-center gap-2 rounded-lg bg-accent-soft px-3 py-2 text-sm text-accent">
          <ShieldCheck size={16} /> Área restringida
        </div>
        <Input
          label="Correo de administrador"
          type="email"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          required
          icon={<Mail size={16} />}
          placeholder="admin@..."
        />
        <Input
          label="Contraseña"
          type="password"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          required
          minLength={8}
          icon={<Lock size={16} />}
          placeholder="••••••••"
        />
        {error && <p className="text-sm text-danger">{error}</p>}
        <Button type="submit" loading={cargando} className="w-full">
          Entrar como administrador
        </Button>
        <Link href="/" className="flex items-center justify-center gap-1.5 text-sm text-muted hover:text-text">
          <ArrowLeft size={14} /> Volver al asistente
        </Link>
      </form>
    </AuthShell>
  );
}
