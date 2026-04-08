'use client';
import React, { useState, useMemo } from 'react';
import { ScrollText, Search, Download, Terminal, Shield, User, ChevronUp, ChevronDown, RefreshCw } from 'lucide-react';
import { AuditEntry, AuditEventType } from '@/components/AuditTrailSection';
import Icon from '@/components/ui/AppIcon';


const allAuditEntries: AuditEntry[] = [
  { id: 'AUD-1001', timestamp: '2026-04-05 21:06:09', actor: 'ops.team@quoodle.io', actorRole: 'Operator', eventType: 'command_execution', action: 'DISPATCH_COMMAND', target: 'WKSTN-055', detail: 'Dispatched CMD-7742 (ping) — TTL 300s, Ed25519 signed, 2FA verified', outcome: 'success' },
  { id: 'AUD-1002', timestamp: '2026-04-05 21:05:47', actor: 'system', actorRole: 'System', eventType: 'system_event', action: 'ALERT_RAISED', target: 'SRV-PROD-04', detail: 'Critical attestation failure — kernel guard state mismatch on boot', outcome: 'failure' },
  { id: 'AUD-1003', timestamp: '2026-04-05 21:04:58', actor: 'ops.team@quoodle.io', actorRole: 'Operator', eventType: 'command_execution', action: 'DISPATCH_COMMAND', target: 'WKSTN-042', detail: 'Dispatched CMD-7740 (lock_screen) — 2FA verified, envelope signed', outcome: 'success' },
  { id: 'AUD-1004', timestamp: '2026-04-05 21:04:22', actor: 'system', actorRole: 'System', eventType: 'policy_change', action: 'POLICY_DRIFT_DETECTED', target: 'WKSTN-011', detail: 'Policy hash mismatch: device reports policy-2025-11, expected policy-2026-04', outcome: 'failure' },
  { id: 'AUD-1005', timestamp: '2026-04-05 21:02:11', actor: 'system', actorRole: 'System', eventType: 'command_execution', action: 'COMMAND_FAILED', target: 'WKSTN-042', detail: 'CMD-7741 failed — kernel opcode 0x4004 not supported on agent v0.0.1', outcome: 'failure' },
  { id: 'AUD-1006', timestamp: '2026-04-05 21:01:30', actor: 'admin@quoodle.io', actorRole: 'Admin', eventType: 'policy_change', action: 'POLICY_UPDATED', target: 'fleet-global', detail: 'Fleet policy updated to policy-2026-04 — signed by admin@quoodle.io, hash: sha256:a3f9...', outcome: 'success' },
  { id: 'AUD-1007', timestamp: '2026-04-05 21:00:05', actor: 'nina.osei@quoodle.io', actorRole: 'Operator', eventType: 'user_action', action: 'ALERT_ACKNOWLEDGED', target: 'ALT-0082', detail: 'Alert ALT-0082 acknowledged — kernel guard missing on WKSTN-031, rationale logged', outcome: 'success' },
  { id: 'AUD-1008', timestamp: '2026-04-05 20:58:44', actor: 'devops@quoodle.io', actorRole: 'Operator', eventType: 'user_action', action: 'ALERT_ACKNOWLEDGED', target: 'ALT-0085', detail: 'Alert ALT-0085 acknowledged — CMD-7738 expired before agent ACK', outcome: 'success' },
  { id: 'AUD-1009', timestamp: '2026-04-05 20:55:00', actor: 'admin@quoodle.io', actorRole: 'Admin', eventType: 'user_action', action: 'DEVICE_QUARANTINED', target: 'SRV-PROD-04', detail: 'Device SRV-PROD-04 quarantined — attestation failure, all commands blocked', outcome: 'success' },
  { id: 'AUD-1010', timestamp: '2026-04-05 20:51:33', actor: 'system', actorRole: 'System', eventType: 'system_event', action: 'TELEMETRY_ANOMALY', target: 'WKSTN-007', detail: 'CPU utilization sustained above 90% for 12 minutes — risk score elevated to 61/100', outcome: 'failure' },
  { id: 'AUD-1011', timestamp: '2026-04-05 20:30:00', actor: 'system', actorRole: 'System', eventType: 'policy_change', action: 'POLICY_SYNCED', target: 'WKSTN-055', detail: 'Policy hash re-synchronized to policy-2026-04 after drift resolution', outcome: 'success' },
  { id: 'AUD-1012', timestamp: '2026-04-05 20:00:00', actor: 'nina.osei@quoodle.io', actorRole: 'Operator', eventType: 'user_action', action: 'ALERT_ACKNOWLEDGED', target: 'ALT-0082', detail: 'Kernel Guard missing alert acknowledged — remediation ticket opened', outcome: 'success' },
  { id: 'AUD-1013', timestamp: '2026-04-05 19:45:00', actor: 'admin@quoodle.io', actorRole: 'Admin', eventType: 'user_action', action: 'USER_LOGIN', target: 'console', detail: 'Admin login from 10.0.1.5 — MFA verified, session token issued', outcome: 'success' },
  { id: 'AUD-1014', timestamp: '2026-04-05 19:30:00', actor: 'ops.team@quoodle.io', actorRole: 'Operator', eventType: 'command_execution', action: 'DISPATCH_COMMAND', target: 'WKSTN-031', detail: 'Dispatched CMD-7735 (get_system_info) — completed in 1.2s', outcome: 'success' },
  { id: 'AUD-1015', timestamp: '2026-04-05 19:14:02', actor: 'system', actorRole: 'System', eventType: 'system_event', action: 'ATTESTATION_FAILED', target: 'SRV-PROD-04', detail: 'Boot attestation failed — PCR[7] mismatch, Secure Boot state changed', outcome: 'failure' },
];

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

