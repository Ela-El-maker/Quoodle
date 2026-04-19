'use client';
import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { ScrollText, Search, Download, Terminal, Shield, User, ChevronUp, ChevronDown, RefreshCw } from 'lucide-react';
import { toast } from 'sonner';
import { type AuditEntry, type AuditEventType } from '@/components/AuditTrailSection';
import { formatLocalDateTime, parseLocalDateTime } from '@/lib/dateTime';

const typeConfig: Record<AuditEventType, { icon: React.ElementType; color: string; bg: string; label: string }> = {
  user_action:       { icon: User,       color: 'text-blue-400',   bg: 'bg-blue-500/10',   label: 'User Action' },
  command_execution: { icon: Terminal,   color: 'text-green-400',  bg: 'bg-green-500/10',  label: 'Command' },
  policy_change:     { icon: Shield,     color: 'text-amber-400',  bg: 'bg-amber-500/10',  label: 'Policy' },
  system_event:      { icon: ScrollText, color: 'text-zinc-400',   bg: 'bg-zinc-500/10',   label: 'System' },
};

const outcomeConfig = {
  success: { text: 'text-green-400', label: 'SUCCESS' },
  failure: { text: 'text-red-400',   label: 'FAILURE' },
  pending: { text: 'text-amber-400', label: 'PENDING' },
};

type SortKey = 'timestamp' | 'actor' | 'action' | 'outcome';

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
  summary?: {
    total_events?: number;
    success_count?: number;
    failure_count?: number;
    active_actors?: number;
  };
}

interface AuditSummary {
  total: number;
  success: number;
  failure: number;
  activeActors: number;
}

function normalizeEventType(value: unknown): AuditEventType {
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
  if (utf8Match?.[1]) {
    return decodeURIComponent(utf8Match[1]);
  }
  const basicMatch = disposition.match(/filename="?([^";]+)"?/i);
  if (basicMatch?.[1]) {
    return basicMatch[1];
  }
  return null;
}

