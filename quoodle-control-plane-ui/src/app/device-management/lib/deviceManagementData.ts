import type { AuditEntry } from '@/components/AuditTrailSection';
import { formatLocalDateTime, formatLocalTime } from '@/lib/dateTime';

export type DeviceStatus = 'online' | 'offline' | 'quarantined' | 'degraded';
export type ComplianceStatus = 'compliant' | 'non_compliant' | 'drift';
export type CommandState =
  | 'queued'
  | 'dispatched'
  | 'ack_received'
  | 'executing'
  | 'completed'
  | 'failed'
  | 'expired'
  | 'rejected';

export interface Device {
  id: string;
  hostname: string;
  osBuild: string;
  owner: string;
  status: DeviceStatus;
  riskScore: number;
  compliance: ComplianceStatus;
  lastSeen: string;
  agentVersion: string;
  policySync: boolean | null;
  kernelGuard: boolean | null;
  ipAddress: string | null;
  sessionId: string | null;
}

export interface ListDeviceApi {
  device_id: string;
  owner_email?: string | null;
  device_name?: string | null;
  lifecycle_state?: string | null;
  last_seen?: string | null;
  agent_version?: string | null;
  os_build?: string | null;
  compliance_status?: string | null;
  risk_score?: number | string | null;
  policy_in_sync?: boolean | null;
  kernel_guard?: boolean | null;
  ip_address?: string | null;
  session_id?: string | null;
}

export interface DetailDeviceApi {
  device_id: string;
  owner_email?: string | null;
  device_name?: string | null;
  lifecycle_state?: string | null;
  last_seen?: string | null;
  agent_version?: string | null;
  os_build?: string | null;
  compliance?: { status?: string | null };
  compliance_status?: string | null;
  risk_score?: number | string | null;
  policy_in_sync?: boolean | null;
  telemetry_latest?: { risk_score?: number | string | null };
  ip_address?: string | null;
  session_id?: string | null;
  kernel_guard?: boolean | null;
}

export interface DeviceCommandRowApi {
  command_id?: string;
  device_id?: string;
  method?: string;
  params?: Record<string, unknown>;
  state?: string;
  queued_at?: string | null;
  completed_at?: string | null;
  result_status?: string | null;
  error_code?: number | string | null;
  error_message?: string | null;
  reason?: string | null;
  actor_email?: string | null;
}

export interface DeviceTelemetryApi {
  device_id?: string;
  timestamp?: string | null;
  metrics?: {
    cpu?: number | null;
    ram?: number | null;
    disk_usage?: number | null;
    network_tx?: number | null;
    network_rx?: number | null;
    risk_score?: number | string | null;
    policy_hash?: string | null;
    kernel_event?: unknown;
  };
}

export interface DeviceAlertApi {
  alert_id?: string;
  device_id?: string;
  severity?: string;
  category?: string;
  message?: string;
  timestamp?: string | null;
  acknowledged?: boolean;
}

export interface DeviceAuditApi {
  id?: string;
  timestamp?: string | null;
  event_type?: string;
  summary?: string;
  details?: Record<string, unknown>;
}

export interface DeviceCommandsResponse {
  commands?: DeviceCommandRowApi[];
  next_before?: string | null;
}

export interface DeviceAlertsResponse {
  alerts?: DeviceAlertApi[];
}

export interface DeviceAuditResponse {
  entries?: DeviceAuditApi[];
}

export type DeviceTelemetryResponse = DeviceTelemetryApi;

export interface CommandCapabilitiesResponse {
  canonical_methods?: string[];
  runtime_supported_methods?: string[];
  rejection_reasons?: Record<string, string>;
}

export interface DrawerCommandEntry {
  id: string;
  method: string;
  params: Record<string, unknown>;
  state: CommandState;
  actor: string;
  queuedAt: string;
  completedAt: string | null;
  duration: string | null;
  resultPreview: string | null;
}

