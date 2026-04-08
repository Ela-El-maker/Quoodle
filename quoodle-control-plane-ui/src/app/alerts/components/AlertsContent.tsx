'use client';
import React, { useState, useMemo, useEffect, useCallback } from 'react';
import { Bell, Search, RefreshCw, ChevronUp, ChevronDown, Eye, CheckCheck, AlertTriangle, Shield, Activity, Info, ChevronRight, Download } from 'lucide-react';
import StatusBadge from '@/components/ui/StatusBadge';
import AlertDetailDrawer from './AlertDetailDrawer';
import AuditTrailSection from '@/components/AuditTrailSection';
import ExportModal from '@/components/ExportModal';
import { toast } from 'sonner';

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

// Backend integration point: GET /api/alerts with severity/status filters
const mockAlerts: Alert[] = [
  { id: 'ALT-0091', severity: 'critical', type: 'attestation_failure',      deviceId: 'SRV-PROD-04', hostname: 'SRV-PROD-04', description: 'Attestation hash mismatch — device may be compromised. Kernel guard reported unexpected state.', triggeredAt: '19:14:02', status: 'active',       acknowledgedBy: null,                    correlationId: 'CORR-7741' },
  { id: 'ALT-0090', severity: 'critical', type: 'compliance_violation',     deviceId: 'SRV-PROD-04', hostname: 'SRV-PROD-04', description: 'Device quarantined due to attestation failure. All non-remediation commands blocked by policy.', triggeredAt: '19:14:05', status: 'active',       acknowledgedBy: null,                    correlationId: 'CORR-7741' },
  { id: 'ALT-0089', severity: 'warning',  type: 'policy_drift',             deviceId: 'WKSTN-011',   hostname: 'WKSTN-011',   description: 'Policy hash mismatch detected. Device reports policy-2025-11, controller expects policy-2026-04.', triggeredAt: '21:00:05', status: 'active',       acknowledgedBy: null,                    correlationId: 'CORR-7739' },
  { id: 'ALT-0088', severity: 'warning',  type: 'telemetry_anomaly',        deviceId: 'WKSTN-007',   hostname: 'WKSTN-007',   description: 'CPU utilization sustained above 90% for 12 minutes. Risk score elevated to 61/100.', triggeredAt: '20:51:33', status: 'acknowledged', acknowledgedBy: 'ops.team@quoodle.io',   correlationId: 'CORR-7737' },
  { id: 'ALT-0087', severity: 'warning',  type: 'device_offline',           deviceId: 'WKSTN-031',   hostname: 'WKSTN-031',   description: 'Device went offline unexpectedly. Last heartbeat received at 21:05:12 UTC.', triggeredAt: '21:05:33', status: 'active',       acknowledgedBy: null,                    correlationId: 'CORR-7736' },
  { id: 'ALT-0086', severity: 'warning',  type: 'command_failure',          deviceId: 'WKSTN-042',   hostname: 'WKSTN-042',   description: 'Command CMD-7741 failed with error 4004 — kernel opcode not supported. Third failure in 2 hours.', triggeredAt: '21:02:11', status: 'active',       acknowledgedBy: null,                    correlationId: 'CORR-7741' },
  { id: 'ALT-0085', severity: 'warning',  type: 'command_expired',          deviceId: 'SRV-PROD-01', hostname: 'SRV-PROD-01', description: 'Command CMD-7738 expired — TTL of 300s exceeded before agent acknowledgement.', triggeredAt: '20:58:44', status: 'acknowledged', acknowledgedBy: 'devops@quoodle.io',     correlationId: 'CORR-7738' },
  { id: 'ALT-0084', severity: 'info',     type: 'device_online',            deviceId: 'WKSTN-088',   hostname: 'WKSTN-088',   description: 'Device WKSTN-088 came online. Agent v0.0.1 authenticated. Policy hash synchronized.', triggeredAt: '21:03:44', status: 'resolved',     acknowledgedBy: 'system',                correlationId: 'CORR-7735' },
  { id: 'ALT-0083', severity: 'info',     type: 'policy_sync',              deviceId: 'WKSTN-055',   hostname: 'WKSTN-055',   description: 'Policy hash re-synchronized after drift. Device now compliant with policy-2026-04.', triggeredAt: '20:30:00', status: 'resolved',     acknowledgedBy: 'system',                correlationId: 'CORR-7730' },
  { id: 'ALT-0082', severity: 'warning',  type: 'kernel_guard_missing',     deviceId: 'WKSTN-031',   hostname: 'WKSTN-031',   description: 'Kernel Guard driver not detected on device. Agent falling back to named pipe transport.', triggeredAt: '20:00:00', status: 'acknowledged', acknowledgedBy: 'nina.osei@quoodle.io',  correlationId: 'CORR-7720' },
];

