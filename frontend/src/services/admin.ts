import { api } from './api';

export interface EstadoAPIKey {
  descripcion: string;
  configurada: boolean;
  vista: string; // enmascarada: ••••1234
  actualizado_por: string | null;
}

export interface ResumenAdmin {
  proveedores_ia_activos: string[];
  usuarios: number;
  consultas: number;
  dataset: number;
  unidades_conocimiento: number;
  unidades_validadas: number;
}

export async function estadoAPIKeys(): Promise<Record<string, EstadoAPIKey>> {
  const { data } = await api.get<{ keys: Record<string, EstadoAPIKey> }>(
    '/admin/config/api-keys'
  );
  return data.keys;
}

export async function guardarAPIKey(
  proveedor: 'gemini' | 'deepseek',
  api_key: string
): Promise<void> {
  await api.put('/admin/config/api-keys', { proveedor, api_key });
}

export async function probarAPIKey(
  proveedor: 'gemini' | 'deepseek'
): Promise<{ ok: boolean; detalle?: string; respuesta?: string; latencia_segundos?: number }> {
  const { data } = await api.post(`/admin/config/probar/${proveedor}`);
  return data;
}

export async function resumenAdmin(): Promise<ResumenAdmin> {
  const { data } = await api.get<ResumenAdmin>('/admin/resumen');
  return data;
}

// ----- Generación de dataset con APIs (controlada por el admin) -----
export async function generarCurriculo(payload: {
  proveedor: 'gemini' | 'deepseek';
  nivel?: string | null;
  limite?: number | null;
  autovalidar_si_aprueba?: boolean;
}): Promise<any> {
  const { data } = await api.post('/knowledge-gen/generar-curriculo', payload);
  return data;
}
