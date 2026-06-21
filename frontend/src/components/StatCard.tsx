import { ReactNode } from 'react';
import { cn } from '@/lib/cn';

interface Props {
  label: string;
  value: ReactNode;
  icon?: ReactNode;
  hint?: string;
  tone?: 'primary' | 'accent' | 'success' | 'warning' | 'neutral';
}

const TONOS: Record<string, string> = {
  primary: 'bg-primary-soft text-primary',
  accent: 'bg-accent-soft text-accent',
  success: 'bg-success/10 text-success',
  warning: 'bg-warning/10 text-warning',
  neutral: 'bg-surface-2 text-muted'
};

export default function StatCard({ label, value, icon, hint, tone = 'primary' }: Props) {
  return (
    <div className="card flex items-center gap-4 p-5">
      {icon && (
        <div className={cn('flex h-12 w-12 items-center justify-center rounded-xl', TONOS[tone])}>
          {icon}
        </div>
      )}
      <div className="min-w-0">
        <div className="text-2xl font-bold leading-tight">{value}</div>
        <div className="truncate text-sm text-muted">{label}</div>
        {hint && <div className="text-xs text-muted/80">{hint}</div>}
      </div>
    </div>
  );
}
