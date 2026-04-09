'use client';
import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { useSearchParams } from 'next/navigation';
import {
  Search,
  SlidersHorizontal,
  Download,
  RefreshCw,
  ChevronUp,
  ChevronDown,
  MoreHorizontal,
  Terminal,
  Eye,
  Shield,
  Monitor,
  X,
  CheckSquare,
  Square,
  RotateCcw,
  Layers,
} from 'lucide-react';
import StatusBadge from '@/components/ui/StatusBadge';
import DeviceDetailDrawer from './DeviceDetailDrawer';
import ExportModal from '@/components/ExportModal';
import { toast } from 'sonner';

type DeviceStatus = 'online' | 'offline' | 'quarantined' | 'degraded';
type ComplianceStatus = 'compliant' | 'non_compliant' | 'drift';

interface Device {
  id: string;
  hostname: string;
  osBuild: string;
  owner: string;
  status: DeviceStatus;
  riskScore: number; // normalized 0..1 for existing UI
  compliance: ComplianceStatus;
  lastSeen: string;
  agentVersion: string;
  policySync: boolean | null;
  kernelGuard: boolean | null;
  ipAddress: string | null;
  sessionId: string | null;
}

interface ListDeviceApi {
  device_id: string;
  owner_email?: string | null;
  device_name?: string | null;
  lifecycle_state?: string | null;
  last_seen?: string | null;
  agent_version?: string | null;
  os_build?: string | null;
  compliance_status?: string | null;
  risk_score?: number | string | null;
}

interface DetailDeviceApi {
  device_id: string;
  owner_email?: string | null;
  device_name?: string | null;
  lifecycle_state?: string | null;
  last_seen?: string | null;
  agent_version?: string | null;
  os_build?: string | null;
  compliance?: { status?: string | null };
  compliance_status?: string | null;
  risk_score?: number | string | null;
  policy_in_sync?: boolean | null;
  telemetry_latest?: { risk_score?: number | string | null };
  ip_address?: string | null;
  session_id?: string | null;
  kernel_guard?: boolean | null;
}

type SortKey = keyof Device;

const VALID_STATUSES: DeviceStatus[] = ['online', 'offline', 'degraded', 'quarantined'];

function normalizeStatus(value: string | null | undefined): DeviceStatus {
  const normalized = String(value ?? '').toLowerCase();
  if (normalized === 'online' || normalized === 'active') return 'online';
  if (normalized === 'quarantined') return 'quarantined';
  if (normalized === 'degraded') return 'degraded';
  return 'offline';
}

function normalizeCompliance(value: string | null | undefined): ComplianceStatus {
  const normalized = String(value ?? '').toLowerCase();
  if (normalized === 'compliant') return 'compliant';
  if (normalized === 'drift' || normalized === 'degraded' || normalized === 'unknown') return 'drift';
  return 'non_compliant';
}

function normalizeRisk(value: number | string | null | undefined): number {
  const parsed = typeof value === 'number' ? value : Number(value ?? 0);
  if (!Number.isFinite(parsed) || parsed <= 0) return 0;
  if (parsed > 1) return Math.max(0, Math.min(1, parsed / 100));
  return Math.max(0, Math.min(1, parsed));
}

function formatLastSeen(value: string | null | undefined): string {
  if (!value) return '-';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return '-';
  return date.toISOString().replace('T', ' ').replace('Z', ' UTC').slice(0, 23);
}

function parseStatusCsv(value: string | null): DeviceStatus[] {
  if (!value) return [];
  return value
    .split(',')
    .map((v) => v.trim().toLowerCase())
    .filter((v): v is DeviceStatus => VALID_STATUSES.includes(v as DeviceStatus));
}

function mapListDevice(item: ListDeviceApi): Device {
  return {
    id: item.device_id,
    hostname: item.device_name?.trim() || item.device_id,
    osBuild: item.os_build?.trim() || '-',
    owner: item.owner_email?.trim() || 'Unknown',
    status: normalizeStatus(item.lifecycle_state),
    riskScore: normalizeRisk(item.risk_score),
    compliance: normalizeCompliance(item.compliance_status),
    lastSeen: formatLastSeen(item.last_seen),
    agentVersion: item.agent_version?.trim() || '-',
    policySync: null,
    kernelGuard: null,
    ipAddress: null,
    sessionId: null,
  };
}

