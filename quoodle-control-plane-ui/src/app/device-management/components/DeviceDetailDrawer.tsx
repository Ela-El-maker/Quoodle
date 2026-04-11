'use client';
import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { X, Monitor, Terminal, Shield, Activity, Clock, Cpu, HardDrive, Wifi, ChevronRight, AlertTriangle, CheckCircle, XCircle, RotateCcw, Bell, Layers, ExternalLink, Radio, Loader2, Network, Users, Camera, Folder, Info, Lock } from 'lucide-react';
import StatusBadge from '@/components/ui/StatusBadge';
import { formatLocalTime } from '@/lib/dateTime';
import { resolveCommandMethod } from '@/lib/commandMethodResolver';
import Link from 'next/link';
import { toast } from 'sonner';
import {
  clampPercent,
  mapCommandHistoryEntry,
  mergeDeviceDetail,
  normalizeRisk,
  type CommandCapabilitiesResponse,
  type DetailDeviceApi,
  type Device,
  type DeviceAlertsResponse,
  type DeviceAuditApi,
  type DeviceAuditResponse,
  type DeviceCommandsResponse,
  type DeviceTelemetryResponse,
  type DrawerCommandEntry,
} from '../lib/deviceManagementData';

interface DeviceDetailDrawerProps {
  device: Device;
  onClose: () => void;
}

interface CommandDispatchResponse {
  command_id?: string;
  reason?: string;
  message?: string;
}

type QuickCommand = {
  id: string;
  label: string;
  icon: React.ElementType;
  risk: 'low' | 'medium' | 'high';
  color: string;
};

type TelemetryState = {
  cpu: number | null;
  ram: number | null;
  diskUsage: number | null;
  networkTx: number | null;
  networkRx: number | null;
  riskScore: number | null;
  timestamp: string | null;
};

type AlertRow = {
  id: string;
  severity: string;
  message: string;
  time: string;
};

type AuditRow = {
  id: string;
  type: string;
  actor: string;
  action: string;
  time: string;
  ok: boolean;
};

const DRAWER_TABS = ['Overview', 'Telemetry', 'Commands', 'Security', 'Alerts', 'Audit'];

const QUICK_COMMANDS: QuickCommand[] = [
  { id: 'system-info',        label: 'System Info',    icon: Info,    risk: 'low',    color: 'text-blue-400 bg-blue-500/10 border-blue-500/20' },
  { id: 'screenshot-capture', label: 'Screenshot',     icon: Camera,  risk: 'medium', color: 'text-purple-400 bg-purple-500/10 border-purple-500/20' },
  { id: 'process-list',       label: 'Processes',      icon: Layers,  risk: 'low',    color: 'text-green-400 bg-green-500/10 border-green-500/20' },
  { id: 'network-info',       label: 'Network',        icon: Network, risk: 'low',    color: 'text-cyan-400 bg-cyan-500/10 border-cyan-500/20' },
  { id: 'filesystem',         label: 'Filesystem',     icon: Folder,  risk: 'low',    color: 'text-amber-400 bg-amber-500/10 border-amber-500/20' },
  { id: 'ping',               label: 'Ping',           icon: Radio,   risk: 'low',    color: 'text-teal-400 bg-teal-500/10 border-teal-500/20' },
  { id: 'lock_screen',        label: 'Lock Screen',    icon: Lock,    risk: 'high',   color: 'text-red-400 bg-red-500/10 border-red-500/20' },
  { id: 'users-list',         label: 'Users',          icon: Users,   risk: 'low',    color: 'text-pink-400 bg-pink-500/10 border-pink-500/20' },
];

