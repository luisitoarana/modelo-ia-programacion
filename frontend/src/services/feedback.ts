import { api } from './api';

/**
 * Servicio de feedback (👍 / 👎) sobre respuestas del asistente.
 *
 * Cada voto persiste en el backend (tabla `feedbacks`) y luego se
 * usa para construir el dataset de RLHF. Ver docs/RLHF_PLAN.md.
 */

export type Voto = 1 | -1;

export type RazonFeedback =
  | 'preciso'
  | 'claro'
  | 'incorrecto'
  | 'alucina'
  | 'incompleto'
  | 'muy_largo'
  | 'muy_corto'
  | 'fuera_de_tema';

export interface FeedbackCreado {
  id: string;
  voto: number;
  fecha_creacion: string;
  ok: boolean;
}

export interface CrearFeedbackPayload {
  mensaje_id: string;
  voto: Voto;
  razon?: RazonFeedback;
  comentario?: string;
}

export async function enviarFeedback(
  payload: CrearFeedbackPayload
): Promise<FeedbackCreado> {
  const { data } = await api.post<FeedbackCreado>('/feedback', payload);
  return data;
}

export async function eliminarFeedback(id: string): Promise<void> {
  await api.delete(`/feedback/${id}`);
}

export interface EstadisticasFeedback {
  total: number;
  positivos: number;
  negativos: number;
  tasa_aprobacion: number;
  pendientes_procesar: number;
  por_modelo: Record<string, number>;
  por_razon: Record<string, number>;
}

export async function obtenerEstadisticas(): Promise<EstadisticasFeedback> {
  const { data } = await api.get<EstadisticasFeedback>('/feedback/estadisticas');
  return data;
}
