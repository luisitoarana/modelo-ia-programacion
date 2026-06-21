import { api } from './api';

/**
 * Servicio frontend del sistema RAG.
 *
 * RAG = Retrieval-Augmented Generation. Sube documentos del usuario al
 * índice vectorial; el chat los cita automáticamente en lugar de alucinar.
 * Ver docs/RAG.md.
 */

export interface EstadoRag {
  disponible: boolean;
  n_documentos: number;
  n_chunks: number;
  dim: number;
  backend: string;
  motivo?: string | null;
}

export interface DocumentoRag {
  id: string;
  titulo: string;
  fuente: string;
  n_chunks: number;
  fecha: string;
  tags: string[];
}

export interface ChunkRag {
  chunk_id: string;
  doc_id: string;
  doc_titulo: string;
  score: number;
  texto: string;
}

export async function obtenerEstadoRag(): Promise<EstadoRag> {
  const { data } = await api.get<EstadoRag>('/rag/estado');
  return data;
}

export async function listarDocumentosRag(): Promise<DocumentoRag[]> {
  const { data } = await api.get<DocumentoRag[]>('/rag/documentos');
  return data;
}

export async function subirTextoRag(payload: {
  titulo: string;
  texto: string;
  fuente?: string;
  tags?: string[];
}): Promise<DocumentoRag> {
  const { data } = await api.post<DocumentoRag>('/rag/subir', {
    titulo: payload.titulo,
    texto: payload.texto,
    fuente: payload.fuente ?? 'subido',
    tags: payload.tags ?? [],
  });
  return data;
}

export async function subirArchivoRag(
  archivo: File,
  opciones: { titulo?: string; tags?: string } = {},
): Promise<DocumentoRag> {
  const form = new FormData();
  form.append('archivo', archivo);
  if (opciones.titulo) form.append('titulo', opciones.titulo);
  if (opciones.tags) form.append('tags', opciones.tags);

  const { data } = await api.post<DocumentoRag>('/rag/subir-archivo', form, {
    headers: { 'Content-Type': 'multipart/form-data' },
  });
  return data;
}

export async function eliminarDocumentoRag(id: string): Promise<void> {
  await api.delete(`/rag/documentos/${id}`);
}

export async function buscarRag(
  consulta: string,
  k = 5,
): Promise<ChunkRag[]> {
  const { data } = await api.post<{ resultados: ChunkRag[] }>('/rag/buscar', {
    consulta,
    k,
  });
  return data.resultados;
}
