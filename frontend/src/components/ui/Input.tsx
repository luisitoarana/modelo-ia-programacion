import { InputHTMLAttributes, forwardRef, ReactNode } from 'react';
import { cn } from '@/lib/cn';

interface Props extends InputHTMLAttributes<HTMLInputElement> {
  label?: string;
  hint?: string;
  icon?: ReactNode;
}

const Input = forwardRef<HTMLInputElement, Props>(
  ({ className, label, hint, icon, id, ...props }, ref) => {
    return (
      <label className="block">
        {label && <span className="mb-1.5 block text-sm font-medium">{label}</span>}
        <div className="relative">
          {icon && (
            <span className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-muted">
              {icon}
            </span>
          )}
          <input
            ref={ref}
            id={id}
            className={cn(
              'h-11 w-full rounded-lg border bg-surface px-3.5 text-sm transition-colors placeholder:text-muted focus-ring',
              icon && 'pl-10',
              className
            )}
            {...props}
          />
        </div>
        {hint && <span className="mt-1 block text-xs text-muted">{hint}</span>}
      </label>
    );
  }
);
Input.displayName = 'Input';
export default Input;
