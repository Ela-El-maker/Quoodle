'use client';

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import type { AuditEntry } from '@/components/AuditTrailSection';
import type { WsEvent } from '@/components/LiveAlertFeed';
import {
  formatLocalDateKey,
  formatLocalDateTime,
  formatLocalDayLabel,
  formatLocalTime,
  formatNowLocalTime,
  parseLocalDateTime,
} from '@/lib/dateTime';
import type { DashboardActivityItem } from '../components/DashboardActivityFeed';
import type { DashboardKpiData } from '../components/DashboardKPIGrid';
import type { FleetStatusDatum } from '../components/DashboardFleetStatusChart';
import type { CommandVolumeDatum } from '../components/DashboardCommandVolumeChart';
import type {
  AttentionDeviceItem,
  FailingCommandItem,
} from '../components/DashboardNeedsAttention';

const AUTO_REFRESH_INTERVAL_MS = 30_000;
const PAGE_SIZE = 200;
const COMMAND_FETCH_MAX_PAGES = 10;
const COMMAND_WINDOW_DAYS = 7;

type DeviceStatus = 'online' | 'offline' | 'quarantined' | 'degraded';
type ComplianceStatus = 'compliant' | 'non_compliant' | 'drift' | 'unknown';

interface DeviceApiRow {
  device_id?: string;
  owner_email?: string | null;
  device_name?: string | null;
  lifecycle_state?: string | null;
  compliance_status?: string | null;
  risk_score?: number | string | null;
  last_seen?: string | null;
  agent_version?: string | null;
}

interface DevicesApiResponse {
  devices?: DeviceApiRow[];
  meta?: {
    current_page?: number;
    last_page?: number;
  };
}

interface AlertApiRow {
  alert_id?: string;
  severity?: string | null;
  message?: string | null;
  timestamp?: string | null;
  device_id?: string | null;
  acknowledged?: boolean;
}

interface AlertsApiResponse {
  alerts?: AlertApiRow[];
}

interface CommandApiRow {
  command_id?: string;
  method?: string | null;
  state?: string | null;
  queued_at?: string | null;
  completed_at?: string | null;
  device_id?: string | null;
  error_code?: number | string | null;
  error_message?: string | null;
  actor_email?: string | null;
}

interface CommandsApiResponse {
  commands?: CommandApiRow[];
  next_before?: string | null;
}

interface NormalizedDevice {
  id: string;
  name: string;
  owner: string;
  status: DeviceStatus;
  compliance: ComplianceStatus;
  risk: number; // 0..1
  lastSeenIso: string | null;
  agentVersion: string | null;
}

interface NormalizedAlert {
  id: string;
  severity: string;
  message: string;
  deviceId: string | null;
  timestampIso: string | null;
  acknowledged: boolean;
}

interface NormalizedCommand {
  id: string;
  method: string;
  state: string;
  deviceId: string | null;
  queuedAtIso: string | null;
  completedAtIso: string | null;
  errorCode: string | null;
  errorMessage: string | null;
  actorEmail: string | null;
}

interface DashboardErrors {
  devices: string | null;
  alerts: string | null;
  commands: string | null;
  audit: string | null;
}

interface DashboardSnapshot {
  kpi: DashboardKpiData;
  fleetStatus: FleetStatusDatum[];
  commandVolume: CommandVolumeDatum[];
  failingCommands: FailingCommandItem[];
  attentionDevices: AttentionDeviceItem[];
  activityItems: DashboardActivityItem[];
  auditEntries: AuditEntry[];
  liveFeedEvents: WsEvent[];
}

export interface UseDashboardDataResult {
  data: DashboardSnapshot;
  loading: boolean;
  refreshing: boolean;
  errors: DashboardErrors;
  refresh: () => Promise<void>;
  lastRefreshLabel: string;
}

const EMPTY_KPI: DashboardKpiData = {
  totalDevices: 0,
  onlineDevices: 0,
  offlineDevices: 0,
  quarantinedDevices: 0,
  activeCommands: 0,
  failingCommands: 0,
  criticalAlerts: 0,
  complianceDrift: 0,
  avgRiskScore: 0,
  fleetOnlineRate: 0,
};

