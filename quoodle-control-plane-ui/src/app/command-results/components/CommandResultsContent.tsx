'use client';

import React, { useCallback, useEffect, useMemo, useState } from 'react';
import {
  AlertTriangle,
  CheckCircle,
  ChevronDown,
  ChevronUp,
  Clock,
  Copy,
  Loader2,
  Monitor,
  RefreshCw,
  Search,
  Terminal,
  XCircle,
} from 'lucide-react';
import { toast } from 'sonner';
import { formatLocalDateTime } from '@/lib/dateTime';
import CommandResultPresentation from '@/components/results/CommandResultPresentation';
import {
  mapCommandListRow,
  mergeCommandDetail,
  resultPreview,
  toRawResultJson,
  type CommandDetailApi,
  type CommandListRowApi,
  type CommandState,
  type NormalizedCommandResult,
} from '@/lib/commandResults';

type ResultStatusFilter = CommandState | 'all';

interface CommandsApiResponse {
  commands?: CommandListRowApi[];
  next_before?: string | null;
}

const statusConfig: Record<CommandState, { color: string; label: string; icon: React.ElementType }> = {
  queued: { color: 'text-muted-foreground', label: 'Queued', icon: Clock },
  dispatched: { color: 'text-blue-400', label: 'Dispatched', icon: Loader2 },
  ack_received: { color: 'text-blue-400', label: 'Acknowledged', icon: Loader2 },
  executing: { color: 'text-blue-400', label: 'Executing', icon: Loader2 },
  completed: { color: 'text-green-400', label: 'Completed', icon: CheckCircle },
  failed: { color: 'text-red-400', label: 'Failed', icon: XCircle },
  expired: { color: 'text-amber-400', label: 'Expired', icon: AlertTriangle },
  rejected: { color: 'text-red-400', label: 'Rejected', icon: XCircle },
};

const knownMethodLabels: Record<string, string> = {
  ping: 'Ping',
  lock_screen: 'Lock Screen',
  logout_user: 'Logout User',
  reboot_device: 'Reboot Device',
  shutdown_device: 'Shutdown Device',
  process_list: 'Process List',
  list_processes: 'Process List',
  system_info: 'System Info',
  collect_system_info: 'System Info',
  telemetry_snapshot: 'Telemetry Snapshot',
};

function methodLabel(method: string): string {
  if (knownMethodLabels[method]) return knownMethodLabels[method];
  return method.replace(/_/g, ' ');
}

function formatTime(value: string | null | undefined): string {
  return formatLocalDateTime(value, '-');
}

function timelineRows(row: NormalizedCommandResult): Array<{ label: string; at: string; done: boolean }> {
  return [
    { label: 'Queued', at: formatTime(row.queuedAt), done: !!row.queuedAt },
    { label: 'Dispatched', at: formatTime(row.dispatchedAt), done: !!row.dispatchedAt },
    { label: 'Completed', at: formatTime(row.completedAt), done: !!row.completedAt },
  ];
}

