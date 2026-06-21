import { useEffect, useState } from 'react';
import {
  Line,
  LineChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
  CartesianGrid,
  Legend
} from 'recharts';
import { MetricaEntrenamiento } from '@/services/model';

interface Props {
  metrics: MetricaEntrenamiento[];
}

export default function LossChart({ metrics }: Props) {
  const [montado, setMontado] = useState(false);
  useEffect(() => setMontado(true), []);

  if (!montado) return <div className="h-72 w-full animate-pulse rounded-lg bg-surface-2" />;
  if (!metrics.length) {
    return (
      <div className="flex h-72 items-center justify-center text-sm text-muted">
        Sin métricas todavía. Entrena un modelo con <code className="mx-1">python -m ml.train</code>.
      </div>
    );
  }

  const data = metrics.map((m) => ({
    iter: m.iter,
    train: m.train_loss,
    val: m.val_loss
  }));

  return (
    <div className="h-72 w-full">
      <ResponsiveContainer width="100%" height="100%">
        <LineChart data={data} margin={{ top: 8, right: 16, bottom: 8, left: -8 }}>
          <CartesianGrid strokeDasharray="3 3" stroke="var(--border)" />
          <XAxis dataKey="iter" stroke="var(--muted)" fontSize={12} />
          <YAxis stroke="var(--muted)" fontSize={12} />
          <Tooltip
            contentStyle={{
              background: 'var(--surface)',
              border: '1px solid var(--border)',
              borderRadius: 10,
              color: 'var(--text)'
            }}
          />
          <Legend />
          <Line type="monotone" dataKey="train" name="train_loss" stroke="var(--primary)" dot={false} strokeWidth={2} />
          <Line type="monotone" dataKey="val" name="val_loss" stroke="var(--accent)" dot={false} strokeWidth={2} />
        </LineChart>
      </ResponsiveContainer>
    </div>
  );
}
