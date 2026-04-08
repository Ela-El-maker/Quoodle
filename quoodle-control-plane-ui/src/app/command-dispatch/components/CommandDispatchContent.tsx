'use client';
import React, { useState, useMemo } from 'react';
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
} from 'lucide-react';
import StatusBadge from '@/components/ui/StatusBadge';
import CommandDetailPanel from './CommandDetailPanel';
import DispatchCommandModal from './DispatchCommandModal';
import { toast } from 'sonner';

type CommandState = 'queued' | 'dispatched' | 'ack_received' | 'executing' | 'completed' | 'failed' | 'expired' | 'rejected';

interface Command {
  id: string;
  traceId: string;
  deviceId: string;
  hostname: string;
  method: string;
  state: CommandState;
  actor: string;
  queuedAt: string;
  ackAt: string | null;
  completedAt: string | null;
  errorCode: number | null;
  errorMessage: string | null;
  priority: 'normal' | 'high';
  requires2fa: boolean;
}

// Backend integration point: GET /api/commands with state filter + pagination
const mockCommands: Command[] = [
  { id: 'CMD-7742', traceId: 'TRACE-7742', deviceId: 'WKSTN-055', hostname: 'WKSTN-055', method: 'ping',        state: 'completed',   actor: 'chloe.dubois@quoodle.io', queuedAt: '21:06:01', ackAt: '21:06:03', completedAt: '21:06:09', errorCode: null, errorMessage: null, priority: 'normal', requires2fa: false },
  { id: 'CMD-7741', traceId: 'TRACE-7741', deviceId: 'WKSTN-042', hostname: 'WKSTN-042', method: 'lock_screen', state: 'failed',      actor: 'raj.mehta@quoodle.io',    queuedAt: '21:01:55', ackAt: '21:01:57', completedAt: null,       errorCode: 4004, errorMessage: 'Kernel opcode not supported',       priority: 'normal', requires2fa: false },
  { id: 'CMD-7740', traceId: 'TRACE-7740', deviceId: 'WKSTN-042', hostname: 'WKSTN-042', method: 'lock_screen', state: 'dispatched',  actor: 'ops.team@quoodle.io',     queuedAt: '21:04:50', ackAt: null,       completedAt: null,       errorCode: null, errorMessage: null, priority: 'normal', requires2fa: false },
  { id: 'CMD-7739', traceId: 'TRACE-7739', deviceId: 'WKSTN-088', hostname: 'WKSTN-088', method: 'ping',        state: 'ack_received',actor: 'ops.team@quoodle.io',     queuedAt: '21:05:40', ackAt: '21:05:42', completedAt: null,       errorCode: null, errorMessage: null, priority: 'normal', requires2fa: false },
  { id: 'CMD-7738', traceId: 'TRACE-7738', deviceId: 'SRV-PROD-01',hostname: 'SRV-PROD-01',method: 'ping',      state: 'expired',     actor: 'devops@quoodle.io',       queuedAt: '20:55:00', ackAt: null,       completedAt: null,       errorCode: null, errorMessage: 'TTL exceeded — dispatch timeout', priority: 'normal', requires2fa: false },
  { id: 'CMD-7737', traceId: 'TRACE-7737', deviceId: 'WKSTN-001', hostname: 'WKSTN-001', method: 'ping',        state: 'completed',   actor: 'sarah.chen@quoodle.io',   queuedAt: '21:03:10', ackAt: '21:03:12', completedAt: '21:03:18', errorCode: null, errorMessage: null, priority: 'normal', requires2fa: false },
  { id: 'CMD-7736', traceId: 'TRACE-7736', deviceId: 'WKSTN-019', hostname: 'WKSTN-019', method: 'lock_screen', state: 'failed',      actor: 'alex.kumar@quoodle.io',   queuedAt: '20:45:00', ackAt: '20:45:02', completedAt: null,       errorCode: null, errorMessage: 'Agent disconnected during execution', priority: 'high',   requires2fa: true },
  { id: 'CMD-7735', traceId: 'TRACE-7735', deviceId: 'PC002',     hostname: 'WKSTN-002', method: 'ping',        state: 'completed',   actor: 'james.wright@quoodle.io', queuedAt: '20:58:00', ackAt: '20:58:02', completedAt: '20:58:08', errorCode: null, errorMessage: null, priority: 'normal', requires2fa: false },
  { id: 'CMD-7734', traceId: 'TRACE-7734', deviceId: 'WKSTN-103', hostname: 'WKSTN-103', method: 'lock_screen', state: 'rejected',    actor: 'yuki.tanaka@quoodle.io',  queuedAt: '20:52:00', ackAt: null,       completedAt: null,       errorCode: null, errorMessage: 'Policy evaluation: role authorization denied', priority: 'normal', requires2fa: false },
  { id: 'CMD-7733', traceId: 'TRACE-7733', deviceId: 'WKSTN-007', hostname: 'WKSTN-007', method: 'ping',        state: 'queued',      actor: 'ops.team@quoodle.io',     queuedAt: '21:06:05', ackAt: null,       completedAt: null,       errorCode: null, errorMessage: null, priority: 'normal', requires2fa: false },
];

