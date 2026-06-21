import { api } from './api';

export interface NodoArchivo {
  nombre: string;
  ruta: string;
  tipo: 'carpeta' | 'archivo';
  tamano: number;
  es_texto: boolean;
}

export interface ArchivoLeido {
  ruta: string;
  nombre: string;
  lenguaje: string;
  tamano: number;
  truncado: boolean;
  contenido: string;
}

export async function listarArbol(ruta = ''): Promise<NodoArchivo[]> {
  const { data } = await api.get<{ elementos: NodoArchivo[] }>('/proyecto/arbol', {
    params: { ruta }
  });
  return data.elementos;
}

export async function leerArchivo(ruta: string): Promise<ArchivoLeido> {
  const { data } = await api.get<ArchivoLeido>('/proyecto/archivo', {
    params: { ruta }
  });
  return data;
}

export async function buscarArchivos(q: string): Promise<NodoArchivo[]> {
  const { data } = await api.get<{ resultados: NodoArchivo[] }>('/proyecto/buscar', {
    params: { q }
  });
  return data.resultados;
}
