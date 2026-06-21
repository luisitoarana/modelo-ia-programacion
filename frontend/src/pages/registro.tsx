import { FormEvent, useState } from 'react';
import { useRouter } from 'next/router';
import Link from 'next/link';
import { registrar, login } from '@/services/auth';
import AuthShell from '@/components/AuthShell';
import Input from '@/components/ui/Input';
import Button from '@/components/ui/Button';
import { mensajeError } from '@/lib/errors';

export default function RegistroPage() {
  const router = useRouter();
  const [nombre, setNombre] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [institucion, setInstitucion] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [cargando, setCargando] = useState(false);

  async function enviar(e: FormEvent) {
    e.preventDefault();
    setCargando(true);
    setError(null);
    try {
      await registrar({ nombre, email, password, institucion });
      await login(email, password);
      router.replace('/');
    } catch (err: any) {
      setError(mensajeError(err, 'No se pudo registrar.'));
    } finally {
      setCargando(false);
    }
  }

  return (
    <AuthShell titulo="Crear cuenta" subtitulo="Estudiante o investigador">
      <form onSubmit={enviar} className="flex flex-col gap-4">
        <Input
          label="Nombre completo"
          value={nombre}
          onChange={(e) => setNombre(e.target.value)}
          required
          minLength={2}
        />
        <Input
          label="Correo"
          type="email"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          required
        />
        <Input
          label="Contraseña (mínimo 8)"
          type="password"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          required
          minLength={8}
        />
        <Input
          label="Institución"
          value={institucion}
          onChange={(e) => setInstitucion(e.target.value)}
          placeholder="Opcional"
        />
        {error && <p className="text-sm text-danger">{error}</p>}
        <Button type="submit" loading={cargando} className="mt-2 w-full">
          Crear cuenta
        </Button>
        <p className="text-center text-sm text-muted">
          ¿Ya tienes cuenta?{' '}
          <Link href="/login" className="font-medium text-primary">
            Inicia sesión
          </Link>
        </p>
      </form>
    </AuthShell>
  );
}
