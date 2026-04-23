'use client';

import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  Plus,
  Search,
  RefreshCw,
  ChevronUp,
  ChevronDown,
  Eye,
  RotateCcw,
  X,
  Terminal,
  CheckSquare,
  Square,
  Loader2,
} from 'lucide-react';
import StatusBadge from '@/components/ui/StatusBadge';
import CommandDetailPanel from './CommandDetailPanel';
import DispatchCommandModal from './DispatchCommandModal';
import { toast } from 'sonner';
import {
  mapCommandListRow,
  originChannelLabel,
  type CommandListRowApi,
  type CommandOriginChannel,
} from '@/lib/commandResults';
import { formatLocalTime } from '@/lib/dateTime';
import { resolveCommandMethod } from '@/lib/commandMethodResolver';

type CommandState = 'queued' | 'dispatched' | 'ack_received' | 'executing' | 'completed' | 'failed' | 'expired' | 'rejected';

interface Command {
  id: string;
  traceId: string;
  deviceId: string;
  hostname: string;
  method: string;
  state: CommandState;
  actor: string;
  originChannel: CommandOriginChannel;
  queuedAt: string;
  queuedAtIso: string | null;
  dispatchedAt: string | null;
  dispatchedAtIso: string | null;
  ackAt: string | null;
  ackAtIso: string | null;
  completedAt: string | null;
  completedAtIso: string | null;
  errorCode: number | null;
  errorMessage: string | null;
  reason: string | null;
  priority: 'normal' | 'high';
  requires2fa: boolean;
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

const stateTabs: { key: string; label: string; states: CommandState[] }[] = [
  { key: 'all', label: 'All', states: ['queued', 'dispatched', 'ack_received', 'executing', 'completed', 'failed', 'expired', 'rejected'] },
  { key: 'active', label: 'Active', states: ['queued', 'dispatched', 'ack_received', 'executing'] },
  { key: 'completed', label: 'Completed', states: ['completed'] },
  { key: 'failed', label: 'Failed', states: ['failed', 'expired', 'rejected'] },
];

type SortKey =
  | 'id'
  | 'hostname'
  | 'method'
  | 'state'
  | 'actor'
  | 'originChannel'
  | 'queuedAt'
  | 'ackAt'
  | 'completedAt';

function parseTimeMs(value: string | null | undefined): number {
  if (!value) return 0;
  const parsed = Date.parse(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function toCommand(rowApi: CommandListRowApi): Command {
  const row = mapCommandListRow(rowApi);
  const ackAtIso = typeof (rowApi as { ack_at?: string | null }).ack_at === 'string'
    ? (rowApi as { ack_at?: string | null }).ack_at ?? null
    : null;
  const priority = String((rowApi as { priority?: unknown }).priority ?? '').toLowerCase() === 'high' ? 'high' : 'normal';
  const requires2fa = Boolean((rowApi as { requires_2fa?: unknown }).requires_2fa ?? (rowApi as { requires2fa?: unknown }).requires2fa ?? false);

  return {
    id: row.commandId,
    traceId: row.traceId ?? '-',
    deviceId: row.deviceId,
    hostname: row.deviceName || row.deviceId,
    method: row.method,
    state: row.state,
    actor: row.actorEmail,
    originChannel: row.originChannel,
    queuedAt: formatLocalTime(row.queuedAt, '-'),
    queuedAtIso: row.queuedAt,
    dispatchedAt: row.dispatchedAt ? formatLocalTime(row.dispatchedAt, '-') : null,
    dispatchedAtIso: row.dispatchedAt,
    ackAt: ackAtIso ? formatLocalTime(ackAtIso, '-') : null,
    ackAtIso,
    completedAt: row.completedAt ? formatLocalTime(row.completedAt, '-') : null,
    completedAtIso: row.completedAt,
    errorCode: row.errorCode,
    errorMessage: row.errorMessage,
    reason: row.reason,
    priority,
    requires2fa,
    params: row.params ?? {},
  };
}

function sortCommands(items: Command[], sortKey: SortKey, sortDir: 'asc' | 'desc'): Command[] {
  const sorted = [...items];
  sorted.sort((a, b) => {
    const direction = sortDir === 'asc' ? 1 : -1;
    if (sortKey === 'queuedAt' || sortKey === 'ackAt' || sortKey === 'completedAt') {
      const aIso = sortKey === 'queuedAt' ? a.queuedAtIso : sortKey === 'ackAt' ? a.ackAtIso : a.completedAtIso;
      const bIso = sortKey === 'queuedAt' ? b.queuedAtIso : sortKey === 'ackAt' ? b.ackAtIso : b.completedAtIso;
      return (parseTimeMs(aIso) - parseTimeMs(bIso)) * direction;
    }
    const av = String(a[sortKey] ?? '');
    const bv = String(b[sortKey] ?? '');
    return av.localeCompare(bv) * direction;
  });
  return sorted;
}

export default function CommandDispatchContent() {
  const [activeTab, setActiveTab] = useState('all');
  const [search, setSearch] = useState('');
  const [sourceFilter, setSourceFilter] = useState<'all' | CommandOriginChannel>('all');
  const [sortKey, setSortKey] = useState<SortKey>('queuedAt');
  const [sortDir, setSortDir] = useState<'asc' | 'desc'>('desc');
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());
  const [detailCommand, setDetailCommand] = useState<Command | null>(null);
  const [showDispatchModal, setShowDispatchModal] = useState(false);
  const [currentPage, setCurrentPage] = useState(1);

  const [commands, setCommands] = useState<Command[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [isRetrying, setIsRetrying] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [refreshNonce, setRefreshNonce] = useState(0);

  const listAbortRef = useRef<AbortController | null>(null);

  const pageSize = 8;
  const allowedStates = stateTabs.find((tab) => tab.key === activeTab)?.states ?? [];

  const fetchCommands = useCallback(async (mode: 'initial' | 'refresh' | 'silent' = 'initial') => {
    if (mode === 'initial') setIsLoading(true);
    if (mode === 'refresh') setIsRefreshing(true);

    listAbortRef.current?.abort();
    const controller = new AbortController();
    listAbortRef.current = controller;

    try {
      const response = await fetch('/api/commands?limit=200', {
        credentials: 'include',
        cache: 'no-store',
        signal: controller.signal,
      });
      if (!response.ok) {
        throw new Error(`http_${response.status}`);
      }

      const payload = (await response.json()) as CommandsApiResponse;
      const mapped = (payload.commands ?? [])
        .map(toCommand)
        .sort((a, b) => parseTimeMs(b.queuedAtIso) - parseTimeMs(a.queuedAtIso));
      setCommands(mapped);
      setSelectedIds((prev) => new Set([...prev].filter((id) => mapped.some((command) => command.id === id))));
      setError(null);
    } catch (fetchError) {
      if ((fetchError as Error).name === 'AbortError') return;
      console.error('command-dispatch-load-failed', fetchError);
      setError('Failed to load data');
      if (mode === 'initial') setCommands([]);
    } finally {
      if (mode === 'initial') setIsLoading(false);
      if (mode === 'refresh') setIsRefreshing(false);
    }
  }, []);

  useEffect(() => {
    void fetchCommands('initial');
  }, [fetchCommands, refreshNonce]);

  useEffect(() => {
    let interval: ReturnType<typeof setInterval> | null = null;
    const startPolling = () => {
      if (interval) clearInterval(interval);
      const pollMs = document.visibilityState === 'visible' ? 10000 : 30000;
      interval = setInterval(() => {
        void fetchCommands('silent');
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
  }, [fetchCommands]);

  const filtered = useMemo(() => {
    const lowered = search.trim().toLowerCase();
    const stateFiltered = commands.filter((command) => allowedStates.includes(command.state));
    const searchFiltered = stateFiltered.filter((command) => (
      !lowered
      || command.id.toLowerCase().includes(lowered)
      || command.hostname.toLowerCase().includes(lowered)
      || command.method.toLowerCase().includes(lowered)
      || command.actor.toLowerCase().includes(lowered)
    ));
    const sourceFiltered = sourceFilter === 'all'
      ? searchFiltered
      : searchFiltered.filter((command) => command.originChannel === sourceFilter);
    return sortCommands(sourceFiltered, sortKey, sortDir);
  }, [activeTab, allowedStates, commands, search, sourceFilter, sortKey, sortDir]);

  const sources = useMemo(
    () => Array.from(new Set(commands.map((command) => command.originChannel))).sort(),
    [commands],
  );

  const totalPages = Math.max(1, Math.ceil(filtered.length / pageSize));
  const paginatedData = filtered.slice((currentPage - 1) * pageSize, currentPage * pageSize);

  useEffect(() => {
    if (currentPage > totalPages) setCurrentPage(totalPages);
  }, [currentPage, totalPages]);

  const toggleSort = (key: SortKey) => {
    if (sortKey === key) setSortDir(sortDir === 'asc' ? 'desc' : 'asc');
    else {
      setSortKey(key);
      setSortDir(key === 'queuedAt' ? 'desc' : 'asc');
    }
  };

  const toggleSelect = (id: string) => {
    setSelectedIds((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  };

  const dispatchRetry = useCallback(async (command: Command): Promise<boolean> => {
    try {
      const response = await fetch('/api/commands', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        credentials: 'include',
        body: JSON.stringify({
          client_message_id: `command-dispatch-retry-${command.deviceId}-${command.method}-${crypto.randomUUID()}`,
          device_id: command.deviceId,
          method: resolveCommandMethod(command.method),
          params: command.params ?? {},
          sensitive: command.priority === 'high' || command.requires2fa,
        }),
      });
      const payload = (await response.json().catch(() => ({}))) as DispatchResponse;
      return Boolean(response.ok && payload.command_id);
    } catch (retryError) {
      console.error('command-dispatch-retry-failed', retryError);
      return false;
    }
  }, []);

  const retrySelected = async () => {
    if (selectedIds.size === 0) return;
    setIsRetrying(true);
    const selected = commands.filter((command) => selectedIds.has(command.id));
    const results = await Promise.all(selected.map((command) => dispatchRetry(command)));
    const successCount = results.filter(Boolean).length;
    const failCount = results.length - successCount;
    if (successCount > 0) toast.success(`Retried ${successCount} command${successCount === 1 ? '' : 's'}`);
    if (failCount > 0) toast.error(`Failed to retry ${failCount} command${failCount === 1 ? '' : 's'}`);
    setSelectedIds(new Set());
    setIsRetrying(false);
    void fetchCommands('refresh');
  };

  const retrySingle = async (command: Command) => {
    const ok = await dispatchRetry(command);
    if (ok) toast.success(`Retry queued for ${command.id}`);
    else toast.error(`Retry failed for ${command.id}`);
    void fetchCommands('refresh');
  };

  const SortIcon = ({ k }: { k: SortKey }) => (
    sortKey === k
      ? (
        sortDir === 'asc'
          ? <ChevronUp size={12} className="text-primary" />
          : <ChevronDown size={12} className="text-primary" />
      )
      : <ChevronUp size={12} className="text-muted-foreground/40" />
  );

  const tabCounts: Record<string, number> = {
    all: commands.length,
    active: commands.filter((command) => ['queued', 'dispatched', 'ack_received', 'executing'].includes(command.state)).length,
    completed: commands.filter((command) => command.state === 'completed').length,
    failed: commands.filter((command) => ['failed', 'expired', 'rejected'].includes(command.state)).length,
  };

  return (
    <div className="space-y-4 fade-in">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">Command Dispatch</h1>
          <p className="text-sm text-muted-foreground mt-0.5">Command lifecycle across all managed devices</p>
        </div>
        <button
          onClick={() => setShowDispatchModal(true)}
          className="flex items-center gap-2 px-3 py-2 text-sm font-medium bg-primary text-primary-foreground rounded-md hover:bg-primary/90 active:scale-95 transition-all duration-150"
        >
          <Plus size={15} />
          Dispatch Command
        </button>
      </div>

      {error && (
        <div className="bg-card border border-red-500/20 rounded-lg px-4 py-3 text-sm text-red-300">
          Failed to load data
        </div>
      )}

      <div className="flex items-center gap-1 bg-muted/30 rounded-lg p-1 w-fit">
        {stateTabs.map((tab) => (
          <button
            key={`cmd-tab-${tab.key}`}
            onClick={() => { setActiveTab(tab.key); setCurrentPage(1); }}
            className={`flex items-center gap-1.5 px-3 py-1.5 rounded-md text-xs font-medium transition-all ${
              activeTab === tab.key
                ? 'bg-card text-foreground shadow-sm'
                : 'text-muted-foreground hover:text-foreground'
            }`}
          >
            {tab.label}
            <span className={`text-[10px] px-1.5 py-0.5 rounded-full tabular-nums ${
              activeTab === tab.key ? 'bg-primary/20 text-primary' : 'bg-muted text-muted-foreground'
            }`}>
              {tabCounts[tab.key] ?? 0}
            </span>
          </button>
        ))}
      </div>

      <div className="flex items-center gap-2">
        <div className="relative flex-1 max-w-sm">
          <Search size={13} className="absolute left-2.5 top-1/2 -translate-y-1/2 text-muted-foreground" />
          <input
            type="text"
            placeholder="Search command ID, device, method, actor..."
            value={search}
            onChange={(event) => { setSearch(event.target.value); setCurrentPage(1); }}
            className="w-full pl-8 pr-3 py-1.5 text-xs bg-muted/60 border border-border rounded-md text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-1 focus:ring-primary/50"
          />
        </div>
        <select
          value={sourceFilter}
          onChange={(event) => {
            setSourceFilter(event.target.value as 'all' | CommandOriginChannel);
            setCurrentPage(1);
          }}
          className="text-xs bg-muted/60 border border-border rounded-md px-2.5 py-1.5 text-foreground focus:outline-none focus:ring-1 focus:ring-primary/50"
        >
          <option value="all">All Sources</option>
          {sources.map((source) => (
            <option key={source} value={source}>{originChannelLabel(source)}</option>
          ))}
        </select>
        <button
          onClick={() => {
            void fetchCommands('refresh');
          }}
          className="flex items-center gap-1.5 px-3 py-1.5 text-xs text-muted-foreground border border-border rounded-md hover:bg-muted/60 transition-colors"
        >
          <RefreshCw size={13} className={isRefreshing ? 'animate-spin' : ''} />
        </button>
      </div>

      {selectedIds.size > 0 && (
        <div className="flex items-center gap-3 px-4 py-2.5 bg-primary/10 border border-primary/20 rounded-lg text-sm slide-in-right">
          <span className="text-primary font-medium">{selectedIds.size} selected</span>
          <button
            onClick={() => { void retrySelected(); }}
            disabled={isRetrying}
            className="flex items-center gap-1.5 px-2.5 py-1 text-xs bg-blue-500/10 border border-blue-500/20 text-blue-400 rounded-md hover:bg-blue-500/20 transition-colors disabled:opacity-60"
          >
            {isRetrying ? <Loader2 size={11} className="animate-spin" /> : <RotateCcw size={11} />} Retry All
          </button>
          <button onClick={() => setSelectedIds(new Set())} className="ml-auto text-muted-foreground hover:text-foreground">
            <X size={13} />
          </button>
        </div>
      )}

      <div className="bg-card border border-border rounded-lg overflow-hidden">
        <div className="overflow-x-auto scrollbar-thin">
          <table className="w-full text-xs">
            <thead>
              <tr className="border-b border-border bg-muted/20">
                <th className="w-10 px-3 py-3">
                  <button
                    onClick={() => {
                      if (selectedIds.size === paginatedData.length) setSelectedIds(new Set());
                      else setSelectedIds(new Set(paginatedData.map((command) => command.id)));
                    }}
                    className="text-muted-foreground hover:text-foreground transition-colors"
                  >
                    {selectedIds.size === paginatedData.length && paginatedData.length > 0
                      ? <CheckSquare size={14} className="text-primary" />
                      : <Square size={14} />}
                  </button>
                </th>
                {[
                  { key: 'id' as SortKey, label: 'Command ID' },
                  { key: 'hostname' as SortKey, label: 'Device' },
                  { key: 'method' as SortKey, label: 'Method' },
                  { key: 'state' as SortKey, label: 'State' },
                  { key: 'actor' as SortKey, label: 'Actor' },
                  { key: 'originChannel' as SortKey, label: 'Source' },
                  { key: 'queuedAt' as SortKey, label: 'Queued' },
                  { key: 'ackAt' as SortKey, label: 'ACK' },
                  { key: 'completedAt' as SortKey, label: 'Completed' },
                ].map((column) => (
                  <th
                    key={`ccol-${column.key}`}
                    className="px-3 py-3 text-left font-semibold text-muted-foreground tracking-wide uppercase text-[10px] cursor-pointer hover:text-foreground transition-colors whitespace-nowrap"
                    onClick={() => toggleSort(column.key)}
                  >
                    <span className="flex items-center gap-1">
                      {column.label}
                      <SortIcon k={column.key} />
                    </span>
                  </th>
                ))}
                <th className="px-3 py-3 text-left font-semibold text-muted-foreground tracking-wide uppercase text-[10px] whitespace-nowrap">
                  Error
                </th>
                <th className="px-3 py-3 w-16" />
              </tr>
            </thead>
            <tbody className="divide-y divide-border">
              {isLoading ? (
                <tr>
                  <td colSpan={12} className="px-4 py-12 text-center">
                    <Loader2 size={32} className="mx-auto text-muted-foreground/30 mb-3 animate-spin" />
                    <p className="text-sm font-medium text-muted-foreground">Loading data...</p>
                  </td>
                </tr>
              ) : paginatedData.length === 0 ? (
                <tr>
                  <td colSpan={12} className="px-4 py-12 text-center">
                    <Terminal size={32} className="mx-auto text-muted-foreground/30 mb-3" />
                    <p className="text-sm font-medium text-muted-foreground">No data available</p>
                    <p className="text-xs text-muted-foreground/60 mt-1">Commands will appear here as they are dispatched</p>
                  </td>
                </tr>
              ) : (
                paginatedData.map((command) => (
                  <tr
                    key={`cmd-row-${command.id}`}
                    className={`group hover:bg-muted/30 transition-colors cursor-pointer ${selectedIds.has(command.id) ? 'bg-primary/5' : ''}`}
                    onClick={() => setDetailCommand(command)}
                  >
                    <td className="px-3 py-3" onClick={(event) => { event.stopPropagation(); toggleSelect(command.id); }}>
                      <button className="text-muted-foreground hover:text-foreground transition-colors">
                        {selectedIds.has(command.id) ? <CheckSquare size={14} className="text-primary" /> : <Square size={14} />}
                      </button>
                    </td>
                    <td className="px-3 py-3 font-mono text-[11px] text-muted-foreground whitespace-nowrap">{command.id}</td>
                    <td className="px-3 py-3 font-medium whitespace-nowrap">{command.hostname}</td>
                    <td className="px-3 py-3 font-mono text-[11px] text-blue-400 whitespace-nowrap">{command.method}</td>
                    <td className="px-3 py-3 whitespace-nowrap">
                      <StatusBadge variant={command.state} pulse={command.state === 'executing' || command.state === 'dispatched'} />
                    </td>
                    <td className="px-3 py-3 text-muted-foreground max-w-[140px] truncate">{command.actor}</td>
                    <td className="px-3 py-3 text-[11px] whitespace-nowrap">
                      <span className="px-2 py-0.5 rounded bg-muted/60 text-muted-foreground">
                        {originChannelLabel(command.originChannel)}
                      </span>
                    </td>
                    <td className="px-3 py-3 tabular-nums text-muted-foreground whitespace-nowrap">{command.queuedAt}</td>
                    <td className="px-3 py-3 tabular-nums text-muted-foreground whitespace-nowrap">{command.ackAt ?? '-'}</td>
                    <td className="px-3 py-3 tabular-nums text-muted-foreground whitespace-nowrap">{command.completedAt ?? '-'}</td>
                    <td className="px-3 py-3 max-w-[160px]">
                      {command.errorCode != null && (
                        <span className="font-mono text-[10px] text-red-400 bg-red-500/10 px-1.5 py-0.5 rounded">
                          {command.errorCode}
                        </span>
                      )}
                      {!command.errorCode && (command.errorMessage || command.reason) && (
                        <span className="text-[11px] text-amber-400 truncate block">{command.errorMessage ?? command.reason}</span>
                      )}
                    </td>
                    <td className="px-3 py-3">
                      <div className="flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
                        <button
                          onClick={(event) => { event.stopPropagation(); setDetailCommand(command); }}
                          className="p-1 rounded text-muted-foreground hover:text-foreground hover:bg-muted transition-colors"
                          title="View command detail"
                        >
                          <Eye size={13} />
                        </button>
                        {(command.state === 'failed' || command.state === 'expired') && (
                          <button
                            onClick={(event) => {
                              event.stopPropagation();
                              void retrySingle(command);
                            }}
                            className="p-1 rounded text-muted-foreground hover:text-blue-400 hover:bg-blue-500/10 transition-colors"
                            title="Retry command"
                          >
                            <RotateCcw size={13} />
                          </button>
                        )}
                      </div>
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>

        {filtered.length > 0 && (
          <div className="flex items-center justify-between px-4 py-3 border-t border-border">
            <p className="text-xs text-muted-foreground">
              Showing {(currentPage - 1) * pageSize + 1}-{Math.min(currentPage * pageSize, filtered.length)} of {filtered.length} commands
            </p>
            <div className="flex items-center gap-1">
              {Array.from({ length: totalPages }, (_, index) => index + 1).map((page) => (
                <button
                  key={`cmdpage-${page}`}
                  onClick={() => setCurrentPage(page)}
                  className={`w-7 h-7 text-xs rounded transition-colors ${
                    currentPage === page
                      ? 'bg-primary text-primary-foreground font-semibold'
                      : 'text-muted-foreground hover:bg-muted hover:text-foreground'
                  }`}
                >
                  {page}
                </button>
              ))}
            </div>
          </div>
        )}
      </div>

      {detailCommand && (
        <CommandDetailPanel
          command={detailCommand}
          onClose={() => setDetailCommand(null)}
          onRetry={async () => {
            await retrySingle(detailCommand);
          }}
        />
      )}

      {showDispatchModal && (
        <DispatchCommandModal
          onClose={() => {
            setShowDispatchModal(false);
            setRefreshNonce((value) => value + 1);
          }}
        />
      )}
    </div>
  );
}


