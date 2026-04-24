import type {
  AnswerArtifactItem,
  CopilotAnswerArtifact,
  CopilotConfidence,
  CopilotConversation,
  CopilotErrorState,
  CopilotEvidenceRef,
  CopilotTranscriptItem,
} from './types';

interface AskPayload {
  conversation_id?: string;
  query: string;
  selected_refs: {
    device_id: string;
  };
  ui_surface: string;
}

interface AskResponse {
  status?: string;
  conversation_id?: string;
  correlation_id?: string;
  artifact?: {
    artifact_id?: string;
    artifact_type?: string;
    state?: string;
    summary?: string | null;
    freshness_seconds?: number | null;
    created_at?: string | null;
  };
  display?: {
    answer_text?: string;
    confidence?: {
      score?: number | null;
      band?: string | null;
    };
    freshness_seconds?: number | null;
    evidence_refs?: Array<{
      source_type?: string;
      source_id?: string;
      excerpt_summary?: string | null;
      freshness_seconds?: number | null;
      rank?: number | null;
      href?: string | null;
      uri?: string | null;
    }>;
    missing_information?: string[];
    suggested_prompts?: string[];
  };
  message?: string;
  code?: string;
}

interface ConversationResponse {
  conversation_id?: string;
  state?: string;
  surface?: string | null;
  last_activity_at?: string | null;
  transcript?: unknown[];
  message?: string;
}

export interface AskCopilotResult {
  status: string;
  conversationId: string;
  correlationId?: string | null;
  artifactItem: AnswerArtifactItem;
  transcriptItems: CopilotTranscriptItem[];
}

function canonicalText(value: string): string {
  return value.replace(/\s+/g, ' ').trim().toLowerCase();
}

function dedupeTranscript(items: CopilotTranscriptItem[]): CopilotTranscriptItem[] {
  const deduped: CopilotTranscriptItem[] = [];

  for (let i = 0; i < items.length; i += 1) {
    const current = items[i];
    const next = i < items.length - 1 ? items[i + 1] : null;

    if (
      current.type === 'assistant_answer' &&
      next &&
      next.type === 'answer_artifact' &&
      canonicalText(current.text) !== '' &&
      canonicalText(current.text) === canonicalText(next.artifact.answer_text)
    ) {
      continue;
    }

    deduped.push(current);
  }

  return deduped;
}

export function normalizeConfidence(input?: { score?: number | null; band?: string | null }): CopilotConfidence {
  const score = typeof input?.score === 'number' && Number.isFinite(input.score) ? input.score : null;
  const rawBand = (input?.band ?? '').toLowerCase();
  const band =
    rawBand === 'high' || rawBand === 'medium' || rawBand === 'low'
      ? rawBand
      : score == null
        ? 'unknown'
        : score >= 0.75
          ? 'high'
          : score >= 0.5
            ? 'medium'
            : 'low';

  return { score, band };
}

function normalizeEvidence(
  rows?: Array<{
    source_type?: string;
    source_id?: string;
    excerpt_summary?: string | null;
    freshness_seconds?: number | null;
    rank?: number | null;
    href?: string | null;
    uri?: string | null;
  }>,
): CopilotEvidenceRef[] {
  if (!Array.isArray(rows)) return [];
  return rows
    .map((item) => ({
      source_type: String(item?.source_type ?? '').trim(),
      source_id: String(item?.source_id ?? '').trim(),
      excerpt_summary: typeof item?.excerpt_summary === 'string' ? item.excerpt_summary : null,
      freshness_seconds: typeof item?.freshness_seconds === 'number' ? item.freshness_seconds : null,
      rank: typeof item?.rank === 'number' ? item.rank : null,
      href:
        typeof item?.href === 'string' && item.href.trim().startsWith('/')
          ? item.href
          : typeof item?.uri === 'string' && item.uri.trim().startsWith('/')
            ? item.uri
            : null,
    }))
    .filter((item) => item.source_type !== '' && item.source_id !== '');
}

