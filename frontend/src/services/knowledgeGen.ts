import { api } from './api';

export interface ItemCurriculo {
  codigo: string;
  nivel: string;
  tema: string;
  titulo: string;
  objetivo_aprendizaje: string;
  prompt_semilla: string;
  conceptos_esperados: string[];
}

export interface UnidadConocimiento {
  id: string;
  codigo_curriculo: string | null;
  nivel: string;
  tema: string;
  objetivo_aprendizaje: string | null;
  pregunta_canonica: string;
  codigo: string;
  codigo_ejemplo?: string;
  explicacion_general: string;
  origen: string;
  estado: string;
  puntaje_calidad: number;
  veces_reutilizada: number;
  validado_por: string | null;
  fecha_creacion: string;
}

export interface EstadisticasConocimiento {
  total_unidades: number;
  validadas: number;
  candidatas: number;
  rechazadas: number;
  reutilizaciones_totales: number;
  consultas_totales: number;
  respondidas_desde_base: number;
  respondidas_por_api: number;
  tasa_independencia_api: number;
  cobertura_curriculo: number;
}

export async function verCurriculo(): Promise<ItemCurriculo[]> {
  const { data } = await api.get<ItemCurriculo[]>('/knowledge-gen/curriculo');
  return data;
}

export async function estadisticasConocimiento(): Promise<EstadisticasConocimiento> {
  const { data } = await api.get<EstadisticasConocimiento>('/knowledge-gen/estadisticas');
  return data;
}

export async function listarUnidades(estado?: string): Promise<UnidadConocimiento[]> {
  const { data } = await api.get<UnidadConocimiento[]>('/knowledge-gen/unidades', {
    params: estado ? { estado } : undefined
  });
  return data;
}

export async function generarItem(codigo: string, proveedor = 'gemini') {
  const { data } = await api.post(`/knowledge-gen/generar-item/${codigo}`, null, {
    params: { proveedor }
  });
  return data;
}

export async function validarUnidad(
  id: string,
  payload: { aprobar: boolean; validado_por: string; observaciones?: string }
) {
  const { data } = await api.post(`/knowledge-gen/unidad/${id}/validar`, payload);
  return data;
}
