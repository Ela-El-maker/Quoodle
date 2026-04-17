'use client';

import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  AlertTriangle,
  Bell,
  CheckCircle2,
  ChevronRight,
  Link2,
  Loader2,
  Monitor,
  Terminal,
  X,
} from 'lucide-react';
import Link from 'next/link';
import { toast } from 'sonner';
import StatusBadge from '@/components/ui/StatusBadge';
import DevicePairingModal from '@/components/DevicePairingModal';
import LiveAlertFeed, { type WsEvent } from '@/components/LiveAlertFeed';
import {
  mapListDevice,
  type Device as ManagedDevice,
  type ListDeviceApi,
} from '@/app/device-management/lib/deviceManagementData';
import { mapCommandListRow, type CommandListRowApi } from '@/lib/commandResults';
import { formatLocalTime } from '@/lib/dateTime';
import { resolveCommandMethod } from '@/lib/commandMethodResolver';

type DeviceStatus = ManagedDevice['status'];
type ComplianceStatus = ManagedDevice['compliance'];

interface Device {
  id: string;
  hostname: string;
  status: DeviceStatus;
  riskScore: number;
  compliance: ComplianceStatus;
  lastSeen: string;
  os: string;
}

interface RecentCommand {
  id: string;
  method: string;
  deviceId: string;
  deviceName: string;
  status: 'dispatched' | 'ack' | 'completed' | 'failed';
  issuedAt: string;
  queuedAtIso: string | null;
}

interface AlertRow {
  id: string;
  title: string;
  severity: 'critical' | 'warning' | 'info';
  deviceName: string;
  time: string;
  timestampIso: string | null;
  acknowledged: boolean;
}

interface OperatorMethod {
  id: string;
  label: string;
  risk: 'low' | 'medium' | 'high';
  desc: string;
}

interface DevicesApiResponse {
  devices?: ListDeviceApi[];
}

interface CommandsApiResponse {
  commands?: CommandListRowApi[];
}

interface AlertsApiResponse {
  alerts?: Array<{
    alert_id?: string;
    device_id?: string;
    severity?: string;
    message?: string;
    timestamp?: string | null;
    acknowledged?: boolean;
  }>;
}

interface CapabilitiesResponse {
  canonical_methods?: string[];
  runtime_supported_methods?: string[];
}

interface DispatchResponse {
  command_id?: string;
  reason?: string;
  message?: string;
}

const cmdStatusColors: Record<RecentCommand['status'], string> = {
  completed: 'text-green-400',
  ack: 'text-amber-400',
  dispatched: 'text-blue-400',
  failed: 'text-red-400',
};

const severityColors: Record<AlertRow['severity'], string> = {
  critical: 'text-red-400 bg-red-500/10 border-red-500/20',
  warning: 'text-amber-400 bg-amber-500/10 border-amber-500/20',
  info: 'text-blue-400 bg-blue-500/10 border-blue-500/20',
};

const MEDIUM_RISK_METHODS = new Set(['lock_screen', 'reboot_device', 'shutdown_device', 'logout_user']);
const HIGH_RISK_METHODS = new Set(['wipe_device', 'factory_reset', 'unenroll_device']);

