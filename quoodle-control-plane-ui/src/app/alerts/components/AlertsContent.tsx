'use client';

import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { Bell, Search, RefreshCw, CheckCheck, AlertTriangle, Shield, Activity, Info, ChevronRight } from 'lucide-react';
import StatusBadge from '@/components/ui/StatusBadge';
import AlertDetailDrawer from './AlertDetailDrawer';
import { toast } from 'sonner';
import { formatLocalTime } from '@/lib/dateTime';

type AlertSeverity = 'critical' | 'warning' | 'info';
type AlertStatus = 'active' | 'acknowledged' | 'resolved';

interface Alert {
  id: string;
  severity: AlertSeverity;
  type: string;
  deviceId: string;
  hostname: string;
  description: string;
  triggeredAt: string;
  status: AlertStatus;
  acknowledgedBy: string | null;
  correlationId: string;
}

interface AlertsResponse {
  alerts?: Array<{
    alert_id?: string;
    severity?: string;
    category?: string;
    device_id?: string;
    message?: string;
    timestamp?: string | null;
    acknowledged?: boolean;
    status?: string;
  }>;
}

const severityTabs = [
  { key: 'all', label: 'All Alerts' },
  { key: 'critical', label: 'Critical' },
  { key: 'warning', label: 'Warning' },
  { key: 'info', label: 'Info' },
];

const statusTabs = [
  { key: 'all', label: 'All' },
  { key: 'active', label: 'Active' },
  { key: 'acknowledged', label: 'Acknowledged' },
  { key: 'resolved', label: 'Resolved' },
];

const alertTypeIcons: Record<string, React.ElementType> = {
  attestation_failure: Shield,
  compliance_violation: Shield,
  policy_drift: Shield,
  telemetry_anomaly: Activity,
  device_offline: Bell,
  command_failure: AlertTriangle,
  command_expired: AlertTriangle,
  device_online: Info,
  policy_sync: Info,
  kernel_guard_missing: AlertTriangle,
};

function normalizeSeverity(value: string | null | undefined): AlertSeverity {
  const normalized = String(value ?? '').toLowerCase();
  if (normalized === 'critical') return 'critical';
  if (normalized === 'warning') return 'warning';
  return 'info';
}

function normalizeStatus(value: string | null | undefined, acknowledged: boolean): AlertStatus {
  const normalized = String(value ?? '').toLowerCase();
  if (normalized === 'active') return 'active';
  if (normalized === 'acknowledged') return 'acknowledged';
  if (normalized === 'resolved') return 'resolved';
  return acknowledged ? 'acknowledged' : 'active';
}

