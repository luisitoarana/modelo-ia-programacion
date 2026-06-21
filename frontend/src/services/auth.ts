import { api, setToken } from './api';

export interface UsuarioPerfil {
  id: string;
  nombre: string;
  email: string;
  rol: 'estudiante' | 'investigador' | 'administrador';
  institucion?: string | null;
  nivel_academico?: string | null;
  activo: boolean;
}

export async function registrar(payload: {
  nombre: string;
  email: string;
  password: string;
  rol?: 'estudiante' | 'investigador' | 'administrador';
  institucion?: string;
  nivel_academico?: string;
}): Promise<UsuarioPerfil> {
  const { data } = await api.post<UsuarioPerfil>('/auth/registro', payload);
  return data;
}

export async function login(email: string, password: string): Promise<UsuarioPerfil> {
  const { data } = await api.post<{ access_token: string; expires_in_seconds: number }>(
    '/auth/login',
    { email, password }
  );
  setToken(data.access_token);
  return obtenerPerfil();
}

export async function obtenerPerfil(): Promise<UsuarioPerfil> {
  const { data } = await api.get<UsuarioPerfil>('/auth/yo');
  return data;
}

export function cerrarSesion() {
  setToken(null);
}
