import { Loader2 } from 'lucide-react';
import { cn } from '@/lib/cn';

export default function Spinner({ className, label }: { className?: string; label?: string }) {
  return (
    <div className="flex items-center justify-center gap-2 text-muted">
      <Loader2 className={cn('h-5 w-5 animate-spin', className)} />
      {label && <span className="text-sm">{label}</span>}
    </div>
  );
}
