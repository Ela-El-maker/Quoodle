'use client';

import React, { useCallback, useEffect, useMemo, useState } from 'react';
import {
  Activity,
  AlertTriangle,
  CheckCircle2,
  Clock,
  Database,
  HeartPulse,
  RefreshCw,
  Server,
  Shield,
  Wifi,
  XCircle,
  Zap,
} from 'lucide-react';
import { toast } from 'sonner';
import AuditTrailSection, { type AuditEntry } from '@/components/AuditTrailSection';
import { formatLocalDateTime } from '@/lib/dateTime';

type HealthStatus = 'healthy' | 'degraded' | 'offline';

interface HealthOverview {
  generated_at: string;
  overall_status: HealthStatus;
  component_counts: {
    healthy: number;
    degraded: number;
    offline: number;
  };
  infra: {
    pending_jobs: number;
    failed_jobs: number;
    disk_used_percent: number | null;
    memory_usage_mb: number;
    memory_peak_mb: number;
    queue_driver: string;
    cache_store: string;
  };
  pipeline: {
    stuck_commands: number;
    replay_rejections_1h: number;
    critical_alerts_open: number;
    telemetry_events_1h: number;
    compliance_drift_devices: number;
  };
  webhooks: {
    sent: number;
    retrying: number;
    dead_letter: number;
    avg_latency_ms: number;
  };
}

interface HealthComponent {
  id: string;
  name: string;
  category: string;
  status: HealthStatus;
  latency_ms: number | null;
  checked_at: string;
  meta: Record<string, unknown>;
}

interface HealthComponentResponse {
  generated_at: string;
  components: HealthComponent[];
}

interface HealthTimeseriesPoint {
  timestamp: string;
  commands_completed: number;
  commands_failed: number;
  telemetry_ingest: number;
  webhook_sent: number;
  webhook_retrying: number;
  webhook_dead_letter: number;
  critical_alerts: number;
}

interface HealthTimeseriesResponse {
  generated_at: string;
  points: HealthTimeseriesPoint[];
}

interface HealthEvent {
  type: string;
  timestamp: string | null;
  severity: 'critical' | 'warning' | 'info';
  title: string;
  detail: string;
  meta?: Record<string, unknown>;
}

interface HealthEventsResponse {
  generated_at: string;
  events: HealthEvent[];
}

interface AuditEventResponseRow {
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

interface AuditEventsResponse {
  events?: AuditEventResponseRow[];
}

const statusIcon: Record<HealthStatus, React.ReactNode> = {
  healthy: <CheckCircle2 size={14} className="text-green-400" />,
  degraded: <AlertTriangle size={14} className="text-amber-400" />,
  offline: <XCircle size={14} className="text-red-400" />,
};

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

function labelRole(value: string | null | undefined): string {
  const normalized = String(value ?? '').trim().toLowerCase();
  if (!normalized) return 'System';
  if (normalized === 'admin') return 'Admin';
  if (normalized === 'viewer') return 'Viewer';
  if (normalized === 'operator') return 'Operator';
  if (normalized === 'system') return 'System';
  return normalized.charAt(0).toUpperCase() + normalized.slice(1);
}

const componentIconMap: Record<string, React.ElementType> = {
  db: Database,
  cache: Database,
  gateway: Wifi,
  queue: Server,
  scheduler: Clock,
  workers: Activity,
  webhooks: Zap,
  pipeline: Shield,
  fleet: HeartPulse,
};

function statusClass(status: HealthStatus): string {
  if (status === 'healthy') return 'text-green-400 bg-green-500/10 border-green-500/20';
  if (status === 'degraded') return 'text-amber-400 bg-amber-500/10 border-amber-500/20';
  return 'text-red-400 bg-red-500/10 border-red-500/20';
}

function safeLocal(value: string | null | undefined): string {
  if (!value) return '-';
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) return value;
  return parsed.toLocaleString();
}

async function requestJson<T>(url: string): Promise<T> {
  const res = await fetch(url, { cache: 'no-store' });
  const payload = (await res.json().catch(() => ({}))) as Record<string, unknown>;
  if (!res.ok) {
    const message = typeof payload.message === 'string' ? payload.message : 'request_failed';
    throw new Error(message);
  }
  return payload as unknown as T;
}