const EMPTY_SNAPSHOT: DashboardSnapshot = {
  kpi: EMPTY_KPI,
  fleetStatus: [
    { name: 'Online', value: 0, color: 'hsl(142 71% 45%)' },
    { name: 'Offline', value: 0, color: 'hsl(240 5% 45%)' },
    { name: 'Degraded', value: 0, color: 'hsl(38 92% 50%)' },
    { name: 'Quarantined', value: 0, color: 'hsl(0 72% 51%)' },
  ],
  commandVolume: [],
  failingCommands: [],
  attentionDevices: [],
  activityItems: [],
  auditEntries: [],
  liveFeedEvents: [],
};

function normalizeStatus(value: string | null | undefined): DeviceStatus {
  const normalized = String(value ?? '').toLowerCase();
  if (normalized === 'active' || normalized === 'online') return 'online';
  if (normalized === 'quarantined') return 'quarantined';
  if (normalized === 'degraded') return 'degraded';
  return 'offline';
}

function normalizeCompliance(value: string | null | undefined): ComplianceStatus {
  const normalized = String(value ?? '').toLowerCase();
  if (normalized === 'compliant') return 'compliant';
  if (normalized === 'drift' || normalized === 'non_compliant') return 'drift';
  if (normalized === 'unknown') return 'unknown';
  return 'non_compliant';
}

function normalizeRisk(value: number | string | null | undefined): number {
  const parsed = typeof value === 'number' ? value : Number(value ?? 0);
  if (!Number.isFinite(parsed) || parsed <= 0) return 0;
  if (parsed > 1) return Math.max(0, Math.min(1, parsed / 100));
  return Math.max(0, Math.min(1, parsed));
}

function formatLocalEventTime(iso: string | null | undefined): string {
  return formatLocalTime(iso, '--:--:--');
}

function formatAuditTimestamp(iso: string | null | undefined): string {
  return formatLocalDateTime(iso, '1970-01-01 00:00:00');
}

function formatDayLabel(date: Date): string {
  return formatLocalDayLabel(date);
}

function nowTimeString(): string {
  return formatNowLocalTime();
}

function parseIsoMs(value: string | null | undefined): number | null {
  if (!value) return null;
  const ms = Date.parse(value);
  return Number.isFinite(ms) ? ms : null;
}

function commandEventTime(command: NormalizedCommand): string | null {
  return command.completedAtIso ?? command.queuedAtIso ?? null;
}

async function fetchDevices(signal: AbortSignal): Promise<NormalizedDevice[]> {
  const devices: NormalizedDevice[] = [];
  let page = 1;
  let lastPage = 1;

  while (page <= lastPage) {
    const response = await fetch(`/api/devices?per_page=${PAGE_SIZE}&page=${page}`, {
      credentials: 'include',
      cache: 'no-store',
      signal,
    });
    if (!response.ok) {
      throw new Error(`devices_fetch_failed_${response.status}`);
    }

    const payload = (await response.json()) as DevicesApiResponse;
    const rows = payload.devices ?? [];
    for (const row of rows) {
      const id = String(row.device_id ?? '').trim();
      if (!id) continue;
      devices.push({
        id,
        name: row.device_name?.trim() || id,
        owner: row.owner_email?.trim() || 'Unknown',
        status: normalizeStatus(row.lifecycle_state),
        compliance: normalizeCompliance(row.compliance_status),
        risk: normalizeRisk(row.risk_score),
        lastSeenIso: row.last_seen ?? null,
        agentVersion: row.agent_version?.trim() || null,
      });
    }

    const current = Number(payload.meta?.current_page ?? page);
    const end = Number(payload.meta?.last_page ?? current);
    lastPage = Number.isFinite(end) && end > 0 ? end : current;
    page = current + 1;
    if (rows.length === 0) break;
  }

  return devices;
}

async function fetchAlerts(signal: AbortSignal): Promise<NormalizedAlert[]> {
  const response = await fetch('/api/alerts?limit=200', {
    credentials: 'include',
    cache: 'no-store',
    signal,
  });
  if (!response.ok) {
    throw new Error(`alerts_fetch_failed_${response.status}`);
  }

  const payload = (await response.json()) as AlertsApiResponse;
  return (payload.alerts ?? [])
    .map((row): NormalizedAlert | null => {
      const id = String(row.alert_id ?? '').trim();
      if (!id) return null;
      return {
        id,
        severity: String(row.severity ?? 'info').toLowerCase(),
        message: row.message?.trim() || 'Alert event',
        deviceId: row.device_id?.trim() || null,
        timestampIso: row.timestamp ?? null,
        acknowledged: Boolean(row.acknowledged),
      };
    })
    .filter((row): row is NormalizedAlert => row !== null);
}

