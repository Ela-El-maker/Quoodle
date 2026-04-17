'use client';

import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  Search,
  RefreshCw,
  RotateCcw,
  X,
  Terminal,
  CheckCircle,
  XCircle,
  Clock,
  ChevronDown,
  ChevronUp,
  Copy,
  Download,
  Filter,
  Loader2,
} from 'lucide-react';
import { toast } from 'sonner';
import StatusBadge from '@/components/ui/StatusBadge';
import { mapCommandListRow, resultPreview, type CommandListRowApi } from '@/lib/commandResults';
import { resolveCommandMethod } from '@/lib/commandMethodResolver';
import { formatLocalDateTime } from '@/lib/dateTime';

type CommandState = 'queued' | 'dispatched' | 'ack_received' | 'executing' | 'completed' | 'failed' | 'expired' | 'rejected';

interface HistoryCommand {
  id: string;
  traceId: string;
  deviceId: string;
  hostname: string;
  method: string;
  state: CommandState;
  actor: string;
  queuedAt: string;
  queuedAtIso: string | null;
  completedAt: string | null;
  completedAtIso: string | null;
  duration: string | null;
  errorMessage: string | null;
  priority: 'normal' | 'high';
  batchId: string | null;
  resultPreview: string | null;
  resultType: string | null;
  params: Record<string, unknown>;
}

interface CommandsApiResponse {
  commands?: CommandListRowApi[];
}

interface DispatchResponse {
  command_id?: string;
  reason?: string;
  message?: string;
}