export default function SystemHealthContent() {
  const [overview, setOverview] = useState<HealthOverview | null>(null);
  const [components, setComponents] = useState<HealthComponent[]>([]);
  const [timeseries, setTimeseries] = useState<HealthTimeseriesPoint[]>([]);
  const [events, setEvents] = useState<HealthEvent[]>([]);
  const [auditEntries, setAuditEntries] = useState<AuditEntry[]>([]);
  const [auditLoading, setAuditLoading] = useState(true);
  const [auditError, setAuditError] = useState<string | null>(null);
  const [lastGeneratedAt, setLastGeneratedAt] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);

  const loadAll = useCallback(async (showLoader: boolean) => {
    if (showLoader) setLoading(true);
    if (showLoader) setAuditLoading(true);
    setRefreshing(true);
    try {
      const [overviewPayload, componentsPayload, timeseriesPayload, eventsPayload] = await Promise.all([
        requestJson<HealthOverview>('/api/system-health/overview'),
        requestJson<HealthComponentResponse>('/api/system-health/components'),
        requestJson<HealthTimeseriesResponse>('/api/system-health/timeseries?window_minutes=360&bucket_minutes=5'),
        requestJson<HealthEventsResponse>('/api/system-health/events?limit=60&window_minutes=180'),
      ]);

      setOverview(overviewPayload);
      setComponents(componentsPayload.components ?? []);
      setTimeseries(timeseriesPayload.points ?? []);
      setEvents(eventsPayload.events ?? []);

      const candidates = [
        overviewPayload.generated_at,
        componentsPayload.generated_at,
        timeseriesPayload.generated_at,
        eventsPayload.generated_at,
      ].filter(Boolean);
      setLastGeneratedAt(candidates.sort().at(-1) ?? null);

      try {
        const auditPayload = await requestJson<AuditEventsResponse>('/api/audit/events?page=1&per_page=120');
        const mappedAuditEntries: AuditEntry[] = (auditPayload.events ?? []).map((event, index) => ({
          id: String(event.id ?? ([event.timestamp, event.action, event.target, index].filter(Boolean).join('|') || `audit-${index}`)),
          timestamp: formatLocalDateTime(event.timestamp ?? null, '-'),
          actor: String(event.actor ?? 'system'),
          actorRole: labelRole(event.actor_role),
          eventType: normalizeAuditEventType(event.event_type),
          action: String(event.action ?? 'EVENT'),
          target: String(event.target ?? ''),
          detail: String(event.detail ?? ''),
          outcome: normalizeAuditOutcome(event.outcome),
        }));
        setAuditEntries(mappedAuditEntries);
        setAuditError(null);
      } catch (auditLoadError) {
        console.error('system-health-audit-load-failed', auditLoadError);
        setAuditEntries([]);
        setAuditError('Failed to load data');
      } finally {
        setAuditLoading(false);
      }
    } catch (error) {
      const message = error instanceof Error ? error.message : 'failed_to_load_system_health';
      toast.error(message);
      if (showLoader) {
        setAuditEntries([]);
        setAuditError('Failed to load data');
        setAuditLoading(false);
      }
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, []);

  useEffect(() => {
    let timer: ReturnType<typeof setInterval> | null = null;

    const startPolling = (): void => {
      if (timer) clearInterval(timer);
      const interval = document.hidden ? 30000 : 5000;
      timer = setInterval(() => {
        void loadAll(false);
      }, interval);
    };

    void loadAll(true);
    startPolling();

    const handleVisibility = (): void => {
      startPolling();
    };

    document.addEventListener('visibilitychange', handleVisibility);
    return () => {
      document.removeEventListener('visibilitychange', handleVisibility);
      if (timer) clearInterval(timer);
    };
  }, [loadAll]);

  const groupedComponents = useMemo(() => {
    return components.reduce<Record<string, HealthComponent[]>>((acc, current) => {
      const key = current.category || 'other';
      if (!acc[key]) acc[key] = [];
      acc[key].push(current);
      return acc;
    }, {});
  }, [components]);

  const latestTs = timeseries.at(-1);
  const latestPointSummary = latestTs
    ? {
        commands: latestTs.commands_completed + latestTs.commands_failed,
        telemetry: latestTs.telemetry_ingest,
        webhooks: latestTs.webhook_sent + latestTs.webhook_retrying + latestTs.webhook_dead_letter,
        critical: latestTs.critical_alerts,
      }
    : { commands: 0, telemetry: 0, webhooks: 0, critical: 0 };

  const stale = useMemo(() => {
    if (!lastGeneratedAt) return true;
    const parsed = new Date(lastGeneratedAt);
    if (Number.isNaN(parsed.getTime())) return true;
    return Date.now() - parsed.getTime() > 90000;
  }, [lastGeneratedAt]);

  const summary = overview?.component_counts ?? { healthy: 0, degraded: 0, offline: 0 };
  const overallStatus: HealthStatus = overview?.overall_status ?? 'offline';
  const overallTitle =
    overallStatus === 'healthy'
      ? 'System Operational'
      : overallStatus === 'degraded'
      ? 'System Degraded — Some Components Impacted'
      : 'System Offline / Critical Failure';

  return (
    <div className="space-y-6 fade-in">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">System Health</h1>
          <p className="text-sm text-muted-foreground mt-0.5">
            Live operational visibility for infrastructure, pipeline, runtime, and integrations
          </p>
        </div>
        <button
          onClick={() => void loadAll(false)}
          className="flex items-center gap-1.5 px-3 py-1.5 text-xs text-muted-foreground border border-border rounded-md hover:bg-muted/60 transition-colors"
        >
          <RefreshCw size={13} className={refreshing ? 'animate-spin' : ''} />
          Refresh
        </button>
      </div>

      {stale && (
        <div className="flex items-center gap-2 px-4 py-2 border border-amber-500/30 bg-amber-500/10 rounded-lg text-amber-300 text-xs">
          <AlertTriangle size={14} className="text-amber-400" />
          Data appears stale — latest probe {safeLocal(lastGeneratedAt)}
        </div>
      )}

      <div className={`flex items-center gap-4 px-4 py-3 border rounded-lg ${statusClass(overallStatus)}`}>
        <HeartPulse size={20} />
        <div className="flex-1">
          <p className="text-sm font-semibold">{overallTitle}</p>
          <p className="text-xs text-muted-foreground mt-0.5">
            {summary.healthy} healthy · {summary.degraded} degraded · {summary.offline} offline
          </p>
        </div>
        <div className="flex items-center gap-1.5 text-[11px] text-muted-foreground">
          <Clock size={11} />
          Last checked {safeLocal(lastGeneratedAt)}
        </div>
      </div>

      <div className="grid grid-cols-2 sm:grid-cols-3 gap-4">
        <HealthCountCard label="Healthy" value={summary.healthy} className="text-green-400 border-green-500/20 bg-green-500/5" />
        <HealthCountCard label="Degraded" value={summary.degraded} className="text-amber-400 border-amber-500/20 bg-amber-500/5" />
        <HealthCountCard label="Offline" value={summary.offline} className="text-red-400 border-red-500/20 bg-red-500/5" />
      </div>

      <div className="grid grid-cols-2 md:grid-cols-4 xl:grid-cols-8 gap-3">
        <MetricCard label="Queue Pending" value={String(overview?.infra.pending_jobs ?? 0)} />
        <MetricCard label="Queue Failed" value={String(overview?.infra.failed_jobs ?? 0)} />
        <MetricCard label="Disk Used" value={`${overview?.infra.disk_used_percent ?? 0}%`} />
        <MetricCard label="Memory MB" value={`${overview?.infra.memory_usage_mb ?? 0}`} />
        <MetricCard label="Stuck Commands" value={String(overview?.pipeline.stuck_commands ?? 0)} />
        <MetricCard label="Replay Rejections" value={String(overview?.pipeline.replay_rejections_1h ?? 0)} />
        <MetricCard label="Webhook DLQ" value={String(overview?.webhooks.dead_letter ?? 0)} />
        <MetricCard label="Webhook Latency" value={`${Math.round(overview?.webhooks.avg_latency_ms ?? 0)}ms`} />
      </div>

      <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
        <MetricCard label="Latest Bucket Commands" value={String(latestPointSummary.commands)} />
        <MetricCard label="Latest Bucket Telemetry" value={String(latestPointSummary.telemetry)} />
        <MetricCard label="Latest Bucket Webhooks" value={String(latestPointSummary.webhooks)} />
        <MetricCard label="Latest Bucket Critical Alerts" value={String(latestPointSummary.critical)} />
      </div>

      {Object.entries(groupedComponents).map(([category, items]) => (
        <div key={category}>
          <h3 className="text-xs font-semibold text-muted-foreground uppercase tracking-widest mb-2">
            {category}
          </h3>
          <div className="space-y-2">
            {items.map((component) => {
              const Icon = componentIconMap[component.id] ?? Server;
              const latency = component.latency_ms;
              return (
                <div
                  key={component.id}
                  className="bg-card border border-border rounded-lg px-4 py-3 flex items-center gap-4 hover:bg-muted/10 transition-colors"
                >
                  <div className="w-8 h-8 rounded-lg bg-muted flex items-center justify-center flex-shrink-0">
                    <Icon size={14} className="text-muted-foreground" />
                  </div>
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-medium">{component.name}</p>
                    <p className="text-[11px] text-muted-foreground truncate">
                      checked {safeLocal(component.checked_at)}
                    </p>
                  </div>
                  <div className="flex items-center gap-5">
                    <div className="text-right hidden sm:block">
                      <p className={`text-xs font-semibold tabular-nums ${latency === null ? 'text-muted-foreground' : latency < 50 ? 'text-green-400' : latency < 200 ? 'text-amber-400' : 'text-red-400'}`}>
                        {latency ?? '—'}{latency !== null ? 'ms' : ''}
                      </p>
                      <p className="text-[10px] text-muted-foreground">latency</p>
                    </div>
                    <div className="flex items-center gap-2">
                      {statusIcon[component.status]}
                      <span className={`text-[10px] font-semibold px-2 py-0.5 rounded-full border ${statusClass(component.status)}`}>
                        {component.status.toUpperCase()}
                      </span>
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      ))}

      <div className="bg-card border border-border rounded-lg overflow-hidden">
        <div className="px-4 py-3 border-b border-border flex items-center justify-between">
          <h3 className="text-sm font-semibold">Recent Health Events</h3>
          <span className="text-xs text-muted-foreground">{events.length} events</span>
        </div>
        <div className="divide-y divide-border">
          {events.slice(0, 20).map((event, index) => (
            <div key={`${event.type}-${event.timestamp}-${index}`} className="px-4 py-3">
              <div className="flex items-center justify-between gap-3">
                <div className="min-w-0">
                  <p className="text-xs font-medium">{event.title}</p>
                  <p className="text-[11px] text-muted-foreground mt-0.5 truncate">{event.detail}</p>
                </div>
                <div className="text-right flex-shrink-0">
                  <p
                    className={`text-[10px] font-semibold uppercase ${
                      event.severity === 'critical'
                        ? 'text-red-400'
                        : event.severity === 'warning'
                        ? 'text-amber-400'
                        : 'text-blue-400'
                    }`}
                  >
                    {event.severity}
                  </p>
                  <p className="text-[10px] text-muted-foreground">{safeLocal(event.timestamp)}</p>
                </div>
              </div>
            </div>
          ))}
          {!loading && events.length === 0 && (
            <div className="px-4 py-8 text-xs text-muted-foreground text-center">No recent events.</div>
          )}
          {loading && (
            <div className="px-4 py-8 text-xs text-muted-foreground text-center">Loading system health data…</div>
          )}
        </div>
      </div>

      <AuditTrailSection
        title="System Health Audit Trail"
        maxRows={4}
        entries={auditEntries}
        loading={auditLoading}
        error={auditError}
      />
    </div>
  );
}

function HealthCountCard({
  label,
  value,
  className,
}: {
  label: string;
  value: number;
  className: string;
}) {
  return (
    <div className={`border rounded-lg p-4 text-center ${className}`}>
      <p className="text-3xl font-bold tabular-nums">{value}</p>
      <p className="text-xs mt-1 uppercase tracking-wide font-medium">{label}</p>
    </div>
  );
}

function MetricCard({ label, value }: { label: string; value: string }) {
  return (
    <div className="bg-card border border-border rounded-lg p-3">
      <p className="text-lg font-bold tabular-nums">{value}</p>
      <p className="text-[10px] text-muted-foreground mt-0.5 leading-tight">{label}</p>
    </div>
  );
}