export const VALID_STATUSES: DeviceStatus[] = ['online', 'offline', 'degraded', 'quarantined'];

export function normalizeStatus(value: string | null | undefined): DeviceStatus {
  const normalized = String(value ?? '').toLowerCase();
  if (normalized === 'online' || normalized === 'active') return 'online';
  if (normalized === 'quarantined') return 'quarantined';
  if (normalized === 'degraded') return 'degraded';
  return 'offline';
}

export function normalizeCompliance(value: string | null | undefined): ComplianceStatus {
  const normalized = String(value ?? '').toLowerCase();
  if (normalized === 'compliant') return 'compliant';
  if (normalized === 'drift' || normalized === 'degraded' || normalized === 'unknown') return 'drift';
  return 'non_compliant';
}

export function normalizeRisk(value: number | string | null | undefined): number {
  const parsed = typeof value === 'number' ? value : Number(value ?? 0);
  if (!Number.isFinite(parsed) || parsed <= 0) return 0;
  if (parsed > 1) return Math.max(0, Math.min(1, parsed / 100));
  return Math.max(0, Math.min(1, parsed));
}

export function clampPercent(value: number | null | undefined): number {
  if (typeof value !== 'number' || !Number.isFinite(value)) return 0;
  return Math.max(0, Math.min(100, value));
}

export function formatDateTime(value: string | null | undefined): string {
  return formatLocalDateTime(value, '-');
}

export function formatTimeOnly(value: string | null | undefined): string {
  return formatLocalTime(value, '-');
}

export function formatAuditTimestamp(value: string | null | undefined): string {
  return formatLocalDateTime(value, '-');
}

export function formatDuration(startIso: string | null | undefined, endIso: string | null | undefined): string | null {
  if (!startIso || !endIso) return null;
  const start = new Date(startIso).getTime();
  const end = new Date(endIso).getTime();
  if (!Number.isFinite(start) || !Number.isFinite(end) || end < start) return null;
  return `${Math.round((end - start) / 1000)}s`;
}

export function parseStatusCsv(value: string | null): DeviceStatus[] {
  if (!value) return [];
  return value
    .split(',')
    .map((v) => v.trim().toLowerCase())
    .filter((v): v is DeviceStatus => VALID_STATUSES.includes(v as DeviceStatus));
}

export function mapListDevice(item: ListDeviceApi): Device {
  return {
    id: item.device_id,
    hostname: item.device_name?.trim() || item.device_id,
    osBuild: item.os_build?.trim() || '-',
    owner: item.owner_email?.trim() || 'Unknown',
    status: normalizeStatus(item.lifecycle_state),
    riskScore: normalizeRisk(item.risk_score),
    compliance: normalizeCompliance(item.compliance_status),
    lastSeen: formatDateTime(item.last_seen),
    agentVersion: item.agent_version?.trim() || '-',
    policySync: typeof item.policy_in_sync === 'boolean' ? item.policy_in_sync : null,
    kernelGuard: typeof item.kernel_guard === 'boolean' ? item.kernel_guard : null,
    ipAddress: item.ip_address?.trim() || null,
    sessionId: item.session_id?.trim() || null,
  };
}

export function mergeDeviceDetail(base: Device, detail: DetailDeviceApi): Device {
  const detailLastSeen = formatDateTime(detail.last_seen);
  return {
    ...base,
    hostname: detail.device_name?.trim() || base.hostname,
    osBuild: detail.os_build?.trim() || base.osBuild,
    owner: detail.owner_email?.trim() || base.owner,
    status: normalizeStatus(detail.lifecycle_state ?? base.status),
    compliance: normalizeCompliance(detail.compliance?.status ?? detail.compliance_status ?? base.compliance),
    riskScore: normalizeRisk(detail.risk_score ?? detail.telemetry_latest?.risk_score ?? base.riskScore),
    lastSeen: detailLastSeen !== '-' ? detailLastSeen : base.lastSeen,
    agentVersion: detail.agent_version?.trim() || base.agentVersion,
    policySync: typeof detail.policy_in_sync === 'boolean' ? detail.policy_in_sync : base.policySync,
    kernelGuard: typeof detail.kernel_guard === 'boolean' ? detail.kernel_guard : base.kernelGuard,
    ipAddress: detail.ip_address?.trim() || base.ipAddress,
    sessionId: detail.session_id?.trim() || base.sessionId,
  };
}