const stateTabs: { key: string; label: string; states: CommandState[] }[] = [
  { key: 'all',      label: 'All',         states: ['queued','dispatched','ack_received','executing','completed','failed','expired','rejected'] },
  { key: 'active',   label: 'Active',      states: ['queued','dispatched','ack_received','executing'] },
  { key: 'completed',label: 'Completed',   states: ['completed'] },
  { key: 'failed',   label: 'Failed',      states: ['failed','expired','rejected'] },
];

type SortKey = keyof Command;

export default function CommandDispatchContent() {
  const [activeTab, setActiveTab] = useState('all');
  const [search, setSearch] = useState('');
  const [sortKey, setSortKey] = useState<SortKey>('queuedAt');
  const [sortDir, setSortDir] = useState<'asc' | 'desc'>('desc');
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());
  const [detailCommand, setDetailCommand] = useState<Command | null>(null);
  const [showDispatchModal, setShowDispatchModal] = useState(false);
  const [currentPage, setCurrentPage] = useState(1);
  const pageSize = 8;

  const allowedStates = stateTabs.find((t) => t.key === activeTab)?.states ?? [];

  const filtered = useMemo(() => {
    let data = mockCommands.filter((c) => {
      const matchState = allowedStates.includes(c.state);
      const matchSearch =
        !search ||
        c.id.toLowerCase().includes(search.toLowerCase()) ||
        c.hostname.toLowerCase().includes(search.toLowerCase()) ||
        c.method.toLowerCase().includes(search.toLowerCase()) ||
        c.actor.toLowerCase().includes(search.toLowerCase());
      return matchState && matchSearch;
    });
    data.sort((a, b) => {
      const av = a[sortKey];
      const bv = b[sortKey];
      if (typeof av === 'string' && typeof bv === 'string') return sortDir === 'asc' ? av.localeCompare(bv) : bv.localeCompare(av);
      return 0;
    });
    return data;
  }, [activeTab, search, sortKey, sortDir, allowedStates]);

  const totalPages = Math.ceil(filtered.length / pageSize);
  const paginatedData = filtered.slice((currentPage - 1) * pageSize, currentPage * pageSize);

  const toggleSort = (key: SortKey) => {
    if (sortKey === key) setSortDir(sortDir === 'asc' ? 'desc' : 'asc');
    else { setSortKey(key); setSortDir('asc'); }
  };

  const toggleSelect = (id: string) => {
    setSelectedIds((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id); else next.add(id);
      return next;
    });
  };

  const SortIcon = ({ k }: { k: SortKey }) =>
    sortKey === k ? (
      sortDir === 'asc' ? <ChevronUp size={12} className="text-primary" /> : <ChevronDown size={12} className="text-primary" />
    ) : (
      <ChevronUp size={12} className="text-muted-foreground/40" />
    );

  const tabCounts: Record<string, number> = {
    all: mockCommands.length,
    active: mockCommands.filter((c) => ['queued','dispatched','ack_received','executing'].includes(c.state)).length,
    completed: mockCommands.filter((c) => c.state === 'completed').length,
    failed: mockCommands.filter((c) => ['failed','expired','rejected'].includes(c.state)).length,
  };

  return (
    <div className="space-y-4 fade-in">
      {/* Header */}
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

      {/* State tabs */}
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
              {tabCounts[tab.key]}
            </span>
          </button>
        ))}
      </div>

      {/* Search + filter row */}
      <div className="flex items-center gap-2">
        <div className="relative flex-1 max-w-sm">
          <Search size={13} className="absolute left-2.5 top-1/2 -translate-y-1/2 text-muted-foreground" />
          <input
            type="text"
            placeholder="Search command ID, device, method, actor…"
            value={search}
            onChange={(e) => { setSearch(e.target.value); setCurrentPage(1); }}
            className="w-full pl-8 pr-3 py-1.5 text-xs bg-muted/60 border border-border rounded-md text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-1 focus:ring-primary/50"
          />
        </div>
        <button
          onClick={() => toast.info('Command list refreshed')}
          className="flex items-center gap-1.5 px-3 py-1.5 text-xs text-muted-foreground border border-border rounded-md hover:bg-muted/60 transition-colors"
        >
          <RefreshCw size={13} />
        </button>
      </div>

      {/* Bulk action bar */}
      {selectedIds.size > 0 && (
        <div className="flex items-center gap-3 px-4 py-2.5 bg-primary/10 border border-primary/20 rounded-lg text-sm slide-in-right">
          <span className="text-primary font-medium">{selectedIds.size} selected</span>
          <button
            onClick={() => { toast.success(`Retried ${selectedIds.size} commands`); setSelectedIds(new Set()); }}
            className="flex items-center gap-1.5 px-2.5 py-1 text-xs bg-blue-500/10 border border-blue-500/20 text-blue-400 rounded-md hover:bg-blue-500/20 transition-colors"
          >
            <RotateCcw size={11} /> Retry All
          </button>
          <button onClick={() => setSelectedIds(new Set())} className="ml-auto text-muted-foreground hover:text-foreground">
            <X size={13} />
          </button>
        </div>
      )}

      {/* Table */}
      <div className="bg-card border border-border rounded-lg overflow-hidden">
        <div className="overflow-x-auto scrollbar-thin">
          <table className="w-full text-xs">
            <thead>
              <tr className="border-b border-border bg-muted/20">
                <th className="w-10 px-3 py-3">
                  <button onClick={() => {
                    if (selectedIds.size === paginatedData.length) setSelectedIds(new Set());
                    else setSelectedIds(new Set(paginatedData.map((c) => c.id)));
                  }} className="text-muted-foreground hover:text-foreground transition-colors">
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
                  { key: 'queuedAt' as SortKey, label: 'Queued' },
                  { key: 'ackAt' as SortKey, label: 'ACK' },
                  { key: 'completedAt' as SortKey, label: 'Completed' },
                ].map((col) => (
                  <th
                    key={`ccol-${col.key}`}
                    className="px-3 py-3 text-left font-semibold text-muted-foreground tracking-wide uppercase text-[10px] cursor-pointer hover:text-foreground transition-colors whitespace-nowrap"
                    onClick={() => toggleSort(col.key)}
                  >
                    <span className="flex items-center gap-1">
                      {col.label}
                      <SortIcon k={col.key} />
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
              {paginatedData.length === 0 ? (
                <tr>
                  <td colSpan={11} className="px-4 py-12 text-center">
                    <Terminal size={32} className="mx-auto text-muted-foreground/30 mb-3" />
                    <p className="text-sm font-medium text-muted-foreground">No commands in this state</p>
                    <p className="text-xs text-muted-foreground/60 mt-1">Commands will appear here as they are dispatched</p>
                  </td>
                </tr>
              ) : (
                paginatedData.map((cmd) => (
                  <tr
                    key={`cmd-row-${cmd.id}`}
                    className={`group hover:bg-muted/30 transition-colors cursor-pointer ${selectedIds.has(cmd.id) ? 'bg-primary/5' : ''}`}
                    onClick={() => setDetailCommand(cmd)}
                  >
                    <td className="px-3 py-3" onClick={(e) => { e.stopPropagation(); toggleSelect(cmd.id); }}>
                      <button className="text-muted-foreground hover:text-foreground transition-colors">
                        {selectedIds.has(cmd.id) ? <CheckSquare size={14} className="text-primary" /> : <Square size={14} />}
                      </button>
                    </td>
                    <td className="px-3 py-3 font-mono text-[11px] text-muted-foreground whitespace-nowrap">{cmd.id}</td>
                    <td className="px-3 py-3 font-medium whitespace-nowrap">{cmd.hostname}</td>
                    <td className="px-3 py-3 font-mono text-[11px] text-blue-400 whitespace-nowrap">{cmd.method}</td>
                    <td className="px-3 py-3 whitespace-nowrap">
                      <StatusBadge variant={cmd.state} pulse={cmd.state === 'executing' || cmd.state === 'dispatched'} />
                    </td>
                    <td className="px-3 py-3 text-muted-foreground max-w-[140px] truncate">{cmd.actor}</td>
                    <td className="px-3 py-3 tabular-nums text-muted-foreground whitespace-nowrap">{cmd.queuedAt}</td>
                    <td className="px-3 py-3 tabular-nums text-muted-foreground whitespace-nowrap">{cmd.ackAt ?? '—'}</td>
                    <td className="px-3 py-3 tabular-nums text-muted-foreground whitespace-nowrap">{cmd.completedAt ?? '—'}</td>
                    <td className="px-3 py-3 max-w-[160px]">
                      {cmd.errorCode && (
                        <span className="font-mono text-[10px] text-red-400 bg-red-500/10 px-1.5 py-0.5 rounded">
                          {cmd.errorCode}
                        </span>
                      )}
                      {cmd.errorMessage && !cmd.errorCode && (
                        <span className="text-[11px] text-amber-400 truncate block">{cmd.errorMessage}</span>
                      )}
                    </td>
                    <td className="px-3 py-3">
                      <div className="flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
                        <button
                          onClick={(e) => { e.stopPropagation(); setDetailCommand(cmd); }}
                          className="p-1 rounded text-muted-foreground hover:text-foreground hover:bg-muted transition-colors"
                          title="View command detail"
                        >
                          <Eye size={13} />
                        </button>
                        {(cmd.state === 'failed' || cmd.state === 'expired') && (
                          <button
                            onClick={(e) => { e.stopPropagation(); toast.success(`Retrying ${cmd.id}`); }}
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
              Showing {(currentPage - 1) * pageSize + 1}–{Math.min(currentPage * pageSize, filtered.length)} of {filtered.length} commands
            </p>
            <div className="flex items-center gap-1">
              {Array.from({ length: totalPages }, (_, i) => i + 1).map((page) => (
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
        <CommandDetailPanel command={detailCommand} onClose={() => setDetailCommand(null)} />
      )}

      {showDispatchModal && (
        <DispatchCommandModal onClose={() => setShowDispatchModal(false)} />
      )}
    </div>
  );
}