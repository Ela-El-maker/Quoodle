export type CommandState =
  | 'queued'
  | 'dispatched'
  | 'ack_received'
  | 'executing'
  | 'completed'
  | 'failed'
  | 'expired'
  | 'rejected';

export type CommandOriginChannel =
  | 'control_ui'
  | 'mobile_app'
  | 'api'
  | 'schedule'
  | 'system'
  | 'unknown';

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
  origin_channel?: string | null;
  origin_session_id?: string | null;
  origin_mobile_device_id?: string | null;
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
  originChannel: CommandOriginChannel;
  originSessionId: string | null;
  originMobileDeviceId: string | null;
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

export function normalizeOriginChannel(value: string | null | undefined): CommandOriginChannel {
  const normalized = String(value ?? '').trim().toLowerCase();
  if (
    normalized === 'control_ui' ||
    normalized === 'mobile_app' ||
    normalized === 'api' ||
    normalized === 'schedule' ||
    normalized === 'system'
  ) {
    return normalized;
  }

  return 'unknown';
}

export function originChannelLabel(value: CommandOriginChannel): string {
  switch (value) {
    case 'control_ui':
      return 'Control UI';
    case 'mobile_app':
      return 'Mobile App';
    case 'api':
      return 'API';
    case 'schedule':
      return 'Scheduler';
    case 'system':
      return 'System';
    default:
      return 'Unknown';
  }
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
    originChannel: normalizeOriginChannel(row.origin_channel),
    originSessionId: row.origin_session_id?.trim() || null,
    originMobileDeviceId: row.origin_mobile_device_id?.trim() || null,
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
      origin_channel: detail.origin_channel ?? base.originChannel,
      origin_session_id: detail.origin_session_id ?? base.originSessionId,
      origin_mobile_device_id: detail.origin_mobile_device_id ?? base.originMobileDeviceId,
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
    origin_channel: row.originChannel,
    origin_session_id: row.originSessionId,
    origin_mobile_device_id: row.originMobileDeviceId,
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
