'use client';
import React, { useState, useMemo } from 'react';
import { Search, SlidersHorizontal, Download, RefreshCw, ChevronUp, ChevronDown, MoreHorizontal, Terminal, Eye, Shield, Monitor, X, CheckSquare, Square, Send, RotateCcw, Layers } from 'lucide-react';
import StatusBadge from '@/components/ui/StatusBadge';
import DeviceDetailDrawer from './DeviceDetailDrawer';
import ExportModal from '@/components/ExportModal';
import { toast } from 'sonner';

// Backend integration point: GET /api/devices with pagination + filters
type DeviceStatus = 'online' | 'offline' | 'quarantined' | 'degraded';
type ComplianceStatus = 'compliant' | 'non_compliant' | 'drift';

interface Device {
  id: string;
  hostname: string;
  osBuild: string;
  owner: string;
  status: DeviceStatus;
  riskScore: number;
  compliance: ComplianceStatus;
  lastSeen: string;
  agentVersion: string;
  policySync: boolean;
  kernelGuard: boolean;
  ipAddress: string;
  sessionId: string | null;
}

const mockDevices: Device[] = [
  { id: 'PC001',      hostname: 'WKSTN-001',    osBuild: '19045.4170', owner: 'sarah.chen@quoodle.io',   status: 'online',      riskScore: 0.12, compliance: 'compliant',     lastSeen: '21:06:11', agentVersion: '0.0.1', policySync: true,  kernelGuard: true,  ipAddress: '10.0.1.11',  sessionId: 'sess-7a2f' },
  { id: 'PC002',      hostname: 'WKSTN-002',    osBuild: '19045.4170', owner: 'james.wright@quoodle.io', status: 'online',      riskScore: 0.08, compliance: 'compliant',     lastSeen: '21:06:09', agentVersion: '0.0.1', policySync: true,  kernelGuard: true,  ipAddress: '10.0.1.12',  sessionId: 'sess-3b8c' },
  { id: 'SRV-PROD-01',hostname: 'SRV-PROD-01', osBuild: '20348.2340', owner: 'devops@quoodle.io',       status: 'online',      riskScore: 0.19, compliance: 'drift',         lastSeen: '21:06:08', agentVersion: '0.0.1', policySync: false, kernelGuard: true,  ipAddress: '10.0.2.1',   sessionId: 'sess-9c1d' },
  { id: 'SRV-PROD-04',hostname: 'SRV-PROD-04', osBuild: '20348.2340', owner: 'devops@quoodle.io',       status: 'quarantined', riskScore: 0.89, compliance: 'non_compliant', lastSeen: '19:14:02', agentVersion: '0.0.1', policySync: false, kernelGuard: false, ipAddress: '10.0.2.4',   sessionId: null },
  { id: 'WKSTN-007',  hostname: 'WKSTN-007',    osBuild: '19045.4170', owner: 'mike.torres@quoodle.io',  status: 'degraded',    riskScore: 0.61, compliance: 'drift',         lastSeen: '21:05:58', agentVersion: '0.0.1', policySync: false, kernelGuard: true,  ipAddress: '10.0.1.17',  sessionId: 'sess-2e4f' },
  { id: 'WKSTN-011',  hostname: 'WKSTN-011',    osBuild: '19045.4170', owner: 'lisa.park@quoodle.io',    status: 'degraded',    riskScore: 0.42, compliance: 'drift',         lastSeen: '21:05:44', agentVersion: '0.0.1', policySync: false, kernelGuard: true,  ipAddress: '10.0.1.21',  sessionId: 'sess-5g7h' },
  { id: 'WKSTN-019',  hostname: 'WKSTN-019',    osBuild: '19045.3570', owner: 'alex.kumar@quoodle.io',   status: 'offline',     riskScore: 0.15, compliance: 'compliant',     lastSeen: '20:41:17', agentVersion: '0.0.1', policySync: true,  kernelGuard: true,  ipAddress: '10.0.1.29',  sessionId: null },
  { id: 'WKSTN-031',  hostname: 'WKSTN-031',    osBuild: '19045.4170', owner: 'nina.osei@quoodle.io',    status: 'offline',     riskScore: 0.11, compliance: 'compliant',     lastSeen: '21:05:33', agentVersion: '0.0.1', policySync: true,  kernelGuard: false, ipAddress: '10.0.1.41',  sessionId: null },
  { id: 'WKSTN-042',  hostname: 'WKSTN-042',    osBuild: '19045.4170', owner: 'raj.mehta@quoodle.io',    status: 'online',      riskScore: 0.24, compliance: 'compliant',     lastSeen: '21:06:07', agentVersion: '0.0.1', policySync: true,  kernelGuard: true,  ipAddress: '10.0.1.52',  sessionId: 'sess-8i9j' },
  { id: 'WKSTN-055',  hostname: 'WKSTN-055',    osBuild: '19045.4170', owner: 'chloe.dubois@quoodle.io', status: 'online',      riskScore: 0.06, compliance: 'compliant',     lastSeen: '21:06:12', agentVersion: '0.0.1', policySync: true,  kernelGuard: true,  ipAddress: '10.0.1.65',  sessionId: 'sess-1k2l' },
  { id: 'WKSTN-088',  hostname: 'WKSTN-088',    osBuild: '19045.4170', owner: 'tom.brennan@quoodle.io',  status: 'online',      riskScore: 0.09, compliance: 'compliant',     lastSeen: '21:06:13', agentVersion: '0.0.1', policySync: true,  kernelGuard: true,  ipAddress: '10.0.1.98',  sessionId: 'sess-3m4n' },
  { id: 'WKSTN-103',  hostname: 'WKSTN-103',    osBuild: '19044.2965', owner: 'yuki.tanaka@quoodle.io',  status: 'online',      riskScore: 0.33, compliance: 'drift',         lastSeen: '21:05:51', agentVersion: '0.0.1', policySync: false, kernelGuard: true,  ipAddress: '10.0.1.113', sessionId: 'sess-5o6p' },
];

