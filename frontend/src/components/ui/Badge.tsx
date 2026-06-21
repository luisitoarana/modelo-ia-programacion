import { HTMLAttributes } from 'react';
import { cn } from '@/lib/cn';

type Tone = 'neutral' | 'primary' | 'accent' | 'success' | 'warning' | 'danger';

const TONES: Record<Tone, string> = {
  neutral: 'bg-surface-2 text-muted border-border',
  primary: 'bg-primary-soft text-primary border-transparent',
  accent: 'bg-accent-soft text-accent border-transparent',
  success: 'border-transparent text-success bg-success/10',
  warning: 'border-transparent text-warning bg-warning/10',
  danger: 'border-transparent text-danger bg-danger/10'
};

interface Props extends HTMLAttributes<HTMLSpanElement> {
  tone?: Tone;
}

export default function Badge({ className, tone = 'neutral', ...props }: Props) {
  return (
    <span
      className={cn(
        'inline-flex items-center gap-1 rounded-full border px-2.5 py-0.5 text-xs font-medium',
        TONES[tone],
        className
      )}
      {...props}
    />
  );
}
