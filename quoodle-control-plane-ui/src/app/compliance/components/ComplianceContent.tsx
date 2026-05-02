'use client';

import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { ShieldCheck, AlertTriangle, CheckCircle2, XCircle, RefreshCw, Download } from 'lucide-react';
import { toast } from 'sonner';
import StatusBadge from '@/components/ui/StatusBadge';
import AuditTrailSection, { type AuditEntry, type AuditEventType } from '@/components/AuditTrailSection';
import ExportModal from '@/components/ExportModal';
import { formatLocalDateTime, formatLocalTime } from '@/lib/dateTime';

type ComplianceStatus = 'compliant' | 'non_compliant' | 'drift' | 'pending';
type ComplianceSeverity = 'critical' | 'warning' | 'info';
type ExportFormat = 'csv' | 'pdf';

interface ComplianceCheckRow {
  id: string;
  category: string;
  control: string;
  description: string;
  status: ComplianceStatus;
  affectedDevices: number;
  lastChecked: string;
  severity: ComplianceSeverity;
}

interface ComplianceSummary {
  compliant: number;
  nonCompliant: number;
  drift: number;
  pending: number;
  total: number;
  score: number;
}

interface ComplianceOverviewApiCheck {
  id?: string;
  category?: string;
  control?: string;
  description?: string;
  status?: string;
  affected_devices?: number;
  last_checked?: string | null;
  severity?: string;
}

interface ComplianceOverviewResponse {
  last_scan_at?: string | null;
  summary?: {
    compliant?: number;
    non_compliant?: number;
    drift?: number;
    pending?: number;
    total?: number;
    score?: number;
  };
  checks?: ComplianceOverviewApiCheck[];
}

