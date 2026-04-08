'use client';
import React, { useState } from 'react';
import { Monitor, Terminal, Bell, Link2, CheckCircle2, AlertTriangle, ChevronRight, Loader2, X,  } from 'lucide-react';
import StatusBadge from '@/components/ui/StatusBadge';
import DevicePairingModal from '@/components/DevicePairingModal';
import LiveAlertFeed from '@/components/LiveAlertFeed';
import { toast } from 'sonner';
import Link from 'next/link';

// ─── Types ────────────────────────────────────────────────────────────────────
type DeviceStatus = 'online' | 'offline' | 'quarantined' | 'degraded';
type ComplianceStatus = 'compliant' | 'non_compliant' | 'drift';

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
}

interface Alert {
  id: string;
  title: string;
  severity: 'critical' | 'warning' | 'info';
  deviceName: string;
  time: string;
  acknowledged: boolean;
}

// ─── Mock data (operator-scoped — only devices assigned to this operator) ─────
const myDevices: Device[] = [
  { id: 'PC001', hostname: 'WKSTN-001', status: 'online', riskScore: 0.12, compliance: 'compliant', lastSeen: '1 min ago', os: 'Windows 11' },
  { id: 'PC002', hostname: 'WKSTN-002', status: 'online', riskScore: 0.08, compliance: 'compliant', lastSeen: '2 min ago', os: 'Windows 11' },
  { id: 'WKSTN-042', hostname: 'WKSTN-042', status: 'online', riskScore: 0.24, compliance: 'compliant', lastSeen: '3 min ago', os: 'Windows 10' },
  { id: 'WKSTN-007', hostname: 'WKSTN-007', status: 'degraded', riskScore: 0.61, compliance: 'drift', lastSeen: '5 min ago', os: 'Windows 11' },
  { id: 'WKSTN-019', hostname: 'WKSTN-019', status: 'offline', riskScore: 0.15, compliance: 'compliant', lastSeen: '25 min ago', os: 'Windows 10' },
];

const recentCommands: RecentCommand[] = [
  { id: 'CMD-7741', method: 'ping', deviceId: 'PC001', deviceName: 'WKSTN-001', status: 'completed', issuedAt: '21:04:11' },
  { id: 'CMD-7742', method: 'lock_screen', deviceId: 'PC002', deviceName: 'WKSTN-002', status: 'completed', issuedAt: '21:02:44' },
  { id: 'CMD-7743', method: 'ping', deviceId: 'WKSTN-042', deviceName: 'WKSTN-042', status: 'ack', issuedAt: '21:06:01' },
  { id: 'CMD-7740', method: 'ping', deviceId: 'WKSTN-007', deviceName: 'WKSTN-007', status: 'failed', issuedAt: '20:58:33' },
];

const myAlerts: Alert[] = [
  { id: 'ALT-201', title: 'Risk score elevated', severity: 'warning', deviceName: 'WKSTN-007', time: '21:05:58', acknowledged: false },
  { id: 'ALT-202', title: 'Policy drift detected', severity: 'warning', deviceName: 'WKSTN-042', time: '20:51:12', acknowledged: false },
  { id: 'ALT-200', title: 'Device offline', severity: 'info', deviceName: 'WKSTN-019', time: '20:41:17', acknowledged: true },
];

const cmdStatusColors: Record<string, string> = {
  completed: 'text-green-400',
  ack: 'text-amber-400',
  dispatched: 'text-blue-400',
  failed: 'text-red-400',
};

const severityColors: Record<string, string> = {
  critical: 'text-red-400 bg-red-500/10 border-red-500/20',
  warning: 'text-amber-400 bg-amber-500/10 border-amber-500/20',
  info: 'text-blue-400 bg-blue-500/10 border-blue-500/20',
};

// ─── Dispatch Command Modal (inline, operator-scoped) ─────────────────────────
interface DispatchModalProps {
  devices: Device[];
  onClose: () => void;
}

const OPERATOR_METHODS = [
  { id: 'ping', label: 'ping', risk: 'low', desc: 'Verify agent connectivity and kernel guard response.' },
  { id: 'lock_screen', label: 'lock_screen', risk: 'medium', desc: 'Lock the device screen immediately.' },
];