async function fetchCommands(signal: AbortSignal, windowStartMs: number): Promise<NormalizedCommand[]> {
  const commands: NormalizedCommand[] = [];
  let before: string | null = null;

  for (let page = 0; page < COMMAND_FETCH_MAX_PAGES; page += 1) {
    const params = new URLSearchParams();
    params.set('limit', String(PAGE_SIZE));
    if (before) params.set('before', before);

    const response = await fetch(`/api/commands?${params.toString()}`, {
      credentials: 'include',
      cache: 'no-store',
      signal,
    });
    if (!response.ok) {
      throw new Error(`commands_fetch_failed_${response.status}`);
    }

    const payload = (await response.json()) as CommandsApiResponse;
    const rows = payload.commands ?? [];
    if (rows.length === 0) break;

    let oldestSeen = Number.MAX_SAFE_INTEGER;
    for (const row of rows) {
      const id = String(row.command_id ?? '').trim();
      if (!id) continue;
      const queuedAtIso = row.queued_at ?? null;
      const completedAtIso = row.completed_at ?? null;
      const eventMs = parseIsoMs(completedAtIso) ?? parseIsoMs(queuedAtIso) ?? 0;
      if (eventMs > 0 && eventMs < oldestSeen) oldestSeen = eventMs;

      commands.push({
        id,
        method: row.method?.trim() || 'unknown',
        state: String(row.state ?? 'queued').toLowerCase(),
        deviceId: row.device_id?.trim() || null,
        queuedAtIso,
        completedAtIso,
        errorCode: row.error_code == null ? null : String(row.error_code),
        errorMessage: row.error_message?.trim() || null,
        actorEmail: row.actor_email?.trim() || null,
      });
    }

    before = payload.next_before ?? null;
    if (!before) break;
    if (oldestSeen < windowStartMs) break;
  }

  return commands;
}

interface AuditApiRow {
  id?: string;
  timestamp?: string | null;
  actor?: string;
  actor_role?: string;
  event_type?: string;
  action?: string;
  target?: string;
  detail?: string;
  outcome?: string;
}

interface AuditApiResponse {
  events?: AuditApiRow[];
}

function normalizeAuditEventType(value: unknown): AuditEntry['eventType'] {
  const normalized = String(value ?? '').trim().toLowerCase();
  if (normalized === 'user_action' || normalized === 'command_execution' || normalized === 'policy_change') {
    return normalized;
  }
  return 'system_event';
}

function normalizeAuditOutcome(value: unknown): AuditEntry['outcome'] {
  const normalized = String(value ?? '').trim().toLowerCase();
  if (normalized === 'success' || normalized === 'failure') {
    return normalized;
  }
  return 'pending';
}

function labelAuditRole(value: unknown): string {
  const normalized = String(value ?? '').trim().toLowerCase();
  if (!normalized) return 'System';
  if (normalized === 'admin') return 'Admin';
  if (normalized === 'viewer') return 'Viewer';
  if (normalized === 'operator') return 'Operator';
  if (normalized === 'system') return 'System';
  return normalized.charAt(0).toUpperCase() + normalized.slice(1);
}

async function fetchAuditEntries(signal: AbortSignal): Promise<AuditEntry[]> {
  const response = await fetch('/api/audit/events?page=1&per_page=120', {
    credentials: 'include',
    cache: 'no-store',
    signal,
  });
  if (!response.ok) {
    throw new Error(`audit_fetch_failed_${response.status}`);
  }

  const payload = (await response.json()) as AuditApiResponse;
  return (payload.events ?? []).map((event, index) => ({
    id: String(event.id ?? ([event.timestamp, event.action, event.target, index].filter(Boolean).join('|') || `audit-${index}`)),
    timestamp: formatAuditTimestamp(event.timestamp ?? null),
    actor: String(event.actor ?? 'system'),
    actorRole: labelAuditRole(event.actor_role),
    eventType: normalizeAuditEventType(event.event_type),
    action: String(event.action ?? 'EVENT'),
    target: String(event.target ?? ''),
    detail: String(event.detail ?? ''),
    outcome: normalizeAuditOutcome(event.outcome),
  }));
}

