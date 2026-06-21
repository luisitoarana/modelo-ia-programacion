import { useEffect, useState } from 'react';
import { useTheme } from 'next-themes';
import { Moon, Sun, Monitor } from 'lucide-react';
import { cn } from '@/lib/cn';

const OPCIONES = [
  { value: 'light', icon: Sun, label: 'Claro' },
  { value: 'dark', icon: Moon, label: 'Oscuro' },
  { value: 'system', icon: Monitor, label: 'Sistema' }
] as const;

export default function ThemeToggle() {
  const { theme, setTheme } = useTheme();
  const [mounted, setMounted] = useState(false);

  useEffect(() => setMounted(true), []);

  if (!mounted) {
    return <div className="h-9 w-[108px] rounded-lg border bg-surface-2" />;
  }

  return (
    <div
      className="inline-flex items-center gap-0.5 rounded-lg border bg-surface-2 p-0.5"
      role="radiogroup"
      aria-label="Tema de color"
    >
      {OPCIONES.map(({ value, icon: Icon, label }) => {
        const activo = theme === value;
        return (
          <button
            key={value}
            type="button"
            title={label}
            aria-label={label}
            aria-checked={activo}
            role="radio"
            onClick={() => setTheme(value)}
            className={cn(
              'flex h-8 w-8 items-center justify-center rounded-md transition-colors',
              activo
                ? 'bg-surface text-primary shadow-soft'
                : 'text-muted hover:text-text'
            )}
          >
            <Icon className="h-4 w-4" />
          </button>
        );
      })}
    </div>
  );
}
