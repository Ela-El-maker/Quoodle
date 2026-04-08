'use client';
import React, { useState, useMemo } from 'react';
import { Search, RefreshCw, RotateCcw, X, Terminal, CheckCircle, XCircle, Clock, ChevronDown, ChevronUp, Copy, Download, Filter } from 'lucide-react';
import { toast } from 'sonner';
import StatusBadge from '@/components/ui/StatusBadge';

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
  completedAt: string | null;
  duration: string | null;
  errorMessage: string | null;
  priority: 'normal' | 'high';
  batchId: string | null;
  resultPreview: string | null;
  resultType: string | null;
}

const mockHistory: HistoryCommand[] = [
  { id: 'CMD-7742', traceId: 'TRACE-7742', deviceId: 'WKSTN-055', hostname: 'WKSTN-055', method: 'system-info', state: 'completed', actor: 'chloe.dubois@quoodle.io', queuedAt: '2026-04-05 21:06:01', completedAt: '2026-04-05 21:06:09', duration: '8s', errorMessage: null, priority: 'normal', batchId: 'BATCH-001', resultPreview: 'Windows 11 Pro 22H2 · 12-core · 32GB RAM · 512GB disk', resultType: 'system-info' },
  { id: 'CMD-7741', traceId: 'TRACE-7741', deviceId: 'WKSTN-042', hostname: 'WKSTN-042', method: 'lock_screen', state: 'failed', actor: 'raj.mehta@quoodle.io', queuedAt: '2026-04-05 21:01:55', completedAt: '2026-04-05 21:01:58', duration: '3s', errorMessage: 'Kernel opcode not supported', priority: 'normal', batchId: null, resultPreview: null, resultType: null },
  { id: 'CMD-7740', traceId: 'TRACE-7740', deviceId: 'WKSTN-042', hostname: 'WKSTN-042', method: 'screenshot-capture', state: 'completed', actor: 'admin@quoodle.io', queuedAt: '2026-04-05 21:04:50', completedAt: '2026-04-05 21:04:54', duration: '4s', errorMessage: null, priority: 'normal', batchId: null, resultPreview: '1920×1080 PNG · 2.4 MB', resultType: 'screenshot-capture' },
  { id: 'CMD-7739', traceId: 'TRACE-7739', deviceId: 'WKSTN-088', hostname: 'WKSTN-088', method: 'process-list', state: 'completed', actor: 'ops.team@quoodle.io', queuedAt: '2026-04-05 21:05:40', completedAt: '2026-04-05 21:05:48', duration: '8s', errorMessage: null, priority: 'normal', batchId: 'BATCH-003', resultPreview: '142 processes · 8 high-CPU · 3 suspicious', resultType: 'process-list' },
  { id: 'CMD-7738', traceId: 'TRACE-7738', deviceId: 'SRV-PROD-01', hostname: 'SRV-PROD-01', method: 'ping', state: 'expired', actor: 'devops@quoodle.io', queuedAt: '2026-04-05 20:55:00', completedAt: null, duration: null, errorMessage: 'TTL exceeded — dispatch timeout', priority: 'normal', batchId: null, resultPreview: null, resultType: null },
  { id: 'CMD-7737', traceId: 'TRACE-7737', deviceId: 'WKSTN-001', hostname: 'WKSTN-001', method: 'filesystem', state: 'completed', actor: 'sarah.chen@quoodle.io', queuedAt: '2026-04-05 21:03:10', completedAt: '2026-04-05 21:03:18', duration: '8s', errorMessage: null, priority: 'normal', batchId: null, resultPreview: 'C:\\ · 512 GB · 187 GB used · 4 dirs scanned', resultType: 'filesystem' },
  { id: 'CMD-7736', traceId: 'TRACE-7736', deviceId: 'WKSTN-019', hostname: 'WKSTN-019', method: 'network-info', state: 'completed', actor: 'alex.kumar@quoodle.io', queuedAt: '2026-04-05 20:45:00', completedAt: '2026-04-05 20:45:06', duration: '6s', errorMessage: null, priority: 'high', batchId: null, resultPreview: '3 interfaces · IPv4 10.0.1.29 · DNS 8.8.8.8', resultType: 'network-info' },
  { id: 'CMD-7735', traceId: 'TRACE-7735', deviceId: 'PC002', hostname: 'WKSTN-002', method: 'installed-apps', state: 'completed', actor: 'james.wright@quoodle.io', queuedAt: '2026-04-05 20:58:00', completedAt: '2026-04-05 20:58:12', duration: '12s', errorMessage: null, priority: 'normal', batchId: 'BATCH-004', resultPreview: '247 apps · 12 outdated · 2 flagged', resultType: 'installed-apps' },
  { id: 'CMD-7734', traceId: 'TRACE-7734', deviceId: 'WKSTN-103', hostname: 'WKSTN-103', method: 'event-logs', state: 'completed', actor: 'yuki.tanaka@quoodle.io', queuedAt: '2026-04-05 20:52:00', completedAt: '2026-04-05 20:52:18', duration: '18s', errorMessage: null, priority: 'normal', batchId: null, resultPreview: '1,024 events · 14 errors · 3 critical', resultType: 'event-logs' },
  { id: 'CMD-7733', traceId: 'TRACE-7733', deviceId: 'WKSTN-007', hostname: 'WKSTN-007', method: 'hardware-info', state: 'completed', actor: 'ops.team@quoodle.io', queuedAt: '2026-04-05 20:40:00', completedAt: '2026-04-05 20:40:09', duration: '9s', errorMessage: null, priority: 'normal', batchId: null, resultPreview: 'Intel i5-11400 · 16GB DDR4 · NVIDIA RTX 3060', resultType: 'hardware-info' },
  { id: 'CMD-7732', traceId: 'TRACE-7732', deviceId: 'WKSTN-055', hostname: 'WKSTN-055', method: 'performance-metrics', state: 'completed', actor: 'chloe.dubois@quoodle.io', queuedAt: '2026-04-05 20:30:00', completedAt: '2026-04-05 20:30:07', duration: '7s', errorMessage: null, priority: 'normal', batchId: 'BATCH-001', resultPreview: 'CPU 12% · RAM 45% · Disk I/O 8 MB/s', resultType: 'performance-metrics' },
  { id: 'CMD-7731', traceId: 'TRACE-7731', deviceId: 'WKSTN-001', hostname: 'WKSTN-001', method: 'services-list', state: 'completed', actor: 'sarah.chen@quoodle.io', queuedAt: '2026-04-05 20:20:00', completedAt: '2026-04-05 20:20:11', duration: '11s', errorMessage: null, priority: 'normal', batchId: null, resultPreview: '312 services · 248 running · 4 stopped', resultType: 'services-list' },
  { id: 'CMD-7730', traceId: 'TRACE-7730', deviceId: 'SRV-PROD-01', hostname: 'SRV-PROD-01', method: 'users-list', state: 'rejected', actor: 'devops@quoodle.io', queuedAt: '2026-04-05 20:10:00', completedAt: null, duration: null, errorMessage: 'Policy evaluation: role authorization denied', priority: 'normal', batchId: null, resultPreview: null, resultType: null },
];

