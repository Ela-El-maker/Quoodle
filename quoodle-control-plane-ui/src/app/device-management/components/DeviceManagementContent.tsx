'use client';
import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
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
import {
  mapListDevice,
  mergeDeviceDetail,
  parseStatusCsv,
  type DetailDeviceApi,
  type Device,
  type DeviceStatus,
  type ListDeviceApi,
} from '../lib/deviceManagementData';

type SortKey = keyof Device;

export default function DeviceManagementContent() {
  const router = useRouter();
  const searchParams = useSearchParams();

  const [devices, setDevices] = useState<Device[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [listError, setListError] = useState<string | null>(null);
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
  const listAbortRef = useRef<AbortController | null>(null);
  const detailAbortRef = useRef<AbortController | null>(null);

  const pageSize = 10;

  const fetchDevices = useCallback(async (mode: 'initial' | 'refresh' | 'silent' = 'initial') => {
    if (mode === 'initial') setIsLoading(true);
    if (mode === 'refresh') setIsRefreshing(true);
    listAbortRef.current?.abort();
    const controller = new AbortController();
    listAbortRef.current = controller;

    try {
      const response = await fetch('/api/devices?per_page=200', {
        method: 'GET',
        credentials: 'include',
        cache: 'no-store',
        signal: controller.signal,
      });
      if (!response.ok) throw new Error(`fetch_failed_${response.status}`);

      const payload = (await response.json()) as { devices?: ListDeviceApi[] };
      const mapped = (payload.devices ?? []).map(mapListDevice);
      setDevices(mapped);
      setSelectedIds((prev) => new Set([...prev].filter((id) => mapped.some((d) => d.id === id))));
      setListError(null);
    } catch (error) {
      if ((error as Error).name === 'AbortError') return;
      console.error('device-list-load-failed', error);
      setListError('Failed to load data');
      if (mode === 'initial') {
        setDevices([]);
        setSelectedIds(new Set());
      }
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
      detailAbortRef.current?.abort();
      const controller = new AbortController();
      detailAbortRef.current = controller;
      try {
        const response = await fetch(`/api/devices/${encodeURIComponent(deviceId)}`, {
          method: 'GET',
          credentials: 'include',
          cache: 'no-store',
          signal: controller.signal,
        });
        if (!response.ok) return;

        const detail = (await response.json()) as DetailDeviceApi;
        const merged = mergeDeviceDetail(baseDevice, detail);
        setDevices((prev) => prev.map((d) => (d.id === merged.id ? merged : d)));
        setSelectedDevice(merged);
      } catch (error) {
        if ((error as Error).name === 'AbortError') return;
        console.error('device-detail-load-failed', error);
        // Keep base device view if detail enrichment fails.
      }
    },
    [devices],
  );

  useEffect(() => {
    void fetchDevices('initial');
  }, [fetchDevices]);

  useEffect(() => {
    let interval: ReturnType<typeof setInterval> | null = null;
    const startPolling = () => {
      if (interval) {
        clearInterval(interval);
      }
      const pollMs = document.visibilityState === 'visible' ? 5000 : 30000;
      interval = setInterval(() => {
        void fetchDevices('silent');
      }, pollMs);
    };

    startPolling();
    const handleVisibility = () => startPolling();
    document.addEventListener('visibilitychange', handleVisibility);

    return () => {
      if (interval) {
        clearInterval(interval);
      }
      document.removeEventListener('visibilitychange', handleVisibility);
      listAbortRef.current?.abort();
      detailAbortRef.current?.abort();
    };
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

  const dispatchCommandToDevice = useCallback(
    async (deviceId: string, method: string, params: Record<string, unknown> = {}, sensitive = false) => {
      const payload = {
        client_message_id: `dm-${deviceId}-${method}-${crypto.randomUUID()}`,
        device_id: deviceId,
        method,
        params,
        sensitive,
      };
      const response = await fetch('/api/commands', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        credentials: 'include',
        body: JSON.stringify(payload),
      });
      const data = (await response.json().catch(() => ({}))) as {
        command_id?: string;
        reason?: string;
        message?: string;
      };

      if (!response.ok || !data.command_id) {
        return { ok: false as const, reason: data.reason ?? data.message ?? `http_${response.status}` };
      }
      return { ok: true as const, commandId: data.command_id };
    },
    [],
  );

  const dispatchBatch = useCallback(
    async (method: string, label: string, params: Record<string, unknown> = {}, sensitive = false) => {
      if (selectedIds.size === 0) return;
      const targets = Array.from(selectedIds);
      setIsBatchRefreshing(true);
      try {
        const results = await Promise.all(
          targets.map((deviceId) => dispatchCommandToDevice(deviceId, method, params, sensitive)),
        );

        const successCount = results.filter((result) => result.ok).length;
        const failCount = results.length - successCount;

        if (successCount > 0) {
          toast.success(`${label}: dispatched to ${successCount} device${successCount === 1 ? '' : 's'}`);
        }
        if (failCount > 0) {
          toast.error(`${label}: failed for ${failCount} device${failCount === 1 ? '' : 's'}`);
        }
      } catch (error) {
        console.error('device-batch-dispatch-failed', error);
        toast.error('Failed to load data');
      } finally {
        setIsBatchRefreshing(false);
      }
    },
    [dispatchCommandToDevice, selectedIds],
  );

  const handleBatchRefresh = async () => {
    setIsBatchRefreshing(true);
    try {
      await fetchDevices('refresh');
      toast.success(`Refreshed ${selectedIds.size} device${selectedIds.size !== 1 ? 's' : ''}`);
    } finally {
      setIsBatchRefreshing(false);
    }
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
              onClick={() => {
                void dispatchBatch('ping', 'Ping', {}, false);
              }}
              disabled={isBatchRefreshing}
              className="flex items-center gap-1.5 px-2.5 py-1 text-xs bg-blue-500/10 border border-blue-500/20 text-blue-400 rounded-md hover:bg-blue-500/20 transition-colors"
            >
              <Terminal size={11} /> Send Command
            </button>
            <button
              onClick={() => {
                void dispatchBatch('ping', 'Policy Sync Check', { policy_sync_probe: true }, false);
              }}
              disabled={isBatchRefreshing}
              className="flex items-center gap-1.5 px-2.5 py-1 text-xs bg-violet-500/10 border border-violet-500/20 text-violet-400 rounded-md hover:bg-violet-500/20 transition-colors"
            >
              <Layers size={11} /> Apply Policy
            </button>
            <button
              onClick={() => {
                void dispatchBatch('lock_screen', 'Lock Screen', {}, true);
              }}
              disabled={isBatchRefreshing}
              className="flex items-center gap-1.5 px-2.5 py-1 text-xs bg-amber-500/10 border border-amber-500/20 text-amber-400 rounded-md hover:bg-amber-500/20 transition-colors"
            >
              <Shield size={11} /> Lock All
            </button>
            <button
              onClick={() => {
                void handleBatchRefresh();
              }}
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
              ) : listError ? (
                <tr>
                  <td colSpan={12} className="px-4 py-12 text-center text-red-400">
                    Failed to load data
                  </td>
                </tr>
              ) : paginatedData.length === 0 ? (
                <tr>
                  <td colSpan={12} className="px-4 py-12 text-center">
                    <Monitor size={32} className="mx-auto text-muted-foreground/30 mb-3" />
                    <p className="text-sm font-medium text-muted-foreground">No devices found</p>
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
                            router.push(`/device-detail?device=${encodeURIComponent(device.id)}`);
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
