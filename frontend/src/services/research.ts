import { api } from './api';

export interface ReporteGeneral {
  usuarios_total: number;
  consultas: {
    total: number;
    completadas: number;
    fallidas: number;
    latencia_promedio_seg: number;
    por_fuente: Record<string, number>;
  };
  dataset: {
    total: number;
    validados: number;
    por_nivel: Record<string, number>;
    por_tema: Record<string, number>;
  };
  evaluaciones: {
    puntaje_promedio: number;
  };
}

export async function obtenerReporteGeneral(): Promise<ReporteGeneral> {
  const { data } = await api.get<ReporteGeneral>('/research/reporte-general');
  return data;
}
