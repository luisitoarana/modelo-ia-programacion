import { cn } from '@/lib/cn';

export default function Skeleton({ className }: { className?: string }) {
  return (
    <div
      className={cn(
        'relative overflow-hidden rounded-lg bg-surface-2',
        'after:absolute after:inset-0 after:-translate-x-full after:animate-shimmer',
        'after:bg-gradient-to-r after:from-transparent after:via-black/5 after:to-transparent dark:after:via-white/5',
        className
      )}
    />
  );
}
