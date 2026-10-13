import { FormEvent, useState } from 'react';
import { useRouter } from 'next/router';
import Link from 'next/link';
import { Mail, Lock } from 'lucide-react';
import { login } from '@/services/auth';
import AuthShell from '@/components/AuthShell';
import Input from '@/components/ui/Input';
import Button from '@/components/ui/Button';
import { mensajeError } from '@/lib/errors';

export default function LoginPage() {
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
      router.replace('/');
    } catch (err: any) {
      setError(mensajeError(err, 'Credenciales inválidas'));
    } finally {
      setCargando(false);
    }
  }

  return (
    <AuthShell titulo="Iniciar sesión" subtitulo="Aprendizaje de Python con andamiaje explicativo">
      <form onSubmit={enviar} className="flex flex-col gap-4">
        <Input
          label="Correo"
          type="email"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          required
          icon={<Mail size={16} />}
          placeholder="tu@correo.com"
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
        <Button type="submit" loading={cargando} className="mt-2 w-full">
          Entrar
        </Button>
        <p className="text-center text-sm text-muted">
          ¿No tienes cuenta?{' '}
          <Link href="/registro" className="font-medium text-primary">
            Crear cuenta
          </Link>
        </p>
      </form>
    </AuthShell>
  );
}
