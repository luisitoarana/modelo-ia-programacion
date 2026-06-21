import { api } from './api';

export interface EstadoModelo {
  disponible: boolean;
  motivo?: string;
  num_parametros?: number;
  device?: string;
  checkpoint?: string;
  habilitado?: boolean;
}

export interface RespuestaModelo {
  texto: string;
  tokens_generados: number;
  latencia_segundos: number;
  device: string;
  num_parametros: number;
  origen: string;
}

export async function estadoModelo(): Promise<EstadoModelo> {
  const { data } = await api.get<EstadoModelo>('/ai/modelo-estado');
  return data;
}

export async function preguntarModelo(payload: {
  instruccion: string;
  entrada?: string;
  max_tokens?: number;
  temperatura?: number;
}): Promise<RespuestaModelo> {
  const { data } = await api.post<RespuestaModelo>('/ai/preguntar-modelo', payload);
  return data;
}

// ----- Panel de experimentos -----
export interface ExperimentoResumen {
  nombre: string;
  num_parametros?: number;
  device?: string;
  iteraciones: number;
  ultimo_val_loss?: number;
  ultimo_train_loss?: number;
}

export interface MetricaEntrenamiento {
  iter: number;
  lr: number;
  train_loss: number | null;
  val_loss: number | null;
  elapsed_seg: number;
}

export interface ExperimentoDetalle {
  nombre: string;
  config: Record<string, any>;
  metrics: MetricaEntrenamiento[];
}

export async function listarExperimentos(): Promise<ExperimentoResumen[]> {
  const { data } = await api.get<{ experimentos: ExperimentoResumen[] }>('/ml/experimentos');
  return data.experimentos;
}

export async function detalleExperimento(nombre: string): Promise<ExperimentoDetalle> {
  const { data } = await api.get<ExperimentoDetalle>(`/ml/experimentos/${nombre}`);
  return data;
}