function buildSnapshot(
  devices: NormalizedDevice[],
  alerts: NormalizedAlert[],
  commands: NormalizedCommand[],
): DashboardSnapshot {
  const totalDevices = devices.length;
  const onlineDevices = devices.filter((d) => d.status === 'online').length;
  const offlineDevices = devices.filter((d) => d.status === 'offline').length;
  const quarantinedDevices = devices.filter((d) => d.status === 'quarantined').length;
  const degradedDevices = devices.filter((d) => d.status === 'degraded').length;

  const activeStates = new Set(['queued', 'dispatched', 'ack_received', 'executing']);
  const failedStates = new Set(['failed', 'expired', 'rejected']);
  const activeCommands = commands.filter((c) => activeStates.has(c.state)).length;
  const failingCommandsCount = commands.filter((c) => failedStates.has(c.state)).length;
  const complianceDrift = devices.filter((d) => d.compliance === 'drift' || d.compliance === 'non_compliant').length;
  const criticalAlerts = alerts.filter((a) => a.severity === 'critical').length;
  const fleetOnlineRate = totalDevices > 0
    ? Number(((onlineDevices / totalDevices) * 100).toFixed(1))
    : 0;

  const avgRiskScore = devices.length > 0
    ? Number((devices.reduce((sum, d) => sum + d.risk, 0) / devices.length).toFixed(4))
    : 0;

  const fleetStatus: FleetStatusDatum[] = [
    { name: 'Online', value: onlineDevices, color: 'hsl(142 71% 45%)' },
    { name: 'Offline', value: offlineDevices, color: 'hsl(240 5% 45%)' },
    { name: 'Degraded', value: degradedDevices, color: 'hsl(38 92% 50%)' },
    { name: 'Quarantined', value: quarantinedDevices, color: 'hsl(0 72% 51%)' },
  ];

  const now = new Date();
  const dayBuckets = new Map<string, CommandVolumeDatum>();
  for (let offset = COMMAND_WINDOW_DAYS - 1; offset >= 0; offset -= 1) {
    const day = new Date(now.getFullYear(), now.getMonth(), now.getDate() - offset, 0, 0, 0, 0);
    const key = formatLocalDateKey(day);
    dayBuckets.set(key, {
      day: formatDayLabel(day),
      completed: 0,
      failed: 0,
      expired: 0,
    });
  }

  for (const command of commands) {
    const eventIso = commandEventTime(command);
    const eventMs = parseIsoMs(eventIso);
    if (!eventMs) continue;
    const dayKey = formatLocalDateKey(new Date(eventMs));
    const bucket = dayBuckets.get(dayKey);
    if (!bucket) continue;

    if (command.state === 'completed') bucket.completed += 1;
    else if (command.state === 'expired') bucket.expired += 1;
    else if (command.state === 'failed' || command.state === 'rejected') bucket.failed += 1;
  }

  const commandVolume = Array.from(dayBuckets.values());
  const deviceNameById = new Map(devices.map((d) => [d.id, d.name]));

  const failingCommands: FailingCommandItem[] = commands
    .filter((command) => failedStates.has(command.state))
    .sort((a, b) => (parseIsoMs(commandEventTime(b)) ?? 0) - (parseIsoMs(commandEventTime(a)) ?? 0))
    .slice(0, 6)
    .map((command) => ({
      id: command.id,
      device: command.deviceId ? (deviceNameById.get(command.deviceId) ?? command.deviceId) : 'Unknown device',
      method: command.method,
      errorCode: command.errorCode,
      errorMsg: command.errorMessage ?? 'Execution failed',
      failedAt: formatLocalEventTime(commandEventTime(command)),
    }));

  const attentionDevices: AttentionDeviceItem[] = devices
    .filter((device) => device.status === 'quarantined' || device.status === 'degraded')
    .sort((a, b) => (parseIsoMs(b.lastSeenIso) ?? 0) - (parseIsoMs(a.lastSeenIso) ?? 0))
    .slice(0, 6)
    .map((device) => {
      let reason = 'Device needs attention';
      if (device.status === 'quarantined') {
        reason = 'Device quarantined by policy';
      } else if (device.compliance === 'drift' || device.compliance === 'non_compliant') {
        reason = 'Compliance drift detected';
      } else if (device.risk >= 0.6) {
        reason = `Elevated risk score (${(device.risk * 100).toFixed(1)}/100)`;
      } else {
        reason = 'Degraded device health reported';
      }

      return {
        id: device.id,
        name: device.name,
        status: device.status === 'quarantined' ? 'quarantined' : 'degraded',
        reason,
        since: `since ${formatLocalEventTime(device.lastSeenIso)}`,
      };
    });

  const commandActivity = commands.map((command) => {
    const ts = commandEventTime(command);
    const sortAt = parseIsoMs(ts) ?? 0;
    return {
      id: `activity-command-${command.id}`,
      type: 'command' as const,
      title: `${command.id} ${command.state}`,
      detail: `${command.method} on ${command.deviceId ?? 'device'}`,
      sortAt,
      time: formatLocalEventTime(ts),
    };
  });

  const alertActivity = alerts.map((alert) => {
    const sortAt = parseIsoMs(alert.timestampIso) ?? 0;
    return {
      id: `activity-alert-${alert.id}`,
      type: 'alert' as const,
      title: `${alert.severity.toUpperCase()} alert`,
      detail: alert.message,
      sortAt,
      time: formatLocalEventTime(alert.timestampIso),
    };
  });

  const deviceActivity = devices
    .filter((device) => Boolean(device.lastSeenIso))
    .map((device) => {
      const sortAt = parseIsoMs(device.lastSeenIso) ?? 0;
      return {
        id: `activity-device-${device.id}`,
        type: 'device' as const,
        title: `${device.name} heartbeat`,
        detail: `${device.status} - Agent ${device.agentVersion ?? '-'}`,
        sortAt,
        time: formatLocalEventTime(device.lastSeenIso),
      };
    });

  const activityItems: DashboardActivityItem[] = [...commandActivity, ...alertActivity, ...deviceActivity]
    .filter((item) => item.sortAt > 0)
    .sort((a, b) => b.sortAt - a.sortAt)
    .slice(0, 12)
    .map(({ id, type, title, detail, time }) => ({ id, type, title, detail, time }));

  const commandAudit: AuditEntry[] = commands.map((command) => {
    const state = command.state.toLowerCase();
    const outcome: AuditEntry['outcome'] =
      state === 'completed' ? 'success' : failedStates.has(state) ? 'failure' : 'pending';
    const action = `COMMAND_${state.toUpperCase()}`;
    return {
      id: `AUD-CMD-${command.id}`,
      timestamp: formatAuditTimestamp(commandEventTime(command)),
      actor: command.actorEmail ?? 'system',
      actorRole: command.actorEmail ? 'Operator' : 'System',
      eventType: 'command_execution',
      action,
      target: command.deviceId ?? 'fleet',
      detail: `${command.method} (${command.id})${command.errorMessage ? ` - ${command.errorMessage}` : ''}`,
      outcome,
    };
  });

  const alertAudit: AuditEntry[] = alerts.map((alert) => ({
    id: `AUD-ALT-${alert.id}`,
    timestamp: formatAuditTimestamp(alert.timestampIso),
    actor: 'system',
    actorRole: 'System',
    eventType: 'system_event',
    action: 'ALERT_RAISED',
    target: alert.deviceId ?? alert.id,
    detail: `${alert.severity.toUpperCase()} - ${alert.message}`,
    outcome: alert.severity === 'info' ? 'pending' : 'failure',
  }));

  const auditEntries: AuditEntry[] = [...commandAudit, ...alertAudit]
    .sort((a, b) => parseLocalDateTime(b.timestamp) - parseLocalDateTime(a.timestamp))
    .slice(0, 120);

  const liveFeedEvents: WsEvent[] = [...commandActivity, ...alertActivity, ...deviceActivity]
    .filter((item) => item.sortAt > 0)
    .sort((a, b) => b.sortAt - a.sortAt)
    .slice(0, 12)
    .map((item) => {
      if (item.type === 'alert') {
        return {
          id: `feed-${item.id}`,
          type: 'alert',
          severity: item.title.toLowerCase().startsWith('critical') ? 'critical' : 'warning',
          title: item.title,
          detail: item.detail,
          timestamp: item.time,
          read: false,
        } as WsEvent;
      }
      if (item.type === 'command') {
        const isFailure = item.title.includes('failed') || item.title.includes('expired') || item.title.includes('rejected');
        return {
          id: `feed-${item.id}`,
          type: 'command_status',
          severity: isFailure ? 'warning' : 'info',
          title: item.title,
          detail: item.detail,
          timestamp: item.time,
          read: false,
        } as WsEvent;
      }
      return {
        id: `feed-${item.id}`,
        type: 'device_state',
        severity: 'info',
        title: item.title,
        detail: item.detail,
        timestamp: item.time,
        read: false,
      } as WsEvent;
    });

  return {
    kpi: {
      totalDevices,
      onlineDevices,
      offlineDevices,
      quarantinedDevices,
      activeCommands,
      failingCommands: failingCommandsCount,
      criticalAlerts,
      complianceDrift,
      avgRiskScore,
      fleetOnlineRate,
    },
    fleetStatus,
    commandVolume,
    failingCommands,
    attentionDevices,
    activityItems,
    auditEntries,
    liveFeedEvents,
  };
}

