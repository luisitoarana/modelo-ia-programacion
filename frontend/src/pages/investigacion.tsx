import { useEffect, useState } from 'react';
import {
  Bar, BarChart, Cell, ResponsiveContainer, Tooltip, XAxis, YAxis, CartesianGrid
} from 'recharts';
import { FlaskConical, Users, MessageSquare, ShieldCheck } from 'lucide-react';
import AppLayout from '@/layouts/AppLayout';
import StatCard from '@/components/StatCard';
import { Card, CardHeader, CardBody } from '@/components/ui/Card';
import { ReporteGeneral, obtenerReporteGeneral } from '@/services/research';
import { estadisticasConocimiento, EstadisticasConocimiento } from '@/services/knowledgeGen';
import { formatNumber } from '@/lib/format';
import { mensajeError } from '@/lib/errors';

const COLORES = ['#2563eb', '#7c3aed', '#16a34a', '#d97706', '#dc2626', '#0ea5e9'];

export default function InvestigacionPage() {
  const [rep, setRep] = useState<ReporteGeneral | null>(null);
  const [kb, setKb] = useState<EstadisticasConocimiento | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [montado, setMontado] = useState(false);

  useEffect(() => {
    setMontado(true);
    obtenerReporteGeneral().then(setRep).catch((e) =>
      setError(mensajeError(e, 'Solo investigadores/administradores.'))
    );
    estadisticasConocimiento().then(setKb).catch(() => {});
  }, []);

  const datosTema = rep
    ? Object.entries(rep.dataset.por_tema)
        .filter(([, v]) => v > 0)
        .map(([k, v]) => ({ name: k, value: v }))
    : [];

  return (
    <AppLayout>
      <div className="mb-4">
        <h1 className="text-2xl font-bold">Reportes de investigación</h1>
        <p className="text-sm text-muted">Métricas para el análisis y la defensa de la tesis.</p>
      </div>

      {error && (
        <Card className="p-5 text-sm text-danger">{error}</Card>
      )}

      {rep && (
        <>
          <div className="mb-5 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
            <StatCard label="Usuarios" value={formatNumber(rep.usuarios_total)} icon={<Users size={20} />} />
            <StatCard label="Consultas" value={formatNumber(rep.consultas.total)} tone="primary" icon={<MessageSquare size={20} />} />
            <StatCard
              label="Independencia API"
              value={`${kb?.tasa_independencia_api ?? 0}%`}
              tone="success"
              icon={<ShieldCheck size={20} />}
            />
            <StatCard
              label="Latencia media"
              value={`${rep.consultas.latencia_promedio_seg.toFixed(2)}s`}
              tone="accent"
              icon={<FlaskConical size={20} />}
            />
          </div>

          <div className="grid gap-4 lg:grid-cols-2">
            <Card>
              <CardHeader title="Dataset por tema" />
              <CardBody>
                {montado && datosTema.length > 0 ? (
                  <div className="h-64">
                    <ResponsiveContainer width="100%" height="100%">
                      <BarChart data={datosTema}>
                        <CartesianGrid strokeDasharray="3 3" stroke="var(--border)" />
                        <XAxis dataKey="name" stroke="var(--muted)" fontSize={11} />
                        <YAxis stroke="var(--muted)" fontSize={11} />
                        <Tooltip
                          contentStyle={{
                            background: 'var(--surface)',
                            border: '1px solid var(--border)',
                            borderRadius: 10
                          }}
                        />
                        <Bar dataKey="value" radius={[6, 6, 0, 0]}>
                          {datosTema.map((_, i) => (
                            <Cell key={i} fill={COLORES[i % COLORES.length]} />
                          ))}
                        </Bar>
                      </BarChart>
                    </ResponsiveContainer>
                  </div>
                ) : (
                  <p className="py-8 text-center text-sm text-muted">Aún sin datos.</p>
                )}
              </CardBody>
            </Card>

            <Card>
              <CardHeader title="Consultas por fuente" />
              <CardBody className="space-y-3 pt-2">
                {Object.entries(rep.consultas.por_fuente).map(([k, v]) => (
                  <div key={k}>
                    <div className="mb-1 flex justify-between text-sm">
                      <span className="capitalize">{k}</span>
                      <span className="text-muted">{v}</span>
                    </div>
                    <div className="h-2 overflow-hidden rounded-full bg-surface-2">
                      <div
                        className="h-full rounded-full bg-primary"
                        style={{
                          width: `${
                            rep.consultas.total ? (v / rep.consultas.total) * 100 : 0
                          }%`
                        }}
                      />
                    </div>
                  </div>
                ))}
                <div className="mt-4 rounded-lg border bg-surface-2/40 p-3 text-sm">
                  <div className="flex justify-between">
                    <span className="text-muted">Completadas</span>
                    <span className="font-semibold text-success">{rep.consultas.completadas}</span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-muted">Fallidas</span>
                    <span className="font-semibold text-danger">{rep.consultas.fallidas}</span>
                  </div>
                </div>
              </CardBody>
            </Card>
          </div>
        </>
      )}
    </AppLayout>
  );
}