function normalizeCommandState(value: string | null | undefined): CommandState {
  const normalized = String(value ?? '').toLowerCase();
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

export function mapCommandHistoryEntry(row: DeviceCommandRowApi): DrawerCommandEntry {
  return {
    id: row.command_id?.trim() || 'unknown',
    method: row.method?.trim() || 'unknown',
    params: row.params ?? {},
    state: normalizeCommandState(row.state),
    actor: row.actor_email?.trim() || 'system',
    queuedAt: formatTimeOnly(row.queued_at),
    completedAt: row.completed_at ? formatTimeOnly(row.completed_at) : null,
    duration: formatDuration(row.queued_at, row.completed_at),
    resultPreview:
      row.error_message?.trim() ||
      row.reason?.trim() ||
      row.result_status?.trim() ||
      (row.error_code == null ? null : `error ${String(row.error_code)}`),
  };
}

function inferActorRole(actor: string): string {
  const lowered = actor.toLowerCase();
  if (lowered === 'system') return 'System';
  if (lowered.includes('admin')) return 'Admin';
  if (lowered.includes('viewer')) return 'Viewer';
  return 'Operator';
}

export function mapCommandRowToAuditEntry(row: DeviceCommandRowApi): AuditEntry {
  const state = normalizeCommandState(row.state);
  const action = state === 'completed' ? 'COMMAND_COMPLETED' : `COMMAND_${state.toUpperCase()}`;
  const outcome = state === 'completed' ? 'success' : ['failed', 'expired', 'rejected'].includes(state) ? 'failure' : 'pending';
  const actor = row.actor_email?.trim() || 'system';

  return {
    id: row.command_id?.trim() || `cmd-${Date.now()}`,
    timestamp: formatAuditTimestamp(row.queued_at ?? row.completed_at),
    actor,
    actorRole: inferActorRole(actor),
    eventType: 'command_execution',
    action,
    target: row.device_id?.trim() || 'device',
    detail: row.error_message?.trim() || row.reason?.trim() || `${row.method ?? 'command'} dispatched`,
    outcome,
  };
}

export function mapAlertRowToAuditEntry(row: DeviceAlertApi): AuditEntry {
  const isAcked = !!row.acknowledged;
  const severity = (row.severity ?? 'unknown').toLowerCase();
  return {
    id: row.alert_id?.trim() || `alert-${Date.now()}`,
    timestamp: formatAuditTimestamp(row.timestamp),
    actor: 'system',
    actorRole: 'System',
    eventType: 'system_event',
    action: isAcked ? 'ALERT_ACKNOWLEDGED' : 'ALERT_RAISED',
    target: row.device_id?.trim() || row.alert_id?.trim() || 'fleet',
    detail: row.message?.trim() || `${severity} alert`,
    outcome: isAcked ? 'success' : severity === 'critical' ? 'failure' : 'pending',
  };
}

export function composeAuditEntries(commands: DeviceCommandRowApi[], alerts: DeviceAlertApi[]): AuditEntry[] {
  return [...commands.map(mapCommandRowToAuditEntry), ...alerts.map(mapAlertRowToAuditEntry)]
    .sort((a, b) => {
      const at = Date.parse(a.timestamp);
      const bt = Date.parse(b.timestamp);
      if (Number.isNaN(at) && Number.isNaN(bt)) return 0;
      if (Number.isNaN(at)) return 1;
      if (Number.isNaN(bt)) return -1;
      return bt - at;
    });
}
