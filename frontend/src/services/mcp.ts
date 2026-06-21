import { api } from './api';

/**
 * Servicio frontend para gestionar el servidor MCP (Model Context Protocol).
 *
 * El MCP server expone tools (leer archivo, ejecutar Python, etc.) que el
 * asistente puede invocar cuando el usuario se lo permite. Ver
 * docs/MCP_PLAN.md.
 */

export type ModoConfirmacion = 'auto' | 'confirmar' | 'bloquear';

export interface McpTool {
  name: string;
  description: string;
  inputSchema: Record<string, unknown>;
}

export interface PermisosMcp {
  directorios_permitidos: string[];
  tools_habilitadas: string[];
  modo_escribir: ModoConfirmacion;
  modo_ejecutar: ModoConfirmacion;
  max_bytes_lectura: number;
  timeout_ejecucion_segundos: number;
}

export interface EstadoMcp {
  activo: boolean;
  handshake_completado: boolean;
  tools: McpTool[];
  permisos: PermisosMcp;
}

export async function obtenerEstadoMcp(): Promise<EstadoMcp> {
  const { data } = await api.get<EstadoMcp>('/mcp/estado');
  return data;
}

export async function actualizarPermisosMcp(
  nuevos: PermisosMcp
): Promise<PermisosMcp> {
  const { data } = await api.put<PermisosMcp>('/mcp/permisos', nuevos);
  return data;
}

export async function pingMcp(): Promise<boolean> {
  const { data } = await api.post<{ ok: boolean }>('/mcp/ping');
  return data.ok;
}

export async function invocarToolMcp(
  nombre: string,
  argumentos: Record<string, unknown>
): Promise<{ contenido: string; es_error: boolean }> {
  const { data } = await api.post('/mcp/invocar', {
    nombre,
    argumentos,
  });
  return data;
}