const severityTabs = [
  { key: 'all',      label: 'All Alerts' },
  { key: 'critical', label: 'Critical' },
  { key: 'warning',  label: 'Warning' },
  { key: 'info',     label: 'Info' },
];

const statusTabs = [
  { key: 'all',          label: 'All' },
  { key: 'active',       label: 'Active' },
  { key: 'acknowledged', label: 'Acknowledged' },
  { key: 'resolved',     label: 'Resolved' },
];

const alertTypeIcons: Record<string, React.ElementType> = {
  attestation_failure:  Shield,
  compliance_violation: Shield,
  policy_drift:         Shield,
  telemetry_anomaly:    Activity,
  device_offline:       Bell,
  command_failure:      AlertTriangle,
  command_expired:      AlertTriangle,
  device_online:        Info,
  policy_sync:          Info,
  kernel_guard_missing: AlertTriangle,
};

type SortKey = keyof Alert;

const AUTO_REFRESH_MS = 30000;

export default function AlertsContent() {
  const [severityFilter, setSeverityFilter] = useState('all');
  const [statusFilter, setStatusFilter] = useState('all');
  const [search, setSearch] = useState('');
  const [sortKey, setSortKey] = useState<SortKey>('triggeredAt');
  const [sortDir, setSortDir] = useState<'asc' | 'desc'>('desc');
  const [selectedAlert, setSelectedAlert] = useState<Alert | null>(null);
  const [acknowledgeIds, setAcknowledgeIds] = useState<Set<string>>(new Set());
  const [refreshing, setRefreshing] = useState(false);
  const [bannerFlash, setBannerFlash] = useState(false);
  const [lastRefresh, setLastRefresh] = useState('');
  const [showExport, setShowExport] = useState(false);

  const doRefresh = useCallback(() => {
    setRefreshing(true);
    setBannerFlash(true);
    setTimeout(() => {
      setRefreshing(false);
      const now = new Date();
      setLastRefresh(`${String(now.getHours()).padStart(2,'0')}:${String(now.getMinutes()).padStart(2,'0')}:${String(now.getSeconds()).padStart(2,'0')}`);
    }, 600);
    setTimeout(() => setBannerFlash(false), 1500);
  }, []);

  useEffect(() => {
    const now = new Date();
    setLastRefresh(`${String(now.getHours()).padStart(2,'0')}:${String(now.getMinutes()).padStart(2,'0')}:${String(now.getSeconds()).padStart(2,'0')}`);
    const timer = setInterval(() => {
      doRefresh();
      toast.info('Alert list auto-refreshed', { duration: 2000 });
    }, AUTO_REFRESH_MS);
    return () => clearInterval(timer);
  }, [doRefresh]);

  const filtered = useMemo(() => {
    let data = mockAlerts.filter((a) => {
      const matchSev = severityFilter === 'all' || a.severity === severityFilter;
      const matchStatus = statusFilter === 'all' || a.status === statusFilter;
      const matchSearch =
        !search ||
        a.id.toLowerCase().includes(search.toLowerCase()) ||
        a.hostname.toLowerCase().includes(search.toLowerCase()) ||
        a.type.toLowerCase().includes(search.toLowerCase()) ||
        a.description.toLowerCase().includes(search.toLowerCase());
      return matchSev && matchStatus && matchSearch;
    });
    data.sort((a, b) => {
      const av = a[sortKey];
      const bv = b[sortKey];
      if (typeof av === 'string' && typeof bv === 'string') return sortDir === 'asc' ? av.localeCompare(bv) : bv.localeCompare(av);
      return 0;
    });
    return data;
  }, [severityFilter, statusFilter, search, sortKey, sortDir]);

  const toggleSort = (key: SortKey) => {
    if (sortKey === key) setSortDir(sortDir === 'asc' ? 'desc' : 'asc');
    else { setSortKey(key); setSortDir('asc'); }
  };

  const SortIcon = ({ k }: { k: SortKey }) =>
    sortKey === k ? (
      sortDir === 'asc' ? <ChevronUp size={12} className="text-primary" /> : <ChevronDown size={12} className="text-primary" />
    ) : (
      <ChevronUp size={12} className="text-muted-foreground/40" />
    );

  const criticalActive = mockAlerts.filter((a) => a.severity === 'critical' && a.status === 'active');

  const handleAcknowledge = (alert: Alert) => {
    setAcknowledgeIds((prev) => new Set([...prev, alert.id]));
    toast.success(`Alert ${alert.id} acknowledged`, { description: `Acknowledged by ops.team@quoodle.io` });
  };

  const counts: Record<string, number> = {
    all: mockAlerts.length,
    critical: mockAlerts.filter((a) => a.severity === 'critical').length,
    warning: mockAlerts.filter((a) => a.severity === 'warning').length,
    info: mockAlerts.filter((a) => a.severity === 'info').length,
  };

  return (
    <div className="space-y-4 fade-in">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight flex items-center gap-2">
            Alerts
            {/* Alert count badge */}
            {criticalActive.length > 0 && (
              <span className={`inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-semibold bg-red-500/20 text-red-400 border border-red-500/30 ${bannerFlash ? 'critical-flash' : ''}`}>
                <span className="w-1.5 h-1.5 rounded-full bg-red-400 pulse-dot" />
                {criticalActive.length} Critical
              </span>
            )}
          </h1>
          <p className="text-sm text-muted-foreground mt-0.5">Operational and security anomalies</p>
        </div>
        <div className="flex items-center gap-2">
          {/* Status badges */}
          <span className="text-[11px] px-2 py-1 rounded-md bg-red-500/10 border border-red-500/20 text-red-400 font-medium tabular-nums">
            {mockAlerts.filter((a) => a.status === 'active').length} Active
          </span>
          <span className="text-[11px] px-2 py-1 rounded-md bg-amber-500/10 border border-amber-500/20 text-amber-400 font-medium tabular-nums">
            {mockAlerts.filter((a) => a.status === 'acknowledged').length} Acked
          </span>
          <button
            onClick={() => setShowExport(true)}
            className="flex items-center gap-1.5 px-3 py-1.5 text-xs text-muted-foreground border border-border rounded-md hover:bg-muted/60 transition-colors"
          >
            <Download size={13} />
            Export
          </button>
          <button
            onClick={() => { doRefresh(); toast.info('Alert list refreshed'); }}
            className="flex items-center gap-1.5 px-3 py-1.5 text-xs text-muted-foreground border border-border rounded-md hover:bg-muted/60 transition-colors"
          >
            <RefreshCw size={13} className={refreshing ? 'animate-spin' : ''} />
            {lastRefresh ? lastRefresh : 'Refresh'}
          </button>
        </div>
      </div>

      {/* Critical persistent banner with flash animation */}
      {criticalActive.length > 0 && (
        <div
          className={`relative flex items-start gap-3 px-4 py-3 border rounded-lg overflow-hidden transition-all duration-300 ${
            bannerFlash
              ? 'bg-red-500/20 border-red-500/60 critical-flash' :'bg-red-500/10 border-red-500/30'
          }`}
        >
          {bannerFlash && (
            <div className="absolute inset-0 bg-gradient-to-r from-transparent via-red-500/10 to-transparent animate-[sweep_0.8s_ease-out]" />
          )}
          <div className={`w-6 h-6 rounded-full bg-red-500/20 flex items-center justify-center flex-shrink-0 mt-0.5 ${bannerFlash ? 'pulse-dot' : ''}`}>
            <Shield size={13} className="text-red-400" />
          </div>
          <div className="flex-1 min-w-0">
            <p className="text-sm font-semibold text-red-400">
              {criticalActive.length} Critical Alert{criticalActive.length !== 1 ? 's' : ''} Require Immediate Action
            </p>
            <p className="text-xs text-muted-foreground mt-0.5">
              {criticalActive.map((a) => a.hostname).join(', ')} — attestation and compliance violations detected
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

      {/* Severity tabs + status filter row */}
      <div className="flex flex-wrap items-center gap-3">
        <div className="flex items-center gap-1 bg-muted/30 rounded-lg p-1">
          {severityTabs.map((tab) => (
            <button
              key={`sev-tab-${tab.key}`}
              onClick={() => setSeverityFilter(tab.key)}
              className={`flex items-center gap-1.5 px-3 py-1.5 rounded-md text-xs font-medium transition-all ${
                severityFilter === tab.key
                  ? 'bg-card text-foreground shadow-sm'
                  : 'text-muted-foreground hover:text-foreground'
              }`}
            >
              {tab.label}
              <span className={`text-[10px] px-1.5 py-0.5 rounded-full tabular-nums ${
                tab.key === 'critical' ? 'bg-red-500/20 text-red-400' :
                tab.key === 'warning'  ? 'bg-amber-500/20 text-amber-400' :
                tab.key === 'info'? 'bg-blue-500/20 text-blue-400' : 'bg-muted text-muted-foreground'
              }`}>
                {counts[tab.key] ?? mockAlerts.length}
              </span>
            </button>
          ))}
        </div>

        <div className="flex items-center gap-1 bg-muted/30 rounded-lg p-1">
          {statusTabs.map((tab) => (
            <button
              key={`status-tab-${tab.key}`}
              onClick={() => setStatusFilter(tab.key)}
              className={`px-3 py-1.5 rounded-md text-xs font-medium transition-all ${
                statusFilter === tab.key
                  ? 'bg-card text-foreground shadow-sm'
                  : 'text-muted-foreground hover:text-foreground'
              }`}
            >
              {tab.label}
            </button>
          ))}
        </div>

        <div className="relative flex-1 min-w-[200px] max-w-xs ml-auto">
          <Search size={13} className="absolute left-2.5 top-1/2 -translate-y-1/2 text-muted-foreground" />
          <input
            type="text"
            placeholder="Search alerts…"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="w-full pl-8 pr-3 py-1.5 text-xs bg-muted/60 border border-border rounded-md text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-1 focus:ring-primary/50"
          />
        </div>
      </div>

      {/* Table */}
      <div className="bg-card border border-border rounded-lg overflow-hidden">
        <div className="overflow-x-auto scrollbar-thin">
          <table className="w-full text-xs">
            <thead>
              <tr className="border-b border-border bg-muted/20">
                {[
                  { key: 'severity' as SortKey, label: 'Severity' },
                  { key: 'type' as SortKey, label: 'Type' },
                  { key: 'hostname' as SortKey, label: 'Device' },
                  { key: 'description' as SortKey, label: 'Description' },
                  { key: 'triggeredAt' as SortKey, label: 'Triggered' },
                  { key: 'status' as SortKey, label: 'Status' },
                  { key: 'acknowledgedBy' as SortKey, label: 'Acknowledged By' },
                ].map((col) => (
                  <th
                    key={`alert-col-${col.key}`}
                    className="px-3 py-3 text-left font-semibold text-muted-foreground tracking-wide uppercase text-[10px] cursor-pointer hover:text-foreground transition-colors whitespace-nowrap"
                    onClick={() => toggleSort(col.key)}
                  >
                    <span className="flex items-center gap-1">
                      {col.label}
                      <SortIcon k={col.key} />
                    </span>
                  </th>
                ))}
                <th className="px-3 py-3 w-20" />
              </tr>
            </thead>
            <tbody className="divide-y divide-border">
              {filtered.length === 0 ? (
                <tr>
                  <td colSpan={8} className="px-4 py-12 text-center">
                    <Bell size={32} className="mx-auto text-muted-foreground/30 mb-3" />
                    <p className="text-sm font-medium text-muted-foreground">No alerts match your filters</p>
                    <p className="text-xs text-muted-foreground/60 mt-1">All clear in the selected view</p>
                  </td>
                </tr>
              ) : (
                filtered.map((alert) => {
                  const IconComp = alertTypeIcons[alert.type] ?? Bell;
                  const isAcked = acknowledgeIds.has(alert.id) || alert.status !== 'active';
                  return (
                    <tr
                      key={`alert-row-${alert.id}`}
                      className={`group hover:bg-muted/30 transition-colors cursor-pointer ${
                        alert.severity === 'critical' && alert.status === 'active' && !acknowledgeIds.has(alert.id)
                          ? 'bg-red-500/5' : ''
                      }`}
                      onClick={() => setSelectedAlert(alert)}
                    >
                      <td className="px-3 py-3 whitespace-nowrap">
                        <StatusBadge variant={alert.severity} pulse={alert.severity === 'critical' && alert.status === 'active'} />
                      </td>
                      <td className="px-3 py-3 whitespace-nowrap">
                        <div className="flex items-center gap-1.5">
                          <IconComp size={12} className="text-muted-foreground flex-shrink-0" />
                          <span className="text-[11px] text-muted-foreground">{alert.type.replace(/_/g, ' ')}</span>
                        </div>
                      </td>
                      <td className="px-3 py-3 font-medium whitespace-nowrap">{alert.hostname}</td>
                      <td className="px-3 py-3 max-w-xs">
                        <p className="truncate text-muted-foreground">{alert.description}</p>
                      </td>
                      <td className="px-3 py-3 tabular-nums text-muted-foreground whitespace-nowrap">{alert.triggeredAt}</td>
                      <td className="px-3 py-3 whitespace-nowrap">
                        <StatusBadge variant={acknowledgeIds.has(alert.id) ? 'acknowledged' : alert.status} />
                      </td>
                      <td className="px-3 py-3 text-muted-foreground max-w-[140px] truncate">
                        {alert.acknowledgedBy ?? '—'}
                      </td>
                      <td className="px-3 py-3">
                        <div className="flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
                          <button
                            onClick={(e) => { e.stopPropagation(); setSelectedAlert(alert); }}
                            className="p-1 rounded text-muted-foreground hover:text-foreground hover:bg-muted transition-colors"
                            title="View alert detail"
                          >
                            <Eye size={13} />
                          </button>
                          {!isAcked && (
                            <button
                              onClick={(e) => { e.stopPropagation(); handleAcknowledge(alert); }}
                              className="p-1 rounded text-muted-foreground hover:text-green-400 hover:bg-green-500/10 transition-colors"
                              title="Acknowledge alert"
                            >
                              <CheckCheck size={13} />
                            </button>
                          )}
                        </div>
                      </td>
                    </tr>
                  );
                })
              )}
            </tbody>
          </table>
        </div>

        <div className="flex items-center justify-between px-4 py-3 border-t border-border">
          <p className="text-xs text-muted-foreground">
            {filtered.length} alert{filtered.length !== 1 ? 's' : ''} · {mockAlerts.filter((a) => a.status === 'active').length} active
          </p>
          <p className="text-[11px] text-muted-foreground">
            Auto-refreshes every 30s · Last: {lastRefresh}
          </p>
        </div>
      </div>

      {/* Audit trail */}
      <AuditTrailSection title="Alerts Audit Trail" maxRows={5} />

      {selectedAlert && (
        <AlertDetailDrawer
          alert={selectedAlert}
          onClose={() => setSelectedAlert(null)}
          onAcknowledge={handleAcknowledge}
        />
      )}

      {showExport && (
        <ExportModal
          title="Alerts"
          fields={[
            { key: 'id', label: 'Alert ID' },
            { key: 'severity', label: 'Severity' },
            { key: 'type', label: 'Alert Type' },
            { key: 'device_id', label: 'Device ID' },
            { key: 'hostname', label: 'Hostname' },
            { key: 'description', label: 'Description' },
            { key: 'triggered_at', label: 'Triggered At' },
            { key: 'status', label: 'Status' },
            { key: 'acknowledged_by', label: 'Acknowledged By' },
            { key: 'correlation_id', label: 'Correlation ID' },
          ]}
          onClose={() => setShowExport(false)}
        />
      )}
    </div>
  );
}