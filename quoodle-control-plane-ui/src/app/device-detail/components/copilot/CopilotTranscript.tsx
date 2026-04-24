import React from 'react';
import CopilotArtifactCard from './CopilotArtifactCard';
import CopilotEvidenceChips from './CopilotEvidenceChips';
import CopilotStateNotice from './CopilotStateNotice';
import type { CopilotTranscriptItem } from './types';

interface CopilotTranscriptProps {
  items: CopilotTranscriptItem[];
}

function timeLabel(timestamp?: string | null): string {
  if (!timestamp) return '';
  const parsed = Date.parse(timestamp);
  if (Number.isNaN(parsed)) return '';
  return new Date(parsed).toLocaleTimeString();
}

export default function CopilotTranscript({ items }: CopilotTranscriptProps) {
  return (
    <ol className="space-y-2" aria-label="Copilot transcript">
      {items.map((item) => {
        switch (item.type) {
          case 'user_message':
            return (
              <li key={item.id} className="flex justify-end">
                <div className="max-w-[92%] rounded-lg bg-primary/12 border border-primary/20 px-3 py-2">
                  <p className="text-xs text-foreground">{item.text}</p>
                  <p className="mt-1 text-[10px] text-muted-foreground text-right">{timeLabel(item.timestamp)}</p>
                </div>
              </li>
            );
          case 'assistant_answer':
            return (
              <li key={item.id} className="rounded-lg border border-border bg-muted/20 px-3 py-2">
                <p className="text-sm text-foreground whitespace-pre-wrap break-words leading-relaxed">{item.text}</p>
                <p className="mt-1 text-[10px] text-muted-foreground">{timeLabel(item.timestamp)}</p>
              </li>
            );
          case 'answer_artifact':
            return (
              <li key={item.id}>
                <CopilotArtifactCard artifact={item.artifact} />
              </li>
            );
          case 'evidence_group':
            return (
              <li key={item.id} className="rounded border border-border bg-muted/10 p-2.5">
                <p className="text-[11px] text-muted-foreground mb-2">Evidence ledger</p>
                <CopilotEvidenceChips evidence={item.evidence} />
              </li>
            );
          case 'missing_info_warning':
            return (
              <li key={item.id} className="rounded border border-amber-500/30 bg-amber-500/10 px-3 py-2 text-[11px] text-amber-100">
                <p className="font-medium">Missing information</p>
                <ul className="mt-1 space-y-1">
                  {item.items.map((entry) => (
                    <li key={entry}>- {entry}</li>
                  ))}
                </ul>
              </li>
            );
          case 'degraded_response_notice':
            return (
              <li key={item.id}>
                <CopilotStateNotice kind="degraded" title="Degraded response" message={item.reason} />
              </li>
            );
          case 'unavailable_notice':
            return (
              <li key={item.id}>
                <CopilotStateNotice kind="unavailable" title="Copilot unavailable" message={item.message} correlationId={item.correlationId} />
              </li>
            );
          case 'suggested_prompts':
            return (
              <li key={item.id} className="rounded border border-border bg-card px-3 py-2">
                <p className="text-[11px] text-muted-foreground mb-1">Suggested next questions</p>
                <ul className="space-y-1 text-xs">
                  {item.prompts.map((prompt) => (
                    <li key={prompt}>- {prompt}</li>
                  ))}
                </ul>
              </li>
            );
          case 'system_status':
            if (item.status === 'loading') {
              return (
                <li key={item.id}>
                  <CopilotStateNotice kind="loading" title="Gathering evidence..." message={item.text} />
                </li>
              );
            }
            return (
              <li key={item.id} className="text-[11px] text-muted-foreground">
                {item.text}
              </li>
            );
          default:
            return null;
        }
      })}
    </ol>
  );
}