function parseTimeMs(value: string | null | undefined): number {
  if (!value) return 0;
  const parsed = Date.parse(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function normalizeSeverity(value: string | null | undefined): AlertRow['severity'] {
  const normalized = String(value ?? '').toLowerCase();
  if (normalized === 'critical') return 'critical';
  if (normalized === 'warning') return 'warning';
  return 'info';
}

function toRecentCommandStatus(state: string): RecentCommand['status'] {
  if (state === 'completed') return 'completed';
  if (state === 'ack_received') return 'ack';
  if (state === 'failed' || state === 'expired' || state === 'rejected') return 'failed';
  return 'dispatched';
}

function methodRisk(method: string): OperatorMethod['risk'] {
  if (HIGH_RISK_METHODS.has(method)) return 'high';
  if (MEDIUM_RISK_METHODS.has(method)) return 'medium';
  return 'low';
}

function methodDescription(method: string): string {
  switch (method) {
    case 'ping':
      return 'Verify agent connectivity and runtime response.';
    case 'lock_screen':
      return 'Lock the device screen immediately.';
    case 'collect_system_info':
      return 'Collect host system profile and health details.';
    case 'list_processes':
      return 'List currently running processes.';
    case 'network_info':
      return 'Collect active network interface and route details.';
    default:
      return 'Run this command on the selected device.';
  }
}

function buildOperatorMethods(payload: CapabilitiesResponse | null): OperatorMethod[] {
  const runtime = payload?.runtime_supported_methods ?? [];
  const canonical = payload?.canonical_methods ?? [];
  const source = runtime.length > 0 ? runtime : canonical;
  const unique = Array.from(new Set(source.map((item) => item.trim()).filter(Boolean))).sort();

  return unique.map((id) => ({
    id,
    label: id,
    risk: methodRisk(id),
    desc: methodDescription(id),
  }));
}

function toLocalDevice(device: ManagedDevice): Device {
  return {
    id: device.id,
    hostname: device.hostname,
    status: device.status,
    riskScore: device.riskScore,
    compliance: device.compliance,
    lastSeen: device.lastSeen,
    os: device.osBuild,
  };
}

function isSameLocalDay(iso: string | null | undefined, now: Date): boolean {
  if (!iso) return false;
  const parsed = new Date(iso);
  if (Number.isNaN(parsed.getTime())) return false;
  return (
    parsed.getFullYear() === now.getFullYear()
    && parsed.getMonth() === now.getMonth()
    && parsed.getDate() === now.getDate()
  );
}

function buildLiveFeedEvents(alerts: AlertRow[], commands: RecentCommand[], devices: Device[]): WsEvent[] {
  type FeedEntry = {
    id: string;
    sortAt: number;
    event: WsEvent;
  };

  const alertEvents: FeedEntry[] = alerts.map((alert) => ({
    id: `feed-alert-${alert.id}`,
    sortAt: parseTimeMs(alert.timestampIso),
    event: {
      id: `feed-alert-${alert.id}`,
      type: 'alert' as const,
      severity: alert.severity,
      title: alert.title,
      detail: `${alert.deviceName} - ${alert.title}`,
      device: alert.deviceName,
      timestamp: alert.time,
      read: false,
    },
  }));

  const commandEvents: FeedEntry[] = commands.map((command) => {
    const severity: 'critical' | 'warning' | 'info' = command.status === 'failed' ? 'warning' : 'info';
    return {
      id: `feed-command-${command.id}`,
      sortAt: parseTimeMs(command.queuedAtIso),
      event: {
        id: `feed-command-${command.id}`,
        type: 'command_status' as const,
        severity,
        title: `${command.id} ${command.status}`,
        detail: `${command.method} on ${command.deviceName}`,
        device: command.deviceName,
        timestamp: command.issuedAt,
        read: false,
      },
    };
  });

  const deviceEvents: FeedEntry[] = devices
    .slice(0, 6)
    .map((device) => {
      const severity: WsEvent['severity'] =
        device.status === 'degraded' || device.status === 'quarantined' ? 'warning' : 'info';
      return ({
      id: `feed-device-${device.id}`,
      sortAt: parseTimeMs(device.lastSeen),
      event: {
        id: `feed-device-${device.id}`,
        type: 'device_state' as const,
        severity,
        title: `${device.hostname} ${device.status}`,
        detail: `${device.os} - risk ${(device.riskScore * 100).toFixed(0)}`,
        device: device.hostname,
        timestamp: formatLocalTime(device.lastSeen, '--:--:--'),
        read: false,
      },
    });
    });

  return [...alertEvents, ...commandEvents, ...deviceEvents]
    .sort((a, b) => b.sortAt - a.sortAt)
    .slice(0, 12)
    .map((entry) => entry.event);
}

interface DispatchModalProps {
  devices: Device[];
  methods: OperatorMethod[];
  initialDeviceId?: string | null;
  onClose: () => void;
  onDispatched: () => void;
}

function OperatorDispatchModal({
  devices,
  methods,
  initialDeviceId,
  onClose,
  onDispatched,
}: DispatchModalProps) {
  const [selectedDevice, setSelectedDevice] = useState('');
  const [selectedMethod, setSelectedMethod] = useState('');
  const [deviceNameConfirm, setDeviceNameConfirm] = useState('');
  const [deviceIdSuffix, setDeviceIdSuffix] = useState('');
  const [confirmError, setConfirmError] = useState('');
  const [loading, setLoading] = useState(false);
  const [submitted, setSubmitted] = useState(false);
  const [step, setStep] = useState<'compose' | 'confirm'>('compose');

  useEffect(() => {
    if (initialDeviceId) {
      setSelectedDevice(initialDeviceId);
    }
  }, [initialDeviceId]);

  const device = devices.find((d) => d.id === selectedDevice);
  const method = methods.find((m) => m.id === selectedMethod);
  const needsConfirm = method?.risk === 'medium' || method?.risk === 'high';

  const handleProceed = () => {
    if (!selectedDevice || !selectedMethod) {
      toast.error('Select a device and command method');
      return;
    }
    if (needsConfirm) {
      setStep('confirm');
      return;
    }
    void handleDispatch();
  };

  const handleDispatch = async () => {
    if (!device || !method) {
      toast.error('Select a device and command method');
      return;
    }

    if (needsConfirm) {
      if (deviceNameConfirm.trim() !== device.hostname) {
        setConfirmError('Device name does not match.');
        return;
      }
      if (deviceIdSuffix.trim().toUpperCase() !== device.id.slice(-6).toUpperCase()) {
        setConfirmError('Device ID suffix does not match.');
        return;
      }
    }

    setLoading(true);
    try {
      const resolvedMethod = resolveCommandMethod(selectedMethod);
      const response = await fetch('/api/commands', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        credentials: 'include',
        body: JSON.stringify({
          client_message_id: `operator-console-${device.id}-${resolvedMethod}-${crypto.randomUUID()}`,
          device_id: device.id,
          method: resolvedMethod,
          params: {},
          sensitive: needsConfirm,
        }),
      });

      const payload = (await response.json().catch(() => ({}))) as DispatchResponse;
      if (!response.ok || !payload.command_id) {
        const reason = payload.reason ?? payload.message ?? `http_${response.status}`;
        throw new Error(reason);
      }

      setSubmitted(true);
      toast.success(`${selectedMethod} queued for ${device.hostname}`, {
        description: `${payload.command_id} - awaiting dispatch`,
      });
      onDispatched();
      window.setTimeout(onClose, 1200);
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Failed to load data';
      toast.error(`Dispatch failed: ${message}`);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="fixed inset-0 bg-black/60 z-50 flex items-center justify-center p-4">
      <div className="bg-zinc-950 border border-border rounded-xl w-full max-w-md shadow-2xl fade-in">
        <div className="flex items-center justify-between px-5 py-4 border-b border-border">
          <div className="flex items-center gap-2">
            <div className="w-7 h-7 rounded-lg bg-primary/10 flex items-center justify-center">
              <Terminal size={14} className="text-primary" />
            </div>
            <h2 className="font-semibold text-sm">Dispatch Command</h2>
          </div>
          <button onClick={onClose} className="p-1.5 rounded-md text-muted-foreground hover:text-foreground hover:bg-muted transition-colors">
            <X size={15} />
          </button>
        </div>

        {submitted ? (
          <div className="flex flex-col items-center justify-center py-12 px-5">
            <div className="w-12 h-12 rounded-full bg-green-500/10 flex items-center justify-center mb-3">
              <CheckCircle2 size={24} className="text-green-400" />
            </div>
            <p className="font-semibold text-sm">Command Queued</p>
            <p className="text-xs text-muted-foreground mt-1">Dispatching to gateway...</p>
          </div>
        ) : step === 'compose' ? (
          <div className="p-5 space-y-4">
            <div>
              <label className="block text-xs font-medium mb-1.5">Target Device <span className="text-red-400">*</span></label>
              <p className="text-[11px] text-muted-foreground mb-2">Only your authorized devices are shown.</p>
              <select
                value={selectedDevice}
                onChange={(event) => setSelectedDevice(event.target.value)}
                className="w-full text-xs bg-muted/60 border border-border rounded-md px-3 py-2 text-foreground focus:outline-none focus:ring-1 focus:ring-primary/50"
              >
                <option value="">Select a device...</option>
                {devices.filter((d) => d.status !== 'offline').map((d) => (
                  <option key={d.id} value={d.id}>{d.hostname} - {d.status}</option>
                ))}
              </select>
            </div>

            {device && (
              <div className="bg-muted/20 border border-border rounded-lg p-3 space-y-1.5">
                <div className="flex items-center justify-between">
                  <span className="text-[11px] font-semibold">{device.hostname}</span>
                  <StatusBadge variant={device.status} />
                </div>
                <div className="flex items-center gap-3 text-[10px] text-muted-foreground">
                  <span>ID: {device.id}</span>
                  <span>Last seen: {device.lastSeen}</span>
                  <span className={device.riskScore > 0.6 ? 'text-red-400' : device.riskScore > 0.3 ? 'text-amber-400' : 'text-green-400'}>
                    Risk: {(device.riskScore * 100).toFixed(0)}
                  </span>
                </div>
              </div>
            )}

            <div>
              <label className="block text-xs font-medium mb-1.5">Command Method <span className="text-red-400">*</span></label>
              <p className="text-[11px] text-muted-foreground mb-2">Only operator-approved methods are shown.</p>
              <div className="space-y-2 max-h-56 overflow-y-auto scrollbar-thin pr-1">
                {methods.length === 0 && (
                  <div className="text-[11px] text-muted-foreground border border-border rounded-lg px-3 py-2.5">
                    No command methods available.
                  </div>
                )}
                {methods.map((m) => (
                  <label
                    key={m.id}
                    className={`flex items-start gap-3 p-3 border rounded-lg cursor-pointer transition-all ${
                      selectedMethod === m.id ? 'border-primary/50 bg-primary/5' : 'border-border hover:border-border/80 hover:bg-muted/20'
                    }`}
                  >
                    <input
                      type="radio"
                      value={m.id}
                      checked={selectedMethod === m.id}
                      onChange={() => setSelectedMethod(m.id)}
                      className="mt-0.5 accent-blue-500"
                    />
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2 mb-0.5">
                        <span className="font-mono text-xs font-semibold">{m.label}</span>
                        <span className={`text-[10px] px-1.5 py-0.5 rounded-full border font-medium ${
                          m.risk === 'low'
                            ? 'bg-green-500/10 border-green-500/20 text-green-400'
                            : m.risk === 'medium'
                              ? 'bg-amber-500/10 border-amber-500/20 text-amber-400'
                              : 'bg-red-500/10 border-red-500/20 text-red-400'
                        }`}>{m.risk} risk</span>
                      </div>
                      <p className="text-[11px] text-muted-foreground">{m.desc}</p>
                    </div>
                  </label>
                ))}
              </div>
            </div>

            {needsConfirm && (
              <div className="bg-amber-500/5 border border-amber-500/20 rounded-lg p-3 flex items-start gap-2">
                <AlertTriangle size={12} className="text-amber-400 flex-shrink-0 mt-0.5" />
                <p className="text-[11px] text-amber-400">This command requires device confirmation on the next step.</p>
              </div>
            )}

            <div className="flex items-center gap-2 pt-1">
              <button onClick={onClose} className="flex-1 py-2 text-xs border border-border rounded-md text-muted-foreground hover:text-foreground hover:bg-muted/60 transition-colors">
                Cancel
              </button>
              <button
                onClick={handleProceed}
                disabled={!selectedDevice || !selectedMethod || methods.length === 0 || loading}
                className="flex-1 flex items-center justify-center gap-2 py-2 text-xs font-medium bg-primary text-primary-foreground rounded-md hover:bg-primary/90 disabled:opacity-50 active:scale-95 transition-all"
              >
                <Terminal size={13} />
                {needsConfirm ? 'Continue' : 'Dispatch'}
              </button>
            </div>
          </div>
        ) : (
          <div className="p-5 space-y-4">
            <div className="bg-amber-500/5 border border-amber-500/20 rounded-lg p-3 flex items-start gap-2.5">
              <AlertTriangle size={14} className="text-amber-400 flex-shrink-0 mt-0.5" />
              <div>
                <p className="text-xs font-semibold text-amber-400">Confirm command execution</p>
                <p className="text-[11px] text-muted-foreground mt-0.5">
                  You are about to run <span className="font-mono text-foreground">{selectedMethod}</span> on{' '}
                  <span className="font-mono text-foreground">{device?.hostname}</span>.
                </p>
              </div>
            </div>

            {device && (
              <div className="bg-muted/20 border border-border rounded-lg p-3 space-y-1.5">
                <div className="flex items-center justify-between">
                  <span className="text-[11px] font-semibold">{device.hostname}</span>
                  <StatusBadge variant={device.status} />
                </div>
                <p className="text-[10px] text-muted-foreground font-mono">ID: {device.id}</p>
              </div>
            )}

            <div className="space-y-3">
              <p className="text-[11px] text-muted-foreground">
                Type the device name and last 6 characters of the device ID to confirm.
              </p>
              <div>
                <label className="block text-xs font-medium mb-1.5">Type device name <span className="text-red-400">*</span></label>
                <input
                  type="text"
                  value={deviceNameConfirm}
                  onChange={(event) => { setDeviceNameConfirm(event.target.value); setConfirmError(''); }}
                  placeholder={device?.hostname}
                  className="w-full text-xs bg-muted/60 border border-border rounded-md px-3 py-2.5 text-foreground font-mono placeholder:text-muted-foreground/50 focus:outline-none focus:ring-1 focus:ring-primary/50 transition-colors"
                  autoComplete="off"
                  spellCheck={false}
                />
              </div>
              <div>
                <label className="block text-xs font-medium mb-1.5">Last 6 chars of device ID <span className="text-red-400">*</span></label>
                <input
                  type="text"
                  value={deviceIdSuffix}
                  onChange={(event) => { setDeviceIdSuffix(event.target.value.toUpperCase()); setConfirmError(''); }}
                  placeholder={device?.id.slice(-6)}
                  maxLength={6}
                  className="w-full text-xs bg-muted/60 border border-border rounded-md px-3 py-2.5 text-foreground font-mono tracking-widest uppercase placeholder:text-muted-foreground/50 focus:outline-none focus:ring-1 focus:ring-primary/50 transition-colors"
                  autoComplete="off"
                />
              </div>
              {confirmError && (
                <div className="flex items-start gap-2 text-[11px] text-red-400 bg-red-500/5 border border-red-500/20 rounded-md px-3 py-2">
                  <AlertTriangle size={11} className="flex-shrink-0 mt-0.5" />
                  {confirmError}
                </div>
              )}
            </div>

            <div className="flex items-center gap-2 pt-1">
              <button onClick={() => setStep('compose')} className="flex-1 py-2 text-xs border border-border rounded-md text-muted-foreground hover:text-foreground hover:bg-muted/60 transition-colors">
                Back
              </button>
              <button
                onClick={() => { void handleDispatch(); }}
                disabled={loading || !deviceNameConfirm || deviceIdSuffix.length < 6}
                className="flex-1 flex items-center justify-center gap-2 py-2 text-xs font-medium bg-primary text-primary-foreground rounded-md hover:bg-primary/90 disabled:opacity-50 active:scale-95 transition-all"
              >
                {loading ? <><Loader2 size={12} className="animate-spin" />Dispatching...</> : <><Terminal size={12} />Execute Command</>}
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

export default function OperatorDashboard() {
  const [showPairModal, setShowPairModal] = useState(false);
  const [showDispatch, setShowDispatch] = useState(false);
  const [dispatchInitialDeviceId, setDispatchInitialDeviceId] = useState<string | null>(null);

  const [devices, setDevices] = useState<Device[]>([]);
  const [recentCommands, setRecentCommands] = useState<RecentCommand[]>([]);
  const [alerts, setAlerts] = useState<AlertRow[]>([]);
  const [operatorMethods, setOperatorMethods] = useState<OperatorMethod[]>([]);

  const [commandsTodayCount, setCommandsTodayCount] = useState(0);
  const [isLoading, setIsLoading] = useState(true);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [ackInFlight, setAckInFlight] = useState<Set<string>>(new Set());

  const fetchAbortRef = useRef<AbortController | null>(null);

  const fetchDashboardData = useCallback(async (mode: 'initial' | 'refresh' | 'silent' = 'initial') => {
    if (mode === 'initial') setIsLoading(true);
    if (mode === 'refresh') setIsRefreshing(true);

    fetchAbortRef.current?.abort();
    const controller = new AbortController();
    fetchAbortRef.current = controller;

    try {
      const [devicesRes, commandsRes, alertsRes, capabilitiesRes] = await Promise.allSettled([
        fetch('/api/devices?per_page=200', { credentials: 'include', cache: 'no-store', signal: controller.signal }),
        fetch('/api/commands?limit=200', { credentials: 'include', cache: 'no-store', signal: controller.signal }),
        fetch('/api/alerts?limit=60', { credentials: 'include', cache: 'no-store', signal: controller.signal }),
        fetch('/api/commands/capabilities', { credentials: 'include', cache: 'no-store', signal: controller.signal }),
      ]);

      let hadError = false;

      if (devicesRes.status === 'fulfilled' && devicesRes.value.ok) {
        const payload = (await devicesRes.value.json()) as DevicesApiResponse;
        const mapped = (payload.devices ?? []).map(mapListDevice).map(toLocalDevice);
        setDevices(mapped);
      } else if (devicesRes.status !== 'rejected') {
        hadError = true;
      }

      if (commandsRes.status === 'fulfilled' && commandsRes.value.ok) {
        const payload = (await commandsRes.value.json()) as CommandsApiResponse;
        const mappedRows = (payload.commands ?? [])
          .map((row) => mapCommandListRow(row))
          .sort((a, b) => parseTimeMs(b.queuedAt) - parseTimeMs(a.queuedAt));

        const nextRecent: RecentCommand[] = mappedRows.slice(0, 10).map((row) => ({
          id: row.commandId,
          method: row.method,
          deviceId: row.deviceId,
          deviceName: row.deviceName || row.deviceId,
          status: toRecentCommandStatus(row.state),
          issuedAt: formatLocalTime(row.queuedAt, '-'),
          queuedAtIso: row.queuedAt,
        }));

        setRecentCommands(nextRecent);

        const now = new Date();
        const todayCount = mappedRows.filter((row) => isSameLocalDay(row.queuedAt, now)).length;
        setCommandsTodayCount(todayCount);
      } else if (commandsRes.status !== 'rejected') {
        hadError = true;
      }

      if (alertsRes.status === 'fulfilled' && alertsRes.value.ok) {
        const payload = (await alertsRes.value.json()) as AlertsApiResponse;
        const mapped = (payload.alerts ?? [])
          .map((alert): AlertRow => ({
            id: String(alert.alert_id ?? '').trim() || `alert-${Math.random().toString(36).slice(2, 8)}`,
            title: String(alert.message ?? 'Alert').trim() || 'Alert',
            severity: normalizeSeverity(alert.severity),
            deviceName: String(alert.device_id ?? 'unknown').trim() || 'unknown',
            time: formatLocalTime(alert.timestamp, '--:--:--'),
            timestampIso: alert.timestamp ?? null,
            acknowledged: Boolean(alert.acknowledged),
          }))
          .sort((a, b) => parseTimeMs(b.timestampIso) - parseTimeMs(a.timestampIso));

        setAlerts(mapped.slice(0, 8));
      } else if (alertsRes.status !== 'rejected') {
        hadError = true;
      }

      if (capabilitiesRes.status === 'fulfilled' && capabilitiesRes.value.ok) {
        const payload = (await capabilitiesRes.value.json()) as CapabilitiesResponse;
        setOperatorMethods(buildOperatorMethods(payload));
      } else if (capabilitiesRes.status !== 'rejected') {
        hadError = true;
      }

      if (devicesRes.status === 'rejected' || commandsRes.status === 'rejected' || alertsRes.status === 'rejected' || capabilitiesRes.status === 'rejected') {
        hadError = true;
      }

      setLoadError(hadError ? 'Failed to load data' : null);
    } catch (error) {
      if ((error as Error).name === 'AbortError') return;
      console.error('operator-dashboard-load-failed', error);
      setLoadError('Failed to load data');
    } finally {
      if (mode === 'initial') setIsLoading(false);
      if (mode === 'refresh') setIsRefreshing(false);
    }
  }, []);

  useEffect(() => {
    void fetchDashboardData('initial');
  }, [fetchDashboardData]);

  useEffect(() => {
    let interval: ReturnType<typeof setInterval> | null = null;

    const startPolling = () => {
      if (interval) clearInterval(interval);
      const pollMs = document.visibilityState === 'visible' ? 10000 : 30000;
      interval = setInterval(() => {
        void fetchDashboardData('silent');
      }, pollMs);
    };

    startPolling();
    const handleVisibility = () => startPolling();
    document.addEventListener('visibilitychange', handleVisibility);

    return () => {
      if (interval) clearInterval(interval);
      document.removeEventListener('visibilitychange', handleVisibility);
      fetchAbortRef.current?.abort();
    };
  }, [fetchDashboardData]);

  const acknowledgeAlert = async (id: string) => {
    setAckInFlight((prev) => new Set(prev).add(id));
    try {
      const response = await fetch(`/api/alerts/${encodeURIComponent(id)}/ack`, {
        method: 'POST',
        credentials: 'include',
      });
      if (!response.ok) {
        throw new Error(`http_${response.status}`);
      }
      setAlerts((prev) => prev.map((alert) => (alert.id === id ? { ...alert, acknowledged: true } : alert)));
      toast.success('Alert acknowledged');
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Failed to load data';
      toast.error(`Acknowledge failed: ${message}`);
    } finally {
      setAckInFlight((prev) => {
        const next = new Set(prev);
        next.delete(id);
        return next;
      });
    }
  };

  const unacknowledgedAlerts = useMemo(() => alerts.filter((alert) => !alert.acknowledged), [alerts]);

  const liveFeedEvents = useMemo(() => buildLiveFeedEvents(alerts, recentCommands, devices), [alerts, recentCommands, devices]);

  const riskColor = (score: number) => (score > 0.6 ? 'text-red-400' : score > 0.3 ? 'text-amber-400' : 'text-green-400');

  return (
    <div className="space-y-6 fade-in">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">Operator Console</h1>
          <p className="text-sm text-muted-foreground mt-0.5">
            {devices.filter((d) => d.status === 'online').length} of {devices.length} devices online - Your assigned fleet
          </p>
        </div>
        <div className="flex items-center gap-2">
          <button
            onClick={() => setShowPairModal(true)}
            className="flex items-center gap-1.5 px-3 py-1.5 text-xs border border-border rounded-md text-muted-foreground hover:text-foreground hover:bg-muted/60 transition-colors"
          >
            <Link2 size={13} />
            Pair Device
          </button>
          <button
            onClick={() => {
              setDispatchInitialDeviceId(null);
              setShowDispatch(true);
            }}
            className="flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium bg-primary text-primary-foreground rounded-md hover:bg-primary/90 active:scale-95 transition-all"
          >
            <Terminal size={13} />
            Dispatch Command
          </button>
        </div>
      </div>

      {loadError && (
        <div className="bg-card border border-red-500/20 rounded-lg px-4 py-3 text-sm text-red-300">
          Failed to load data
        </div>
      )}

      <div className="grid grid-cols-2 lg:grid-cols-4 gap-3">
        {[
          { label: 'My Devices', value: devices.length, icon: Monitor, color: 'text-primary' },
          { label: 'Online', value: devices.filter((d) => d.status === 'online').length, icon: CheckCircle2, color: 'text-green-400' },
          { label: 'Alerts', value: unacknowledgedAlerts.length, icon: Bell, color: unacknowledgedAlerts.length > 0 ? 'text-red-400' : 'text-muted-foreground' },
          { label: 'Commands Today', value: commandsTodayCount, icon: Terminal, color: 'text-primary' },
        ].map((kpi) => (
          <div key={kpi.label} className="bg-card border border-border rounded-lg p-4">
            <div className="flex items-center justify-between mb-2">
              <p className="text-xs text-muted-foreground">{kpi.label}</p>
              <kpi.icon size={14} className={kpi.color} />
            </div>
            <p className="text-2xl font-bold tabular-nums">{kpi.value}</p>
          </div>
        ))}
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-4">
        <div className="lg:col-span-2 bg-card border border-border rounded-lg overflow-hidden">
          <div className="flex items-center justify-between px-4 py-3 border-b border-border">
            <div className="flex items-center gap-2">
              <Monitor size={14} className="text-primary" />
              <h2 className="text-sm font-semibold">My Devices</h2>
            </div>
            <Link href="/device-management" className="flex items-center gap-1 text-[11px] text-muted-foreground hover:text-foreground transition-colors">
              View all <ChevronRight size={11} />
            </Link>
          </div>
          <div className="divide-y divide-border">
            {isLoading ? (
              <div className="px-4 py-6 text-xs text-muted-foreground">Loading data...</div>
            ) : devices.length === 0 ? (
              <div className="px-4 py-6 text-xs text-muted-foreground">No data available</div>
            ) : (
              devices.map((device) => (
                <div key={device.id} className="flex items-center gap-3 px-4 py-3 hover:bg-muted/20 transition-colors">
                  <div className="w-7 h-7 rounded-md bg-muted/40 flex items-center justify-center flex-shrink-0">
                    <Monitor size={13} className="text-muted-foreground" />
                  </div>
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2">
                      <p className="text-xs font-medium font-mono truncate">{device.hostname}</p>
                      <StatusBadge variant={device.status} />
                    </div>
                    <p className="text-[10px] text-muted-foreground mt-0.5">
                      {device.id} - {device.os} - Last seen {device.lastSeen}
                    </p>
                  </div>
                  <div className="flex items-center gap-2 flex-shrink-0">
                    <span className={`text-[10px] font-mono font-semibold ${riskColor(device.riskScore)}`}>
                      {(device.riskScore * 100).toFixed(0)}
                    </span>
                    <button
                      onClick={() => {
                        setDispatchInitialDeviceId(device.id);
                        setShowDispatch(true);
                      }}
                      disabled={device.status === 'offline'}
                      className="p-1.5 rounded-md text-muted-foreground hover:text-foreground hover:bg-muted disabled:opacity-30 disabled:cursor-not-allowed transition-colors"
                      title="Dispatch command"
                    >
                      <Terminal size={12} />
                    </button>
                  </div>
                </div>
              ))
            )}
          </div>
        </div>

        <div className="bg-card border border-border rounded-lg overflow-hidden">
          <div className="flex items-center justify-between px-4 py-3 border-b border-border">
            <div className="flex items-center gap-2">
              <Bell size={14} className="text-primary" />
              <h2 className="text-sm font-semibold">My Alerts</h2>
              {unacknowledgedAlerts.length > 0 && (
                <span className="text-[10px] px-1.5 py-0.5 rounded-full bg-red-500/20 text-red-400 font-semibold">
                  {unacknowledgedAlerts.length}
                </span>
              )}
            </div>
            <Link href="/alerts" className="flex items-center gap-1 text-[11px] text-muted-foreground hover:text-foreground transition-colors">
              View all <ChevronRight size={11} />
            </Link>
          </div>
          <div className="divide-y divide-border">
            {isLoading ? (
              <div className="px-4 py-6 text-xs text-muted-foreground">Loading data...</div>
            ) : alerts.length === 0 ? (
              <div className="px-4 py-6 text-xs text-muted-foreground">No data available</div>
            ) : (
              alerts.map((alert) => (
                <div key={alert.id} className={`px-4 py-3 ${alert.acknowledged ? 'opacity-50' : ''}`}>
                  <div className="flex items-start justify-between gap-2">
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-1.5 mb-0.5">
                        <span className={`text-[10px] px-1.5 py-0.5 rounded-full border font-medium ${severityColors[alert.severity]}`}>
                          {alert.severity}
                        </span>
                      </div>
                      <p className="text-xs font-medium truncate">{alert.title}</p>
                      <p className="text-[10px] text-muted-foreground mt-0.5">{alert.deviceName} - {alert.time}</p>
                    </div>
                    {!alert.acknowledged && (
                      <button
                        onClick={() => { void acknowledgeAlert(alert.id); }}
                        disabled={ackInFlight.has(alert.id)}
                        className="flex-shrink-0 p-1 rounded text-muted-foreground hover:text-green-400 transition-colors disabled:opacity-60"
                        title="Acknowledge"
                      >
                        {ackInFlight.has(alert.id) ? <Loader2 size={13} className="animate-spin" /> : <CheckCircle2 size={13} />}
                      </button>
                    )}
                  </div>
                </div>
              ))
            )}
          </div>
        </div>
      </div>

      <div className="bg-card border border-border rounded-lg overflow-hidden">
        <div className="flex items-center justify-between px-4 py-3 border-b border-border">
          <div className="flex items-center gap-2">
            <Terminal size={14} className="text-primary" />
            <h2 className="text-sm font-semibold">Recent Commands</h2>
          </div>
          <div className="flex items-center gap-2">
            <button
              onClick={() => { void fetchDashboardData('refresh'); }}
              className="flex items-center gap-1.5 px-2.5 py-1 text-[11px] text-muted-foreground border border-border rounded-md hover:bg-muted/60 transition-colors"
            >
              {isRefreshing ? <Loader2 size={11} className="animate-spin" /> : null}
              Refresh
            </button>
            <Link href="/command-dispatch" className="flex items-center gap-1 text-[11px] text-muted-foreground hover:text-foreground transition-colors">
              View all <ChevronRight size={11} />
            </Link>
          </div>
        </div>
        <div className="overflow-x-auto">
          <table className="w-full text-xs">
            <thead>
              <tr className="border-b border-border bg-muted/20">
                {['Command ID', 'Method', 'Device', 'Status', 'Issued At'].map((header) => (
                  <th key={header} className="text-left px-4 py-2.5 text-[10px] font-semibold text-muted-foreground uppercase tracking-wider">{header}</th>
                ))}
              </tr>
            </thead>
            <tbody className="divide-y divide-border">
              {isLoading ? (
                <tr>
                  <td colSpan={5} className="px-4 py-8 text-center text-xs text-muted-foreground">Loading data...</td>
                </tr>
              ) : recentCommands.length === 0 ? (
                <tr>
                  <td colSpan={5} className="px-4 py-8 text-center text-xs text-muted-foreground">No data available</td>
                </tr>
              ) : (
                recentCommands.map((cmd) => (
                  <tr key={cmd.id} className="hover:bg-muted/20 transition-colors">
                    <td className="px-4 py-2.5 font-mono text-muted-foreground">{cmd.id}</td>
                    <td className="px-4 py-2.5 font-mono font-medium">{cmd.method}</td>
                    <td className="px-4 py-2.5 font-mono text-muted-foreground">{cmd.deviceName}</td>
                    <td className="px-4 py-2.5">
                      <span className={`font-medium capitalize ${cmdStatusColors[cmd.status]}`}>{cmd.status}</span>
                    </td>
                    <td className="px-4 py-2.5 text-muted-foreground tabular-nums">{cmd.issuedAt}</td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>

      <LiveAlertFeed
        pushInterval={10000}
        maxEvents={10}
        events={liveFeedEvents}
        loading={isLoading}
        error={loadError}
      />

      {showPairModal && (
        <DevicePairingModal
          onClose={() => setShowPairModal(false)}
          onPaired={(device) => {
            toast.success(`${device.deviceName} added to your fleet`);
            setShowPairModal(false);
            void fetchDashboardData('refresh');
          }}
        />
      )}

      {showDispatch && (
        <OperatorDispatchModal
          devices={devices}
          methods={operatorMethods}
          initialDeviceId={dispatchInitialDeviceId}
          onClose={() => {
            setShowDispatch(false);
            setDispatchInitialDeviceId(null);
          }}
          onDispatched={() => {
            void fetchDashboardData('refresh');
          }}
        />
      )}
    </div>
  );
}