export default function AuditContent() {
  const [search, setSearch] = useState('');
  const [typeFilter, setTypeFilter] = useState<AuditEventType | 'all'>('all');
  const [outcomeFilter, setOutcomeFilter] = useState<'all' | 'success' | 'failure'>('all');
  const [sortKey, setSortKey] = useState<SortKey>('timestamp');
  const [sortDir, setSortDir] = useState<'asc' | 'desc'>('desc');
  const [entries, setEntries] = useState<AuditEntry[]>([]);
  const [summary, setSummary] = useState<AuditSummary>({
    total: 0,
    success: 0,
    failure: 0,
    activeActors: 0,
  });
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const requestAbortRef = useRef<AbortController | null>(null);

  const loadAudit = useCallback(async (mode: 'initial' | 'refresh' = 'initial') => {
    if (mode === 'initial') {
      setLoading(true);
    } else {
      setRefreshing(true);
    }

    requestAbortRef.current?.abort();
    const controller = new AbortController();
    requestAbortRef.current = controller;

    try {
      const response = await fetch('/api/audit/events?page=1&per_page=200', {
        credentials: 'include',
        cache: 'no-store',
        signal: controller.signal,
      });
      if (!response.ok) {
        throw new Error(`http_${response.status}`);
      }

      const payload = (await response.json()) as AuditEventsResponse;
      const mapped: AuditEntry[] = (payload.events ?? []).map((event, index) => ({
        id: String(event.id ?? ([event.timestamp, event.action, event.target, index].filter(Boolean).join('|') || `audit-${index}`)),
        timestamp: formatLocalDateTime(event.timestamp ?? null, '-'),
        actor: String(event.actor ?? 'system'),
        actorRole: labelRole(event.actor_role),
        eventType: normalizeEventType(event.event_type),
        action: String(event.action ?? 'EVENT'),
        target: String(event.target ?? ''),
        detail: String(event.detail ?? ''),
        outcome: normalizeOutcome(event.outcome),
      }));

      if (!controller.signal.aborted) {
        setEntries(mapped);
        setSummary({
          total: Number(payload.summary?.total_events ?? mapped.length),
          success: Number(payload.summary?.success_count ?? mapped.filter((entry) => entry.outcome === 'success').length),
          failure: Number(payload.summary?.failure_count ?? mapped.filter((entry) => entry.outcome === 'failure').length),
          activeActors: Number(payload.summary?.active_actors ?? new Set(mapped.map((entry) => entry.actor)).size),
        });
        setError(null);
      }
    } catch (loadError) {
      if (controller.signal.aborted) return;
      console.error('audit-events-load-failed', loadError);
      setError('Failed to load data');
      if (mode === 'initial') {
        setEntries([]);
        setSummary({
          total: 0,
          success: 0,
          failure: 0,
          activeActors: 0,
        });
      }
    } finally {
      if (controller.signal.aborted) return;
      if (mode === 'initial') {
        setLoading(false);
      } else {
        setRefreshing(false);
      }
    }
  }, []);

  useEffect(() => {
    void loadAudit('initial');
  }, [loadAudit]);

  useEffect(() => {
    let timer: ReturnType<typeof setInterval> | null = null;

    const startPolling = () => {
      if (timer) clearInterval(timer);
      const pollMs = document.visibilityState === 'visible' ? 15000 : 30000;
      timer = setInterval(() => {
        void loadAudit('refresh');
      }, pollMs);
    };

    startPolling();
    const handleVisibilityChange = () => startPolling();
    document.addEventListener('visibilitychange', handleVisibilityChange);

    return () => {
      if (timer) clearInterval(timer);
      document.removeEventListener('visibilitychange', handleVisibilityChange);
      requestAbortRef.current?.abort();
    };
  }, [loadAudit]);

  const runExport = useCallback(async () => {
    const params = new URLSearchParams();
    params.set('format', 'csv');
    if (search.trim() !== '') params.set('q', search.trim());
    if (typeFilter !== 'all') params.set('type', typeFilter);
    if (outcomeFilter !== 'all') params.set('outcome', outcomeFilter);

    const response = await fetch(`/api/audit/events/export?${params.toString()}`, {
      credentials: 'include',
      cache: 'no-store',
    });

    if (!response.ok) {
      throw new Error(`http_${response.status}`);
    }

    const blob = await response.blob();
    const filename = parseFilename(response.headers.get('content-disposition')) ?? `audit-events-${Date.now()}.csv`;
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = filename;
    link.click();
    URL.revokeObjectURL(url);
  }, [outcomeFilter, search, typeFilter]);

  const filtered = useMemo(() => {
    const data = entries.filter((entry) => {
      const matchType = typeFilter === 'all' || entry.eventType === typeFilter;
      const matchOutcome = outcomeFilter === 'all' || entry.outcome === outcomeFilter;
      const searchValue = search.trim().toLowerCase();
      const matchSearch =
        !searchValue ||
        entry.actor.toLowerCase().includes(searchValue) ||
        entry.action.toLowerCase().includes(searchValue) ||
        entry.target.toLowerCase().includes(searchValue) ||
        entry.detail.toLowerCase().includes(searchValue);
      return matchType && matchOutcome && matchSearch;
    });

    return [...data].sort((a, b) => {
      if (sortKey === 'timestamp') {
        const av = parseLocalDateTime(a.timestamp);
        const bv = parseLocalDateTime(b.timestamp);
        return sortDir === 'asc' ? av - bv : bv - av;
      }

      const av = String(a[sortKey] ?? '');
      const bv = String(b[sortKey] ?? '');
      return sortDir === 'asc' ? av.localeCompare(bv) : bv.localeCompare(av);
    });
  }, [entries, outcomeFilter, search, sortDir, sortKey, typeFilter]);

  const toggleSort = (key: SortKey) => {
    if (sortKey === key) setSortDir(sortDir === 'asc' ? 'desc' : 'asc');
    else { setSortKey(key); setSortDir('desc'); }
  };

  const SortIcon = ({ k }: { k: SortKey }) =>
    sortKey === k ? (
      sortDir === 'asc' ? <ChevronUp size={12} className="text-primary" /> : <ChevronDown size={12} className="text-primary" />
    ) : (
      <ChevronUp size={12} className="text-muted-foreground/40" />
    );

  return (
    <div className="space-y-6 fade-in">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">Audit Trail</h1>
          <p className="text-sm text-muted-foreground mt-0.5">Immutable log of user actions, command executions, and policy changes</p>
          {error && <p className="text-xs text-red-400 mt-1.5">{error}</p>}
        </div>
        <button
          onClick={() => {
            void runExport().catch((loadError) => {
              console.error('audit-export-failed', loadError);
              toast.error('Failed to export report');
            });
          }}
          className="flex items-center gap-1.5 px-3 py-1.5 text-xs text-muted-foreground border border-border rounded-md hover:bg-muted/60 transition-colors"
        >
          <Download size={13} />
          Export CSV
        </button>
      </div>

      {/* Summary cards */}
      <div className="grid grid-cols-2 sm:grid-cols-4 gap-4">
        <div className="bg-card border border-border rounded-lg p-4">
          <p className="text-3xl font-bold tabular-nums">{summary.total}</p>
          <p className="text-xs text-muted-foreground mt-1 uppercase tracking-wide font-medium">Total Events</p>
        </div>
        <div className="bg-green-500/5 border border-green-500/20 rounded-lg p-4">
          <p className="text-3xl font-bold tabular-nums text-green-400">{summary.success}</p>
          <p className="text-xs text-green-400/70 mt-1 uppercase tracking-wide font-medium">Successful</p>
        </div>
        <div className="bg-red-500/5 border border-red-500/20 rounded-lg p-4">
          <p className="text-3xl font-bold tabular-nums text-red-400">{summary.failure}</p>
          <p className="text-xs text-red-400/70 mt-1 uppercase tracking-wide font-medium">Failures</p>
        </div>
        <div className="bg-card border border-border rounded-lg p-4">
          <p className="text-3xl font-bold tabular-nums text-blue-400">{summary.activeActors}</p>
          <p className="text-xs text-blue-400/70 mt-1 uppercase tracking-wide font-medium">Active Actors</p>
        </div>
      </div>

      {/* Filters */}
      <div className="flex flex-wrap items-center gap-3">
        <div className="flex items-center gap-1 bg-muted/30 rounded-lg p-1">
          {(['all', 'user_action', 'command_execution', 'policy_change', 'system_event'] as const).map((t) => (
            <button
              key={t}
              onClick={() => setTypeFilter(t)}
              className={`px-3 py-1.5 rounded-md text-xs font-medium transition-all ${
                typeFilter === t ? 'bg-card text-foreground shadow-sm' : 'text-muted-foreground hover:text-foreground'
              }`}
            >
              {t === 'all' ? 'All' : typeConfig[t]?.label ?? t}
            </button>
          ))}
        </div>
        <div className="flex items-center gap-1 bg-muted/30 rounded-lg p-1">
          {(['all', 'success', 'failure'] as const).map((o) => (
            <button
              key={o}
              onClick={() => setOutcomeFilter(o)}
              className={`px-3 py-1.5 rounded-md text-xs font-medium transition-all capitalize ${
                outcomeFilter === o ? 'bg-card text-foreground shadow-sm' : 'text-muted-foreground hover:text-foreground'
              }`}
            >
              {o === 'all' ? 'All Outcomes' : o}
            </button>
          ))}
        </div>
        <div className="relative flex-1 min-w-[200px] max-w-xs ml-auto">
          <Search size={13} className="absolute left-2.5 top-1/2 -translate-y-1/2 text-muted-foreground" />
          <input
            type="text"
            placeholder="Search actor, action, target..."
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
                  { key: 'timestamp' as SortKey, label: 'Timestamp' },
                  { key: 'actor' as SortKey,     label: 'Actor' },
                ].map((col) => (
                  <th
                    key={col.key}
                    className="px-3 py-3 text-left font-semibold text-muted-foreground tracking-wide uppercase text-[10px] cursor-pointer hover:text-foreground transition-colors whitespace-nowrap"
                    onClick={() => toggleSort(col.key)}
                  >
                    <span className="flex items-center gap-1">{col.label}<SortIcon k={col.key} /></span>
                  </th>
                ))}
                <th className="px-3 py-3 text-left font-semibold text-muted-foreground tracking-wide uppercase text-[10px] whitespace-nowrap">Type</th>
                <th
                  className="px-3 py-3 text-left font-semibold text-muted-foreground tracking-wide uppercase text-[10px] cursor-pointer hover:text-foreground transition-colors whitespace-nowrap"
                  onClick={() => toggleSort('action')}
                >
                  <span className="flex items-center gap-1">Action<SortIcon k="action" /></span>
                </th>
                <th className="px-3 py-3 text-left font-semibold text-muted-foreground tracking-wide uppercase text-[10px] whitespace-nowrap">Target</th>
                <th className="px-3 py-3 text-left font-semibold text-muted-foreground tracking-wide uppercase text-[10px]">Detail</th>
                <th
                  className="px-3 py-3 text-left font-semibold text-muted-foreground tracking-wide uppercase text-[10px] cursor-pointer hover:text-foreground transition-colors whitespace-nowrap"
                  onClick={() => toggleSort('outcome')}
                >
                  <span className="flex items-center gap-1">Outcome<SortIcon k="outcome" /></span>
                </th>
              </tr>
            </thead>
            <tbody className="divide-y divide-border">
              {loading ? (
                <tr>
                  <td colSpan={7} className="px-4 py-12 text-center">
                    <RefreshCw size={32} className="mx-auto text-muted-foreground/30 mb-3 animate-spin" />
                    <p className="text-sm text-muted-foreground">Loading audit events...</p>
                  </td>
                </tr>
              ) : filtered.length === 0 ? (
                <tr>
                  <td colSpan={7} className="px-4 py-12 text-center">
                    <ScrollText size={32} className="mx-auto text-muted-foreground/30 mb-3" />
                    <p className="text-sm text-muted-foreground">No audit events match your filters</p>
                  </td>
                </tr>
              ) : (
                filtered.map((entry) => {
                  const cfg = typeConfig[entry.eventType];
                  const Icon = cfg.icon;
                  const oc = outcomeConfig[entry.outcome];
                  const [datePart, timePart = '--:--:--'] = entry.timestamp.split(' ');
                  return (
                    <tr key={entry.id} className="hover:bg-muted/20 transition-colors">
                      <td className="px-3 py-3 font-mono text-[11px] text-muted-foreground whitespace-nowrap">
                        <div>{datePart}</div>
                        <div className="text-primary">{timePart}</div>
                      </td>
                      <td className="px-3 py-3 whitespace-nowrap">
                        <p className="font-medium text-foreground truncate max-w-[160px]">{entry.actor}</p>
                        <p className="text-[10px] text-muted-foreground">{entry.actorRole}</p>
                      </td>
                      <td className="px-3 py-3 whitespace-nowrap">
                        <span className={`inline-flex items-center gap-1 px-1.5 py-0.5 rounded text-[10px] font-medium ${cfg.bg} ${cfg.color}`}>
                          <Icon size={10} />
                          {cfg.label}
                        </span>
                      </td>
                      <td className="px-3 py-3 font-mono text-[11px] text-foreground whitespace-nowrap">{entry.action}</td>
                      <td className="px-3 py-3 font-mono text-[11px] text-primary whitespace-nowrap">{entry.target}</td>
                      <td className="px-3 py-3 text-muted-foreground max-w-[280px]">
                        <p className="truncate">{entry.detail}</p>
                      </td>
                      <td className="px-3 py-3 whitespace-nowrap">
                        <span className={`font-semibold uppercase text-[10px] ${oc.text}`}>{oc.label}</span>
                      </td>
                    </tr>
                  );
                })
              )}
            </tbody>
          </table>
        </div>
        <div className="border-t border-border px-4 py-2.5 flex items-center justify-between">
          <p className="text-[11px] text-muted-foreground">
            Showing {filtered.length} of {summary.total} events
          </p>
          <button
            onClick={() => {
              void loadAudit('refresh');
            }}
            className="flex items-center gap-1.5 text-xs text-muted-foreground hover:text-foreground transition-colors"
          >
            <RefreshCw size={11} className={refreshing ? 'animate-spin' : ''} />
            {refreshing ? 'Refreshing...' : 'Refresh'}
          </button>
        </div>
      </div>
    </div>
  );
}
