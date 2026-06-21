import { SelectHTMLAttributes, forwardRef } from 'react';
import { ChevronDown } from 'lucide-react';
import { cn } from '@/lib/cn';

interface Option {
  value: string;
  label: string;
}

interface Props extends SelectHTMLAttributes<HTMLSelectElement> {
  label?: string;
  options: Option[];
}

const Select = forwardRef<HTMLSelectElement, Props>(
  ({ className, label, options, ...props }, ref) => {
    return (
      <label className="block">
        {label && <span className="mb-1.5 block text-sm font-medium">{label}</span>}
        <div className="relative">
          <select
            ref={ref}
            className={cn(
              'h-11 w-full appearance-none rounded-lg border bg-surface px-3.5 pr-10 text-sm transition-colors focus-ring',
              className
            )}
            {...props}
          >
            {options.map((o) => (
              <option key={o.value} value={o.value}>
                {o.label}
              </option>
            ))}
          </select>
          <ChevronDown className="pointer-events-none absolute right-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted" />
        </div>
      </label>
    );
  }
);
Select.displayName = 'Select';
export default Select;
