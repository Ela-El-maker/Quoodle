'use client';
import React, { useState, useMemo } from 'react';
import { ScrollText, Terminal, Shield, User, ChevronDown, ChevronUp, Filter, Download, Calendar, X } from 'lucide-react';

export type AuditEventType = 'user_action' | 'command_execution' | 'policy_change' | 'system_event';

export interface AuditEntry {
  id: string;
  timestamp: string;
  actor: string;
  actorRole: string;
  eventType: AuditEventType;
  action: string;
  target: string;
  detail: string;
  outcome: 'success' | 'failure' | 'pending';
}

const defaultEntries: AuditEntry[] = [];

const typeConfig: Record<AuditEventType, { icon: React.ElementType; color: string; bg: string; label: string }> = {
  user_action:       { icon: User,       color: 'text-blue-400',   bg: 'bg-blue-500/10',   label: 'User Action' },
  command_execution: { icon: Terminal,   color: 'text-green-400',  bg: 'bg-green-500/10',  label: 'Command' },
  policy_change:     { icon: Shield,     color: 'text-amber-400',  bg: 'bg-amber-500/10',  label: 'Policy' },
  system_event:      { icon: ScrollText, color: 'text-muted-foreground',   bg: 'bg-muted/50',   label: 'System' },
};

const outcomeConfig = {
  success: 'text-green-400',
  failure: 'text-red-400',
  pending: 'text-amber-400',
};

interface AuditTrailSectionProps {
  entries?: AuditEntry[];
  maxRows?: number;
  title?: string;
  loading?: boolean;
  error?: string | null;
}

