import React from 'react';
import type { CopilotEvidenceRef } from './types';

interface CopilotEvidenceChipsProps {
  evidence: CopilotEvidenceRef[];
}

function freshnessLabel(seconds: number | null | undefined): string {
  if (typeof seconds !== 'number' || !Number.isFinite(seconds)) return 'freshness unknown';
  if (seconds < 60) return `${Math.round(seconds)}s old`;
  if (seconds < 3600) return `${Math.round(seconds / 60)}m old`;
  return `${Math.round(seconds / 3600)}h old`;
}

function isSafeRelativeHref(value: string | null | undefined): value is string {
  return typeof value === 'string' && value.trim().startsWith('/');
}

function compact(value: string, head = 10, tail = 8): string {
  if (value.length <= head + tail + 1) return value;
  return `${value.slice(0, head)}...${value.slice(-tail)}`;
}

export default function CopilotEvidenceChips({ evidence }: CopilotEvidenceChipsProps) {
  if (evidence.length === 0) {
    return <p className="text-[11px] text-muted-foreground">No evidence references were attached.</p>;
  }

  return (
    <div className="flex flex-wrap gap-2" aria-label="Evidence references">
      {evidence.map((row) => {
        const sourceType = row.source_type.trim();
        const sourceId = row.source_id.trim();
        const compactId = compact(sourceId);
        const label = sourceId !== '' && sourceId !== sourceType ? `${sourceType}:${compactId}` : sourceType;
        const title = `${row.excerpt_summary ?? `${sourceType}:${sourceId}`} | ${freshnessLabel(row.freshness_seconds)}`;
        const key = `${row.source_type}-${row.source_id}-${row.rank ?? 0}`;

        if (isSafeRelativeHref(row.href)) {
          return (
            <a
              key={key}
              href={row.href}
              className="inline-flex items-center rounded-full border border-border bg-background px-2 py-1 text-[10px] text-muted-foreground hover:border-primary/40 hover:text-foreground focus:outline-none focus:ring-1 focus:ring-primary/40"
              title={title}
            >
              {label}
            </a>
          );
        }

        return (
          <span
            key={key}
            className="inline-flex items-center rounded-full border border-border bg-background px-2 py-1 text-[10px] text-muted-foreground"
            title={title}
          >
            {label}
          </span>
        );
      })}
    </div>
  );
}
