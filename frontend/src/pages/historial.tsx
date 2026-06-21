import { useEffect, useState } from 'react';
import { History } from 'lucide-react';
import AppLayout from '@/layouts/AppLayout';
import { Card } from '@/components/ui/Card';
import Badge from '@/components/ui/Badge';
import EmptyState from '@/components/ui/EmptyState';
import Skeleton from '@/components/ui/Skeleton';
import { ConsultaLeer, obtenerHistorial } from '@/services/ai';
import { formatDate, formatSeconds } from '@/lib/format';

export default function HistorialPage() {
  const [items, setItems] = useState<ConsultaLeer[]>([]);
  const [cargando, setCargando] = useState(true);

  useEffect(() => {
    obtenerHistorial()
      .then(setItems)
      .finally(() => setCargando(false));
  }, []);

  return (
    <AppLayout>
      <div className="mb-4">
        <h1 className="text-2xl font-bold">Historial de consultas</h1>
        <p className="text-sm text-muted">Tus interacciones, ordenadas por fecha.</p>
      </div>

      {cargando && (
        <div className="space-y-3">
          {[0, 1, 2].map((i) => (
            <Skeleton key={i} className="h-24 w-full" />
          ))}
        </div>
      )}

      {!cargando && items.length === 0 && (
        <EmptyState
          icon={<History size={22} />}
          title="Aún no tienes consultas"
          description="Cuando generes o expliques código, aparecerá aquí."
        />
      )}

      <div className="space-y-3">
        {items.map((c) => (
          <Card key={c.id} className="p-4">
            <div className="mb-2 flex flex-wrap gap-2">
              <Badge tone="primary">{c.modelo_usado}</Badge>
              <Badge tone={c.estado === 'completada' ? 'success' : 'warning'}>{c.estado}</Badge>
              <Badge tone="neutral">tokens {c.tokens_totales}</Badge>
              <Badge tone="neutral">{formatSeconds(c.latencia_segundos)}</Badge>
            </div>
            <p className="whitespace-pre-wrap text-sm">{c.prompt_original}</p>
            <p className="mt-1 text-xs text-muted">{formatDate(c.fecha_creacion)}</p>
          </Card>
        ))}
      </div>
    </AppLayout>
  );
}