function parseTimeMs(value: string | null | undefined): number {
  if (!value) return 0;
  const parsed = Date.parse(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function formatDuration(startIso: string | null | undefined, endIso: string | null | undefined): string | null {
  if (!startIso || !endIso) return null;
  const start = parseTimeMs(startIso);
  const end = parseTimeMs(endIso);
  if (!start || !end || end < start) return null;
  return `${Math.round((end - start) / 1000)}s`;
}

function toHistoryCommand(rowApi: CommandListRowApi): HistoryCommand {
  const normalized = mapCommandListRow(rowApi);
  const priority = String((rowApi as { priority?: unknown }).priority ?? '').toLowerCase() === 'high' ? 'high' : 'normal';
  const batchId = (rowApi as { batch_id?: unknown }).batch_id;
  const resultTypeRaw = (normalized.result?.meta as { kind?: unknown } | undefined)?.kind;

  return {
    id: normalized.commandId,
    traceId: normalized.traceId ?? '-',
    deviceId: normalized.deviceId,
    hostname: normalized.deviceName || normalized.deviceId,
    method: normalized.method,
    state: normalized.state,
    actor: normalized.actorEmail,
    queuedAt: formatLocalDateTime(normalized.queuedAt, '-'),
    queuedAtIso: normalized.queuedAt,
    completedAt: normalized.completedAt ? formatLocalDateTime(normalized.completedAt, '-') : null,
    completedAtIso: normalized.completedAt,
    duration: formatDuration(normalized.queuedAt, normalized.completedAt),
    errorMessage: normalized.errorMessage ?? normalized.reason,
    priority,
    batchId: typeof batchId === 'string' && batchId.trim() ? batchId.trim() : null,
    resultPreview: resultPreview(normalized),
    resultType: typeof resultTypeRaw === 'string' && resultTypeRaw.trim() ? resultTypeRaw.trim() : null,
    params: normalized.params ?? {},
  };
}

export default function CommandHistoryContent() {
  const [search, setSearch] = useState('');
  const [deviceFilter, setDeviceFilter] = useState('all');
  const [methodFilter, setMethodFilter] = useState('all');
  const [actorFilter, setActorFilter] = useState('all');
  const [stateFilter, setStateFilter] = useState('all');
  const [dateFrom, setDateFrom] = useState('');
  const [dateTo, setDateTo] = useState('');
  const [expandedId, setExpandedId] = useState<string | null>(null);
  const [sortKey, setSortKey] = useState<keyof HistoryCommand>('queuedAt');
  const [sortDir, setSortDir] = useState<'asc' | 'desc'>('desc');

  const [history, setHistory] = useState<HistoryCommand[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [isReplaying, setIsReplaying] = useState<Set<string>>(new Set());
  const [error, setError] = useState<string | null>(null);

  const listAbortRef = useRef<AbortController | null>(null);

  const fetchHistory = useCallback(async (mode: 'initial' | 'refresh' | 'silent' = 'initial') => {
    if (mode === 'initial') setIsLoading(true);
    if (mode === 'refresh') setIsRefreshing(true);

    listAbortRef.current?.abort();
    const controller = new AbortController();
    listAbortRef.current = controller;

    try {
      const response = await fetch('/api/commands?limit=300', {
        credentials: 'include',
        cache: 'no-store',
        signal: controller.signal,
      });
      if (!response.ok) throw new Error(`http_${response.status}`);
      const payload = (await response.json()) as CommandsApiResponse;
      const mapped = (payload.commands ?? [])
        .map(toHistoryCommand)
        .sort((a, b) => parseTimeMs(b.queuedAtIso) - parseTimeMs(a.queuedAtIso));
      setHistory(mapped);
      setError(null);
    } catch (fetchError) {
      if ((fetchError as Error).name === 'AbortError') return;
      console.error('command-history-load-failed', fetchError);
      setError('Failed to load data');
      if (mode === 'initial') setHistory([]);
    } finally {
      if (mode === 'initial') setIsLoading(false);
      if (mode === 'refresh') setIsRefreshing(false);
    }
  }, []);

  useEffect(() => {
    void fetchHistory('initial');
  }, [fetchHistory]);

  useEffect(() => {
    let interval: ReturnType<typeof setInterval> | null = null;
    const startPolling = () => {
      if (interval) clearInterval(interval);
      const pollMs = document.visibilityState === 'visible' ? 15000 : 30000;
      interval = setInterval(() => {
        void fetchHistory('silent');
      }, pollMs);
    };

    startPolling();
    const handleVisibility = () => startPolling();
    document.addEventListener('visibilitychange', handleVisibility);

    return () => {
      if (interval) clearInterval(interval);
      document.removeEventListener('visibilitychange', handleVisibility);
      listAbortRef.current?.abort();
    };
  }, [fetchHistory]);

  const actors = useMemo(() => Array.from(new Set(history.map((command) => command.actor))).sort(), [history]);
  const devices = useMemo(() => Array.from(new Set(history.map((command) => command.hostname))).sort(), [history]);
  const methods = useMemo(() => Array.from(new Set(history.map((command) => command.method))).sort(), [history]);

  const filtered = useMemo(() => {
    const lowered = search.trim().toLowerCase();
    const fromMs = dateFrom ? parseTimeMs(`${dateFrom}T00:00:00`) : 0;
    const toMs = dateTo ? parseTimeMs(`${dateTo}T23:59:59`) : 0;

    const data = history.filter((command) => {
      const queuedMs = parseTimeMs(command.queuedAtIso);
      const matchSearch = !lowered
        || command.id.toLowerCase().includes(lowered)
        || command.hostname.toLowerCase().includes(lowered)
        || command.method.toLowerCase().includes(lowered)
        || command.actor.toLowerCase().includes(lowered)
        || command.traceId.toLowerCase().includes(lowered);
      const matchDevice = deviceFilter === 'all' || command.hostname === deviceFilter;
      const matchMethod = methodFilter === 'all' || command.method === methodFilter;
      const matchActor = actorFilter === 'all' || command.actor === actorFilter;
      const matchState = stateFilter === 'all' || command.state === stateFilter;
      const matchFrom = fromMs === 0 || queuedMs >= fromMs;
      const matchTo = toMs === 0 || queuedMs <= toMs;
      return matchSearch && matchDevice && matchMethod && matchActor && matchState && matchFrom && matchTo;
    });

    data.sort((a, b) => {
      const direction = sortDir === 'asc' ? 1 : -1;
      if (sortKey === 'queuedAt' || sortKey === 'completedAt') {
        const aValue = sortKey === 'queuedAt' ? a.queuedAtIso : a.completedAtIso;
        const bValue = sortKey === 'queuedAt' ? b.queuedAtIso : b.completedAtIso;
        return (parseTimeMs(aValue) - parseTimeMs(bValue)) * direction;
      }
      const av = String(a[sortKey] ?? '');
      const bv = String(b[sortKey] ?? '');
      return av.localeCompare(bv) * direction;
    });

    return data;
  }, [history, search, deviceFilter, methodFilter, actorFilter, stateFilter, sortKey, sortDir, dateFrom, dateTo]);

  const toggleSort = (key: keyof HistoryCommand) => {
    if (sortKey === key) setSortDir((value) => (value === 'asc' ? 'desc' : 'asc'));
    else {
      setSortKey(key);
      setSortDir(key === 'queuedAt' ? 'desc' : 'asc');
    }
  };

  const SortIcon = ({ k }: { k: keyof HistoryCommand }) => (
    sortKey === k
      ? (sortDir === 'asc' ? <ChevronUp size={11} className="text-primary" /> : <ChevronDown size={11} className="text-primary" />)
      : <ChevronUp size={11} className="text-muted-foreground/30" />
  );

  const stateIcon = (state: CommandState) => {
    if (state === 'completed') return <CheckCircle size={12} className="text-green-400 flex-shrink-0" />;
    if (state === 'failed' || state === 'expired' || state === 'rejected') return <XCircle size={12} className="text-red-400 flex-shrink-0" />;
    return <Clock size={12} className="text-amber-400 flex-shrink-0" />;
  };

  const replayCommand = async (command: HistoryCommand) => {
    setIsReplaying((prev) => new Set(prev).add(command.id));
    try {
      const response = await fetch('/api/commands', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        credentials: 'include',
        body: JSON.stringify({
          client_message_id: `history-replay-${command.deviceId}-${command.method}-${crypto.randomUUID()}`,
          device_id: command.deviceId,
          method: resolveCommandMethod(command.method),
          params: command.params ?? {},
          sensitive: command.priority === 'high',
        }),
      });

      const payload = (await response.json().catch(() => ({}))) as DispatchResponse;
      if (!response.ok || !payload.command_id) {
        const reason = payload.reason ?? payload.message ?? `http_${response.status}`;
        throw new Error(reason);
      }

      toast.success(`Replay queued (${payload.command_id})`);
      void fetchHistory('refresh');
    } catch (replayError) {
      const message = replayError instanceof Error ? replayError.message : 'Failed to load data';
      toast.error(`Replay failed: ${message}`);
    } finally {
      setIsReplaying((prev) => {
        const next = new Set(prev);
        next.delete(command.id);
        return next;
      });
    }
  };

  const clearFilters = () => {
    setSearch('');
    setDeviceFilter('all');
    setMethodFilter('all');
    setActorFilter('all');
    setStateFilter('all');
    setDateFrom('');
    setDateTo('');
  };

  const hasFilters = search || deviceFilter !== 'all' || methodFilter !== 'all' || actorFilter !== 'all' || stateFilter !== 'all' || dateFrom || dateTo;

  return (
    <div className="space-y-4 fade-in">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">Command History</h1>
          <p className="text-sm text-muted-foreground mt-0.5">
            {filtered.length} of {history.length} commands - Searchable with one-click replay
          </p>
        </div>
        <div className="flex items-center gap-2">
          <button
            onClick={() => { void fetchHistory('refresh'); }}
            className="flex items-center gap-1.5 px-3 py-1.5 text-xs text-muted-foreground border border-border rounded-md hover:bg-muted/60 transition-colors"
          >
            <RefreshCw size={13} className={isRefreshing ? 'animate-spin' : ''} /> Refresh
          </button>
          <button
            onClick={() => toast.success('Exporting history...')}
            className="flex items-center gap-1.5 px-3 py-1.5 text-xs text-muted-foreground border border-border rounded-md hover:bg-muted/60 transition-colors"
          >
            <Download size={13} /> Export
          </button>
        </div>
      </div>

      {error && (
        <div className="bg-card border border-red-500/20 rounded-lg px-4 py-3 text-sm text-red-300">
          Failed to load data
        </div>
      )}

      <div className="bg-card border border-border rounded-lg p-4 space-y-3">
        <div className="flex items-center gap-2">
          <Filter size={13} className="text-muted-foreground" />
          <span className="text-xs font-semibold text-muted-foreground uppercase tracking-wide">Filters</span>
          {hasFilters && (
            <button onClick={clearFilters} className="flex items-center gap-1 text-xs text-muted-foreground hover:text-foreground transition-colors ml-auto">
              <X size={11} /> Clear all
            </button>
          )}
        </div>
        <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-2">
          <div className="relative col-span-2 md:col-span-1">
            <Search size={12} className="absolute left-2.5 top-1/2 -translate-y-1/2 text-muted-foreground" />
            <input
              type="text"
              placeholder="Search ID, device, method, actor..."
              value={search}
              onChange={(event) => setSearch(event.target.value)}
              className="w-full pl-7 pr-3 py-1.5 text-xs bg-muted/60 border border-border rounded-md text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-1 focus:ring-primary/50"
            />
          </div>
          <select value={deviceFilter} onChange={(event) => setDeviceFilter(event.target.value)} className="text-xs bg-muted/60 border border-border rounded-md px-2.5 py-1.5 text-foreground focus:outline-none focus:ring-1 focus:ring-primary/50">
            <option value="all">All Devices</option>
            {devices.map((device) => <option key={device} value={device}>{device}</option>)}
          </select>
          <select value={methodFilter} onChange={(event) => setMethodFilter(event.target.value)} className="text-xs bg-muted/60 border border-border rounded-md px-2.5 py-1.5 text-foreground focus:outline-none focus:ring-1 focus:ring-primary/50">
            <option value="all">All Commands</option>
            {methods.map((method) => <option key={method} value={method}>{method}</option>)}
          </select>
          <select value={actorFilter} onChange={(event) => setActorFilter(event.target.value)} className="text-xs bg-muted/60 border border-border rounded-md px-2.5 py-1.5 text-foreground focus:outline-none focus:ring-1 focus:ring-primary/50">
            <option value="all">All Actors</option>
            {actors.map((actor) => <option key={actor} value={actor}>{actor.split('@')[0]}</option>)}
          </select>
          <select value={stateFilter} onChange={(event) => setStateFilter(event.target.value)} className="text-xs bg-muted/60 border border-border rounded-md px-2.5 py-1.5 text-foreground focus:outline-none focus:ring-1 focus:ring-primary/50">
            <option value="all">All States</option>
            <option value="completed">Completed</option>
            <option value="failed">Failed</option>
            <option value="expired">Expired</option>
            <option value="rejected">Rejected</option>
          </select>
        </div>
      </div>

      <div className="bg-card border border-border rounded-lg overflow-hidden">
        <div className="overflow-x-auto scrollbar-thin">
          <table className="w-full text-xs">
            <thead>
              <tr className="border-b border-border bg-muted/20">
                {[
                  { key: 'id' as keyof HistoryCommand, label: 'Command ID' },
                  { key: 'hostname' as keyof HistoryCommand, label: 'Device' },
                  { key: 'method' as keyof HistoryCommand, label: 'Command' },
                  { key: 'state' as keyof HistoryCommand, label: 'State' },
                  { key: 'actor' as keyof HistoryCommand, label: 'Actor' },
                  { key: 'queuedAt' as keyof HistoryCommand, label: 'Queued At' },
                  { key: 'duration' as keyof HistoryCommand, label: 'Duration' },
                ].map((column) => (
                  <th
                    key={column.key}
                    className="px-3 py-3 text-left font-semibold text-muted-foreground tracking-wide uppercase text-[10px] cursor-pointer hover:text-foreground transition-colors whitespace-nowrap"
                    onClick={() => toggleSort(column.key)}
                  >
                    <span className="flex items-center gap-1">{column.label}<SortIcon k={column.key} /></span>
                  </th>
                ))}
                <th className="px-3 py-3 text-left font-semibold text-muted-foreground tracking-wide uppercase text-[10px] whitespace-nowrap">Result Preview</th>
                <th className="px-3 py-3 w-20" />
              </tr>
            </thead>
            <tbody className="divide-y divide-border">
              {isLoading ? (
                <tr>
                  <td colSpan={9} className="px-4 py-12 text-center">
                    <Loader2 size={32} className="mx-auto text-muted-foreground/30 mb-3 animate-spin" />
                    <p className="text-sm font-medium text-muted-foreground">Loading data...</p>
                  </td>
                </tr>
              ) : filtered.length === 0 ? (
                <tr>
                  <td colSpan={9} className="px-4 py-12 text-center">
                    <Terminal size={32} className="mx-auto text-muted-foreground/30 mb-3" />
                    <p className="text-sm font-medium text-muted-foreground">No data available</p>
                  </td>
                </tr>
              ) : filtered.map((command) => (
                <React.Fragment key={command.id}>
                  <tr
                    className={`hover:bg-muted/20 transition-colors cursor-pointer ${expandedId === command.id ? 'bg-muted/10' : ''}`}
                    onClick={() => setExpandedId(expandedId === command.id ? null : command.id)}
                  >
                    <td className="px-3 py-3 font-mono text-[11px] text-primary font-semibold">{command.id}</td>
                    <td className="px-3 py-3 font-mono text-[11px]">{command.hostname}</td>
                    <td className="px-3 py-3">
                      <span className="px-2 py-0.5 bg-muted/60 rounded text-[11px] font-mono">{command.method}</span>
                    </td>
                    <td className="px-3 py-3">
                      <div className="flex items-center gap-1.5">
                        {stateIcon(command.state)}
                        <StatusBadge variant={command.state} size="sm" />
                      </div>
                    </td>
                    <td className="px-3 py-3 text-[11px] text-muted-foreground max-w-[120px] truncate">{command.actor.split('@')[0]}</td>
                    <td className="px-3 py-3 text-[11px] text-muted-foreground tabular-nums whitespace-nowrap">{command.queuedAt}</td>
                    <td className="px-3 py-3 text-[11px] text-muted-foreground">{command.duration ?? '-'}</td>
                    <td className="px-3 py-3 text-[11px] text-muted-foreground max-w-[180px] truncate italic">
                      {command.resultPreview ?? (command.errorMessage ? <span className="text-red-400 not-italic">{command.errorMessage}</span> : '-')}
                    </td>
                    <td className="px-3 py-3">
                      <div className="flex items-center gap-1.5" onClick={(event) => event.stopPropagation()}>
                        {(command.state === 'completed' || command.state === 'failed') && (
                          <button
                            onClick={() => { void replayCommand(command); }}
                            disabled={isReplaying.has(command.id)}
                            title="Replay command"
                            className="flex items-center gap-1 px-2 py-1 text-[11px] bg-primary/10 border border-primary/20 text-primary rounded hover:bg-primary/20 transition-colors disabled:opacity-60"
                          >
                            {isReplaying.has(command.id) ? <Loader2 size={10} className="animate-spin" /> : <RotateCcw size={10} />} Replay
                          </button>
                        )}
                      </div>
                    </td>
                  </tr>
                  {expandedId === command.id && (
                    <tr className="bg-muted/10">
                      <td colSpan={9} className="px-4 py-4">
                        <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
                          <div className="bg-muted/30 rounded-lg p-3">
                            <p className="text-[10px] text-muted-foreground uppercase tracking-wide mb-1">Trace ID</p>
                            <p className="text-xs font-mono">{command.traceId}</p>
                          </div>
                          <div className="bg-muted/30 rounded-lg p-3">
                            <p className="text-[10px] text-muted-foreground uppercase tracking-wide mb-1">Device ID</p>
                            <p className="text-xs font-mono">{command.deviceId}</p>
                          </div>
                          <div className="bg-muted/30 rounded-lg p-3">
                            <p className="text-[10px] text-muted-foreground uppercase tracking-wide mb-1">Priority</p>
                            <p className="text-xs font-semibold capitalize">{command.priority}</p>
                          </div>
                          <div className="bg-muted/30 rounded-lg p-3">
                            <p className="text-[10px] text-muted-foreground uppercase tracking-wide mb-1">Batch ID</p>
                            <p className="text-xs font-mono">{command.batchId ?? '-'}</p>
                          </div>
                          {command.completedAt && (
                            <div className="bg-muted/30 rounded-lg p-3">
                              <p className="text-[10px] text-muted-foreground uppercase tracking-wide mb-1">Completed At</p>
                              <p className="text-xs font-mono">{command.completedAt}</p>
                            </div>
                          )}
                          {command.resultPreview && (
                            <div className="bg-muted/30 rounded-lg p-3 col-span-2">
                              <p className="text-[10px] text-muted-foreground uppercase tracking-wide mb-1">Result Summary</p>
                              <p className="text-xs">{command.resultPreview}</p>
                            </div>
                          )}
                          {command.errorMessage && (
                            <div className="bg-red-500/10 border border-red-500/20 rounded-lg p-3 col-span-2">
                              <p className="text-[10px] text-red-400 uppercase tracking-wide mb-1">Error</p>
                              <p className="text-xs text-red-400">{command.errorMessage}</p>
                            </div>
                          )}
                        </div>
                        <div className="flex items-center gap-2 mt-3">
                          <button
                            onClick={() => { void replayCommand(command); }}
                            disabled={isReplaying.has(command.id)}
                            className="flex items-center gap-1.5 px-3 py-1.5 text-xs bg-primary/10 border border-primary/20 text-primary rounded-md hover:bg-primary/20 transition-colors disabled:opacity-60"
                          >
                            {isReplaying.has(command.id) ? <Loader2 size={11} className="animate-spin" /> : <RotateCcw size={11} />} Replay Command
                          </button>
                          <button
                            onClick={async () => {
                              await navigator.clipboard.writeText(command.id);
                              toast.success('Command ID copied');
                            }}
                            className="flex items-center gap-1.5 px-3 py-1.5 text-xs text-muted-foreground border border-border rounded-md hover:bg-muted/60 transition-colors"
                          >
                            <Copy size={11} /> Copy ID
                          </button>
                        </div>
                      </td>
                    </tr>
                  )}
                </React.Fragment>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}