export default function AuditContent() {
  const [search, setSearch] = useState('');
  const [typeFilter, setTypeFilter] = useState<AuditEventType | 'all'>('all');
  const [outcomeFilter, setOutcomeFilter] = useState<'all' | 'success' | 'failure'>('all');
  const [sortKey, setSortKey] = useState<SortKey>('timestamp');
  const [sortDir, setSortDir] = useState<'asc' | 'desc'>('desc');

  const filtered = useMemo(() => {
    let data = allAuditEntries.filter((e) => {
      const matchType = typeFilter === 'all' || e.eventType === typeFilter;
      const matchOutcome = outcomeFilter === 'all' || e.outcome === outcomeFilter;
      const matchSearch =
        !search ||
        e.actor.toLowerCase().includes(search.toLowerCase()) ||
        e.action.toLowerCase().includes(search.toLowerCase()) ||
        e.target.toLowerCase().includes(search.toLowerCase()) ||
        e.detail.toLowerCase().includes(search.toLowerCase());
      return matchType && matchOutcome && matchSearch;
    });
    data.sort((a, b) => {
      const av = a[sortKey];
      const bv = b[sortKey];
      if (typeof av === 'string' && typeof bv === 'string')
        return sortDir === 'asc' ? av.localeCompare(bv) : bv.localeCompare(av);
      return 0;
    });
    return data;
  }, [search, typeFilter, outcomeFilter, sortKey, sortDir]);

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

  const counts = {
    total:   allAuditEntries.length,
    success: allAuditEntries.filter((e) => e.outcome === 'success').length,
    failure: allAuditEntries.filter((e) => e.outcome === 'failure').length,
  };

  return (
    <div className="space-y-6 fade-in">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">Audit Trail</h1>
          <p className="text-sm text-muted-foreground mt-0.5">Immutable log of user actions, command executions, and policy changes</p>
        </div>
        <button className="flex items-center gap-1.5 px-3 py-1.5 text-xs text-muted-foreground border border-border rounded-md hover:bg-muted/60 transition-colors">
          <Download size={13} />
          Export CSV
        </button>
      </div>

      {/* Summary cards */}
      <div className="grid grid-cols-2 sm:grid-cols-4 gap-4">
        <div className="bg-card border border-border rounded-lg p-4">
          <p className="text-3xl font-bold tabular-nums">{counts.total}</p>
          <p className="text-xs text-muted-foreground mt-1 uppercase tracking-wide font-medium">Total Events</p>
        </div>
        <div className="bg-green-500/5 border border-green-500/20 rounded-lg p-4">
          <p className="text-3xl font-bold tabular-nums text-green-400">{counts.success}</p>
          <p className="text-xs text-green-400/70 mt-1 uppercase tracking-wide font-medium">Successful</p>
        </div>
        <div className="bg-red-500/5 border border-red-500/20 rounded-lg p-4">
          <p className="text-3xl font-bold tabular-nums text-red-400">{counts.failure}</p>
          <p className="text-xs text-red-400/70 mt-1 uppercase tracking-wide font-medium">Failures</p>
        </div>
        <div className="bg-card border border-border rounded-lg p-4">
          <p className="text-3xl font-bold tabular-nums text-blue-400">4</p>
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
            placeholder="Search actor, action, target…"
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
              {filtered.length === 0 ? (
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
                  return (
                    <tr key={entry.id} className="hover:bg-muted/20 transition-colors">
                      <td className="px-3 py-3 font-mono text-[11px] text-muted-foreground whitespace-nowrap">
                        <div>{entry.timestamp.split(' ')[0]}</div>
                        <div className="text-primary">{entry.timestamp.split(' ')[1]}</div>
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
            Showing {filtered.length} of {allAuditEntries.length} events
          </p>
          <button className="flex items-center gap-1.5 text-xs text-muted-foreground hover:text-foreground transition-colors">
            <RefreshCw size={11} />
            Refresh
          </button>
        </div>
      </div>
    </div>
  );
}