export function useDashboardData(): UseDashboardDataResult {
  const [data, setData] = useState<DashboardSnapshot>(EMPTY_SNAPSHOT);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [errors, setErrors] = useState<DashboardErrors>({
    devices: null,
    alerts: null,
    commands: null,
    audit: null,
  });
  const [lastRefreshLabel, setLastRefreshLabel] = useState('');
  const pollTimerRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const abortRef = useRef<AbortController | null>(null);
  const dataSignatureRef = useRef<string>('');

  const load = useCallback(async (mode: 'initial' | 'refresh') => {
    if (mode === 'initial') setLoading(true);
    if (mode === 'refresh') setRefreshing(true);

    abortRef.current?.abort();
    const controller = new AbortController();
    abortRef.current = controller;

    const nowMs = Date.now();
    const windowStartMs = nowMs - COMMAND_WINDOW_DAYS * 24 * 60 * 60 * 1000;

    const [devicesResult, alertsResult, commandsResult, auditResult] = await Promise.allSettled([
      fetchDevices(controller.signal),
      fetchAlerts(controller.signal),
      fetchCommands(controller.signal, windowStartMs),
      fetchAuditEntries(controller.signal),
    ]);

    if (controller.signal.aborted) return;

    const nextErrors: DashboardErrors = {
      devices: devicesResult.status === 'rejected' ? 'Failed to load data' : null,
      alerts: alertsResult.status === 'rejected' ? 'Failed to load data' : null,
      commands: commandsResult.status === 'rejected' ? 'Failed to load data' : null,
      audit: auditResult.status === 'rejected' ? 'Failed to load data' : null,
    };
    setErrors(nextErrors);

    if (devicesResult.status === 'rejected') {
      console.error('[dashboard] devices fetch failed', devicesResult.reason);
    }
    if (alertsResult.status === 'rejected') {
      console.error('[dashboard] alerts fetch failed', alertsResult.reason);
    }
    if (commandsResult.status === 'rejected') {
      console.error('[dashboard] commands fetch failed', commandsResult.reason);
    }
    if (auditResult.status === 'rejected') {
      console.error('[dashboard] audit fetch failed', auditResult.reason);
    }

    const snapshot = buildSnapshot(
      devicesResult.status === 'fulfilled' ? devicesResult.value : [],
      alertsResult.status === 'fulfilled' ? alertsResult.value : [],
      commandsResult.status === 'fulfilled' ? commandsResult.value : [],
    );
    const finalSnapshot: DashboardSnapshot = {
      ...snapshot,
      auditEntries: auditResult.status === 'fulfilled' ? auditResult.value : snapshot.auditEntries,
    };
    const signature = JSON.stringify(finalSnapshot);
    if (signature !== dataSignatureRef.current) {
      dataSignatureRef.current = signature;
      setData(finalSnapshot);
    }

    setLastRefreshLabel(nowTimeString());
    setLoading(false);
    setRefreshing(false);
  }, []);

  const refresh = useCallback(async () => {
    await load('refresh');
  }, [load]);

  useEffect(() => {
    const initialTimer = setTimeout(() => {
      void load('initial');
    }, 0);

    pollTimerRef.current = setInterval(() => {
      void load('refresh');
    }, AUTO_REFRESH_INTERVAL_MS);

    return () => {
      clearTimeout(initialTimer);
      if (pollTimerRef.current) clearInterval(pollTimerRef.current);
      abortRef.current?.abort();
    };
  }, [load]);

  return useMemo(
    () => ({
      data,
      loading,
      refreshing,
      errors,
      refresh,
      lastRefreshLabel,
    }),
    [data, loading, refreshing, errors, refresh, lastRefreshLabel],
  );
}
