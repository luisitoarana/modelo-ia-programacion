import { api } from './api';
import { RespuestaIAEducativa } from './ai';

export interface DatasetRegistro {
  id: string;
  usuario_id: string;
  consulta_id: string;
  nivel: string;
  tema: string;
  pregunta: string;
  codigo: string;
  explicacion_general: string;
  respuesta_json: RespuestaIAEducativa;
  fuente_ia: string;
  validado: boolean;
  exportado_para_finetuning: boolean;
  fecha_creacion: string;
}

export interface DatasetEstadisticas {
  total: number;
  validados: number;
  exportados_finetuning: number;
  pendientes_validacion: number;
}

export async function listarDataset(params?: {
  solo_validados?: boolean;
  limite?: number;
}): Promise<DatasetRegistro[]> {
  const { data } = await api.get<DatasetRegistro[]>('/dataset/', { params });
  return data;
}

export async function estadisticasDataset(): Promise<DatasetEstadisticas> {
  const { data } = await api.get<DatasetEstadisticas>('/dataset/estadisticas');
  return data;
}

export async function validarRegistro(
  id: string,
  payload: { validado: boolean; validado_por: string; observaciones_validacion?: string }
): Promise<DatasetRegistro> {
  const { data } = await api.post<DatasetRegistro>(`/dataset/${id}/validar`, payload);
  return data;
}

export async function exportarJSONL(params?: {
  solo_validados?: boolean;
  nombre_archivo?: string;
}): Promise<{ cantidad: number; ruta: string }> {
  const { data } = await api.post('/dataset/exportar-jsonl', null, { params });
  return data;
}
