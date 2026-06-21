import { api } from './api';

export interface ExplicacionLinea {
  linea_numero: number;
  codigo_linea: string;
  semantica: string;
  impacto_en_memoria: string;
}

export interface ConceptoClave {
  concepto: string;
  definicion: string;
  tipo: 'sintactico' | 'logico' | 'algoritmico' | 'pedagogico';
}

export interface AnalisisComplejidad {
  temporal: string;
  espacial: string;
  justificacion: string;
}

export interface ActividadEvaluativa {
  tipo: 'opcion_multiple' | 'completar_codigo' | 'traza_logica' | 'explicacion_libre';
  enunciado: string;
  opciones: string[];
  respuesta_correcta: string;
  retroalimentacion_esperada: string;
}

export interface RespuestaIAEducativa {
  nivel: 'basico' | 'intermedio' | 'avanzado';
  tema: string;
  pregunta: string;
  codigo: string;
  explicacion_general: string;
  explicacion_linea_por_linea: ExplicacionLinea[];
  conceptos_clave: ConceptoClave[];
  analisis_complejidad: AnalisisComplejidad | null;
  actividad_evaluativa: ActividadEvaluativa | null;
  fuente_ia: 'gemini' | 'deepseek-r1' | 'modelo-local';
  metadata: { tokens_totales: number; latencia_segundos: number };
}

export interface ConsultaLeer {
  id: string;
  prompt_original: string;
  modelo_usado: string;
  estado: string;
  tokens_totales: number;
  latencia_segundos: number;
  fecha_creacion: string;
  respuesta: RespuestaIAEducativa | null;
  error_mensaje?: string | null;
  intentos_reparacion_json: number;
  origen_respuesta: string;
  score_recuperacion: number;
  puntaje_calidad: number;
}

export interface SolicitudGeneracion {
  prompt: string;
  nivel_solicitado?: 'basico' | 'intermedio' | 'avanzado' | null;
  tema_solicitado?: string | null;
  proveedor?: 'propio' | 'auto' | 'gemini' | 'deepseek';
  temperatura?: number;
}

export async function generarExplicacion(
  payload: SolicitudGeneracion
): Promise<ConsultaLeer> {
  const { data } = await api.post<ConsultaLeer>('/ai/generar', payload);
  return data;
}

export async function obtenerHistorial(): Promise<ConsultaLeer[]> {
  const { data } = await api.get<ConsultaLeer[]>('/ai/historial');
  return data;
}

export async function obtenerProveedores(): Promise<{
  disponibles: string[];
  por_defecto: string;
}> {
  const { data } = await api.get('/ai/proveedores');
  return data;
}
