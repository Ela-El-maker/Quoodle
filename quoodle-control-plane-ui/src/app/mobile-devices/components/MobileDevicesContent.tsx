'use client';

import React, { useCallback, useEffect, useMemo, useState } from 'react';
import Link from 'next/link';
import { Link2, RefreshCw, Search, Smartphone } from 'lucide-react';
import { formatLocalDateTime } from '@/lib/dateTime';
import { mapCommandListRow, originChannelLabel, type CommandListRowApi } from '@/lib/commandResults';

type SyncState = 'synced' | 'idle' | 'stale' | 'offline';

interface MobileLinkedDeviceApi {
  device_id?: string | null;
  device_name?: string | null;
  linked_at?: string | null;
  linked_via?: string | null;
}

interface MobileDeviceApi {
  id?: string | null;
  device_fingerprint?: string | null;
  platform?: string | null;
  os_version?: string | null;
  device_model?: string | null;
  app_version?: string | null;
  push_token?: string | null;
  first_seen_at?: string | null;
  last_seen_at?: string | null;
  linked_devices?: MobileLinkedDeviceApi[] | null;
}

interface MobileDevicesResponse {
  mobile_devices?: MobileDeviceApi[];
}

interface CommandsResponse {
  commands?: CommandListRowApi[];
}

interface MobileDeviceRow {
  id: string;
  fingerprint: string;
  platform: string;
  osVersion: string;
  model: string;
  appVersion: string;
  firstSeenAt: string | null;
  lastSeenAt: string | null;
  linkedDevices: Array<{
    deviceId: string;
    deviceName: string;
    linkedAt: string | null;
    linkedVia: string;
  }>;
}

function toSyncState(lastSeenAt: string | null): SyncState {
  if (!lastSeenAt) return 'offline';
  const lastSeenMs = Date.parse(lastSeenAt);
  if (!Number.isFinite(lastSeenMs)) return 'offline';

  const deltaMs = Date.now() - lastSeenMs;
  if (deltaMs <= 2 * 60 * 1000) return 'synced';
  if (deltaMs <= 15 * 60 * 1000) return 'idle';
  if (deltaMs <= 24 * 60 * 60 * 1000) return 'stale';
  return 'offline';
}

function syncStateBadgeClass(sync: SyncState): string {
  switch (sync) {
    case 'synced':
      return 'bg-green-500/10 text-green-400 border border-green-500/20';
    case 'idle':
      return 'bg-blue-500/10 text-blue-400 border border-blue-500/20';
    case 'stale':
      return 'bg-amber-500/10 text-amber-400 border border-amber-500/20';
    default:
      return 'bg-muted text-muted-foreground border border-border';
  }
}

function syncStateLabel(sync: SyncState): string {
  switch (sync) {
    case 'synced':
      return 'Synced';
    case 'idle':
      return 'Idle';
    case 'stale':
      return 'Stale';
    default:
      return 'Offline';
  }
}

function mapMobileDevice(row: MobileDeviceApi): MobileDeviceRow {
  const fingerprint = String(row.device_fingerprint ?? '').trim();
  const fallbackIdBase = [
    String(row.platform ?? '').trim().toLowerCase(),
    String(row.device_model ?? '').trim().toLowerCase(),
    String(row.first_seen_at ?? '').trim().toLowerCase(),
  ]
    .filter((part) => part !== '')
    .join('-')
    .replace(/[^a-z0-9-]/g, '');
  const id = String(row.id ?? '').trim() || fingerprint || (fallbackIdBase !== '' ? fallbackIdBase : 'mobile-unknown');

  return {
    id,
    fingerprint,
    platform: String(row.platform ?? '').trim() || 'Unknown',
    osVersion: String(row.os_version ?? '').trim() || '-',
    model: String(row.device_model ?? '').trim() || 'Unspecified model',
    appVersion: String(row.app_version ?? '').trim() || '-',
    firstSeenAt: typeof row.first_seen_at === 'string' ? row.first_seen_at : null,
    lastSeenAt: typeof row.last_seen_at === 'string' ? row.last_seen_at : null,
    linkedDevices: (row.linked_devices ?? [])
      .map((link) => ({
        deviceId: String(link.device_id ?? '').trim(),
        deviceName: String(link.device_name ?? '').trim() || String(link.device_id ?? '').trim() || 'Unknown device',
        linkedAt: typeof link.linked_at === 'string' ? link.linked_at : null,
        linkedVia: String(link.linked_via ?? '').trim() || 'pair_confirm',
      }))
      .filter((link) => link.deviceId !== ''),
  };
}

