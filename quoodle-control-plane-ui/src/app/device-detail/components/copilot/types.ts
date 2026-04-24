export type CopilotConfidenceBand = 'low' | 'medium' | 'high' | 'unknown';

export interface CopilotConfidence {
  score: number | null;
  band: CopilotConfidenceBand;
}

export interface CopilotFreshness {
  seconds: number | null;
  fetchedAt?: string | null;
}

export interface CopilotEvidenceRef {
  source_type: string;
  source_id: string;
  excerpt_summary?: string | null;
  freshness_seconds?: number | null;
  rank?: number | null;
  href?: string | null;
}

export interface CopilotAnswerArtifact {
  artifact_id: string;
  artifact_type: 'answer';
  state: 'created' | 'incomplete' | 'degraded' | string;
  answer_text: string;
  answer_class: 'explanation' | 'why_blocked' | 'status_summary' | string;
  confidence: CopilotConfidence;
  freshness: CopilotFreshness;
  evidence_refs: CopilotEvidenceRef[];
  missing_information: string[];
  suggested_prompts: string[];
  created_at?: string | null;
}

export interface CopilotContextChip {
  key: string;
  label: string;
  value: string;
  tone?: 'default' | 'muted' | 'warning';
}

export interface CopilotErrorState {
  code:
    | 'scope_failure'
    | 'unavailable'
    | 'timeout'
    | 'persistence_failure'
    | 'validation_error'
    | 'unknown';
  title: string;
  message: string;
  correlationId?: string | null;
  retryable: boolean;
}

export interface TranscriptBase {
  id: string;
  timestamp?: string | null;
}

export interface UserMessageItem extends TranscriptBase {
  type: 'user_message';
  text: string;
}

export interface AssistantAnswerItem extends TranscriptBase {
  type: 'assistant_answer';
  text: string;
}

export interface SystemStatusItem extends TranscriptBase {
  type: 'system_status';
  text: string;
  status: 'loading' | 'info' | 'error';
}

export interface EvidenceGroupItem extends TranscriptBase {
  type: 'evidence_group';
  evidence: CopilotEvidenceRef[];
}

export interface MissingInfoWarningItem extends TranscriptBase {
  type: 'missing_info_warning';
  items: string[];
}

export interface DegradedResponseNoticeItem extends TranscriptBase {
  type: 'degraded_response_notice';
  reason: string;
}

export interface UnavailableNoticeItem extends TranscriptBase {
  type: 'unavailable_notice';
  message: string;
  correlationId?: string | null;
}

export interface SuggestedPromptsItem extends TranscriptBase {
  type: 'suggested_prompts';
  prompts: string[];
}

export interface AnswerArtifactItem extends TranscriptBase {
  type: 'answer_artifact';
  artifact: CopilotAnswerArtifact;
}

export type CopilotTranscriptItem =
  | UserMessageItem
  | AssistantAnswerItem
  | SystemStatusItem
  | EvidenceGroupItem
  | MissingInfoWarningItem
  | DegradedResponseNoticeItem
  | UnavailableNoticeItem
  | SuggestedPromptsItem
  | AnswerArtifactItem;

export interface CopilotConversation {
  conversationId: string;
  state: string;
  transcript: CopilotTranscriptItem[];
  surface: string;
  context: {
    deviceId: string;
    deviceName: string;
    scopeLabel: string;
  };
  lastActivityAt?: string | null;
}

