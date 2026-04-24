import React from 'react';
import { AlertTriangle, Loader2 } from 'lucide-react';

interface CopilotStateNoticeProps {
  kind: 'loading' | 'degraded' | 'unavailable' | 'scope';
  title: string;
  message: string;
  correlationId?: string | null;
}

export default function CopilotStateNotice({ kind, title, message, correlationId }: CopilotStateNoticeProps) {
  if (kind === 'loading') {
    return (
      <div className="rounded border border-border bg-muted/20 px-3 py-2 text-xs text-muted-foreground flex items-center gap-2" aria-live="polite">
        <Loader2 size={12} className="animate-spin text-primary" />
        <div>
          <p className="text-foreground/90">{title}</p>
          <p>{message}</p>
        </div>
      </div>
    );
  }

  const tone =
    kind === 'degraded'
      ? 'border-amber-500/40 bg-amber-500/10 text-amber-100'
      : 'border-red-500/40 bg-red-500/10 text-red-100';

  return (
    <div className={`rounded border px-3 py-2 text-xs ${tone}`} role="status" aria-live="polite">
      <div className="flex items-start gap-2">
        <AlertTriangle size={13} className="mt-0.5" />
        <div>
          <p className="font-medium">{title}</p>
          <p className="opacity-90">{message}</p>
          {correlationId && <p className="mt-1 text-[10px] opacity-80">Correlation ID: {correlationId}</p>}
        </div>
      </div>
    </div>
  );
}

