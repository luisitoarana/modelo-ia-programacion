/** Utilidades de formato para la UI. */

export function formatNumber(n: number | null | undefined): string {
  if (n === null || n === undefined || Number.isNaN(n)) return '0';
  return new Intl.NumberFormat('es-PE').format(n);
}

export function formatSeconds(s: number | null | undefined): string {
  if (!s) return '0.00 s';
  return `${s.toFixed(2)} s`;
}

export function formatDate(iso: string): string {
  try {
    return new Date(iso).toLocaleString('es-PE', {
      day: '2-digit',
      month: 'short',
      year: 'numeric',
      hour: '2-digit',
      minute: '2-digit'
    });
  } catch {
    return iso;
  }
}

export function capitalize(s: string): string {
  return s ? s.charAt(0).toUpperCase() + s.slice(1) : s;
}

const NIVEL_LABEL: Record<string, string> = {
  basico: 'Básico',
  intermedio: 'Intermedio',
  avanzado: 'Avanzado'
};

export function nivelLabel(nivel: string): string {
  return NIVEL_LABEL[nivel] ?? capitalize(nivel);
}
