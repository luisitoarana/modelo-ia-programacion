import { TextareaHTMLAttributes, forwardRef } from 'react';
import { cn } from '@/lib/cn';

interface Props extends TextareaHTMLAttributes<HTMLTextAreaElement> {
  label?: string;
}

const Textarea = forwardRef<HTMLTextAreaElement, Props>(
  ({ className, label, ...props }, ref) => {
    return (
      <label className="block">
        {label && <span className="mb-1.5 block text-sm font-medium">{label}</span>}
        <textarea
          ref={ref}
          className={cn(
            'w-full rounded-lg border bg-surface px-3.5 py-3 text-sm leading-relaxed transition-colors placeholder:text-muted focus-ring resize-y',
            className
          )}
          {...props}
        />
      </label>
    );
  }
);
Textarea.displayName = 'Textarea';
export default Textarea;