interface ComplianceAuditApiEvent {
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

interface ComplianceAuditResponse {
  events?: ComplianceAuditApiEvent[];
}

const baseCategories = ['All', 'Attestation', 'Policy Sync', 'Kernel Guard', 'Agent Version', 'Encryption', 'Command Auth', 'Heartbeat', 'Quarantine'];

const statusIcon: Record<ComplianceStatus, React.ReactNode> = {
  compliant: <CheckCircle2 size={14} className="text-green-400" />,
  non_compliant: <XCircle size={14} className="text-red-400" />,
  drift: <AlertTriangle size={14} className="text-amber-400" />,
  pending: <RefreshCw size={14} className="text-muted-foreground" />,
};

const severityBg: Record<ComplianceSeverity, string> = {
  critical: 'border-l-red-500',
  warning: 'border-l-amber-500',
  info: 'border-l-zinc-600',
};

function normalizeComplianceStatus(value: unknown): ComplianceStatus {
  const normalized = String(value ?? '').trim().toLowerCase();
  if (normalized === 'compliant') return 'compliant';
  if (normalized === 'drift') return 'drift';
  if (normalized === 'non_compliant') return 'non_compliant';
  return 'pending';
}

function normalizeComplianceSeverity(value: unknown): ComplianceSeverity {
  const normalized = String(value ?? '').trim().toLowerCase();
  if (normalized === 'critical') return 'critical';
  if (normalized === 'warning') return 'warning';
  return 'info';
}

function normalizeAuditEventType(value: unknown): AuditEventType {
  const normalized = String(value ?? '').trim().toLowerCase();
  if (normalized === 'user_action' || normalized === 'command_execution' || normalized === 'policy_change') {
    return normalized;
  }
  return 'system_event';
}

function normalizeOutcome(value: unknown): AuditEntry['outcome'] {
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

function parseFilename(disposition: string | null): string | null {
  if (!disposition) return null;
  const utf8Match = disposition.match(/filename\*=UTF-8''([^;]+)/i);
  if (utf8Match && utf8Match[1]) {
    return decodeURIComponent(utf8Match[1]);
  }
  const basicMatch = disposition.match(/filename="?([^";]+)"?/i);
  if (basicMatch && basicMatch[1]) {
    return basicMatch[1];
  }
  return null;
}

function formatUtcClock(value: string | null | undefined): string {
  if (!value) return '--:--:--';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return '--:--:--';
  const hh = String(date.getUTCHours()).padStart(2, '0');
  const mm = String(date.getUTCMinutes()).padStart(2, '0');
  const ss = String(date.getUTCSeconds()).padStart(2, '0');
  return `${hh}:${mm}:${ss}`;
}

const EMPTY_SUMMARY: ComplianceSummary = {
  compliant: 0,
  nonCompliant: 0,
  drift: 0,
  pending: 0,
  total: 0,
  score: 0,
};

export default function ComplianceContent() {
  const [categoryFilter, setCategoryFilter] = useState('All');
  const [statusFilter, setStatusFilter] = useState<string>('all');
  const [showExport, setShowExport] = useState(false);
  const [checks, setChecks] = useState<ComplianceCheckRow[]>([]);
  const [summary, setSummary] = useState<ComplianceSummary>(EMPTY_SUMMARY);
  const [lastScanAt, setLastScanAt] = useState<string | null>(null);
  const [auditEntries, setAuditEntries] = useState<AuditEntry[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [auditError, setAuditError] = useState<string | null>(null);
  const requestAbortRef = useRef<AbortController | null>(null);

  const loadCompliance = useCallback(async (mode: 'initial' | 'refresh' = 'initial') => {
    if (mode === 'initial') {
      setLoading(true);
    } else {
      setRefreshing(true);
    }

    requestAbortRef.current?.abort();
    const controller = new AbortController();
    requestAbortRef.current = controller;

    const [overviewRes, auditRes] = await Promise.allSettled([
      fetch('/api/compliance/overview', { credentials: 'include', cache: 'no-store', signal: controller.signal }),
      fetch('/api/compliance/audit?per_page=120&page=1', { credentials: 'include', cache: 'no-store', signal: controller.signal }),
    ]);

    if (controller.signal.aborted) return;

    if (overviewRes.status === 'fulfilled' && overviewRes.value.ok) {
      const payload = (await overviewRes.value.json()) as ComplianceOverviewResponse;
      const nextChecks = (payload.checks ?? []).map((check): ComplianceCheckRow => ({
        id: String(check.id ?? 'unknown'),
        category: String(check.category ?? 'Unknown'),
        control: String(check.control ?? 'UNKNOWN'),
        description: String(check.description ?? 'No description'),
        status: normalizeComplianceStatus(check.status),
        affectedDevices: Number(check.affected_devices ?? 0),
        lastChecked: formatLocalTime(check.last_checked ?? null, '--:--:--'),
        severity: normalizeComplianceSeverity(check.severity),
      }));

      const providedSummary = payload.summary;
      const compliant = Number(providedSummary?.compliant ?? nextChecks.filter((check) => check.status === 'compliant').length);
      const nonCompliant = Number(providedSummary?.non_compliant ?? nextChecks.filter((check) => check.status === 'non_compliant').length);
      const drift = Number(providedSummary?.drift ?? nextChecks.filter((check) => check.status === 'drift').length);
      const pending = Number(providedSummary?.pending ?? nextChecks.filter((check) => check.status === 'pending').length);
      const total = Number(providedSummary?.total ?? nextChecks.length);
      const score = Number(providedSummary?.score ?? (total > 0 ? Math.round((compliant / total) * 100) : 0));

      setChecks(nextChecks);
      setSummary({ compliant, nonCompliant, drift, pending, total, score });
      setLastScanAt(payload.last_scan_at ?? null);
      setError(null);
    } else {
      const status = overviewRes.status === 'fulfilled' ? overviewRes.value.status : 0;
      console.error('compliance-overview-load-failed', overviewRes.status === 'rejected' ? overviewRes.reason : status);
      setError('Failed to load data');
      if (mode === 'initial') {
        setChecks([]);
        setSummary(EMPTY_SUMMARY);
        setLastScanAt(null);
      }
    }

    if (auditRes.status === 'fulfilled' && auditRes.value.ok) {
      const payload = (await auditRes.value.json()) as ComplianceAuditResponse;
      const mappedEntries: AuditEntry[] = (payload.events ?? []).map((event, index) => ({
        id: String(event.id ?? ([event.timestamp, event.action, event.target, index].filter(Boolean).join('|') || `cmp-audit-${index}`)),
        timestamp: formatLocalDateTime(event.timestamp ?? null, '-'),
        actor: String(event.actor ?? 'system'),
        actorRole: labelRole(event.actor_role),
        eventType: normalizeAuditEventType(event.event_type),
        action: String(event.action ?? 'EVENT'),
        target: String(event.target ?? 'fleet'),
        detail: String(event.detail ?? ''),
        outcome: normalizeOutcome(event.outcome),
      }));
      setAuditEntries(mappedEntries);
      setAuditError(null);
    } else {
      const status = auditRes.status === 'fulfilled' ? auditRes.value.status : 0;
      console.error('compliance-audit-load-failed', auditRes.status === 'rejected' ? auditRes.reason : status);
      setAuditError('Failed to load data');
      if (mode === 'initial') {
        setAuditEntries([]);
      }
    }

    if (mode === 'initial') {
      setLoading(false);
    } else {
      setRefreshing(false);
    }
  }, []);

  useEffect(() => {
    const timer = setTimeout(() => {
      void loadCompliance('initial');
    }, 0);
    return () => clearTimeout(timer);
  }, [loadCompliance]);

  useEffect(() => {
    let timer: ReturnType<typeof setInterval> | null = null;
    const startPolling = () => {
      if (timer) clearInterval(timer);
      const pollMs = document.visibilityState === 'visible' ? 30000 : 60000;
      timer = setInterval(() => {
        void loadCompliance('refresh');
      }, pollMs);
    };

    startPolling();
    const onVisibilityChange = () => startPolling();
    document.addEventListener('visibilitychange', onVisibilityChange);

    return () => {
      if (timer) clearInterval(timer);
      document.removeEventListener('visibilitychange', onVisibilityChange);
      requestAbortRef.current?.abort();
    };
  }, [loadCompliance]);

  const filtered = useMemo(() => checks.filter((check) => {
    const matchCategory = categoryFilter === 'All' || check.category === categoryFilter;
    const matchStatus = statusFilter === 'all' || check.status === statusFilter;
    return matchCategory && matchStatus;
  }), [checks, categoryFilter, statusFilter]);

  const categories = useMemo(() => {
    const merged = new Set<string>(baseCategories);
    checks.forEach((check) => merged.add(check.category));
    return Array.from(merged);
  }, [checks]);

  const runExport = useCallback(async (
    format: ExportFormat,
    dateRange: { from: string; to: string },
    selectedFields: string[],
  ) => {
    const params = new URLSearchParams();
    params.set('format', format);
    if (dateRange.from) params.set('from', dateRange.from);
    if (dateRange.to) params.set('to', dateRange.to);
    if (selectedFields.length > 0) params.set('fields', selectedFields.join(','));

    const response = await fetch(`/api/compliance/export?${params.toString()}`, {
      credentials: 'include',
      cache: 'no-store',
    });

    if (!response.ok) {
      throw new Error(`http_${response.status}`);
    }

    const blob = await response.blob();
    const filename =
      parseFilename(response.headers.get('content-disposition'))
      ?? `compliance-export-${Date.now()}.${format === 'pdf' ? 'pdf' : 'csv'}`;
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = filename;
    link.click();
    URL.revokeObjectURL(url);
  }, []);

  const score = summary.score;

  return (
    <div className="space-y-6 fade-in">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">Compliance</h1>
          <p className="text-sm text-muted-foreground mt-0.5">Policy controls and regulatory posture across the fleet</p>
          {error && <p className="text-xs text-red-400 mt-1.5">{error}</p>}
        </div>
        <div className="flex items-center gap-2">
          <button
            onClick={() => setShowExport(true)}
            className="flex items-center gap-1.5 px-3 py-1.5 text-xs text-muted-foreground border border-border rounded-md hover:bg-muted/60 transition-colors"
          >
            <Download size={13} />
            Export
          </button>
          <div className="flex items-center gap-2 text-xs text-muted-foreground bg-muted/40 border border-border rounded-md px-3 py-1.5">
            <span className={`w-1.5 h-1.5 rounded-full ${refreshing ? 'bg-amber-400' : 'bg-green-400'} pulse-dot`} />
            Last scan {formatUtcClock(lastScanAt)} UTC
          </div>
        </div>
      </div>

      {/* Score cards */}
      <div className="grid grid-cols-2 sm:grid-cols-4 gap-4">
        <div className="bg-card border border-border rounded-lg p-4 text-center">
          <p className={`text-3xl font-bold tabular-nums ${score >= 80 ? 'text-green-400' : score >= 60 ? 'text-amber-400' : 'text-red-400'}`}>{score}%</p>
          <p className="text-xs text-muted-foreground mt-1 uppercase tracking-wide font-medium">Compliance Score</p>
        </div>
        <div
          className="bg-green-500/5 border border-green-500/20 rounded-lg p-4 text-center cursor-pointer hover:border-green-500/40 transition-colors"
          onClick={() => setStatusFilter(statusFilter === 'compliant' ? 'all' : 'compliant')}
        >
          <p className="text-3xl font-bold tabular-nums text-green-400">{summary.compliant}</p>
          <p className="text-xs text-green-400/70 mt-1 uppercase tracking-wide font-medium">Compliant</p>
        </div>
        <div
          className="bg-amber-500/5 border border-amber-500/20 rounded-lg p-4 text-center cursor-pointer hover:border-amber-500/40 transition-colors"
          onClick={() => setStatusFilter(statusFilter === 'drift' ? 'all' : 'drift')}
        >
          <p className="text-3xl font-bold tabular-nums text-amber-400">{summary.drift}</p>
          <p className="text-xs text-amber-400/70 mt-1 uppercase tracking-wide font-medium">Drift</p>
        </div>
        <div
          className="bg-red-500/5 border border-red-500/20 rounded-lg p-4 text-center cursor-pointer hover:border-red-500/40 transition-colors"
          onClick={() => setStatusFilter(statusFilter === 'non_compliant' ? 'all' : 'non_compliant')}
        >
          <p className="text-3xl font-bold tabular-nums text-red-400">{summary.nonCompliant}</p>
          <p className="text-xs text-red-400/70 mt-1 uppercase tracking-wide font-medium">Non-Compliant</p>
        </div>
      </div>

      {/* Category filter */}
      <div className="flex flex-wrap gap-1.5">
        {categories.map((category) => (
          <button
            key={category}
            onClick={() => setCategoryFilter(category)}
            className={`px-3 py-1 rounded-full text-xs font-medium transition-all ${
              categoryFilter === category
                ? 'bg-primary/20 text-primary border border-primary/30'
                : 'bg-muted/40 text-muted-foreground border border-border hover:text-foreground'
            }`}
          >
            {category}
          </button>
        ))}
      </div>

      {/* Controls list */}
      <div className="space-y-2">
        {loading && checks.length === 0 && (
          <div className="bg-card border border-border rounded-lg px-4 py-12 text-center">
            <RefreshCw size={20} className="mx-auto text-muted-foreground animate-spin mb-3" />
            <p className="text-sm text-muted-foreground">Loading data...</p>
          </div>
        )}
        {!loading && filtered.map((check) => (
          <div
            key={check.id}
            className={`bg-card border border-border border-l-2 ${severityBg[check.severity]} rounded-lg px-4 py-3 flex items-center gap-4 hover:bg-muted/10 transition-colors`}
          >
            <div className="flex-shrink-0">{statusIcon[check.status]}</div>
            <div className="flex-1 min-w-0">
              <div className="flex items-center gap-2 flex-wrap">
                <span className="font-mono text-[11px] text-muted-foreground">{check.control}</span>
                <span className="text-[10px] px-1.5 py-0.5 rounded bg-muted text-muted-foreground">{check.category}</span>
              </div>
              <p className="text-sm font-medium mt-0.5">{check.description}</p>
            </div>
            <div className="flex items-center gap-4 flex-shrink-0">
              {check.affectedDevices > 0 && (
                <div className="text-right">
                  <p className="text-xs font-semibold text-red-400">{check.affectedDevices}</p>
                  <p className="text-[10px] text-muted-foreground">affected</p>
                </div>
              )}
              <StatusBadge variant={check.status} />
              <span className="font-mono text-[10px] text-muted-foreground">{check.lastChecked}</span>
            </div>
          </div>
        ))}
        {!loading && filtered.length === 0 && (
          <div className="bg-card border border-border rounded-lg px-4 py-12 text-center">
            <ShieldCheck size={32} className="mx-auto text-muted-foreground/30 mb-3" />
            <p className="text-sm text-muted-foreground">No controls match the selected filters</p>
          </div>
        )}
      </div>

      {/* Audit trail */}
      <AuditTrailSection title="Compliance Audit Trail" maxRows={5} entries={auditEntries} loading={loading} error={auditError} />

      {showExport && (
        <ExportModal
          title="Compliance"
          fields={[
            { key: 'id', label: 'Check ID' },
            { key: 'category', label: 'Category' },
            { key: 'control', label: 'Control ID' },
            { key: 'description', label: 'Description' },
            { key: 'status', label: 'Status' },
            { key: 'affected_devices', label: 'Affected Devices' },
            { key: 'last_checked', label: 'Last Checked' },
            { key: 'severity', label: 'Severity' },
          ]}
          onClose={() => setShowExport(false)}
          onExport={(format, dateRange, selectedFields) => {
            void runExport(format, dateRange, selectedFields).catch((loadError) => {
              console.error('compliance-export-failed', loadError);
              toast.error('Failed to export report');
            });
          }}
        />
      )}
    </div>
  );
}