type SortKey = keyof Device;

export default function DeviceManagementContent() {
  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState<string>('all');
  const [complianceFilter, setComplianceFilter] = useState<string>('all');
  const [sortKey, setSortKey] = useState<SortKey>('lastSeen');
  const [sortDir, setSortDir] = useState<'asc' | 'desc'>('desc');
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());
  const [selectedDevice, setSelectedDevice] = useState<Device | null>(null);
  const [currentPage, setCurrentPage] = useState(1);
  const [showExport, setShowExport] = useState(false);
  const [isBatchRefreshing, setIsBatchRefreshing] = useState(false);
  const pageSize = 10;

  const filtered = useMemo(() => {
    let data = mockDevices.filter((d) => {
      const matchSearch =
        !search ||
        d.hostname.toLowerCase().includes(search.toLowerCase()) ||
        d.id.toLowerCase().includes(search.toLowerCase()) ||
        d.owner.toLowerCase().includes(search.toLowerCase());
      const matchStatus = statusFilter === 'all' || d.status === statusFilter;
      const matchCompliance = complianceFilter === 'all' || d.compliance === complianceFilter;
      return matchSearch && matchStatus && matchCompliance;
    });

    data.sort((a, b) => {
      const av = a[sortKey];
      const bv = b[sortKey];
      if (typeof av === 'string' && typeof bv === 'string') {
        return sortDir === 'asc' ? av.localeCompare(bv) : bv.localeCompare(av);
      }
      if (typeof av === 'number' && typeof bv === 'number') {
        return sortDir === 'asc' ? av - bv : bv - av;
      }
      return 0;
    });

    return data;
  }, [search, statusFilter, complianceFilter, sortKey, sortDir]);

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

  const toggleAll = () => {
    if (selectedIds.size === filtered.length) setSelectedIds(new Set());
    else setSelectedIds(new Set(filtered.map((d) => d.id)));
  };

  const handleBatchRefresh = () => {
    setIsBatchRefreshing(true);
    setTimeout(() => {
      setIsBatchRefreshing(false);
      toast.success(`Refreshed ${selectedIds.size} device${selectedIds.size !== 1 ? 's' : ''}`);
    }, 1200);
  };

  const SortIcon = ({ k }: { k: SortKey }) =>
    sortKey === k ? (
      sortDir === 'asc' ? <ChevronUp size={12} className="text-primary" /> : <ChevronDown size={12} className="text-primary" />
    ) : (
      <ChevronUp size={12} className="text-muted-foreground/40" />
    );

  const riskColor = (score: number) =>
    score > 0.6 ? 'text-red-400' : score > 0.3 ? 'text-amber-400' : 'text-green-400';

  return (
    <div className="space-y-4 fade-in">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">Device Management</h1>
          <p className="text-sm text-muted-foreground mt-0.5">
            {filtered.length} device{filtered.length !== 1 ? 's' : ''} · Fleet operational triage
          </p>
        </div>
        <div className="flex items-center gap-2">
          <button
            onClick={() => setShowExport(true)}
            className="flex items-center gap-1.5 px-3 py-1.5 text-xs text-muted-foreground border border-border rounded-md hover:bg-muted/60 transition-colors"
          >
            <Download size={13} />
            Export
          </button>
          <button
            onClick={() => toast.info('Device list refreshed')}
            className="flex items-center gap-1.5 px-3 py-1.5 text-xs text-muted-foreground border border-border rounded-md hover:bg-muted/60 transition-colors"
          >
            <RefreshCw size={13} />
            Refresh
          </button>
        </div>
      </div>

      {/* Filter bar */}
      <div className="flex flex-wrap items-center gap-2">
        <div className="relative flex-1 min-w-[200px] max-w-xs">
          <Search size={13} className="absolute left-2.5 top-1/2 -translate-y-1/2 text-muted-foreground" />
          <input
            type="text"
            placeholder="Search hostname, device ID, owner…"
            value={search}
            onChange={(e) => { setSearch(e.target.value); setCurrentPage(1); }}
            className="w-full pl-8 pr-3 py-1.5 text-xs bg-muted/60 border border-border rounded-md text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-1 focus:ring-primary/50"
          />
        </div>

        <div className="flex items-center gap-1.5">
          <SlidersHorizontal size={13} className="text-muted-foreground" />
          <span className="text-xs text-muted-foreground">Filters:</span>
        </div>

        <select
          value={statusFilter}
          onChange={(e) => { setStatusFilter(e.target.value); setCurrentPage(1); }}
          className="text-xs bg-muted/60 border border-border rounded-md px-2.5 py-1.5 text-foreground focus:outline-none focus:ring-1 focus:ring-primary/50"
        >
          <option value="all">All Status</option>
          <option value="online">Online</option>
          <option value="offline">Offline</option>
          <option value="degraded">Degraded</option>
          <option value="quarantined">Quarantined</option>
        </select>

        <select
          value={complianceFilter}
          onChange={(e) => { setComplianceFilter(e.target.value); setCurrentPage(1); }}
          className="text-xs bg-muted/60 border border-border rounded-md px-2.5 py-1.5 text-foreground focus:outline-none focus:ring-1 focus:ring-primary/50"
        >
          <option value="all">All Compliance</option>
          <option value="compliant">Compliant</option>
          <option value="non_compliant">Non-Compliant</option>
          <option value="drift">Drift</option>
        </select>

        {(search || statusFilter !== 'all' || complianceFilter !== 'all') && (
          <button
            onClick={() => { setSearch(''); setStatusFilter('all'); setComplianceFilter('all'); setCurrentPage(1); }}
            className="flex items-center gap-1 text-xs text-muted-foreground hover:text-foreground transition-colors"
          >
            <X size={12} /> Clear
          </button>
        )}
      </div>

      {/* Bulk action bar */}
      {selectedIds.size > 0 && (
        <div className="flex flex-wrap items-center gap-2 px-4 py-2.5 bg-primary/10 border border-primary/20 rounded-lg text-sm slide-in-right">
          <span className="text-primary font-medium">{selectedIds.size} selected</span>
          <span className="text-border">|</span>
          <button
            onClick={toggleAll}
            className="text-xs text-muted-foreground hover:text-foreground transition-colors"
          >
            {selectedIds.size === filtered.length ? 'Deselect All' : `Select All (${filtered.length})`}
          </button>
          <div className="flex items-center gap-2 ml-1">
            <button
              onClick={() => toast.success(`Dispatched ping to ${selectedIds.size} devices`)}
              className="flex items-center gap-1.5 px-2.5 py-1 text-xs bg-blue-500/10 border border-blue-500/20 text-blue-400 rounded-md hover:bg-blue-500/20 transition-colors"
            >
              <Terminal size={11} /> Send Command
            </button>
            <button
              onClick={() => toast.info(`Applying policy to ${selectedIds.size} devices…`)}
              className="flex items-center gap-1.5 px-2.5 py-1 text-xs bg-violet-500/10 border border-violet-500/20 text-violet-400 rounded-md hover:bg-violet-500/20 transition-colors"
            >
              <Layers size={11} /> Apply Policy
            </button>
            <button
              onClick={() => toast.warning(`Lock screen sent to ${selectedIds.size} devices`)}
              className="flex items-center gap-1.5 px-2.5 py-1 text-xs bg-amber-500/10 border border-amber-500/20 text-amber-400 rounded-md hover:bg-amber-500/20 transition-colors"
            >
              <Shield size={11} /> Lock All
            </button>
            <button
              onClick={handleBatchRefresh}
              disabled={isBatchRefreshing}
              className="flex items-center gap-1.5 px-2.5 py-1 text-xs bg-green-500/10 border border-green-500/20 text-green-400 rounded-md hover:bg-green-500/20 transition-colors disabled:opacity-50"
            >
              <RotateCcw size={11} className={isBatchRefreshing ? 'animate-spin' : ''} />
              {isBatchRefreshing ? 'Refreshing…' : 'Batch Refresh'}
            </button>
          </div>
          <button
            onClick={() => setSelectedIds(new Set())}
            className="ml-auto text-muted-foreground hover:text-foreground transition-colors"
          >
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
                  <button onClick={toggleAll} className="text-muted-foreground hover:text-foreground transition-colors">
                    {selectedIds.size === paginatedData.length && paginatedData.length > 0
                      ? <CheckSquare size={14} className="text-primary" />
                      : <Square size={14} />}
                  </button>
                </th>
                {[
                  { key: 'id' as SortKey, label: 'Device ID' },
                  { key: 'hostname' as SortKey, label: 'Hostname' },
                  { key: 'osBuild' as SortKey, label: 'OS Build' },
                  { key: 'owner' as SortKey, label: 'Owner' },
                  { key: 'status' as SortKey, label: 'Status' },
                  { key: 'riskScore' as SortKey, label: 'Risk Score' },
                  { key: 'compliance' as SortKey, label: 'Compliance' },
                  { key: 'lastSeen' as SortKey, label: 'Last Seen' },
                  { key: 'agentVersion' as SortKey, label: 'Agent' },
                ].map((col) => (
                  <th
                    key={`col-${col.key}`}
                    className="px-3 py-3 text-left font-semibold text-muted-foreground tracking-wide uppercase text-[10px] cursor-pointer hover:text-foreground transition-colors whitespace-nowrap"
                    onClick={() => toggleSort(col.key)}
                  >
                    <span className="flex items-center gap-1">
                      {col.label}
                      <SortIcon k={col.key} />
                    </span>
                  </th>
                ))}
                <th className="px-3 py-3 text-left font-semibold text-muted-foreground tracking-wide uppercase text-[10px]">
                  Policy Sync
                </th>
                <th className="px-3 py-3 w-16" />
              </tr>
            </thead>
            <tbody className="divide-y divide-border">
              {paginatedData.length === 0 ? (
                <tr>
                  <td colSpan={12} className="px-4 py-12 text-center">
                    <Monitor size={32} className="mx-auto text-muted-foreground/30 mb-3" />
                    <p className="text-sm font-medium text-muted-foreground">No devices match your filters</p>
                    <p className="text-xs text-muted-foreground/60 mt-1">Try adjusting your search or filter criteria</p>
                  </td>
                </tr>
              ) : (
                paginatedData.map((device) => (
                  <tr
                    key={`device-row-${device.id}`}
                    className={`group hover:bg-muted/30 transition-colors cursor-pointer ${selectedIds.has(device.id) ? 'bg-primary/5' : ''}`}
                    onClick={() => setSelectedDevice(device)}
                  >
                    <td className="px-3 py-3" onClick={(e) => { e.stopPropagation(); toggleSelect(device.id); }}>
                      <button className="text-muted-foreground hover:text-foreground transition-colors">
                        {selectedIds.has(device.id)
                          ? <CheckSquare size={14} className="text-primary" />
                          : <Square size={14} />}
                      </button>
                    </td>
                    <td className="px-3 py-3 font-mono text-[11px] text-muted-foreground whitespace-nowrap">{device.id}</td>
                    <td className="px-3 py-3 font-medium whitespace-nowrap">{device.hostname}</td>
                    <td className="px-3 py-3 font-mono text-[11px] text-muted-foreground whitespace-nowrap">{device.osBuild}</td>
                    <td className="px-3 py-3 text-muted-foreground max-w-[160px] truncate">{device.owner}</td>
                    <td className="px-3 py-3 whitespace-nowrap">
                      <StatusBadge variant={device.status} pulse={device.status === 'online'} />
                    </td>
                    <td className="px-3 py-3 whitespace-nowrap">
                      <span className={`font-mono font-semibold tabular-nums ${riskColor(device.riskScore)}`}>
                        {(device.riskScore * 100).toFixed(0)}
                      </span>
                      <span className="text-muted-foreground">/100</span>
                    </td>
                    <td className="px-3 py-3 whitespace-nowrap">
                      <StatusBadge variant={device.compliance} />
                    </td>
                    <td className="px-3 py-3 tabular-nums text-muted-foreground whitespace-nowrap">{device.lastSeen}</td>
                    <td className="px-3 py-3 font-mono text-[11px] text-muted-foreground">{device.agentVersion}</td>
                    <td className="px-3 py-3 whitespace-nowrap">
                      {device.policySync ? (
                        <span className="text-[11px] text-green-400">✓ Synced</span>
                      ) : (
                        <span className="text-[11px] text-amber-400">⚠ Mismatch</span>
                      )}
                    </td>
                    <td className="px-3 py-3">
                      <div className="flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
                        <button
                          onClick={(e) => { e.stopPropagation(); setSelectedDevice(device); }}
                          className="p-1 rounded text-muted-foreground hover:text-foreground hover:bg-muted transition-colors"
                          title="View device detail"
                        >
                          <Eye size={13} />
                        </button>
                        <button
                          onClick={(e) => { e.stopPropagation(); toast.info(`Opening command panel for ${device.hostname}`); }}
                          className="p-1 rounded text-muted-foreground hover:text-blue-400 hover:bg-blue-500/10 transition-colors"
                          title="Dispatch command"
                        >
                          <Terminal size={13} />
                        </button>
                        <button
                          onClick={(e) => e.stopPropagation()}
                          className="p-1 rounded text-muted-foreground hover:text-foreground hover:bg-muted transition-colors"
                          title="More actions"
                        >
                          <MoreHorizontal size={13} />
                        </button>
                      </div>
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>

        {/* Pagination */}
        {filtered.length > 0 && (
          <div className="flex items-center justify-between px-4 py-3 border-t border-border">
            <p className="text-xs text-muted-foreground">
              Showing {(currentPage - 1) * pageSize + 1}–{Math.min(currentPage * pageSize, filtered.length)} of {filtered.length} devices
            </p>
            <div className="flex items-center gap-1">
              {Array.from({ length: totalPages }, (_, i) => i + 1).map((page) => (
                <button
                  key={`page-${page}`}
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

      {/* Device detail drawer */}
      {selectedDevice && (
        <DeviceDetailDrawer
          device={selectedDevice}
          onClose={() => setSelectedDevice(null)}
        />
      )}

      {showExport && (
        <ExportModal
          title="Devices"
          fields={[
            { key: 'id', label: 'Device ID' },
            { key: 'hostname', label: 'Hostname' },
            { key: 'os_build', label: 'OS Build' },
            { key: 'owner', label: 'Owner' },
            { key: 'status', label: 'Status' },
            { key: 'risk_score', label: 'Risk Score' },
            { key: 'compliance', label: 'Compliance' },
            { key: 'last_seen', label: 'Last Seen' },
            { key: 'agent_version', label: 'Agent Version' },
            { key: 'policy_sync', label: 'Policy Sync' },
            { key: 'kernel_guard', label: 'Kernel Guard' },
            { key: 'ip_address', label: 'IP Address' },
            { key: 'session_id', label: 'Session ID' },
          ]}
          onClose={() => setShowExport(false)}
        />
      )}
    </div>
  );
}