export default function CommandResultsContent() {
  const [results, setResults] = useState<NormalizedCommandResult[]>([]);
  const [details, setDetails] = useState<Record<string, NormalizedCommandResult>>({});
  const [expandedIds, setExpandedIds] = useState<Set<string>>(new Set());
  const [search, setSearch] = useState('');
  const [deviceFilter, setDeviceFilter] = useState('all');
  const [statusFilter, setStatusFilter] = useState<ResultStatusFilter>('all');
  const [methodFilter, setMethodFilter] = useState('all');
  const [isLoading, setIsLoading] = useState(true);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [nextBefore, setNextBefore] = useState<string | null>(null);
  const [isLoadingMore, setIsLoadingMore] = useState(false);

  const fetchCommandList = useCallback(async (opts?: { append?: boolean; before?: string | null; silent?: boolean }) => {
    const append = opts?.append === true;
    const before = opts?.before;
    const silent = opts?.silent === true;

    if (!silent && !append) {
      setIsLoading(true);
    }
    if (!silent && append) {
      setIsLoadingMore(true);
    }

    try {
      const params = new URLSearchParams();
      params.set('limit', '50');
      if (before) params.set('before', before);
      const response = await fetch(`/api/commands?${params.toString()}`, {
        credentials: 'include',
        cache: 'no-store',
      });

      if (!response.ok) {
        throw new Error(`Failed to load data (${response.status})`);
      }

      const payload = (await response.json()) as CommandsApiResponse;
      const mapped = (payload.commands ?? []).map((row) => mapCommandListRow(row));

      setResults((prev) => {
        if (!append) return mapped;
        const byId = new Map(prev.map((item) => [item.commandId, item]));
        for (const item of mapped) {
          if (!byId.has(item.commandId)) {
            byId.set(item.commandId, item);
          }
        }
        return Array.from(byId.values());
      });

      setNextBefore(payload.next_before ?? null);
      setError(null);
    } catch (fetchError) {
      const message = fetchError instanceof Error ? fetchError.message : 'Failed to load data';
      setError(message);
      console.error('command-results list fetch error', fetchError);
    } finally {
      if (!silent && !append) {
        setIsLoading(false);
      }
      if (!silent && append) {
        setIsLoadingMore(false);
      }
    }
  }, []);

  const fetchCommandDetail = useCallback(async (commandId: string) => {
    if (details[commandId]) return;

    try {
      const response = await fetch(`/api/commands/${encodeURIComponent(commandId)}`, {
        credentials: 'include',
        cache: 'no-store',
      });
      if (!response.ok) {
        throw new Error(`Failed to load command detail (${response.status})`);
      }

      const payload = (await response.json()) as CommandDetailApi;
      setDetails((prev) => {
        const base = results.find((item) => item.commandId === commandId);
        if (!base) return prev;
        return {
          ...prev,
          [commandId]: mergeCommandDetail(base, payload),
        };
      });
    } catch (detailError) {
      console.error('command-results detail fetch error', detailError);
      toast.error('Failed to load data');
    }
  }, [details, results]);

  useEffect(() => {
    void fetchCommandList();
  }, [fetchCommandList]);

  useEffect(() => {
    const timer = setInterval(() => {
      void fetchCommandList({ silent: true });
    }, 15000);

    return () => clearInterval(timer);
  }, [fetchCommandList]);

  const rows = useMemo(() => {
    return results
      .map((row) => details[row.commandId] ?? row)
      .sort((a, b) => {
        const at = Date.parse(a.queuedAt ?? '') || 0;
        const bt = Date.parse(b.queuedAt ?? '') || 0;
        return bt - at;
      });
  }, [details, results]);

  const devices = useMemo(() => Array.from(new Set(rows.map((r) => r.deviceName))).sort(), [rows]);
  const methods = useMemo(() => Array.from(new Set(rows.map((r) => r.method))).sort(), [rows]);

  const filtered = useMemo(() => {
    const term = search.trim().toLowerCase();
    return rows.filter((row) => {
      if (deviceFilter !== 'all' && row.deviceName !== deviceFilter) return false;
      if (statusFilter !== 'all' && row.state !== statusFilter) return false;
      if (methodFilter !== 'all' && row.method !== methodFilter) return false;
      if (!term) return true;
      return (
        row.commandId.toLowerCase().includes(term) ||
        row.deviceName.toLowerCase().includes(term) ||
        row.actorEmail.toLowerCase().includes(term) ||
        row.method.toLowerCase().includes(term)
      );
    });
  }, [deviceFilter, methodFilter, rows, search, statusFilter]);

  const toggleExpand = async (commandId: string) => {
    setExpandedIds((prev) => {
      const next = new Set(prev);
      if (next.has(commandId)) {
        next.delete(commandId);
      } else {
        next.add(commandId);
      }
      return next;
    });

    if (!details[commandId]) {
      await fetchCommandDetail(commandId);
    }
  };

  return (
    <div className="space-y-4 fade-in">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">Command Results</h1>
          <p className="text-sm text-muted-foreground mt-0.5">
            Real command outputs and artifacts · {rows.length} results
          </p>
        </div>
        <button
          onClick={async () => {
            setIsRefreshing(true);
            await fetchCommandList();
            setIsRefreshing(false);
            toast.success('Results refreshed');
          }}
          className="flex items-center gap-1.5 px-3 py-1.5 text-xs text-muted-foreground border border-border rounded-md hover:bg-muted/60 transition-colors"
        >
          <RefreshCw size={13} className={isRefreshing ? 'animate-spin' : ''} /> Refresh
        </button>
      </div>

      <div className="flex flex-wrap items-center gap-2">
        <div className="relative">
          <Search size={13} className="absolute left-2.5 top-1/2 -translate-y-1/2 text-muted-foreground" />
          <input
            placeholder="Search command, device, actor..."
            value={search}
            onChange={(event) => setSearch(event.target.value)}
            className="pl-8 pr-3 py-1.5 text-xs bg-muted/60 border border-border rounded-md text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-1 focus:ring-primary/50 w-52"
          />
        </div>

        <select
          value={deviceFilter}
          onChange={(event) => setDeviceFilter(event.target.value)}
          className="text-xs bg-muted/60 border border-border rounded-md px-2.5 py-1.5 text-foreground focus:outline-none focus:ring-1 focus:ring-primary/50"
        >
          <option value="all">All Devices</option>
          {devices.map((device) => (
            <option key={device} value={device}>{device}</option>
          ))}
        </select>

        <select
          value={statusFilter}
          onChange={(event) => setStatusFilter(event.target.value as ResultStatusFilter)}
          className="text-xs bg-muted/60 border border-border rounded-md px-2.5 py-1.5 text-foreground focus:outline-none focus:ring-1 focus:ring-primary/50"
        >
          <option value="all">All Status</option>
          {Object.entries(statusConfig).map(([state, cfg]) => (
            <option key={state} value={state}>{cfg.label}</option>
          ))}
        </select>

        <select
          value={methodFilter}
          onChange={(event) => setMethodFilter(event.target.value)}
          className="text-xs bg-muted/60 border border-border rounded-md px-2.5 py-1.5 text-foreground focus:outline-none focus:ring-1 focus:ring-primary/50"
        >
          <option value="all">All Commands</option>
          {methods.map((method) => (
            <option key={method} value={method}>{methodLabel(method)}</option>
          ))}
        </select>
      </div>

      {error && (
        <div className="bg-card border border-red-500/20 rounded-lg px-4 py-3 text-sm text-red-300">
          Failed to load data
        </div>
      )}

      {isLoading ? (
        <div className="bg-card border border-border rounded-lg px-4 py-12 text-center">
          <Loader2 size={32} className="mx-auto text-muted-foreground/40 mb-3 animate-spin" />
          <p className="text-sm font-medium text-muted-foreground">Loading command results...</p>
        </div>
      ) : filtered.length === 0 ? (
        <div className="bg-card border border-border rounded-lg px-4 py-12 text-center">
          <Terminal size={32} className="mx-auto text-muted-foreground/30 mb-3" />
          <p className="text-sm font-medium text-muted-foreground">No data available</p>
        </div>
      ) : (
        <div className="space-y-3">
          {filtered.map((row) => {
            const expanded = expandedIds.has(row.commandId);
            const StatusIcon = statusConfig[row.state].icon;
            const timeline = timelineRows(row);

            return (
              <div key={row.commandId} className="bg-card border border-border rounded-lg overflow-hidden">
                <div
                  className="flex items-center gap-3 px-4 py-3 cursor-pointer hover:bg-muted/20 transition-colors"
                  onClick={() => {
                    void toggleExpand(row.commandId);
                  }}
                >
                  <StatusIcon
                    size={15}
                    className={`flex-shrink-0 ${statusConfig[row.state].color} ${row.state === 'executing' || row.state === 'ack_received' || row.state === 'dispatched' ? 'animate-spin' : ''}`}
                  />
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2 flex-wrap">
                      <span className="text-sm font-medium font-mono">{row.commandId}</span>
                      <span className="text-xs text-muted-foreground bg-muted/60 px-2 py-0.5 rounded">{methodLabel(row.method)}</span>
                      <span className={`text-[10px] font-semibold uppercase tracking-wider px-1.5 py-0.5 rounded-full ${
                        row.state === 'completed'
                          ? 'bg-green-500/10 text-green-400'
                          : row.state === 'failed' || row.state === 'rejected'
                            ? 'bg-red-500/10 text-red-400'
                            : row.state === 'executing' || row.state === 'ack_received' || row.state === 'dispatched'
                              ? 'bg-blue-500/10 text-blue-400'
                              : 'bg-muted text-muted-foreground'
                      }`}>
                        {statusConfig[row.state].label}
                      </span>
                    </div>
                    <div className="flex items-center gap-3 mt-0.5 text-[11px] text-muted-foreground">
                      <span className="flex items-center gap-1"><Monitor size={10} /> {row.deviceName}</span>
                      <span>{row.actorEmail}</span>
                      <span className="flex items-center gap-1"><Clock size={10} /> {formatTime(row.queuedAt)}</span>
                    </div>
                  </div>
                  <button
                    onClick={(event) => {
                      event.stopPropagation();
                      void navigator.clipboard.writeText(toRawResultJson(row));
                      toast.success('Raw output copied');
                    }}
                    className="p-1.5 text-muted-foreground hover:text-foreground transition-colors"
                    title="Copy raw output"
                  >
                    <Copy size={13} />
                  </button>
                  {expanded ? <ChevronUp size={14} className="text-muted-foreground" /> : <ChevronDown size={14} className="text-muted-foreground" />}
                </div>

                {expanded && (
                  <div className="border-t border-border px-4 py-4 space-y-4">
                    <div className="grid grid-cols-1 md:grid-cols-3 gap-2">
                      {timeline.map((step) => (
                        <div key={`${row.commandId}-${step.label}`} className="bg-muted/20 border border-border rounded-md px-3 py-2">
                          <p className="text-[10px] uppercase tracking-wide text-muted-foreground">{step.label}</p>
                          <p className="text-xs mt-1">{step.at}</p>
                        </div>
                      ))}
                    </div>

                    <div className="bg-muted/20 border border-border rounded-lg p-3">
                      <p className="text-[10px] uppercase tracking-wide text-muted-foreground mb-2">Result Summary</p>
                      <p className="text-xs">{resultPreview(row)}</p>
                    </div>
                    <CommandResultPresentation key={`render-${row.commandId}`} row={row} />
                  </div>
                )}
              </div>
            );
          })}

          <div className="flex items-center justify-center">
            {nextBefore ? (
              <button
                onClick={async () => {
                  await fetchCommandList({ append: true, before: nextBefore });
                }}
                disabled={isLoadingMore}
                className="flex items-center gap-1.5 px-3 py-1.5 text-xs text-muted-foreground border border-border rounded-md hover:bg-muted/60 transition-colors disabled:opacity-60"
              >
                {isLoadingMore ? <Loader2 size={13} className="animate-spin" /> : null}
                {isLoadingMore ? 'Loading...' : 'Load more'}
              </button>
            ) : (
              <p className="text-xs text-muted-foreground">No more results</p>
            )}
          </div>
        </div>
      )}
    </div>
  );
}
