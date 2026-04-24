import React from 'react';
import CopilotEvidenceChips from './CopilotEvidenceChips';
import type { CopilotAnswerArtifact } from './types';

interface CopilotArtifactCardProps {
  artifact: CopilotAnswerArtifact;
}

function confidenceTone(band: string): string {
  if (band === 'high') return 'text-green-400';
  if (band === 'medium') return 'text-amber-400';
  if (band === 'low') return 'text-red-400';
  return 'text-muted-foreground';
}

function freshnessValue(seconds: number | null): string {
  if (seconds == null) return 'Unknown';
  if (seconds < 60) return `${Math.round(seconds)}s`;
  if (seconds < 3600) return `${Math.round(seconds / 60)}m`;
  return `${Math.round(seconds / 3600)}h`;
}

function cleanAnswerText(text: string): string {
  return text
    .replace(/\r\n/g, '\n')
    .replace(/^#{1,6}\s*/gm, '')
    .replace(/\*\*/g, '')
    .trim();
}

export default function CopilotArtifactCard({ artifact }: CopilotArtifactCardProps) {
  const answerText = cleanAnswerText(artifact.answer_text);

  return (
    <article className="rounded-lg border border-border bg-card p-3 space-y-3" aria-label="Answer artifact">
      <header className="flex items-center justify-between gap-3">
        <div>
          <p className="text-[11px] uppercase tracking-wide text-muted-foreground">Answer Artifact</p>
          <p className="text-xs text-foreground/90">{artifact.answer_class.replace('_', ' ')}</p>
        </div>
        <span className="rounded-full border border-border bg-muted/30 px-2 py-0.5 text-[10px] text-muted-foreground">
          {artifact.state}
        </span>
      </header>

      <p className="text-sm leading-relaxed whitespace-pre-wrap break-words">{answerText}</p>

      <div className="flex flex-wrap items-center gap-3 text-[11px]">
        <span className={confidenceTone(artifact.confidence.band)}>
          Confidence {artifact.confidence.band}
          {typeof artifact.confidence.score === 'number' ? ` (${artifact.confidence.score.toFixed(2)})` : ''}
        </span>
        <span className="text-muted-foreground">Freshness {freshnessValue(artifact.freshness.seconds)}</span>
      </div>

      <CopilotEvidenceChips evidence={artifact.evidence_refs} />

      {artifact.missing_information.length > 0 && (
        <div className="rounded border border-amber-500/30 bg-amber-500/10 px-2.5 py-2">
          <p className="text-[11px] font-medium text-amber-300">Missing information</p>
          <ul className="mt-1 space-y-1 text-[11px] text-amber-100/90">
            {artifact.missing_information.map((item) => (
              <li key={item}>- {item}</li>
            ))}
          </ul>
        </div>
      )}
    </article>
  );
}