function exportToCSV(entries: AuditEntry[], title: string) {
  const headers = ['ID', 'Timestamp', 'Actor', 'Role', 'Type', 'Action', 'Target', 'Detail', 'Outcome'];
  const rows = entries.map((e) => [
    e.id, e.timestamp, e.actor, e.actorRole, e.eventType, e.action, e.target,
    `"${e.detail.replace(/"/g, '""')}"`, e.outcome,
  ]);
  const csv = [headers.join(','), ...rows.map((r) => r.join(','))].join('\n');
  const blob = new Blob([csv], { type: 'text/csv' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = `audit-trail-${title.toLowerCase().replace(/\s+/g, '-')}-${Date.now()}.csv`;
  a.click();
  URL.revokeObjectURL(url);
}

export default function AuditTrailSection({
  entries = defaultEntries,
  maxRows = 5,
  title = 'Audit Trail',
  loading = false,
  error = null,
}: AuditTrailSectionProps) {
  const [expanded, setExpanded] = useState(false);
  const [typeFilter, setTypeFilter] = useState<AuditEventType | 'all'>('all');
  const [actorFilter, setActorFilter] = useState<string>('all');
  const [dateFrom, setDateFrom] = useState('');
  const [dateTo, setDateTo] = useState('');
  const [showDatePicker, setShowDatePicker] = useState(false);

  // Unique actors from provided entries
  const actors = useMemo(() => Array.from(new Set(entries.map((e) => e.actor))), [entries]);

  const filtered = useMemo(() => {
    if (loading || error) return [];
    return entries.filter((e) => {
      if (typeFilter !== 'all' && e.eventType !== typeFilter) return false;
      if (actorFilter !== 'all' && e.actor !== actorFilter) return false;
      if (dateFrom) {
        const entryDate = e.timestamp.split(' ')[0];
        if (entryDate < dateFrom) return false;
      }
      if (dateTo) {
        const entryDate = e.timestamp.split(' ')[0];
        if (entryDate > dateTo) return false;
      }
      return true;
    });
  }, [entries, typeFilter, actorFilter, dateFrom, dateTo, loading, error]);

  const visible = expanded ? filtered : filtered.slice(0, maxRows);
  const hasDateFilter = dateFrom || dateTo;

  const clearDateFilter = () => {
    setDateFrom('');
    setDateTo('');
    setShowDatePicker(false);
  };

  // Event type facet counts
  const facetCounts = useMemo(() => {
    const counts: Record<string, number> = { all: entries.length };
    entries.forEach((e) => {
      counts[e.eventType] = (counts[e.eventType] || 0) + 1;
    });
    return counts;
  }, [entries]);

  return (
    <div className="bg-card border border-border rounded-lg overflow-hidden">
      {/* Header */}
      <div className="flex items-center justify-between px-4 py-3 border-b border-border flex-wrap gap-2">
        <div className="flex items-center gap-2">
          <ScrollText size={14} className="text-muted-foreground" />
          <h3 className="text-sm font-semibold">{title}</h3>
          <span className="text-[10px] font-semibold px-1.5 py-0.5 rounded-full bg-muted text-muted-foreground tabular-nums">
            {filtered.length}
          </span>
        </div>
        <div className="flex items-center gap-2 flex-wrap">
          {/* Actor filter */}
          <div className="flex items-center gap-1">
            <User size={11} className="text-muted-foreground" />
            <select
              value={actorFilter}
              onChange={(e) => setActorFilter(e.target.value)}
              className="text-[11px] bg-muted/60 border border-border rounded px-1.5 py-0.5 text-muted-foreground focus:outline-none focus:ring-1 focus:ring-primary/50 max-w-[130px]"
            >
              <option value="all">All Actors</option>
              {actors.map((a) => (
                <option key={a} value={a}>{a}</option>
              ))}
            </select>
          </div>

          {/* Event type filter */}
          <div className="flex items-center gap-1">
            <Filter size={11} className="text-muted-foreground" />
            <select
              value={typeFilter}
              onChange={(e) => setTypeFilter(e.target.value as AuditEventType | 'all')}
              className="text-[11px] bg-muted/60 border border-border rounded px-1.5 py-0.5 text-muted-foreground focus:outline-none focus:ring-1 focus:ring-primary/50"
            >
              <option value="all">All Events ({facetCounts['all'] || 0})</option>
              <option value="user_action">User Actions ({facetCounts['user_action'] || 0})</option>
              <option value="command_execution">Commands ({facetCounts['command_execution'] || 0})</option>
              <option value="policy_change">Policy ({facetCounts['policy_change'] || 0})</option>
              <option value="system_event">System ({facetCounts['system_event'] || 0})</option>
            </select>
          </div>

          {/* Date range picker */}
          <div className="relative">
            <button
              onClick={() => setShowDatePicker(!showDatePicker)}
              className={`flex items-center gap-1 text-[11px] px-1.5 py-0.5 rounded border transition-colors ${
                hasDateFilter
                  ? 'bg-primary/10 border-primary/30 text-primary' :'bg-muted/60 border-border text-muted-foreground hover:text-foreground'
              }`}
            >
              <Calendar size={11} />
              {hasDateFilter ? `${dateFrom || '…'} → ${dateTo || '…'}` : 'Date Range'}
              {hasDateFilter && (
                <span
                  onClick={(e) => { e.stopPropagation(); clearDateFilter(); }}
                  className="ml-0.5 hover:text-red-400 cursor-pointer"
                >
                  <X size={10} />
                </span>
              )}
            </button>
            {showDatePicker && (
              <div className="absolute right-0 top-full mt-1 z-20 bg-popover border border-border rounded-lg p-3 shadow-xl min-w-[220px]">
                <p className="text-[10px] font-semibold text-muted-foreground uppercase tracking-wide mb-2">Date Range</p>
                <div className="space-y-2">
                  <div>
                    <label className="text-[10px] text-muted-foreground block mb-0.5">From</label>
                    <input
                      type="date"
                      value={dateFrom}
                      onChange={(e) => setDateFrom(e.target.value)}
                      className="w-full text-[11px] bg-muted/60 border border-border rounded px-2 py-1 text-foreground focus:outline-none focus:ring-1 focus:ring-primary/50"
                    />
                  </div>
                  <div>
                    <label className="text-[10px] text-muted-foreground block mb-0.5">To</label>
                    <input
                      type="date"
                      value={dateTo}
                      onChange={(e) => setDateTo(e.target.value)}
                      className="w-full text-[11px] bg-muted/60 border border-border rounded px-2 py-1 text-foreground focus:outline-none focus:ring-1 focus:ring-primary/50"
                    />
                  </div>
                  <div className="flex gap-1.5 pt-1">
                    <button
                      onClick={clearDateFilter}
                      className="flex-1 text-[11px] py-1 border border-border rounded text-muted-foreground hover:text-foreground transition-colors"
                    >
                      Clear
                    </button>
                    <button
                      onClick={() => setShowDatePicker(false)}
                      className="flex-1 text-[11px] py-1 bg-primary/10 border border-primary/30 text-primary rounded hover:bg-primary/20 transition-colors"
                    >
                      Apply
                    </button>
                  </div>
                </div>
              </div>
            )}
          </div>

          {/* Export CSV */}
          <button
            onClick={() => exportToCSV(filtered, title)}
            className="flex items-center gap-1 text-[11px] px-1.5 py-0.5 rounded border bg-muted/60 border-border text-muted-foreground hover:text-foreground hover:bg-muted transition-colors"
            title="Export filtered audit log as CSV"
          >
            <Download size={11} />
            Export
          </button>
        </div>
      </div>

      {/* Event type facet pills */}
      <div className="flex items-center gap-1.5 px-4 py-2 border-b border-border overflow-x-auto scrollbar-thin">
        {(['all', 'user_action', 'command_execution', 'policy_change', 'system_event'] as const).map((t) => {
          const cfg = t === 'all' ? null : typeConfig[t];
          const isActive = typeFilter === t;
          const count = t === 'all' ? entries.length : (facetCounts[t] || 0);
          return (
            <button
              key={t}
              onClick={() => setTypeFilter(t)}
              className={`flex items-center gap-1 px-2 py-0.5 rounded-full text-[10px] font-medium border whitespace-nowrap transition-all ${
                isActive
                  ? cfg
                    ? `${cfg.bg} ${cfg.color} border-current/30`
                    : 'bg-primary/10 text-primary border-primary/30' :'bg-muted/30 text-muted-foreground border-border hover:border-border/80'
              }`}
            >
              {cfg && <cfg.icon size={9} />}
              {t === 'all' ? 'All' : cfg?.label}
              <span className="tabular-nums opacity-70">{count}</span>
            </button>
          );
        })}
      </div>

      {/* Table */}
      <div className="overflow-x-auto scrollbar-thin">
        <table className="w-full text-xs">
          <thead>
            <tr className="border-b border-border bg-muted/20">
              <th className="px-3 py-2.5 text-left font-semibold text-muted-foreground tracking-wide uppercase text-[10px] whitespace-nowrap">Timestamp</th>
              <th className="px-3 py-2.5 text-left font-semibold text-muted-foreground tracking-wide uppercase text-[10px] whitespace-nowrap">Actor</th>
              <th className="px-3 py-2.5 text-left font-semibold text-muted-foreground tracking-wide uppercase text-[10px] whitespace-nowrap">Type</th>
              <th className="px-3 py-2.5 text-left font-semibold text-muted-foreground tracking-wide uppercase text-[10px] whitespace-nowrap">Action</th>
              <th className="px-3 py-2.5 text-left font-semibold text-muted-foreground tracking-wide uppercase text-[10px] whitespace-nowrap">Target</th>
              <th className="px-3 py-2.5 text-left font-semibold text-muted-foreground tracking-wide uppercase text-[10px]">Detail</th>
              <th className="px-3 py-2.5 text-left font-semibold text-muted-foreground tracking-wide uppercase text-[10px] whitespace-nowrap">Outcome</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-border">
            {loading ? (
              <tr>
                <td colSpan={7} className="px-4 py-8 text-center text-xs text-muted-foreground">
                  Loading data...
                </td>
              </tr>
            ) : error ? (
              <tr>
                <td colSpan={7} className="px-4 py-8 text-center text-xs text-red-400">
                  Failed to load data
                </td>
              </tr>
            ) : visible.length === 0 ? (
              <tr>
                <td colSpan={7} className="px-4 py-8 text-center text-xs text-muted-foreground">
                  No audit events match the selected filters
                </td>
              </tr>
            ) : (
              visible.map((entry) => {
                const cfg = typeConfig[entry.eventType];
                const EntryIcon = cfg.icon;
                return (
                  <tr key={entry.id} className="hover:bg-muted/20 transition-colors">
                    <td className="px-3 py-2.5 font-mono text-[11px] text-muted-foreground whitespace-nowrap">
                      {entry.timestamp.split(' ')[1]}
                    </td>
                    <td className="px-3 py-2.5 whitespace-nowrap">
                      <div>
                        <p className="font-medium text-foreground truncate max-w-[140px]">{entry.actor}</p>
                        <p className="text-[10px] text-muted-foreground">{entry.actorRole}</p>
                      </div>
                    </td>
                    <td className="px-3 py-2.5 whitespace-nowrap">
                      <span className={`inline-flex items-center gap-1 px-1.5 py-0.5 rounded text-[10px] font-medium ${cfg.bg} ${cfg.color}`}>
                        <EntryIcon size={10} />
                        {cfg.label}
                      </span>
                    </td>
                    <td className="px-3 py-2.5 font-mono text-[11px] text-foreground whitespace-nowrap">{entry.action}</td>
                    <td className="px-3 py-2.5 font-mono text-[11px] text-primary whitespace-nowrap">{entry.target}</td>
                    <td className="px-3 py-2.5 text-muted-foreground max-w-[260px]">
                      <p className="truncate">{entry.detail}</p>
                    </td>
                    <td className="px-3 py-2.5 whitespace-nowrap">
                      <span className={`font-semibold uppercase text-[10px] ${outcomeConfig[entry.outcome]}`}>
                        {entry.outcome}
                      </span>
                    </td>
                  </tr>
                );
              })
            )}
          </tbody>
        </table>
      </div>

      {/* Expand/collapse */}
      {!loading && !error && filtered.length > maxRows && (
        <div className="border-t border-border px-4 py-2.5">
          <button
            onClick={() => setExpanded(!expanded)}
            className="flex items-center gap-1.5 text-xs text-muted-foreground hover:text-foreground transition-colors"
          >
            {expanded ? <ChevronUp size={13} /> : <ChevronDown size={13} />}
            {expanded ? 'Show less' : `Show ${filtered.length - maxRows} more events`}
          </button>
        </div>
      )}

    </div>
  );
}


