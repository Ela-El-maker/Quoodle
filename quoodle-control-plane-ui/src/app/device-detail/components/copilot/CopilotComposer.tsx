import React, { useEffect, useRef } from 'react';
import { Send } from 'lucide-react';

interface CopilotComposerProps {
  value: string;
  disabled?: boolean;
  onChange: (value: string) => void;
  onSubmit: () => void;
}

export default function CopilotComposer({ value, disabled = false, onChange, onSubmit }: CopilotComposerProps) {
  const textareaRef = useRef<HTMLTextAreaElement | null>(null);

  useEffect(() => {
    if (!disabled) {
      textareaRef.current?.focus();
    }
  }, [disabled]);

  return (
    <div className="space-y-2">
      <label htmlFor="copilot-composer" className="sr-only">
        Ask device health copilot
      </label>
      <textarea
        ref={textareaRef}
        id="copilot-composer"
        value={value}
        disabled={disabled}
        rows={3}
        onChange={(event) => onChange(event.target.value)}
        onKeyDown={(event) => {
          if (event.key === 'Enter' && !event.shiftKey) {
            event.preventDefault();
            if (!disabled) onSubmit();
          }
        }}
        placeholder="Ask why this device is unhealthy..."
        className="w-full rounded-md border border-border bg-muted/30 px-3 py-2 text-sm text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-1 focus:ring-primary/40 resize-none disabled:opacity-60"
      />
      <div className="flex items-center justify-between">
        <p className="text-[10px] text-muted-foreground">Enter to send | Shift+Enter for newline</p>
        <button
          type="button"
          onClick={onSubmit}
          disabled={disabled || value.trim() === ''}
          className="inline-flex items-center gap-1.5 rounded-md border border-primary/30 bg-primary/15 px-3 py-1.5 text-xs text-primary hover:bg-primary/20 disabled:opacity-50"
        >
          <Send size={12} />
          Send
        </button>
      </div>
    </div>
  );
}