export default function MobileDevicesContent() {
  const [devices, setDevices] = useState<MobileDeviceRow[]>([]);
  const [commands, setCommands] = useState<CommandListRowApi[]>([]);
  const [expanded, setExpanded] = useState<Set<string>>(new Set());
  const [search, setSearch] = useState('');
  const [syncFilter, setSyncFilter] = useState<'all' | SyncState>('all');
  const [isLoading, setIsLoading] = useState(true);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const fetchData = useCallback(async (mode: 'initial' | 'refresh' | 'silent' = 'initial') => {
    if (mode === 'initial') setIsLoading(true);
    if (mode === 'refresh') setIsRefreshing(true);

    try {
      const [mobileRes, commandRes] = await Promise.all([
        fetch('/api/mobile-devices', { credentials: 'include', cache: 'no-store' }),
        fetch('/api/commands?limit=300', { credentials: 'include', cache: 'no-store' }),
      ]);

      if (!mobileRes.ok) {
        throw new Error(`mobile_devices_${mobileRes.status}`);
      }

      const mobilePayload = (await mobileRes.json()) as MobileDevicesResponse;
      const mappedDevices = (mobilePayload.mobile_devices ?? []).map(mapMobileDevice);

      let commandRows: CommandListRowApi[] = [];
      if (commandRes.ok) {
        const commandPayload = (await commandRes.json()) as CommandsResponse;
        commandRows = commandPayload.commands ?? [];
      }

      setDevices(mappedDevices);
      setCommands(commandRows);
      setError(null);
    } catch (fetchError) {
      console.error('mobile-devices-load-failed', fetchError);
      setError('Failed to load data');
      if (mode === 'initial') {
        setDevices([]);
        setCommands([]);
      }
    } finally {
      if (mode === 'initial') setIsLoading(false);
      if (mode === 'refresh') setIsRefreshing(false);
    }
  }, []);

  useEffect(() => {
    void fetchData('initial');
  }, [fetchData]);

  useEffect(() => {
    const timer = setInterval(() => {
      void fetchData('silent');
    }, 15000);
    return () => clearInterval(timer);
  }, [fetchData]);

  const commands24h = useMemo(() => {
    const cutoff = Date.now() - 24 * 60 * 60 * 1000;
    return commands
      .map((row) => mapCommandListRow(row))
      .filter((row) => {
        if (!row.queuedAt) return false;
        const ts = Date.parse(row.queuedAt);
        return Number.isFinite(ts) && ts >= cutoff;
      });
  }, [commands]);

  const filtered = useMemo(() => {
    const term = search.trim().toLowerCase();
    return devices.filter((device) => {
      const sync = toSyncState(device.lastSeenAt);
      if (syncFilter !== 'all' && sync !== syncFilter) return false;
      if (!term) return true;

      return (
        device.model.toLowerCase().includes(term) ||
        device.platform.toLowerCase().includes(term) ||
        device.fingerprint.toLowerCase().includes(term) ||
        device.linkedDevices.some((link) => (
          link.deviceId.toLowerCase().includes(term) ||
          link.deviceName.toLowerCase().includes(term)
        ))
      );
    });
  }, [devices, search, syncFilter]);

  const summary = useMemo(() => {
    const counts = {
      total: filtered.length,
      synced: 0,
      idle: 0,
      stale: 0,
      offline: 0,
    };

    for (const device of filtered) {
      const sync = toSyncState(device.lastSeenAt);
      counts[sync] += 1;
    }

    return counts;
  }, [filtered]);

  return (
    <div className="space-y-4 fade-in">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">Mobile Devices</h1>
          <p className="text-sm text-muted-foreground mt-0.5">
            Mobile app sessions linked to managed endpoints and command-source activity
          </p>
        </div>
        <button
          onClick={() => {
            void fetchData('refresh');
          }}
          className="flex items-center gap-1.5 px-3 py-1.5 text-xs text-muted-foreground border border-border rounded-md hover:bg-muted/60 transition-colors"
        >
          <RefreshCw size={13} className={isRefreshing ? 'animate-spin' : ''} />
          Refresh
        </button>
      </div>

      {error && (
        <div className="bg-card border border-red-500/20 rounded-lg px-4 py-3 text-sm text-red-300">
          Failed to load data
        </div>
      )}

      <div className="grid grid-cols-2 md:grid-cols-5 gap-2">
        <div className="bg-card border border-border rounded-md px-3 py-2">
          <p className="text-[10px] uppercase tracking-wide text-muted-foreground">Total</p>
          <p className="text-lg font-semibold">{summary.total}</p>
        </div>
        <div className="bg-card border border-border rounded-md px-3 py-2">
          <p className="text-[10px] uppercase tracking-wide text-muted-foreground">Synced</p>
          <p className="text-lg font-semibold text-green-400">{summary.synced}</p>
        </div>
        <div className="bg-card border border-border rounded-md px-3 py-2">
          <p className="text-[10px] uppercase tracking-wide text-muted-foreground">Idle</p>
          <p className="text-lg font-semibold text-blue-400">{summary.idle}</p>
        </div>
        <div className="bg-card border border-border rounded-md px-3 py-2">
          <p className="text-[10px] uppercase tracking-wide text-muted-foreground">Stale</p>
          <p className="text-lg font-semibold text-amber-400">{summary.stale}</p>
        </div>
        <div className="bg-card border border-border rounded-md px-3 py-2">
          <p className="text-[10px] uppercase tracking-wide text-muted-foreground">Offline</p>
          <p className="text-lg font-semibold text-muted-foreground">{summary.offline}</p>
        </div>
      </div>

      <div className="flex flex-wrap items-center gap-2">
        <div className="relative flex-1 min-w-[220px] max-w-sm">
          <Search size={13} className="absolute left-2.5 top-1/2 -translate-y-1/2 text-muted-foreground" />
          <input
            type="text"
            placeholder="Search model, platform, fingerprint, linked device..."
            value={search}
            onChange={(event) => setSearch(event.target.value)}
            className="w-full pl-8 pr-3 py-1.5 text-xs bg-muted/60 border border-border rounded-md text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-1 focus:ring-primary/50"
          />
        </div>
        <select
          value={syncFilter}
          onChange={(event) => setSyncFilter(event.target.value as 'all' | SyncState)}
          className="text-xs bg-muted/60 border border-border rounded-md px-2.5 py-1.5 text-foreground focus:outline-none focus:ring-1 focus:ring-primary/50"
        >
          <option value="all">All Sync States</option>
          <option value="synced">Synced</option>
          <option value="idle">Idle</option>
          <option value="stale">Stale</option>
          <option value="offline">Offline</option>
        </select>
      </div>

      <div className="bg-card border border-border rounded-lg overflow-hidden">
        <div className="overflow-x-auto scrollbar-thin">
          <table className="w-full text-xs">
            <thead>
              <tr className="border-b border-border bg-muted/20">
                <th className="px-3 py-3 text-left font-semibold text-muted-foreground tracking-wide uppercase text-[10px]">Mobile Device</th>
                <th className="px-3 py-3 text-left font-semibold text-muted-foreground tracking-wide uppercase text-[10px]">Platform</th>
                <th className="px-3 py-3 text-left font-semibold text-muted-foreground tracking-wide uppercase text-[10px]">App Version</th>
                <th className="px-3 py-3 text-left font-semibold text-muted-foreground tracking-wide uppercase text-[10px]">Sync</th>
                <th className="px-3 py-3 text-left font-semibold text-muted-foreground tracking-wide uppercase text-[10px]">Last Seen</th>
                <th className="px-3 py-3 text-left font-semibold text-muted-foreground tracking-wide uppercase text-[10px]">Linked Endpoints</th>
                <th className="px-3 py-3 text-left font-semibold text-muted-foreground tracking-wide uppercase text-[10px]">Cmd Source (24h)</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-border">
              {isLoading ? (
                <tr>
                  <td colSpan={7} className="px-4 py-12 text-center text-muted-foreground">
                    Loading mobile devices...
                  </td>
                </tr>
              ) : filtered.length === 0 ? (
                <tr>
                  <td colSpan={7} className="px-4 py-12 text-center">
                    <Smartphone size={32} className="mx-auto text-muted-foreground/30 mb-3" />
                    <p className="text-sm font-medium text-muted-foreground">No mobile devices found</p>
                  </td>
                </tr>
              ) : (
                filtered.map((device) => {
                  const isExpanded = expanded.has(device.id);
                  const sync = toSyncState(device.lastSeenAt);
                  const linkedIds = new Set(device.linkedDevices.map((link) => link.deviceId));
                  const relatedCommands = commands24h.filter((command) => linkedIds.has(command.deviceId));
                  const mobileSent = relatedCommands.filter((command) => command.originChannel === 'mobile_app').length;
                  const controlUiSent = relatedCommands.filter((command) => command.originChannel === 'control_ui').length;
                  const otherSent = relatedCommands.length - mobileSent - controlUiSent;

                  return (
                    <React.Fragment key={device.id}>
                      <tr
                        className={`hover:bg-muted/30 transition-colors cursor-pointer ${isExpanded ? 'bg-muted/20' : ''}`}
                        onClick={() => {
                          setExpanded((prev) => {
                            const next = new Set(prev);
                            if (next.has(device.id)) {
                              next.delete(device.id);
                            } else {
                              next.add(device.id);
                            }
                            return next;
                          });
                        }}
                      >
                        <td className="px-3 py-3">
                          <div className="flex items-center gap-2">
                            <Smartphone size={14} className="text-muted-foreground" />
                            <div>
                              <p className="font-medium">{device.model}</p>
                              <p className="text-[11px] text-muted-foreground font-mono max-w-[260px] truncate">{device.fingerprint}</p>
                            </div>
                          </div>
                        </td>
                        <td className="px-3 py-3 whitespace-nowrap">{device.platform} {device.osVersion !== '-' ? `(${device.osVersion})` : ''}</td>
                        <td className="px-3 py-3 font-mono text-[11px] text-muted-foreground">{device.appVersion}</td>
                        <td className="px-3 py-3">
                          <span className={`px-2 py-0.5 rounded-full text-[10px] font-semibold uppercase tracking-wide ${syncStateBadgeClass(sync)}`}>
                            {syncStateLabel(sync)}
                          </span>
                        </td>
                        <td className="px-3 py-3 tabular-nums text-muted-foreground whitespace-nowrap">{formatLocalDateTime(device.lastSeenAt, 'Never')}</td>
                        <td className="px-3 py-3">
                          <span className="px-2 py-0.5 rounded bg-muted/60 text-muted-foreground">
                            {device.linkedDevices.length}
                          </span>
                        </td>
                        <td className="px-3 py-3">
                          <div className="flex items-center gap-1 flex-wrap">
                            <span className="px-2 py-0.5 rounded bg-blue-500/10 text-blue-400 text-[10px]">UI {controlUiSent}</span>
                            <span className="px-2 py-0.5 rounded bg-green-500/10 text-green-400 text-[10px]">Mobile {mobileSent}</span>
                            <span className="px-2 py-0.5 rounded bg-muted text-muted-foreground text-[10px]">Other {Math.max(otherSent, 0)}</span>
                          </div>
                        </td>
                      </tr>
                      {isExpanded && (
                        <tr className="bg-muted/10">
                          <td colSpan={7} className="px-4 py-4">
                            {device.linkedDevices.length === 0 ? (
                              <p className="text-xs text-muted-foreground">No linked endpoints for this mobile session yet.</p>
                            ) : (
                              <div className="space-y-2">
                                <p className="text-[11px] text-muted-foreground uppercase tracking-wide">Linked Endpoints</p>
                                <div className="grid gap-2">
                                  {device.linkedDevices.map((link) => (
                                    <div key={`${device.id}-${link.deviceId}`} className="flex items-center justify-between bg-muted/20 border border-border rounded-md px-3 py-2">
                                      <div className="flex items-center gap-2">
                                        <Link2 size={12} className="text-muted-foreground" />
                                        <div>
                                          <p className="text-xs font-medium">{link.deviceName}</p>
                                          <p className="text-[11px] text-muted-foreground font-mono">{link.deviceId}</p>
                                        </div>
                                      </div>
                                      <div className="text-right">
                                        <p className="text-[11px] text-muted-foreground">{formatLocalDateTime(link.linkedAt, '-')}</p>
                                        <p className="text-[10px] text-muted-foreground uppercase tracking-wide">{link.linkedVia}</p>
                                      </div>
                                      <Link
                                        href={`/device-detail?device=${encodeURIComponent(link.deviceId)}`}
                                        className="ml-3 text-[11px] text-primary hover:underline"
                                        onClick={(event) => event.stopPropagation()}
                                      >
                                        Open
                                      </Link>
                                    </div>
                                  ))}
                                </div>
                                <p className="text-[11px] text-muted-foreground">
                                  Command source labels:
                                  {' '}
                                  <span className="text-blue-400">{originChannelLabel('control_ui')}</span>
                                  {' / '}
                                  <span className="text-green-400">{originChannelLabel('mobile_app')}</span>
                                  {' / '}
                                  <span className="text-muted-foreground">Other</span>
                                </p>
                              </div>
                            )}
                          </td>
                        </tr>
                      )}
                    </React.Fragment>
                  );
                })
              )}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