function toErrorState(payload: AskResponse, status: number): CopilotErrorState {
  const code = String(payload.code ?? payload.message ?? '').toLowerCase();
  const correlationId = typeof payload.correlation_id === 'string' ? payload.correlation_id : null;

  if (status === 403 || code.includes('scope') || code.includes('forbidden')) {
    return {
      code: 'scope_failure',
      title: 'Scope denied',
      message: 'Copilot cannot access this device scope.',
      correlationId,
      retryable: false,
    };
  }

  if (status === 422) {
    return {
      code: 'validation_error',
      title: 'Request invalid',
      message: 'The copilot request could not be validated.',
      correlationId,
      retryable: false,
    };
  }

  if (status === 503 || code.includes('timeout') || code.includes('unavailable')) {
    return {
      code: code.includes('timeout') ? 'timeout' : 'unavailable',
      title: 'Copilot unavailable',
      message: 'Copilot is temporarily unavailable. Retry in a moment.',
      correlationId,
      retryable: true,
    };
  }

  return {
    code: 'unknown',
    title: 'Copilot failed',
    message: 'Copilot could not complete this request.',
    correlationId,
    retryable: true,
  };
}

function normalizeStringArray(values: unknown): string[] {
  if (!Array.isArray(values)) return [];
  return values
    .map((item) => (typeof item === 'string' ? item.trim() : ''))
    .filter((item) => item.length > 0);
}

export async function askCopilot(payload: AskPayload, signal?: AbortSignal): Promise<AskCopilotResult> {
  const response = await fetch('/api/ai/copilot/ask', {
    method: 'POST',
    credentials: 'include',
    cache: 'no-store',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
    signal,
  });

  const body = (await response.json().catch(() => ({}))) as AskResponse;
  if (!response.ok) {
    throw toErrorState(body, response.status);
  }

  const conversationId = String(body.conversation_id ?? '').trim();
  if (!conversationId) {
    throw {
      code: 'persistence_failure',
      title: 'Conversation unavailable',
      message: 'Copilot response was not persisted as a conversation.',
      retryable: true,
      correlationId: body.correlation_id ?? null,
    } satisfies CopilotErrorState;
  }

  const confidence = normalizeConfidence(body.display?.confidence);
  const freshnessSeconds =
    typeof body.display?.freshness_seconds === 'number'
      ? body.display.freshness_seconds
      : typeof body.artifact?.freshness_seconds === 'number'
        ? body.artifact.freshness_seconds
        : null;
  const evidence = normalizeEvidence(body.display?.evidence_refs);
  const missingInformation = normalizeStringArray(body.display?.missing_information);
  const suggestedPrompts = normalizeStringArray(body.display?.suggested_prompts);

  const artifact: CopilotAnswerArtifact = {
    artifact_id: String(body.artifact?.artifact_id ?? ''),
    artifact_type: 'answer',
    state: String(body.artifact?.state ?? 'created'),
    answer_text: String(body.display?.answer_text ?? body.artifact?.summary ?? '').trim(),
    answer_class: 'explanation',
    confidence,
    freshness: {
      seconds: freshnessSeconds,
      fetchedAt: body.artifact?.created_at ?? null,
    },
    evidence_refs: evidence,
    missing_information: missingInformation,
    suggested_prompts: suggestedPrompts,
    created_at: body.artifact?.created_at ?? null,
  };

  const artifactItem: AnswerArtifactItem = {
    id: `artifact-${artifact.artifact_id || Date.now()}`,
    type: 'answer_artifact',
    timestamp: artifact.created_at ?? new Date().toISOString(),
    artifact,
  };

  const transcriptItems: CopilotTranscriptItem[] = [artifactItem];

  if (artifact.evidence_refs.length > 0) {
    transcriptItems.push({
      id: `evidence-${Date.now()}`,
      type: 'evidence_group',
      timestamp: artifact.created_at ?? new Date().toISOString(),
      evidence: artifact.evidence_refs,
    });
  }
  if (artifact.missing_information.length > 0) {
    transcriptItems.push({
      id: `missing-${Date.now()}`,
      type: 'missing_info_warning',
      timestamp: artifact.created_at ?? new Date().toISOString(),
      items: artifact.missing_information,
    });
  }
  if ((body.status ?? '').toLowerCase() === 'degraded' || artifact.state === 'incomplete' || confidence.band === 'low') {
    transcriptItems.push({
      id: `degraded-${Date.now()}`,
      type: 'degraded_response_notice',
      timestamp: artifact.created_at ?? new Date().toISOString(),
      reason: 'Context is partial or confidence is reduced.',
    });
  }
  if (artifact.suggested_prompts.length > 0) {
    transcriptItems.push({
      id: `prompts-${Date.now()}`,
      type: 'suggested_prompts',
      timestamp: artifact.created_at ?? new Date().toISOString(),
      prompts: artifact.suggested_prompts,
    });
  }

  return {
    status: body.status ?? 'ok',
    conversationId,
    correlationId: body.correlation_id ?? null,
    artifactItem,
    transcriptItems: dedupeTranscript(transcriptItems),
  };
}