function parseIso(value: string | null | undefined): number {
  if (!value) return 0;
  const parsed = Date.parse(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

export default function AlertsContent() {
  const [alerts, setAlerts] = useState<Alert[]>([]);
  const [severityFilter, setSeverityFilter] = useState('all');
  const [statusFilter, setStatusFilter] = useState('all');
  const [search, setSearch] = useState('');
  const [selectedAlert, setSelectedAlert] = useState<Alert | null>(null);
  const [acknowledgeIds, setAcknowledgeIds] = useState<Set<string>>(new Set());
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [lastRefresh, setLastRefresh] = useState('');

  const loadAlerts = useCallback(async (mode: 'initial' | 'refresh' | 'silent' = 'initial') => {
    if (mode === 'initial') setLoading(true);
    if (mode === 'refresh') setRefreshing(true);
    try {
      const response = await fetch('/api/alerts?limit=200', { credentials: 'include', cache: 'no-store' });
      if (!response.ok) {
        throw new Error(`http_${response.status}`);
      }
      const payload = (await response.json()) as AlertsResponse;
      const mapped = (payload.alerts ?? [])
        .map((row): Alert & { _tsMs: number } => {
          const alertId = String(row.alert_id ?? '').trim();
          const category = String(row.category ?? 'system').trim() || 'system';
          const device = String(row.device_id ?? 'unknown').trim() || 'unknown';
          const message = String(row.message ?? 'Alert').trim() || 'Alert';
          const acknowledged = Boolean(row.acknowledged);

          return {
            id: alertId,
            severity: normalizeSeverity(row.severity),
            type: category,
            deviceId: device,
            hostname: device,
            description: message,
            triggeredAt: formatLocalTime(row.timestamp, '--:--:--'),
            status: normalizeStatus(row.status, acknowledged),
            acknowledgedBy: acknowledged ? 'operator' : null,
            correlationId: alertId,
            _tsMs: parseIso(row.timestamp),
          };
        })
        .filter((row) => row.id !== '')
        .sort((a, b) => b._tsMs - a._tsMs)
        .map((item): Alert => ({
          id: item.id,
          severity: item.severity,
          type: item.type,
          deviceId: item.deviceId,
          hostname: item.hostname,
          description: item.description,
          triggeredAt: item.triggeredAt,
          status: item.status,
          acknowledgedBy: item.acknowledgedBy,
          correlationId: item.correlationId,
        }));

      setAlerts(mapped);
      setLoadError(null);
      const now = new Date();
      setLastRefresh(`${String(now.getHours()).padStart(2, '0')}:${String(now.getMinutes()).padStart(2, '0')}:${String(now.getSeconds()).padStart(2, '0')}`);
    } catch (error) {
      console.error('alerts-load-failed', error);
      setLoadError('Failed to load alerts');
    } finally {
      if (mode === 'initial') setLoading(false);
      if (mode === 'refresh') setRefreshing(false);
    }
  }, []);

  useEffect(() => {
    void loadAlerts('initial');
  }, [loadAlerts]);

  useEffect(() => {
    const interval = setInterval(() => {
      void loadAlerts('silent');
    }, 30000);
    return () => clearInterval(interval);
  }, [loadAlerts]);

  const filtered = useMemo(() => {
    return alerts.filter((alert) => {
      const matchSeverity = severityFilter === 'all' || alert.severity === severityFilter;
      const matchStatus = statusFilter === 'all' || alert.status === statusFilter;
      const q = search.trim().toLowerCase();
      const matchSearch = q === ''
        || alert.id.toLowerCase().includes(q)
        || alert.hostname.toLowerCase().includes(q)
        || alert.type.toLowerCase().includes(q)
        || alert.description.toLowerCase().includes(q);
      return matchSeverity && matchStatus && matchSearch;
    });
  }, [alerts, severityFilter, statusFilter, search]);

  const criticalActive = useMemo(
    () => alerts.filter((alert) => alert.severity === 'critical' && alert.status === 'active'),
    [alerts],
  );

  const counts: Record<string, number> = useMemo(() => ({
    all: alerts.length,
    critical: alerts.filter((item) => item.severity === 'critical').length,
    warning: alerts.filter((item) => item.severity === 'warning').length,
    info: alerts.filter((item) => item.severity === 'info').length,
  }), [alerts]);

  const handleAcknowledge = async (alert: Alert) => {
    setAcknowledgeIds((prev) => new Set(prev).add(alert.id));
    try {
      const response = await fetch(`/api/alerts/${encodeURIComponent(alert.id)}/ack`, {
        method: 'POST',
        credentials: 'include',
      });
      if (!response.ok) {
        throw new Error(`http_${response.status}`);
      }
      setAlerts((prev) => prev.map((item) => (item.id === alert.id ? { ...item, status: 'acknowledged', acknowledgedBy: 'operator' } : item)));
      toast.success(`Alert ${alert.id} acknowledged`);
    } catch (error) {
      console.error('alert-acknowledge-failed', error);
      toast.error('Failed to acknowledge alert');
    } finally {
      setAcknowledgeIds((prev) => {
        const next = new Set(prev);
        next.delete(alert.id);
        return next;
      });
    }
  };

  return (
    <div className="space-y-4 fade-in">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight flex items-center gap-2">
            Alerts
            {criticalActive.length > 0 && (
              <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-semibold bg-red-500/20 text-red-400 border border-red-500/30">
                <span className="w-1.5 h-1.5 rounded-full bg-red-400 pulse-dot" />
                {criticalActive.length} Critical
              </span>
            )}
          </h1>
          <p className="text-sm text-muted-foreground mt-0.5">Operational and security anomalies</p>
        </div>
        <div className="flex items-center gap-2">
          <span className="text-[11px] px-2 py-1 rounded-md bg-red-500/10 border border-red-500/20 text-red-400 font-medium tabular-nums">
            {alerts.filter((item) => item.status === 'active').length} Active
          </span>
          <span className="text-[11px] px-2 py-1 rounded-md bg-amber-500/10 border border-amber-500/20 text-amber-400 font-medium tabular-nums">
            {alerts.filter((item) => item.status === 'acknowledged').length} Acked
          </span>
          <button
            onClick={() => void loadAlerts('refresh')}
            className="flex items-center gap-1.5 px-3 py-1.5 text-xs text-muted-foreground border border-border rounded-md hover:bg-muted/60 transition-colors"
          >
            <RefreshCw size={13} className={refreshing ? 'animate-spin' : ''} />
            {lastRefresh || 'Refresh'}
          </button>
        </div>
      </div>

      {criticalActive.length > 0 && (
        <div className="relative flex items-start gap-3 px-4 py-3 border rounded-lg bg-red-500/10 border-red-500/30">
          <div className="w-6 h-6 rounded-full bg-red-500/20 flex items-center justify-center flex-shrink-0 mt-0.5">
            <Shield size={13} className="text-red-400" />
          </div>
          <div className="flex-1 min-w-0">
            <p className="text-sm font-semibold text-red-400">
              {criticalActive.length} Critical Alert{criticalActive.length !== 1 ? 's' : ''} Require Immediate Action
            </p>
            <p className="text-xs text-muted-foreground mt-0.5">
              {criticalActive.map((item) => item.hostname).join(', ')}
            </p>
          </div>
          <button
            onClick={() => setSeverityFilter('critical')}
            className="flex items-center gap-1 text-xs text-red-400 hover:text-red-300 transition-colors flex-shrink-0"
          >
            View <ChevronRight size={12} />
          </button>
        </div>
      )}

      <div className="flex flex-wrap items-center gap-2">
        <div className="relative">
          <Search size={13} className="absolute left-2.5 top-1/2 -translate-y-1/2 text-muted-foreground" />
          <input
            placeholder="Search by alert, host, type..."
            value={search}
            onChange={(event) => setSearch(event.target.value)}
            className="pl-8 pr-3 py-1.5 text-xs bg-muted/60 border border-border rounded-md text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-1 focus:ring-primary/50 w-60"
          />
        </div>
        <div className="h-4 w-px bg-border" />
        <div className="flex items-center gap-1">
          {severityTabs.map((tab) => (
            <button
              key={tab.key}
              onClick={() => setSeverityFilter(tab.key)}
              className={`px-2.5 py-1 text-xs rounded-md transition-colors ${
                severityFilter === tab.key ? 'bg-primary/20 text-primary' : 'text-muted-foreground hover:text-foreground hover:bg-muted/60'
              }`}
            >
              {tab.label}
              <span className="ml-1 text-[10px] tabular-nums">({counts[tab.key] ?? 0})</span>
            </button>
          ))}
        </div>
        <div className="h-4 w-px bg-border" />
        <div className="flex items-center gap-1 bg-muted/30 rounded-md p-0.5">
          {statusTabs.map((tab) => (
            <button
              key={tab.key}
              onClick={() => setStatusFilter(tab.key)}
              className={`px-2.5 py-1 text-xs rounded transition-colors ${
                statusFilter === tab.key ? 'bg-card text-foreground shadow-sm' : 'text-muted-foreground hover:text-foreground'
              }`}
            >
              {tab.label}
            </button>
          ))}
        </div>
      </div>

      <div className="bg-card border border-border rounded-lg overflow-hidden">
        <div className="grid grid-cols-12 text-[11px] uppercase tracking-wide text-muted-foreground border-b border-border px-3 py-2">
          <div className="col-span-2">Severity</div>
          <div className="col-span-2">Type</div>
          <div className="col-span-2">Device</div>
          <div className="col-span-4">Description</div>
          <div className="col-span-1">Time</div>
          <div className="col-span-1 text-right">Action</div>
        </div>

        {loading ? (
          <div className="px-4 py-10 text-sm text-muted-foreground text-center">Loading alerts...</div>
        ) : null}
        {!loading && loadError ? (
          <div className="px-4 py-4 text-sm text-red-300 border-t border-red-500/20">{loadError}</div>
        ) : null}
        {!loading && !loadError && filtered.length === 0 ? (
          <div className="px-4 py-10 text-sm text-muted-foreground text-center">No alerts match current filters</div>
        ) : null}

        {!loading && !loadError && filtered.map((alert) => {
          const TypeIcon = alertTypeIcons[alert.type] ?? Bell;
          const acknowledging = acknowledgeIds.has(alert.id);
          return (
            <div
              key={alert.id}
              className="grid grid-cols-12 items-center px-3 py-2.5 border-t border-border/70 hover:bg-muted/20 cursor-pointer transition-colors"
              onClick={() => setSelectedAlert(alert)}
            >
              <div className="col-span-2">
                <StatusBadge variant={alert.severity} />
              </div>
              <div className="col-span-2 flex items-center gap-1.5 text-xs">
                <TypeIcon size={12} className="text-muted-foreground" />
                <span className="truncate">{alert.type.replace(/_/g, ' ')}</span>
              </div>
              <div className="col-span-2 text-xs font-mono truncate">{alert.hostname}</div>
              <div className="col-span-4 text-xs text-muted-foreground truncate">{alert.description}</div>
              <div className="col-span-1 text-xs">{alert.triggeredAt}</div>
              <div className="col-span-1 flex justify-end">
                {alert.status === 'active' ? (
                  <button
                    onClick={(event) => {
                      event.stopPropagation();
                      void handleAcknowledge(alert);
                    }}
                    disabled={acknowledging}
                    className="inline-flex items-center gap-1 text-[11px] px-2 py-1 rounded-md border border-emerald-500/30 text-emerald-300 hover:bg-emerald-500/10 disabled:opacity-60"
                  >
                    <CheckCheck size={11} />
                    {acknowledging ? 'Ack...' : 'Ack'}
                  </button>
                ) : (
                  <span className="text-[11px] text-muted-foreground">Acked</span>
                )}
              </div>
            </div>
          );
        })}
      </div>

      {!loading && !loadError ? (
        <p className="text-xs text-muted-foreground">
          {filtered.length} alert{filtered.length === 1 ? '' : 's'} shown
        </p>
      ) : null}

      {selectedAlert && (
        <AlertDetailDrawer
          alert={selectedAlert}
          onClose={() => setSelectedAlert(null)}
          onAcknowledge={(alert) => { void handleAcknowledge(alert); }}
        />
      )}
    </div>
  );
}