const ACTORS = Array.from(new Set(mockHistory.map(c => c.actor)));
const DEVICES = Array.from(new Set(mockHistory.map(c => c.hostname)));
const METHODS = Array.from(new Set(mockHistory.map(c => c.method)));

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

  const filtered = useMemo(() => {
    let data = mockHistory.filter(c => {
      const matchSearch = !search || c.id.toLowerCase().includes(search.toLowerCase()) || c.hostname.toLowerCase().includes(search.toLowerCase()) || c.method.toLowerCase().includes(search.toLowerCase()) || c.actor.toLowerCase().includes(search.toLowerCase()) || c.traceId.toLowerCase().includes(search.toLowerCase());
      const matchDevice = deviceFilter === 'all' || c.hostname === deviceFilter;
      const matchMethod = methodFilter === 'all' || c.method === methodFilter;
      const matchActor = actorFilter === 'all' || c.actor === actorFilter;
      const matchState = stateFilter === 'all' || c.state === stateFilter;
      return matchSearch && matchDevice && matchMethod && matchActor && matchState;
    });
    data.sort((a, b) => {
      const av = a[sortKey] ?? '';
      const bv = b[sortKey] ?? '';
      if (typeof av === 'string' && typeof bv === 'string') return sortDir === 'asc' ? av.localeCompare(bv) : bv.localeCompare(av);
      return 0;
    });
    return data;
  }, [search, deviceFilter, methodFilter, actorFilter, stateFilter, sortKey, sortDir]);

  const toggleSort = (key: keyof HistoryCommand) => {
    if (sortKey === key) setSortDir(d => d === 'asc' ? 'desc' : 'asc');
    else { setSortKey(key); setSortDir('desc'); }
  };

  const SortIcon = ({ k }: { k: keyof HistoryCommand }) =>
    sortKey === k ? (sortDir === 'asc' ? <ChevronUp size={11} className="text-primary" /> : <ChevronDown size={11} className="text-primary" />) : <ChevronUp size={11} className="text-muted-foreground/30" />;

  const stateIcon = (s: CommandState) => {
    if (s === 'completed') return <CheckCircle size={12} className="text-green-400 flex-shrink-0" />;
    if (s === 'failed' || s === 'expired' || s === 'rejected') return <XCircle size={12} className="text-red-400 flex-shrink-0" />;
    return <Clock size={12} className="text-amber-400 flex-shrink-0" />;
  };

  const replayCommand = (cmd: HistoryCommand) => {
    toast.promise(
      new Promise(resolve => setTimeout(resolve, 1000)),
      { loading: `Re-dispatching ${cmd.method} to ${cmd.hostname}…`, success: `Command replayed — new ID assigned`, error: 'Replay failed' }
    );
  };

  const clearFilters = () => {
    setSearch(''); setDeviceFilter('all'); setMethodFilter('all');
    setActorFilter('all'); setStateFilter('all'); setDateFrom(''); setDateTo('');
  };

  const hasFilters = search || deviceFilter !== 'all' || methodFilter !== 'all' || actorFilter !== 'all' || stateFilter !== 'all' || dateFrom || dateTo;

  return (
    <div className="space-y-4 fade-in">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">Command History</h1>
          <p className="text-sm text-muted-foreground mt-0.5">
            {filtered.length} of {mockHistory.length} commands · Searchable with one-click replay
          </p>
        </div>
        <div className="flex items-center gap-2">
          <button onClick={() => toast.info('History refreshed')} className="flex items-center gap-1.5 px-3 py-1.5 text-xs text-muted-foreground border border-border rounded-md hover:bg-muted/60 transition-colors">
            <RefreshCw size={13} /> Refresh
          </button>
          <button onClick={() => toast.success('Exporting history…')} className="flex items-center gap-1.5 px-3 py-1.5 text-xs text-muted-foreground border border-border rounded-md hover:bg-muted/60 transition-colors">
            <Download size={13} /> Export
          </button>
        </div>
      </div>

      {/* Filters */}
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
              placeholder="Search ID, device, method, actor…"
              value={search}
              onChange={e => setSearch(e.target.value)}
              className="w-full pl-7 pr-3 py-1.5 text-xs bg-muted/60 border border-border rounded-md text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-1 focus:ring-primary/50"
            />
          </div>
          <select value={deviceFilter} onChange={e => setDeviceFilter(e.target.value)} className="text-xs bg-muted/60 border border-border rounded-md px-2.5 py-1.5 text-foreground focus:outline-none focus:ring-1 focus:ring-primary/50">
            <option value="all">All Devices</option>
            {DEVICES.map(d => <option key={d} value={d}>{d}</option>)}
          </select>
          <select value={methodFilter} onChange={e => setMethodFilter(e.target.value)} className="text-xs bg-muted/60 border border-border rounded-md px-2.5 py-1.5 text-foreground focus:outline-none focus:ring-1 focus:ring-primary/50">
            <option value="all">All Commands</option>
            {METHODS.map(m => <option key={m} value={m}>{m}</option>)}
          </select>
          <select value={actorFilter} onChange={e => setActorFilter(e.target.value)} className="text-xs bg-muted/60 border border-border rounded-md px-2.5 py-1.5 text-foreground focus:outline-none focus:ring-1 focus:ring-primary/50">
            <option value="all">All Actors</option>
            {ACTORS.map(a => <option key={a} value={a}>{a.split('@')[0]}</option>)}
          </select>
          <select value={stateFilter} onChange={e => setStateFilter(e.target.value)} className="text-xs bg-muted/60 border border-border rounded-md px-2.5 py-1.5 text-foreground focus:outline-none focus:ring-1 focus:ring-primary/50">
            <option value="all">All States</option>
            <option value="completed">Completed</option>
            <option value="failed">Failed</option>
            <option value="expired">Expired</option>
            <option value="rejected">Rejected</option>
          </select>
        </div>
      </div>

      {/* Results */}
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
                ].map(col => (
                  <th
                    key={col.key}
                    className="px-3 py-3 text-left font-semibold text-muted-foreground tracking-wide uppercase text-[10px] cursor-pointer hover:text-foreground transition-colors whitespace-nowrap"
                    onClick={() => toggleSort(col.key)}
                  >
                    <span className="flex items-center gap-1">{col.label}<SortIcon k={col.key} /></span>
                  </th>
                ))}
                <th className="px-3 py-3 text-left font-semibold text-muted-foreground tracking-wide uppercase text-[10px] whitespace-nowrap">Result Preview</th>
                <th className="px-3 py-3 w-20" />
              </tr>
            </thead>
            <tbody className="divide-y divide-border">
              {filtered.length === 0 ? (
                <tr>
                  <td colSpan={9} className="px-4 py-12 text-center">
                    <Terminal size={32} className="mx-auto text-muted-foreground/30 mb-3" />
                    <p className="text-sm font-medium text-muted-foreground">No commands match your filters</p>
                  </td>
                </tr>
              ) : filtered.map(cmd => (
                <React.Fragment key={cmd.id}>
                  <tr
                    className={`hover:bg-muted/20 transition-colors cursor-pointer ${expandedId === cmd.id ? 'bg-muted/10' : ''}`}
                    onClick={() => setExpandedId(expandedId === cmd.id ? null : cmd.id)}
                  >
                    <td className="px-3 py-3 font-mono text-[11px] text-primary font-semibold">{cmd.id}</td>
                    <td className="px-3 py-3 font-mono text-[11px]">{cmd.hostname}</td>
                    <td className="px-3 py-3">
                      <span className="px-2 py-0.5 bg-muted/60 rounded text-[11px] font-mono">{cmd.method}</span>
                    </td>
                    <td className="px-3 py-3">
                      <div className="flex items-center gap-1.5">
                        {stateIcon(cmd.state)}
                        <StatusBadge variant={cmd.state} size="sm" />
                      </div>
                    </td>
                    <td className="px-3 py-3 text-[11px] text-muted-foreground max-w-[120px] truncate">{cmd.actor.split('@')[0]}</td>
                    <td className="px-3 py-3 text-[11px] text-muted-foreground tabular-nums whitespace-nowrap">{cmd.queuedAt}</td>
                    <td className="px-3 py-3 text-[11px] text-muted-foreground">{cmd.duration ?? '—'}</td>
                    <td className="px-3 py-3 text-[11px] text-muted-foreground max-w-[180px] truncate italic">
                      {cmd.resultPreview ?? (cmd.errorMessage ? <span className="text-red-400 not-italic">{cmd.errorMessage}</span> : '—')}
                    </td>
                    <td className="px-3 py-3">
                      <div className="flex items-center gap-1.5" onClick={e => e.stopPropagation()}>
                        {(cmd.state === 'completed' || cmd.state === 'failed') && (
                          <button
                            onClick={() => replayCommand(cmd)}
                            title="Replay command"
                            className="flex items-center gap-1 px-2 py-1 text-[11px] bg-primary/10 border border-primary/20 text-primary rounded hover:bg-primary/20 transition-colors"
                          >
                            <RotateCcw size={10} /> Replay
                          </button>
                        )}
                      </div>
                    </td>
                  </tr>
                  {expandedId === cmd.id && (
                    <tr className="bg-muted/10">
                      <td colSpan={9} className="px-4 py-4">
                        <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
                          <div className="bg-muted/30 rounded-lg p-3">
                            <p className="text-[10px] text-muted-foreground uppercase tracking-wide mb-1">Trace ID</p>
                            <p className="text-xs font-mono">{cmd.traceId}</p>
                          </div>
                          <div className="bg-muted/30 rounded-lg p-3">
                            <p className="text-[10px] text-muted-foreground uppercase tracking-wide mb-1">Device ID</p>
                            <p className="text-xs font-mono">{cmd.deviceId}</p>
                          </div>
                          <div className="bg-muted/30 rounded-lg p-3">
                            <p className="text-[10px] text-muted-foreground uppercase tracking-wide mb-1">Priority</p>
                            <p className="text-xs font-semibold capitalize">{cmd.priority}</p>
                          </div>
                          <div className="bg-muted/30 rounded-lg p-3">
                            <p className="text-[10px] text-muted-foreground uppercase tracking-wide mb-1">Batch ID</p>
                            <p className="text-xs font-mono">{cmd.batchId ?? '—'}</p>
                          </div>
                          {cmd.completedAt && (
                            <div className="bg-muted/30 rounded-lg p-3">
                              <p className="text-[10px] text-muted-foreground uppercase tracking-wide mb-1">Completed At</p>
                              <p className="text-xs font-mono">{cmd.completedAt}</p>
                            </div>
                          )}
                          {cmd.resultPreview && (
                            <div className="bg-muted/30 rounded-lg p-3 col-span-2">
                              <p className="text-[10px] text-muted-foreground uppercase tracking-wide mb-1">Result Summary</p>
                              <p className="text-xs">{cmd.resultPreview}</p>
                            </div>
                          )}
                          {cmd.errorMessage && (
                            <div className="bg-red-500/10 border border-red-500/20 rounded-lg p-3 col-span-2">
                              <p className="text-[10px] text-red-400 uppercase tracking-wide mb-1">Error</p>
                              <p className="text-xs text-red-400">{cmd.errorMessage}</p>
                            </div>
                          )}
                        </div>
                        <div className="flex items-center gap-2 mt-3">
                          <button onClick={() => replayCommand(cmd)} className="flex items-center gap-1.5 px-3 py-1.5 text-xs bg-primary/10 border border-primary/20 text-primary rounded-md hover:bg-primary/20 transition-colors">
                            <RotateCcw size={11} /> Replay Command
                          </button>
                          <button onClick={() => { navigator.clipboard.writeText(cmd.id); toast.success('Command ID copied'); }} className="flex items-center gap-1.5 px-3 py-1.5 text-xs text-muted-foreground border border-border rounded-md hover:bg-muted/60 transition-colors">
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