function normalizeTranscript(raw: unknown[]): CopilotTranscriptItem[] {
  if (!Array.isArray(raw)) return [];

  const normalized = raw
    .map((item) => {
      if (!item || typeof item !== 'object' || Array.isArray(item)) return null;
      const record = item as Record<string, unknown>;
      const type = String(record.type ?? '').trim();
      const id = String(record.id ?? '').trim();
      const timestamp = typeof record.timestamp === 'string' ? record.timestamp : null;
      if (!type || !id) return null;

      switch (type) {
        case 'user_message':
        case 'assistant_answer':
        case 'system_status':
          return {
            id,
            type,
            timestamp,
            text: String(record.text ?? ''),
            ...(type === 'system_status' ? { status: 'info' as const } : {}),
          } as CopilotTranscriptItem;
        case 'missing_info_warning':
          return {
            id,
            type,
            timestamp,
            items: normalizeStringArray(record.items),
          } as CopilotTranscriptItem;
        case 'suggested_prompts':
          return {
            id,
            type,
            timestamp,
            prompts: normalizeStringArray(record.prompts),
          } as CopilotTranscriptItem;
        case 'degraded_response_notice':
          return {
            id,
            type,
            timestamp,
            reason: String(record.reason ?? 'Context is partial.'),
          } as CopilotTranscriptItem;
        case 'unavailable_notice':
          return {
            id,
            type,
            timestamp,
            message: String(record.message ?? 'Copilot unavailable'),
            correlationId: typeof record.correlationId === 'string' ? record.correlationId : null,
          } as CopilotTranscriptItem;
        case 'evidence_group':
          return {
            id,
            type,
            timestamp,
            evidence: normalizeEvidence(record.evidence as never),
          } as CopilotTranscriptItem;
        case 'answer_artifact': {
          const artifactValue = record.artifact;
          if (!artifactValue || typeof artifactValue !== 'object' || Array.isArray(artifactValue)) return null;
          const artifact = artifactValue as Record<string, unknown>;
          return {
            id,
            type,
            timestamp,
            artifact: {
              artifact_id: String(artifact.artifact_id ?? ''),
              artifact_type: 'answer',
              state: String(artifact.state ?? 'created'),
              answer_text: String(artifact.answer_text ?? ''),
              answer_class: String(artifact.answer_class ?? 'explanation'),
              confidence: normalizeConfidence(artifact.confidence as { score?: number | null; band?: string | null }),
              freshness: {
                seconds: typeof artifact.freshness_seconds === 'number' ? artifact.freshness_seconds : null,
                fetchedAt: typeof artifact.created_at === 'string' ? artifact.created_at : null,
              },
              evidence_refs: normalizeEvidence(artifact.evidence_refs as never),
              missing_information: normalizeStringArray(artifact.missing_information),
              suggested_prompts: normalizeStringArray(artifact.suggested_prompts),
              created_at: typeof artifact.created_at === 'string' ? artifact.created_at : null,
            },
          } as CopilotTranscriptItem;
        }
        default:
          return null;
      }
    })
    .filter((row): row is CopilotTranscriptItem => row !== null);

  return dedupeTranscript(normalized);
}

export async function fetchConversation(
  conversationId: string,
  context: { deviceId: string; deviceName: string },
  signal?: AbortSignal,
): Promise<CopilotConversation> {
  const response = await fetch(`/api/ai/copilot/conversations/${encodeURIComponent(conversationId)}`, {
    method: 'GET',
    credentials: 'include',
    cache: 'no-store',
    signal,
  });

  const body = (await response.json().catch(() => ({}))) as ConversationResponse;
  if (!response.ok) {
    const status = response.status;
    throw toErrorState({ message: body.message }, status);
  }

  return {
    conversationId: String(body.conversation_id ?? conversationId),
    state: String(body.state ?? 'active'),
    surface: String(body.surface ?? 'web.device_detail'),
    transcript: normalizeTranscript(Array.isArray(body.transcript) ? body.transcript : []),
    context: {
      deviceId: context.deviceId,
      deviceName: context.deviceName,
      scopeLabel: 'Current device only',
    },
    lastActivityAt: typeof body.last_activity_at === 'string' ? body.last_activity_at : null,
  };
}
