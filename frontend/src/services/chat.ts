import { api } from './api';

export interface FuenteRag {
  doc_id: string;
  titulo: string;
  score: number;
  chunk_id: string;
}

export interface FuenteWeb {
  titulo?: string;
  url?: string;
  snippet?: string;
}

export interface MetadatosMensaje {
  origen?: string;
  proveedor?: string;
  modelo?: string;
  fuentes_rag?: FuenteRag[];
  fuentes_web?: FuenteWeb[];
  n_imagenes?: number;
  multimodal?: boolean;
  categoria?: string;
}

export interface Mensaje {
  id: string;
  rol: 'usuario' | 'asistente';
  contenido: string;
  origen_respuesta?: string | null;
  tokens_totales: number;
  latencia_segundos: number;
  fecha_creacion: string;
  metadata_json?: MetadatosMensaje | null;
}

export interface ConversacionResumen {
  id: string;
  titulo: string;
  proyecto?: string | null;
  fecha_actualizacion: string;
}

export interface ConversacionDetalle extends ConversacionResumen {
  mensajes: Mensaje[];
}

export interface RespuestaEnvio {
  conversacion_id: string;
  titulo: string;
  mensaje_usuario: Mensaje;
  mensaje_asistente: Mensaje;
}

export async function listarConversaciones(): Promise<ConversacionResumen[]> {
  const { data } = await api.get<ConversacionResumen[]>('/chat/conversaciones');
  return data;
}

export async function obtenerConversacion(id: string): Promise<ConversacionDetalle> {
  const { data } = await api.get<ConversacionDetalle>(`/chat/conversaciones/${id}`);
  return data;
}

export interface ProveedorIA {
  id: string;
  nombre: string;
  descripcion: string;
  tipo: 'auto' | 'propio' | 'api';
  disponible: boolean;
}

export async function listarProveedores(): Promise<ProveedorIA[]> {
  const { data } = await api.get<{ proveedores: ProveedorIA[] }>('/chat/proveedores');
  return data.proveedores;
}

export async function enviarMensaje(
  convId: string,
  contenido: string,
  opciones: { idioma?: string; buscarWeb?: boolean; proveedor?: string } = {}
): Promise<RespuestaEnvio> {
  const { data } = await api.post<RespuestaEnvio>(
    `/chat/conversaciones/${convId}/mensajes`,
    {
      contenido,
      idioma: opciones.idioma ?? 'es',
      buscar_web: opciones.buscarWeb ?? false,
      proveedor: opciones.proveedor ?? 'auto',
    }
  );
  return data;
}

/**
 * Envía mensaje con imágenes adjuntas. Usa el endpoint multimodal del
 * backend (multipart/form-data) que rutea al proveedor Gemini Vision.
 *
 * Restricciones del backend: máx 3 imágenes, 5 MB por imagen,
 * formatos PNG/JPEG/WebP.
 */
export async function enviarMensajeConImagenes(
  convId: string,
  contenido: string,
  imagenes: File[],
  opciones: { idioma?: string; buscarWeb?: boolean } = {}
): Promise<RespuestaEnvio> {
  const form = new FormData();
  form.append('contenido', contenido);
  form.append('idioma', opciones.idioma ?? 'es');
  form.append('buscar_web', String(opciones.buscarWeb ?? false));
  for (const img of imagenes) {
    form.append('imagenes', img, img.name);
  }
  const { data } = await api.post<RespuestaEnvio>(
    `/chat/conversaciones/${convId}/mensajes-multimodal`,
    form,
    { headers: { 'Content-Type': 'multipart/form-data' } }
  );
  return data;
}

export async function mensajeRapido(
  contenido: string,
  opciones: { idioma?: string; buscarWeb?: boolean; proveedor?: string } = {}
): Promise<RespuestaEnvio> {
  const { data } = await api.post<RespuestaEnvio>('/chat/mensaje-rapido', {
    contenido,
    idioma: opciones.idioma ?? 'es',
    buscar_web: opciones.buscarWeb ?? false,
    proveedor: opciones.proveedor ?? 'auto',
  });
  return data;
}

export async function renombrarConversacion(id: string, titulo: string): Promise<void> {
  await api.patch(`/chat/conversaciones/${id}`, { titulo });
}

export async function eliminarConversacion(id: string): Promise<void> {
  await api.delete(`/chat/conversaciones/${id}`);
}
