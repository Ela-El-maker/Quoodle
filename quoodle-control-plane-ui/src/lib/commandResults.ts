export type CommandState =
  | 'queued'
  | 'dispatched'
  | 'ack_received'
  | 'executing'
  | 'completed'
  | 'failed'
  | 'expired'
  | 'rejected';

export interface CommandResultObject {
  status?: string | null;
  notes?: string | null;
  artifact_url?: string | null;
  artifact_checksum?: string | null;
  data?: unknown;
  output_text?: string | null;
  meta?: Record<string, unknown> | null;
  [key: string]: unknown;
}

export interface CommandListRowApi {
  command_id?: string | null;
  device_id?: string | null;
  device_name?: string | null;
  method?: string | null;
  params?: Record<string, unknown> | null;
  state?: string | null;
  execution_state?: string | null;
  queued_at?: string | null;
  dispatched_at?: string | null;
  completed_at?: string | null;
  trace_id?: string | null;
  result?: CommandResultObject | null;
  result_status?: string | null;
  result_notes?: string | null;
  artifact_url?: string | null;
  artifact_checksum?: string | null;
  error_code?: number | string | null;
  error_message?: string | null;
  reason?: string | null;
  actor_email?: string | null;
}

export interface CommandDetailApi extends CommandListRowApi {
  audit?: Record<string, unknown> | null;
}

export interface NormalizedCommandResult {
  id: string;
  commandId: string;
  deviceId: string;
  deviceName: string;
  method: string;
  params: Record<string, unknown>;
  state: CommandState;
  executionState: string | null;
  queuedAt: string | null;
  dispatchedAt: string | null;
  completedAt: string | null;
  traceId: string | null;
  actorEmail: string;
  result: CommandResultObject | null;
  resultStatus: string | null;
  resultNotes: string | null;
  artifactUrl: string | null;
  artifactChecksum: string | null;
  errorCode: number | null;
  errorMessage: string | null;
  reason: string | null;
}

export function normalizeCommandState(value: string | null | undefined): CommandState {
  const normalized = String(value ?? '').trim().toLowerCase();
  if (
    normalized === 'queued' ||
    normalized === 'dispatched' ||
    normalized === 'ack_received' ||
    normalized === 'executing' ||
    normalized === 'completed' ||
    normalized === 'failed' ||
    normalized === 'expired' ||
    normalized === 'rejected'
  ) {
    return normalized;
  }
  return 'queued';
}

function normalizeResultObject(result: unknown): CommandResultObject | null {
  if (!result || typeof result !== 'object' || Array.isArray(result)) return null;
  return result as CommandResultObject;
}

function toNumber(value: number | string | null | undefined): number | null {
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  if (typeof value === 'string' && value.trim() !== '') {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) return parsed;
  }
  return null;
}

function normalizeArtifactUrl(value: unknown): string | null {
  if (typeof value !== 'string') return null;
  const raw = value.trim();
  if (!raw) return null;

  if (raw.startsWith('/api/artifact/')) {
    return raw;
  }

  try {
    const parsed = new URL(raw);
    const match = parsed.pathname.match(/\/api\/artifact\/([^/?#]+)/i);
    if (match?.[1]) {
      return `/api/artifact/${match[1]}`;
    }
  } catch {
    // Keep non-URL strings as-is.
  }

  return raw;
}

export function mapCommandListRow(row: CommandListRowApi): NormalizedCommandResult {
  const result = normalizeResultObject(row.result);
  const commandId = row.command_id?.trim() || 'unknown';
  const deviceId = row.device_id?.trim() || 'unknown';

  return {
    id: commandId,
    commandId,
    deviceId,
    deviceName: row.device_name?.trim() || deviceId,
    method: row.method?.trim() || 'unknown',
    params: row.params ?? {},
    state: normalizeCommandState(row.state),
    executionState: row.execution_state?.trim() || null,
    queuedAt: row.queued_at ?? null,
    dispatchedAt: row.dispatched_at ?? null,
    completedAt: row.completed_at ?? null,
    traceId: row.trace_id?.trim() || null,
    actorEmail: row.actor_email?.trim() || 'Unknown',
    result,
    resultStatus: row.result_status?.trim() || (typeof result?.status === 'string' ? result.status : null),
    resultNotes: row.result_notes?.trim() || (typeof result?.notes === 'string' ? result.notes : null),
    artifactUrl:
      normalizeArtifactUrl(row.artifact_url) ??
      normalizeArtifactUrl(result?.artifact_url),
    artifactChecksum:
      row.artifact_checksum?.trim() || (typeof result?.artifact_checksum === 'string' ? result.artifact_checksum : null),
    errorCode: toNumber(row.error_code),
    errorMessage: row.error_message?.trim() || null,
    reason: row.reason?.trim() || null,
  };
}

export function mergeCommandDetail(
  base: NormalizedCommandResult,
  detail: CommandDetailApi,
): NormalizedCommandResult {
  return {
    ...base,
    ...mapCommandListRow({
      ...detail,
      command_id: detail.command_id ?? base.commandId,
      device_id: detail.device_id ?? base.deviceId,
      device_name: detail.device_name ?? base.deviceName,
      method: detail.method ?? base.method,
      params: detail.params ?? base.params,
      state: detail.state ?? base.state,
      execution_state: detail.execution_state ?? base.executionState,
      queued_at: detail.queued_at ?? base.queuedAt,
      dispatched_at: detail.dispatched_at ?? base.dispatchedAt,
      completed_at: detail.completed_at ?? base.completedAt,
      trace_id: detail.trace_id ?? base.traceId,
      actor_email: detail.actor_email ?? base.actorEmail,
      result: detail.result ?? base.result,
      result_status: detail.result_status ?? base.resultStatus,
      result_notes: detail.result_notes ?? base.resultNotes,
      artifact_url: detail.artifact_url ?? base.artifactUrl,
      artifact_checksum: detail.artifact_checksum ?? base.artifactChecksum,
      error_code: detail.error_code ?? base.errorCode,
      error_message: detail.error_message ?? base.errorMessage,
      reason: detail.reason ?? base.reason,
    }),
    id: base.id,
  };
}

export function extractResultData(row: NormalizedCommandResult): unknown {
  if (!row.result) return null;
  if (row.result.data !== undefined) return row.result.data;
  return null;
}

export function extractOutputText(row: NormalizedCommandResult): string {
  if (!row.result) return '';
  if (typeof row.result.output_text === 'string' && row.result.output_text.trim() !== '') {
    return row.result.output_text;
  }
  if (typeof row.result.notes === 'string' && row.result.notes.trim() !== '') {
    return row.result.notes;
  }
  return '';
}

export function toRawResultJson(row: NormalizedCommandResult): string {
  const payload = {
    command_id: row.commandId,
    device_id: row.deviceId,
    method: row.method,
    state: row.state,
    execution_state: row.executionState,
    queued_at: row.queuedAt,
    dispatched_at: row.dispatchedAt,
    completed_at: row.completedAt,
    trace_id: row.traceId,
    actor_email: row.actorEmail,
    result: row.result,
    error_code: row.errorCode,
    error_message: row.errorMessage,
    reason: row.reason,
  };
  return JSON.stringify(payload, null, 2);
}

export function resultPreview(row: NormalizedCommandResult): string {
  return (
    row.resultNotes ||
    row.errorMessage ||
    row.reason ||
    row.resultStatus ||
    (row.errorCode == null ? 'No data available' : `error ${row.errorCode}`)
  );
}

export function isTerminalState(state: CommandState): boolean {
  return ['completed', 'failed', 'expired', 'rejected'].includes(state);
}
