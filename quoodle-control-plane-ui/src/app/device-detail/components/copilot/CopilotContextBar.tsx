import React from 'react';
import type { CopilotContextChip } from './types';

interface CopilotContextBarProps {
  chips: CopilotContextChip[];
}

export default function CopilotContextBar({ chips }: CopilotContextBarProps) {
  return (
    <div className="flex flex-wrap gap-2" aria-label="Copilot context">
      {chips.map((chip) => (
        <span
          key={chip.key}
          className={`inline-flex items-center gap-1 rounded-full border px-2 py-1 text-[10px] ${
            chip.tone === 'warning'
              ? 'border-amber-500/40 bg-amber-500/10 text-amber-300'
              : chip.tone === 'muted'
                ? 'border-border bg-muted/30 text-muted-foreground'
                : 'border-border bg-background text-foreground/85'
          }`}
        >
          <span className="uppercase tracking-wide text-[9px] opacity-80">{chip.label}</span>
          <span className="font-medium">{chip.value}</span>
        </span>
      ))}
    </div>
  );
}