function OperatorDispatchModal({ devices, onClose }: DispatchModalProps) {
  const [selectedDevice, setSelectedDevice] = useState('');
  const [selectedMethod, setSelectedMethod] = useState('');
  const [deviceNameConfirm, setDeviceNameConfirm] = useState('');
  const [deviceIdSuffix, setDeviceIdSuffix] = useState('');
  const [confirmError, setConfirmError] = useState('');
  const [loading, setLoading] = useState(false);
  const [submitted, setSubmitted] = useState(false);
  const [step, setStep] = useState<'compose' | 'confirm'>('compose');

  const device = devices.find((d) => d.id === selectedDevice);
  const method = OPERATOR_METHODS.find((m) => m.id === selectedMethod);
  const needsConfirm = method?.risk === 'medium' || method?.risk === 'high';

  const handleProceed = () => {
    if (!selectedDevice || !selectedMethod) {
      toast.error('Select a device and command method');
      return;
    }
    if (needsConfirm) {
      setStep('confirm');
    } else {
      handleDispatch();
    }
  };

  const handleDispatch = async () => {
    if (needsConfirm && device) {
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
    await new Promise((r) => setTimeout(r, 1400));
    setLoading(false);
    setSubmitted(true);
    toast.success(`${selectedMethod} queued for ${device?.hostname}`, { description: 'Awaiting dispatch' });
    setTimeout(onClose, 1200);
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
            <p className="text-xs text-muted-foreground mt-1">Dispatching to gateway…</p>
          </div>
        ) : step === 'compose' ? (
          <div className="p-5 space-y-4">
            {/* Device selector */}
            <div>
              <label className="block text-xs font-medium mb-1.5">Target Device <span className="text-red-400">*</span></label>
              <p className="text-[11px] text-muted-foreground mb-2">Only your authorized devices are shown.</p>
              <select
                value={selectedDevice}
                onChange={(e) => setSelectedDevice(e.target.value)}
                className="w-full text-xs bg-muted/60 border border-border rounded-md px-3 py-2 text-foreground focus:outline-none focus:ring-1 focus:ring-primary/50"
              >
                <option value="">Select a device…</option>
                {devices.filter((d) => d.status !== 'offline').map((d) => (
                  <option key={d.id} value={d.id}>{d.hostname} — {d.status}</option>
                ))}
              </select>
            </div>

            {/* Device identity panel */}
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

            {/* Method selector */}
            <div>
              <label className="block text-xs font-medium mb-1.5">Command Method <span className="text-red-400">*</span></label>
              <p className="text-[11px] text-muted-foreground mb-2">Only operator-approved methods are shown.</p>
              <div className="space-y-2">
                {OPERATOR_METHODS.map((m) => (
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
                          m.risk === 'low' ? 'bg-green-500/10 border-green-500/20 text-green-400' : 'bg-amber-500/10 border-amber-500/20 text-amber-400'
                        }`}>{m.risk} risk</span>
                      </div>
                      <p className="text-[11px] text-muted-foreground">{m.desc}</p>
                    </div>
                  </label>
                ))}
              </div>
            </div>

            {/* Sensitive command notice */}
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
                disabled={!selectedDevice || !selectedMethod}
                className="flex-1 flex items-center justify-center gap-2 py-2 text-xs font-medium bg-primary text-primary-foreground rounded-md hover:bg-primary/90 disabled:opacity-50 active:scale-95 transition-all"
              >
                <Terminal size={13} />
                {needsConfirm ? 'Continue' : 'Dispatch'}
              </button>
            </div>
          </div>
        ) : (
          /* Confirmation step */
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

            {/* Device identity */}
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
                  onChange={(e) => { setDeviceNameConfirm(e.target.value); setConfirmError(''); }}
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
                  onChange={(e) => { setDeviceIdSuffix(e.target.value.toUpperCase()); setConfirmError(''); }}
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
                onClick={handleDispatch}
                disabled={loading || !deviceNameConfirm || deviceIdSuffix.length < 6}
                className="flex-1 flex items-center justify-center gap-2 py-2 text-xs font-medium bg-primary text-primary-foreground rounded-md hover:bg-primary/90 disabled:opacity-50 active:scale-95 transition-all"
              >
                {loading ? <><Loader2 size={12} className="animate-spin" />Dispatching…</> : <><Terminal size={12} />Execute Command</>}
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

// ─── Main Operator Dashboard ──────────────────────────────────────────────────
export default function OperatorDashboard() {
  const [showPairModal, setShowPairModal] = useState(false);
  const [showDispatch, setShowDispatch] = useState(false);
  const [alerts, setAlerts] = useState(myAlerts);

  const unacknowledgedAlerts = alerts.filter((a) => !a.acknowledged);

  const acknowledgeAlert = (id: string) => {
    setAlerts((prev) => prev.map((a) => a.id === id ? { ...a, acknowledged: true } : a));
    toast.success('Alert acknowledged');
  };

  const riskColor = (score: number) =>
    score > 0.6 ? 'text-red-400' : score > 0.3 ? 'text-amber-400' : 'text-green-400';

  return (
    <div className="space-y-6 fade-in">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">Operator Console</h1>
          <p className="text-sm text-muted-foreground mt-0.5">
            {myDevices.filter((d) => d.status === 'online').length} of {myDevices.length} devices online · Your assigned fleet
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
            onClick={() => setShowDispatch(true)}
            className="flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium bg-primary text-primary-foreground rounded-md hover:bg-primary/90 active:scale-95 transition-all"
          >
            <Terminal size={13} />
            Dispatch Command
          </button>
        </div>
      </div>

      {/* KPI row */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-3">
        {[
          { label: 'My Devices', value: myDevices.length, icon: Monitor, color: 'text-primary' },
          { label: 'Online', value: myDevices.filter((d) => d.status === 'online').length, icon: CheckCircle2, color: 'text-green-400' },
          { label: 'Alerts', value: unacknowledgedAlerts.length, icon: Bell, color: unacknowledgedAlerts.length > 0 ? 'text-red-400' : 'text-muted-foreground' },
          { label: 'Commands Today', value: recentCommands.length, icon: Terminal, color: 'text-primary' },
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
        {/* My Devices */}
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
            {myDevices.map((device) => (
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
                    {device.id} · {device.os} · Last seen {device.lastSeen}
                  </p>
                </div>
                <div className="flex items-center gap-2 flex-shrink-0">
                  <span className={`text-[10px] font-mono font-semibold ${riskColor(device.riskScore)}`}>
                    {(device.riskScore * 100).toFixed(0)}
                  </span>
                  <button
                    onClick={() => { setShowDispatch(true); }}
                    disabled={device.status === 'offline'}
                    className="p-1.5 rounded-md text-muted-foreground hover:text-foreground hover:bg-muted disabled:opacity-30 disabled:cursor-not-allowed transition-colors"
                    title="Dispatch command"
                  >
                    <Terminal size={12} />
                  </button>
                </div>
              </div>
            ))}
          </div>
        </div>

        {/* Alerts panel */}
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
            {alerts.map((alert) => (
              <div key={alert.id} className={`px-4 py-3 ${alert.acknowledged ? 'opacity-50' : ''}`}>
                <div className="flex items-start justify-between gap-2">
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-1.5 mb-0.5">
                      <span className={`text-[10px] px-1.5 py-0.5 rounded-full border font-medium ${severityColors[alert.severity]}`}>
                        {alert.severity}
                      </span>
                    </div>
                    <p className="text-xs font-medium truncate">{alert.title}</p>
                    <p className="text-[10px] text-muted-foreground mt-0.5">{alert.deviceName} · {alert.time}</p>
                  </div>
                  {!alert.acknowledged && (
                    <button
                      onClick={() => acknowledgeAlert(alert.id)}
                      className="flex-shrink-0 p-1 rounded text-muted-foreground hover:text-green-400 transition-colors"
                      title="Acknowledge"
                    >
                      <CheckCircle2 size={13} />
                    </button>
                  )}
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>

      {/* Recent commands */}
      <div className="bg-card border border-border rounded-lg overflow-hidden">
        <div className="flex items-center justify-between px-4 py-3 border-b border-border">
          <div className="flex items-center gap-2">
            <Terminal size={14} className="text-primary" />
            <h2 className="text-sm font-semibold">Recent Commands</h2>
          </div>
          <Link href="/command-dispatch" className="flex items-center gap-1 text-[11px] text-muted-foreground hover:text-foreground transition-colors">
            View all <ChevronRight size={11} />
          </Link>
        </div>
        <div className="overflow-x-auto">
          <table className="w-full text-xs">
            <thead>
              <tr className="border-b border-border bg-muted/20">
                {['Command ID', 'Method', 'Device', 'Status', 'Issued At'].map((h) => (
                  <th key={h} className="text-left px-4 py-2.5 text-[10px] font-semibold text-muted-foreground uppercase tracking-wider">{h}</th>
                ))}
              </tr>
            </thead>
            <tbody className="divide-y divide-border">
              {recentCommands.map((cmd) => (
                <tr key={cmd.id} className="hover:bg-muted/20 transition-colors">
                  <td className="px-4 py-2.5 font-mono text-muted-foreground">{cmd.id}</td>
                  <td className="px-4 py-2.5 font-mono font-medium">{cmd.method}</td>
                  <td className="px-4 py-2.5 font-mono text-muted-foreground">{cmd.deviceName}</td>
                  <td className="px-4 py-2.5">
                    <span className={`font-medium capitalize ${cmdStatusColors[cmd.status]}`}>{cmd.status}</span>
                  </td>
                  <td className="px-4 py-2.5 text-muted-foreground tabular-nums">{cmd.issuedAt}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      {/* Live FastAPI WebSocket feed */}
      <LiveAlertFeed pushInterval={10000} maxEvents={10} />

      {/* Modals */}
      {showPairModal && (
        <DevicePairingModal
          onClose={() => setShowPairModal(false)}
          onPaired={(device) => {
            toast.success(`${device.deviceName} added to your fleet`);
            setShowPairModal(false);
          }}
        />
      )}
      {showDispatch && (
        <OperatorDispatchModal
          devices={myDevices}
          onClose={() => setShowDispatch(false)}
        />
      )}
    </div>
  );
}