function mergeDetail(base: Device, detail: DetailDeviceApi): Device {
  return {
    ...base,
    hostname: detail.device_name?.trim() || base.hostname,
    osBuild: detail.os_build?.trim() || base.osBuild,
    owner: detail.owner_email?.trim() || base.owner,
    status: normalizeStatus(detail.lifecycle_state ?? base.status),
    compliance: normalizeCompliance(detail.compliance?.status ?? detail.compliance_status ?? base.compliance),
    riskScore: normalizeRisk(
      detail.risk_score ?? detail.telemetry_latest?.risk_score ?? base.riskScore,
    ),
    lastSeen: formatLastSeen(detail.last_seen) !== '-' ? formatLastSeen(detail.last_seen) : base.lastSeen,
    agentVersion: detail.agent_version?.trim() || base.agentVersion,
    policySync: typeof detail.policy_in_sync === 'boolean' ? detail.policy_in_sync : base.policySync,
    kernelGuard: typeof detail.kernel_guard === 'boolean' ? detail.kernel_guard : base.kernelGuard,
    ipAddress: detail.ip_address?.trim() || base.ipAddress,
    sessionId: detail.session_id?.trim() || base.sessionId,
  };
}

export default function DeviceManagementContent() {
  const searchParams = useSearchParams();

  const [devices, setDevices] = useState<Device[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState<string>('all');
  const [statusCsvFilter, setStatusCsvFilter] = useState<DeviceStatus[] | null>(null);
  const [complianceFilter, setComplianceFilter] = useState<string>('all');
  const [sortKey, setSortKey] = useState<SortKey>('lastSeen');
  const [sortDir, setSortDir] = useState<'asc' | 'desc'>('desc');
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());
  const [selectedDevice, setSelectedDevice] = useState<Device | null>(null);
  const [currentPage, setCurrentPage] = useState(1);
  const [showExport, setShowExport] = useState(false);
  const [isBatchRefreshing, setIsBatchRefreshing] = useState(false);
  const [pendingOpenDeviceId, setPendingOpenDeviceId] = useState<string | null>(null);

  const pageSize = 10;

  const fetchDevices = useCallback(async (mode: 'initial' | 'refresh' = 'initial') => {
    if (mode === 'initial') setIsLoading(true);
    if (mode === 'refresh') setIsRefreshing(true);

    try {
      const response = await fetch('/api/devices?per_page=200', {
        method: 'GET',
        credentials: 'include',
        cache: 'no-store',
      });
      if (!response.ok) throw new Error(`fetch_failed_${response.status}`);

      const payload = (await response.json()) as { devices?: ListDeviceApi[] };
      const mapped = (payload.devices ?? []).map(mapListDevice);
      setDevices(mapped);
      setSelectedIds((prev) => new Set([...prev].filter((id) => mapped.some((d) => d.id === id))));
    } catch {
      toast.error('Could not load devices');
      setDevices([]);
      setSelectedIds(new Set());
    } finally {
      if (mode === 'initial') setIsLoading(false);
      if (mode === 'refresh') setIsRefreshing(false);
    }
  }, []);

  const openDeviceWithDetail = useCallback(
    async (deviceId: string) => {
      const baseDevice = devices.find((d) => d.id === deviceId);
      if (!baseDevice) return;

      setSelectedDevice(baseDevice);
      try {
        const response = await fetch(`/api/devices/${encodeURIComponent(deviceId)}`, {
          method: 'GET',
          credentials: 'include',
          cache: 'no-store',
        });
        if (!response.ok) return;

        const detail = (await response.json()) as DetailDeviceApi;
        const merged = mergeDetail(baseDevice, detail);
        setDevices((prev) => prev.map((d) => (d.id === merged.id ? merged : d)));
        setSelectedDevice(merged);
      } catch {
        // Keep base device view if detail enrichment fails.
      }
    },
    [devices],
  );

  useEffect(() => {
    void fetchDevices('initial');
  }, [fetchDevices]);

  useEffect(() => {
    const statusParam = searchParams.get('status');
    const idParam = searchParams.get('id');

    const statuses = parseStatusCsv(statusParam);
    if (statuses.length === 1) {
      setStatusFilter(statuses[0]);
      setStatusCsvFilter(null);
      setCurrentPage(1);
    } else if (statuses.length > 1) {
      setStatusFilter('all');
      setStatusCsvFilter(statuses);
      setCurrentPage(1);
    }

    if (idParam) setPendingOpenDeviceId(idParam);
  }, [searchParams]);

  useEffect(() => {
    if (!pendingOpenDeviceId || devices.length === 0) return;
    const found = devices.find((d) => d.id === pendingOpenDeviceId);
    if (found) {
      void openDeviceWithDetail(found.id);
    }
    setPendingOpenDeviceId(null);
  }, [pendingOpenDeviceId, devices, openDeviceWithDetail]);

  const filtered = useMemo(() => {
    const loweredSearch = search.trim().toLowerCase();
    const statusSet = statusCsvFilter && statusCsvFilter.length > 0 ? new Set(statusCsvFilter) : null;

    const data = devices.filter((d) => {
      const matchSearch =
        !loweredSearch ||
        d.hostname.toLowerCase().includes(loweredSearch) ||
        d.id.toLowerCase().includes(loweredSearch) ||
        d.owner.toLowerCase().includes(loweredSearch);

      const matchStatus = statusSet
        ? statusSet.has(d.status)
        : statusFilter === 'all' || d.status === statusFilter;

      const matchCompliance = complianceFilter === 'all' || d.compliance === complianceFilter;
      return matchSearch && matchStatus && matchCompliance;
    });

    data.sort((a, b) => {
      if (sortKey === 'lastSeen') {
        const av = Date.parse(a.lastSeen);
        const bv = Date.parse(b.lastSeen);
        if (!Number.isNaN(av) && !Number.isNaN(bv)) return sortDir === 'asc' ? av - bv : bv - av;
      }

      const av = a[sortKey];
      const bv = b[sortKey];

      if (typeof av === 'string' && typeof bv === 'string') {
        return sortDir === 'asc' ? av.localeCompare(bv) : bv.localeCompare(av);
      }
      if (typeof av === 'number' && typeof bv === 'number') {
        return sortDir === 'asc' ? av - bv : bv - av;
      }
      if (typeof av === 'boolean' && typeof bv === 'boolean') {
        return sortDir === 'asc' ? Number(av) - Number(bv) : Number(bv) - Number(av);
      }
      return 0;
    });

    return data;
  }, [devices, search, statusFilter, statusCsvFilter, complianceFilter, sortKey, sortDir]);

  useEffect(() => {
    const totalPages = Math.max(1, Math.ceil(filtered.length / pageSize));
    if (currentPage > totalPages) setCurrentPage(totalPages);
  }, [filtered.length, currentPage]);

  const totalPages = Math.ceil(filtered.length / pageSize);
  const paginatedData = filtered.slice((currentPage - 1) * pageSize, currentPage * pageSize);

  const toggleSort = (key: SortKey) => {
    if (sortKey === key) setSortDir(sortDir === 'asc' ? 'desc' : 'asc');
    else {
      setSortKey(key);
      setSortDir('asc');
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
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">Device Management</h1>
          <p className="text-sm text-muted-foreground mt-0.5">
            {filtered.length} device{filtered.length !== 1 ? 's' : ''} - Fleet operational triage
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
            onClick={() => {
              void fetchDevices('refresh');
            }}
            className="flex items-center gap-1.5 px-3 py-1.5 text-xs text-muted-foreground border border-border rounded-md hover:bg-muted/60 transition-colors"
          >
            <RefreshCw size={13} className={isRefreshing ? 'animate-spin' : ''} />
            {isRefreshing ? 'Refreshing...' : 'Refresh'}
          </button>
        </div>
      </div>

      <div className="flex flex-wrap items-center gap-2">
        <div className="relative flex-1 min-w-[200px] max-w-xs">
          <Search size={13} className="absolute left-2.5 top-1/2 -translate-y-1/2 text-muted-foreground" />
          <input
            type="text"
            placeholder="Search hostname, device ID, owner..."
            value={search}
            onChange={(e) => {
              setSearch(e.target.value);
              setCurrentPage(1);
            }}
            className="w-full pl-8 pr-3 py-1.5 text-xs bg-muted/60 border border-border rounded-md text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-1 focus:ring-primary/50"
          />
        </div>

        <div className="flex items-center gap-1.5">
          <SlidersHorizontal size={13} className="text-muted-foreground" />
          <span className="text-xs text-muted-foreground">Filters:</span>
        </div>

        <select
          value={statusFilter}
          onChange={(e) => {
            setStatusFilter(e.target.value);
            setStatusCsvFilter(null);
            setCurrentPage(1);
          }}
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
          onChange={(e) => {
            setComplianceFilter(e.target.value);
            setCurrentPage(1);
          }}
          className="text-xs bg-muted/60 border border-border rounded-md px-2.5 py-1.5 text-foreground focus:outline-none focus:ring-1 focus:ring-primary/50"
        >
          <option value="all">All Compliance</option>
          <option value="compliant">Compliant</option>
          <option value="non_compliant">Non-Compliant</option>
          <option value="drift">Drift</option>
        </select>

        {(search || statusFilter !== 'all' || complianceFilter !== 'all' || !!statusCsvFilter) && (
          <button
            onClick={() => {
              setSearch('');
              setStatusFilter('all');
              setStatusCsvFilter(null);
              setComplianceFilter('all');
              setCurrentPage(1);
            }}
            className="flex items-center gap-1 text-xs text-muted-foreground hover:text-foreground transition-colors"
          >
            <X size={12} /> Clear
          </button>
        )}
      </div>

      {selectedIds.size > 0 && (
        <div className="flex flex-wrap items-center gap-2 px-4 py-2.5 bg-primary/10 border border-primary/20 rounded-lg text-sm slide-in-right">
          <span className="text-primary font-medium">{selectedIds.size} selected</span>
          <span className="text-border">|</span>
          <button onClick={toggleAll} className="text-xs text-muted-foreground hover:text-foreground transition-colors">
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
              onClick={() => toast.info(`Applying policy to ${selectedIds.size} devices...`)}
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
              {isBatchRefreshing ? 'Refreshing...' : 'Batch Refresh'}
            </button>
          </div>
          <button onClick={() => setSelectedIds(new Set())} className="ml-auto text-muted-foreground hover:text-foreground transition-colors">
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
                  <button onClick={toggleAll} className="text-muted-foreground hover:text-foreground transition-colors">
                    {selectedIds.size === paginatedData.length && paginatedData.length > 0 ? (
                      <CheckSquare size={14} className="text-primary" />
                    ) : (
                      <Square size={14} />
                    )}
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
                <th className="px-3 py-3 text-left font-semibold text-muted-foreground tracking-wide uppercase text-[10px]">Policy Sync</th>
                <th className="px-3 py-3 w-16" />
              </tr>
            </thead>
            <tbody className="divide-y divide-border">
              {isLoading ? (
                <tr>
                  <td colSpan={12} className="px-4 py-12 text-center text-muted-foreground">
                    Loading devices...
                  </td>
                </tr>
              ) : paginatedData.length === 0 ? (
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
                    onClick={() => {
                      void openDeviceWithDetail(device.id);
                    }}
                  >
                    <td
                      className="px-3 py-3"
                      onClick={(e) => {
                        e.stopPropagation();
                        toggleSelect(device.id);
                      }}
                    >
                      <button className="text-muted-foreground hover:text-foreground transition-colors">
                        {selectedIds.has(device.id) ? <CheckSquare size={14} className="text-primary" /> : <Square size={14} />}
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
                      {device.policySync === null ? (
                        <span className="text-[11px] text-muted-foreground">- Unknown</span>
                      ) : device.policySync ? (
                        <span className="text-[11px] text-green-400">Synced</span>
                      ) : (
                        <span className="text-[11px] text-amber-400">Mismatch</span>
                      )}
                    </td>
                    <td className="px-3 py-3">
                      <div className="flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
                        <button
                          onClick={(e) => {
                            e.stopPropagation();
                            void openDeviceWithDetail(device.id);
                          }}
                          className="p-1 rounded text-muted-foreground hover:text-foreground hover:bg-muted transition-colors"
                          title="View device detail"
                        >
                          <Eye size={13} />
                        </button>
                        <button
                          onClick={(e) => {
                            e.stopPropagation();
                            toast.info(`Opening command panel for ${device.hostname}`);
                          }}
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

        {filtered.length > 0 && (
          <div className="flex items-center justify-between px-4 py-3 border-t border-border">
            <p className="text-xs text-muted-foreground">
              Showing {(currentPage - 1) * pageSize + 1}-{Math.min(currentPage * pageSize, filtered.length)} of {filtered.length} devices
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

      {selectedDevice && <DeviceDetailDrawer device={selectedDevice} onClose={() => setSelectedDevice(null)} />}

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

