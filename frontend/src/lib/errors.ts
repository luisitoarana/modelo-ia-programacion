import { AxiosError } from 'axios';

/**
 * Convierte cualquier error (incl. validaciones 422 de FastAPI, cuyo `detail`
 * es una lista de objetos) en un string legible para mostrar en la UI.
 * Nunca devuelve un objeto, evitando el crash "Objects are not valid as a React child".
 */
export function mensajeError(err: unknown, fallback = 'Ocurrió un error inesperado'): string {
  const e = err as AxiosError<any>;
  const detail = e?.response?.data?.detail;

  if (detail == null) {
    return e?.message || fallback;
  }
  if (typeof detail === 'string') {
    return detail;
  }
  if (Array.isArray(detail)) {
    const partes = detail
      .map((d: any) => {
        if (typeof d === 'string') return d;
        const campo = Array.isArray(d?.loc) ? d.loc[d.loc.length - 1] : undefined;
        return campo ? `${campo}: ${d?.msg ?? ''}` : d?.msg ?? JSON.stringify(d);
      })
      .filter(Boolean);
    return partes.length ? partes.join(' · ') : fallback;
  }
  if (typeof detail === 'object') {
    return (detail as any).msg || JSON.stringify(detail);
  }
  return String(detail);
}