export default function DeviceDetailDrawer({ device, onClose }: DeviceDetailDrawerProps) {
  const [activeTab, setActiveTab] = useState('Overview');
  const [currentDevice, setCurrentDevice] = useState<Device>(device);
  const [dispatchingCmd, setDispatchingCmd] = useState<string | null>(null);
  const [isLoadingBundle, setIsLoadingBundle] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [commandHistory, setCommandHistory] = useState<DrawerCommandEntry[]>([]);
  const [alerts, setAlerts] = useState<AlertRow[]>([]);
  const [auditRows, setAuditRows] = useState<AuditRow[]>([]);
  const [capabilities, setCapabilities] = useState<Required<CommandCapabilitiesResponse>>({
    canonical_methods: [],
    runtime_supported_methods: [],
    rejection_reasons: {},
  });
  const [telemetry, setTelemetry] = useState<TelemetryState>({
    cpu: null,
    ram: null,
    diskUsage: null,
    networkTx: null,
    networkRx: null,
    riskScore: null,
    timestamp: null,
  });
  const bundleAbortRef = useRef<AbortController | null>(null);

  const riskColor = currentDevice.riskScore > 0.6 ? 'text-red-400' : currentDevice.riskScore > 0.3 ? 'text-amber-400' : 'text-green-400';

  const isTerminalState = (state: string | null | undefined) => ['completed', 'failed', 'expired', 'rejected'].includes(String(state ?? '').toLowerCase());

  const formatTime = (value: string | null | undefined): string => {
    return formatLocalTime(value, '-');
  };

  const commandBlockedReason = useCallback(
    (method: string): string | null => {
      if (capabilities.canonical_methods.length === 0) return null;
      const resolvedMethod = resolveCommandMethod(method);
      const canonical = new Set(capabilities.canonical_methods);
      const runtimeSupported = new Set(capabilities.runtime_supported_methods);
      if (!canonical.has(resolvedMethod)) return 'unknown_command';
      if (!runtimeSupported.has(resolvedMethod)) return capabilities.rejection_reasons[resolvedMethod] ?? 'not_supported_runtime';
      return null;
    },
    [capabilities],
  );

  const reasonToText = (reason: string): string => {
    if (reason === 'unknown_command') return 'Unsupported command id';
    if (reason === 'not_supported_runtime') return 'Not supported by runtime';
    return reason.replaceAll('_', ' ');
  };

  const loadBundle = useCallback(async (mode: 'initial' | 'refresh' = 'initial') => {
    if (mode === 'initial') setIsLoadingBundle(true);
    bundleAbortRef.current?.abort();
    const controller = new AbortController();
    bundleAbortRef.current = controller;
    const encodedId = encodeURIComponent(device.id);

    try {
      const [detailRes, commandsRes, telemetryRes, alertsRes, auditRes, capsRes] = await Promise.allSettled([
        fetch(`/api/devices/${encodedId}`, { credentials: 'include', cache: 'no-store', signal: controller.signal }),
        fetch(`/api/devices/${encodedId}/commands?limit=40`, { credentials: 'include', cache: 'no-store', signal: controller.signal }),
        fetch(`/api/devices/${encodedId}/telemetry`, { credentials: 'include', cache: 'no-store', signal: controller.signal }),
        fetch(`/api/devices/${encodedId}/alerts?limit=100`, { credentials: 'include', cache: 'no-store', signal: controller.signal }),
        fetch(`/api/devices/${encodedId}/audit?limit=100`, { credentials: 'include', cache: 'no-store', signal: controller.signal }),
        fetch(`/api/commands/capabilities?device_id=${encodedId}`, { credentials: 'include', cache: 'no-store', signal: controller.signal }),
      ]);

      if (detailRes.status === 'fulfilled' && detailRes.value.ok) {
        const detailPayload = (await detailRes.value.json()) as DetailDeviceApi;
        setCurrentDevice((previous) => mergeDeviceDetail(previous, detailPayload));
      }

      if (commandsRes.status === 'fulfilled' && commandsRes.value.ok) {
        const payload = (await commandsRes.value.json()) as DeviceCommandsResponse;
        const sortedRows = [...(payload.commands ?? [])].sort((a, b) => {
          const aTs = Date.parse(a.queued_at ?? a.completed_at ?? '');
          const bTs = Date.parse(b.queued_at ?? b.completed_at ?? '');
          if (Number.isNaN(aTs) && Number.isNaN(bTs)) return 0;
          if (Number.isNaN(aTs)) return 1;
          if (Number.isNaN(bTs)) return -1;
          return bTs - aTs;
        });
        setCommandHistory(sortedRows.map(mapCommandHistoryEntry));
      } else if (mode === 'initial') {
        setCommandHistory([]);
      }

      if (telemetryRes.status === 'fulfilled' && telemetryRes.value.ok) {
        const payload = (await telemetryRes.value.json()) as DeviceTelemetryResponse;
        const nextTelemetry: TelemetryState = {
          cpu: payload.metrics?.cpu ?? null,
          ram: payload.metrics?.ram ?? null,
          diskUsage: payload.metrics?.disk_usage ?? null,
          networkTx: payload.metrics?.network_tx ?? null,
          networkRx: payload.metrics?.network_rx ?? null,
          riskScore: payload.metrics?.risk_score == null ? null : normalizeRisk(payload.metrics.risk_score),
          timestamp: payload.timestamp ?? null,
        };
        setTelemetry(nextTelemetry);
        if (nextTelemetry.riskScore != null) {
          setCurrentDevice((previous) => ({ ...previous, riskScore: nextTelemetry.riskScore as number }));
        }
      }

      if (alertsRes.status === 'fulfilled' && alertsRes.value.ok) {
        const payload = (await alertsRes.value.json()) as DeviceAlertsResponse;
        setAlerts(
          (payload.alerts ?? []).map((alert) => ({
            id: alert.alert_id?.trim() || 'alert',
            severity: (alert.severity ?? 'low').toLowerCase(),
            message: alert.message?.trim() || 'Alert',
            time: formatTime(alert.timestamp),
          })),
        );
      } else if (mode === 'initial') {
        setAlerts([]);
      }

      if (auditRes.status === 'fulfilled' && auditRes.value.ok) {
        const payload = (await auditRes.value.json()) as DeviceAuditResponse;
        setAuditRows(
          (payload.entries ?? []).map((entry: DeviceAuditApi) => {
            const eventType = entry.event_type?.trim() || 'system_event';
            const lowerSummary = String(entry.summary ?? '').toLowerCase();
            const ok = !lowerSummary.includes('fail') && !lowerSummary.includes('error') && !lowerSummary.includes('reject');
            return {
              id: entry.id?.trim() || `audit-${Math.random().toString(36).slice(2, 8)}`,
              type: eventType.includes('command') ? 'command' : eventType.includes('policy') ? 'policy' : 'system',
              actor: 'system',
              action: entry.summary?.trim() || eventType.replaceAll('_', ' '),
              time: formatTime(entry.timestamp),
              ok,
            };
          }),
        );
      } else if (mode === 'initial') {
        setAuditRows([]);
      }

      if (capsRes.status === 'fulfilled' && capsRes.value.ok) {
        const payload = (await capsRes.value.json()) as CommandCapabilitiesResponse;
        setCapabilities({
          canonical_methods: payload.canonical_methods ?? [],
          runtime_supported_methods: payload.runtime_supported_methods ?? [],
          rejection_reasons: payload.rejection_reasons ?? {},
        });
      }

      setLoadError(null);
    } catch (error) {
      if ((error as Error).name === 'AbortError') return;
      console.error('device-drawer-load-failed', error);
      setLoadError('Failed to load data');
    } finally {
      if (mode === 'initial') setIsLoadingBundle(false);
    }
  }, [device.id]);

  useEffect(() => {
    setCurrentDevice(device);
    void loadBundle('initial');
    const interval = window.setInterval(() => {
      void loadBundle('refresh');
    }, 30000);
    return () => {
      window.clearInterval(interval);
      bundleAbortRef.current?.abort();
    };
  }, [device, loadBundle]);

  const dispatchAndWait = useCallback(async (method: string, cmdLabel: string, params: Record<string, unknown> = {}, sensitive = false) => {
    const dispatchMethod = resolveCommandMethod(method);
    if (currentDevice.status !== 'online') {
      toast.error(`${currentDevice.hostname} is ${currentDevice.status} - cannot dispatch commands`);
      return;
    }
    const blockedReason = commandBlockedReason(method);
    if (blockedReason) {
      toast.error(`${cmdLabel} blocked: ${reasonToText(blockedReason)}`);
      return;
    }
    setDispatchingCmd(method);
    try {
      const response = await fetch('/api/commands', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        credentials: 'include',
        body: JSON.stringify({
          client_message_id: `drawer-${currentDevice.id}-${dispatchMethod}-${crypto.randomUUID()}`,
          device_id: currentDevice.id,
          method: dispatchMethod,
          params,
          sensitive,
        }),
      });
      const payload = (await response.json().catch(() => ({}))) as CommandDispatchResponse;
      if (!response.ok || !payload.command_id) {
        const reason = payload.reason ?? payload.message ?? `http_${response.status}`;
        toast.error(`${cmdLabel} failed: ${reasonToText(reason)}`);
        setDispatchingCmd(null);
        return;
      }
      toast.success(`${cmdLabel} dispatched (${payload.command_id})`);
      const deadline = Date.now() + 90000;
      while (Date.now() < deadline) {
        await new Promise((resolve) => window.setTimeout(resolve, 2000));
        const pollRes = await fetch(`/api/commands/${encodeURIComponent(payload.command_id)}`, {
          credentials: 'include',
          cache: 'no-store',
        });
        if (!pollRes.ok) continue;
        const pollPayload = (await pollRes.json().catch(() => ({}))) as { state?: string; reason?: string; error_message?: string };
        if (isTerminalState(pollPayload.state)) {
          if (pollPayload.state === 'completed') {
            toast.success(`${cmdLabel} completed`);
          } else {
            toast.error(`${cmdLabel} ${pollPayload.state}: ${pollPayload.error_message ?? pollPayload.reason ?? 'failed'}`);
          }
          break;
        }
      }
      await loadBundle('refresh');
    } catch (error) {
      console.error('device-drawer-dispatch-failed', error);
      toast.error('Failed to load data');
    } finally {
      setDispatchingCmd(null);
    }
  }, [commandBlockedReason, currentDevice.hostname, currentDevice.id, currentDevice.status, loadBundle]);

  const telemetryCards = useMemo(() => [
    { label: 'CPU Usage', icon: Cpu, value: telemetry.cpu == null ? 'Unknown' : `${telemetry.cpu}%`, bar: clampPercent(telemetry.cpu), color: 'bg-green-500' },
    { label: 'RAM Usage', icon: Activity, value: telemetry.ram == null ? 'Unknown' : `${telemetry.ram}%`, bar: clampPercent(telemetry.ram), color: 'bg-blue-500' },
    { label: 'Disk Usage', icon: HardDrive, value: telemetry.diskUsage == null ? 'Unknown' : `${telemetry.diskUsage}%`, bar: clampPercent(telemetry.diskUsage), color: 'bg-amber-500' },
    { label: 'Network TX', icon: Wifi, value: telemetry.networkTx == null ? 'Unknown' : `${telemetry.networkTx} Mbps`, bar: clampPercent(telemetry.networkTx), color: 'bg-cyan-400' },
    { label: 'Network RX', icon: Wifi, value: telemetry.networkRx == null ? 'Unknown' : `${telemetry.networkRx} Mbps`, bar: clampPercent(telemetry.networkRx), color: 'bg-violet-400' },
  ], [telemetry]);

  const stateIcon = (s: string) => {
    if (s === 'completed') return <CheckCircle size={11} className="text-green-400 flex-shrink-0" />;
    if (['failed', 'expired', 'rejected'].includes(s)) return <XCircle size={11} className="text-red-400 flex-shrink-0" />;
    return <Clock size={11} className="text-amber-400 flex-shrink-0" />;
  };

  return (
    <>
      {/* Backdrop */}
      <div className="fixed inset-0 bg-black/40 z-40" onClick={onClose} />

      {/* Drawer */}
      <div className="fixed inset-y-0 right-0 w-full max-w-lg bg-zinc-950 border-l border-border z-50 flex flex-col slide-in-right">
        {/* Header */}
        <div className="flex items-start justify-between px-5 py-4 border-b border-border flex-shrink-0">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-lg bg-muted flex items-center justify-center">
              <Monitor size={18} className="text-muted-foreground" />
            </div>
            <div>
              <h2 className="font-semibold text-sm">{currentDevice.hostname}</h2>
              <p className="text-[11px] text-muted-foreground font-mono">{currentDevice.id} - {currentDevice.ipAddress ?? '-'}</p>
            </div>
          </div>
          <div className="flex items-center gap-2">
            <StatusBadge variant={currentDevice.status} pulse={currentDevice.status === 'online'} />
            <button onClick={onClose} className="p-1.5 rounded-md text-muted-foreground hover:text-foreground hover:bg-muted transition-colors">
              <X size={15} />
            </button>
          </div>
        </div>

        {/* CTA Banner - Deep link to full device page */}
        <div className="px-5 py-3 bg-primary/5 border-b border-primary/20 flex-shrink-0">
          <Link
            href={`/device-detail?device=${currentDevice.id}`}
            className="flex items-center justify-between group"
          >
            <div>
              <p className="text-xs font-semibold text-primary">Open Full Device Console</p>
              <p className="text-[11px] text-muted-foreground">Commands - Trace - Results - History - Telemetry - Alerts - Audit - everything in one place</p>
            </div>
            <div className="flex items-center gap-1 text-primary group-hover:gap-2 transition-all">
              <ExternalLink size={14} />
            </div>
          </Link>
        </div>

        {/* Tabs */}
        <div className="flex border-b border-border px-3 flex-shrink-0 overflow-x-auto scrollbar-thin">
          {DRAWER_TABS.map((tab) => (
            <button
              key={`drawer-tab-${tab}`}
              onClick={() => setActiveTab(tab)}
              className={`px-3 py-2.5 text-xs font-medium border-b-2 transition-colors whitespace-nowrap ${
                activeTab === tab ? 'border-primary text-primary' : 'border-transparent text-muted-foreground hover:text-foreground'
              }`}
            >
              {tab}
            </button>
          ))}
        </div>

        {/* Content */}
        <div className="flex-1 overflow-y-auto scrollbar-thin p-5 space-y-4">
          {loadError && (
            <div className="bg-red-500/10 border border-red-500/20 rounded-lg px-3 py-2 text-xs text-red-400">
              Failed to load data
            </div>
          )}

          {/* Overview */}
          {activeTab === 'Overview' && (
            <>
              <div className="grid grid-cols-2 gap-2">
                {[
                  { label: 'IP Address',    value: currentDevice.ipAddress ?? '-',       mono: true },
                  { label: 'OS Build',      value: currentDevice.osBuild,                mono: true },
                  { label: 'Agent Version', value: currentDevice.agentVersion,           mono: true },
                  { label: 'Session ID',    value: currentDevice.sessionId ?? '-',       mono: true },
                  { label: 'Owner',         value: currentDevice.owner,                  mono: false },
                  { label: 'Kernel Guard',  value: currentDevice.kernelGuard === null ? 'Unknown' : currentDevice.kernelGuard ? 'Active' : 'Inactive', mono: false },
                ].map((item) => (
                  <div key={`detail-${item.label}`} className="bg-muted/30 rounded-lg p-3">
                    <p className="text-[10px] text-muted-foreground uppercase tracking-wide mb-1">{item.label}</p>
                    <p className={`text-xs font-medium truncate ${item.mono ? 'font-mono' : ''}`}>{item.value}</p>
                  </div>
                ))}
              </div>

              <div className="bg-muted/30 rounded-lg p-3">
                <div className="flex items-center justify-between mb-2">
                  <p className="text-[10px] text-muted-foreground uppercase tracking-wide">Risk Score</p>
                  <span className={`text-lg font-bold tabular-nums ${riskColor}`}>
                    {(currentDevice.riskScore * 100).toFixed(0)}<span className="text-xs font-normal text-muted-foreground">/100</span>
                  </span>
                </div>
                <div className="h-1.5 bg-muted rounded-full overflow-hidden">
                  <div
                    className={`h-full rounded-full ${currentDevice.riskScore > 0.6 ? 'bg-red-500' : currentDevice.riskScore > 0.3 ? 'bg-amber-500' : 'bg-green-500'}`}
                    style={{ width: `${currentDevice.riskScore * 100}%` }}
                  />
                </div>
              </div>

              <div className="bg-muted/30 rounded-lg p-3">
                <p className="text-[10px] text-muted-foreground uppercase tracking-wide mb-2">Policy Sync</p>
                {currentDevice.policySync === null ? (
                  <p className="text-xs text-muted-foreground font-medium">Unknown</p>
                ) : currentDevice.policySync ? (
                  <p className="text-xs text-green-400 font-medium">Policy hash synchronized</p>
                ) : (
                  <p className="text-xs text-amber-400 font-medium">Hash mismatch</p>
                )}
              </div>

              {/* Recent activity summary */}
              <div className="bg-muted/30 rounded-lg p-3">
                <p className="text-[10px] text-muted-foreground uppercase tracking-wide mb-2">Recent Activity</p>
                {isLoadingBundle ? (
                  <p className="text-[11px] text-muted-foreground">Loading data...</p>
                ) : commandHistory.length === 0 ? (
                  <p className="text-[11px] text-muted-foreground">No activity available</p>
                ) : (
                  <div className="space-y-1.5">
                    {commandHistory.slice(0, 3).map((cmd) => (
                      <div key={cmd.id} className="flex items-center gap-2">
                        {stateIcon(cmd.state)}
                        <span className="text-[11px] font-mono text-muted-foreground">{cmd.id}</span>
                        <span className="text-[11px] flex-1">{cmd.method}</span>
                        <span className="text-[11px] text-muted-foreground tabular-nums">{cmd.queuedAt}</span>
                      </div>
                    ))}
                  </div>
                )}
              </div>
            </>
          )}

          {/* Telemetry */}
          {activeTab === 'Telemetry' && (
            <div className="space-y-3">
              {telemetryCards.map((metric) => (
                <div key={`metric-${metric.label}`} className="bg-muted/30 rounded-lg p-3">
                  <div className="flex items-center justify-between mb-2">
                    <div className="flex items-center gap-2">
                      <metric.icon size={13} className="text-muted-foreground" />
                      <p className="text-xs font-medium">{metric.label}</p>
                    </div>
                    <span className="text-xs font-semibold tabular-nums">{metric.value}</span>
                  </div>
                  <div className="h-1 bg-muted rounded-full overflow-hidden">
                    <div className={`h-full rounded-full ${metric.color}`} style={{ width: `${metric.bar}%` }} />
                  </div>
                </div>
              ))}
              <p className="text-[11px] text-muted-foreground text-center">
                {telemetry.timestamp ? `Last snapshot: ${formatTime(telemetry.timestamp)}` : 'No data available'}
              </p>
              <Link href={`/telemetry-monitoring?device=${currentDevice.id}`} className="flex items-center justify-center gap-1.5 w-full py-2 text-xs text-primary border border-primary/20 rounded-lg hover:bg-primary/5 transition-colors">
                Full telemetry history <ChevronRight size={12} />
              </Link>
            </div>
          )}

          {/* Commands */}
          {activeTab === 'Commands' && (
            <div className="space-y-3">
              <p className="text-[11px] text-muted-foreground">Quick-dispatch common commands. For the full command library with all {'>'}40 commands, open the device console.</p>
              <div className="grid grid-cols-2 gap-2">
                {QUICK_COMMANDS.map(cmd => (
                  <button
                    key={cmd.id}
                    onClick={() => {
                      void dispatchAndWait(cmd.id, cmd.label, {}, cmd.risk === 'high');
                    }}
                    disabled={dispatchingCmd === cmd.id || currentDevice.status !== 'online' || !!commandBlockedReason(cmd.id)}
                    className={`flex items-center gap-2 px-3 py-2.5 text-xs font-medium border rounded-lg transition-colors hover:opacity-80 disabled:opacity-50 disabled:cursor-not-allowed ${cmd.color}`}
                    title={commandBlockedReason(cmd.id) ? reasonToText(commandBlockedReason(cmd.id) as string) : cmd.label}
                  >
                    {dispatchingCmd === cmd.id ? <Loader2 size={12} className="animate-spin" /> : <cmd.icon size={12} />}
                    {cmd.label}
                  </button>
                ))}
              </div>
              <div className="space-y-1.5">
                <p className="text-[10px] text-muted-foreground uppercase tracking-wide">Recent Commands</p>
                {isLoadingBundle ? (
                  <p className="text-[11px] text-muted-foreground">Loading data...</p>
                ) : commandHistory.length === 0 ? (
                  <p className="text-[11px] text-muted-foreground">No activity available</p>
                ) : (
                  commandHistory.map((cmd) => (
                    <div key={`drawer-cmd-${cmd.id}`} className="flex items-center gap-3 bg-muted/30 rounded-lg px-3 py-2.5">
                      {stateIcon(cmd.state)}
                      <span className="font-mono text-[11px] text-muted-foreground">{cmd.id}</span>
                      <span className="text-xs font-medium flex-1">{cmd.method}</span>
                      <span className="text-[11px] text-muted-foreground tabular-nums">{cmd.queuedAt}</span>
                      <button
                        onClick={() => {
                          void dispatchAndWait(cmd.method, `Replay ${cmd.method}`, cmd.params, false);
                        }}
                        className="p-1 text-muted-foreground hover:text-primary transition-colors"
                        title="Replay"
                      >
                        <RotateCcw size={10} />
                      </button>
                    </div>
                  ))
                )}
              </div>
              <Link href={`/device-detail?device=${currentDevice.id}`} className="flex items-center justify-center gap-1.5 w-full py-2.5 text-xs font-medium bg-primary/10 border border-primary/20 text-primary rounded-lg hover:bg-primary/20 transition-colors">
                <Terminal size={12} /> Open Full Command Library (40+ commands)
              </Link>
            </div>
          )}

          {/* Security */}
          {activeTab === 'Security' && (
            <div className="space-y-3">
              <div className="bg-muted/30 rounded-lg p-3 space-y-2">
                <p className="text-[10px] text-muted-foreground uppercase tracking-wide mb-2">Compliance Status</p>
                <StatusBadge variant={currentDevice.compliance} size="md" />
                {currentDevice.compliance !== 'compliant' && (
                  <p className="text-[11px] text-amber-400 mt-2">
                    Policy hash mismatch detected. Last attestation:{' '}
                    {telemetry.timestamp ? `${formatTime(telemetry.timestamp)}` : 'Unknown'}
                  </p>
                )}
              </div>
              <div className="bg-muted/30 rounded-lg p-3">
                <p className="text-[10px] text-muted-foreground uppercase tracking-wide mb-2">Kernel Guard</p>
                {currentDevice.kernelGuard === null ? (
                  <p className="text-xs font-medium text-muted-foreground">Unknown</p>
                ) : (
                  <p className={`text-xs font-medium ${currentDevice.kernelGuard ? 'text-green-400' : 'text-red-400'}`}>
                    {currentDevice.kernelGuard ? 'Kernel guard active' : 'Kernel guard not detected'}
                  </p>
                )}
              </div>
              <div className="bg-muted/30 rounded-lg p-3">
                <p className="text-[10px] text-muted-foreground uppercase tracking-wide mb-2">Risk Score</p>
                <div className="flex items-center gap-3">
                  <span className={`text-2xl font-bold tabular-nums ${riskColor}`}>{(currentDevice.riskScore * 100).toFixed(0)}</span>
                  <div className="flex-1">
                    <div className="h-2 bg-muted rounded-full overflow-hidden">
                      <div className={`h-full rounded-full ${currentDevice.riskScore > 0.6 ? 'bg-red-500' : currentDevice.riskScore > 0.3 ? 'bg-amber-500' : 'bg-green-500'}`} style={{ width: `${currentDevice.riskScore * 100}%` }} />
                    </div>
                    <p className="text-[10px] text-muted-foreground mt-1">{currentDevice.riskScore > 0.6 ? 'High risk - immediate attention required' : currentDevice.riskScore > 0.3 ? 'Medium risk - monitor closely' : 'Low risk - within acceptable range'}</p>
                  </div>
                </div>
              </div>
              {currentDevice.status === 'quarantined' && (
                <div className="bg-red-500/10 border border-red-500/20 rounded-lg p-3">
                  <div className="flex items-center gap-2 mb-1">
                    <Shield size={13} className="text-red-400" />
                    <p className="text-xs font-semibold text-red-400">Device Quarantined</p>
                  </div>
                  <p className="text-[11px] text-muted-foreground">Attestation hash mismatch. Only approved investigation commands are permitted.</p>
                </div>
              )}
            </div>
          )}

          {/* Alerts */}
          {activeTab === 'Alerts' && (
            <div className="space-y-2">
              {isLoadingBundle ? (
                <p className="text-xs text-muted-foreground">Loading data...</p>
              ) : alerts.length === 0 ? (
                <p className="text-xs text-muted-foreground">No alerts</p>
              ) : (
                alerts.map((alert) => (
                  <div key={alert.id} className={`flex items-start gap-3 bg-muted/20 border rounded-lg p-3 ${alert.severity === 'high' || alert.severity === 'critical' ? 'border-red-500/30' : alert.severity === 'medium' ? 'border-amber-500/30' : 'border-border'}`}>
                    <AlertTriangle size={13} className={alert.severity === 'high' || alert.severity === 'critical' ? 'text-red-400' : alert.severity === 'medium' ? 'text-amber-400' : 'text-muted-foreground'} />
                    <div>
                      <p className="text-xs font-medium">{alert.message}</p>
                      <p className="text-[11px] text-muted-foreground">{alert.id} - {alert.time}</p>
                    </div>
                  </div>
                ))
              )}
              <Link href={`/alerts?device=${currentDevice.id}`} className="flex items-center justify-center gap-1.5 w-full py-2 text-xs text-primary border border-primary/20 rounded-lg hover:bg-primary/5 transition-colors">
                All alerts for this device <ChevronRight size={12} />
              </Link>
            </div>
          )}

          {/* Audit */}
          {activeTab === 'Audit' && (
            <div className="space-y-2">
              {isLoadingBundle ? (
                <p className="text-xs text-muted-foreground">Loading data...</p>
              ) : auditRows.length === 0 ? (
                <p className="text-xs text-muted-foreground">No data available</p>
              ) : (
                auditRows.map((entry) => (
                  <div key={entry.id} className="flex items-center gap-3 bg-muted/20 rounded-lg px-3 py-2.5">
                    <div className={`w-1.5 h-1.5 rounded-full flex-shrink-0 ${entry.ok ? 'bg-green-500' : 'bg-red-500'}`} />
                    <span className={`text-[10px] font-semibold px-1.5 py-0.5 rounded-full ${entry.type === 'command' ? 'bg-blue-500/10 text-blue-400' : entry.type === 'policy' ? 'bg-violet-500/10 text-violet-400' : 'bg-zinc-500/10 text-zinc-400'}`}>{entry.type}</span>
                    <span className="text-[11px] flex-1">{entry.action}</span>
                    <span className="text-[11px] text-muted-foreground">{entry.actor}</span>
                    <span className="text-[11px] text-muted-foreground tabular-nums">{entry.time}</span>
                  </div>
                ))
              )}
              <Link href="/audit" className="flex items-center justify-center gap-1.5 w-full py-2 text-xs text-primary border border-primary/20 rounded-lg hover:bg-primary/5 transition-colors">
                Full audit trail <ChevronRight size={12} />
              </Link>
            </div>
          )}
        </div>

        {/* Footer - CTA row */}
        <div className="border-t border-border px-5 py-3 flex-shrink-0">
          <Link
            href={`/device-detail?device=${currentDevice.id}`}
            className="w-full flex items-center justify-center gap-2 py-2.5 text-sm font-semibold bg-primary text-primary-foreground rounded-lg hover:bg-primary/90 transition-colors"
          >
            <Monitor size={14} />
            Open Full Device Console
            <ExternalLink size={12} className="ml-1" />
          </Link>
          <div className="flex items-center gap-2 mt-2">
            <Link href={`/telemetry-monitoring?device=${currentDevice.id}`} className="flex-1 flex items-center justify-center gap-1.5 py-1.5 text-xs border border-border rounded-md text-muted-foreground hover:text-foreground hover:bg-muted/60 transition-colors">
              <Activity size={11} /> Telemetry
            </Link>
            <Link href={`/command-dispatch?device=${currentDevice.id}`} className="flex-1 flex items-center justify-center gap-1.5 py-1.5 text-xs border border-border rounded-md text-muted-foreground hover:text-foreground hover:bg-muted/60 transition-colors">
              <Terminal size={11} /> Dispatch
            </Link>
            <Link href="/command-history" className="flex-1 flex items-center justify-center gap-1.5 py-1.5 text-xs border border-border rounded-md text-muted-foreground hover:text-foreground hover:bg-muted/60 transition-colors">
              <Clock size={11} /> History
            </Link>
            <Link href={`/alerts?device=${currentDevice.id}`} className="flex-1 flex items-center justify-center gap-1.5 py-1.5 text-xs border border-border rounded-md text-muted-foreground hover:text-foreground hover:bg-muted/60 transition-colors">
              <Bell size={11} /> Alerts
            </Link>
          </div>
        </div>
      </div>
    </>
  );
}


