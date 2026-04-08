'use client';
import React, { useState } from 'react';
import { X, Monitor, Terminal, Shield, Activity, Clock, Cpu, HardDrive, Wifi, ChevronRight, AlertTriangle, CheckCircle, XCircle, RotateCcw, Bell, Layers, ExternalLink, Radio, Loader2, Network, Users, Camera, Folder, Info, Lock } from 'lucide-react';
import StatusBadge from '@/components/ui/StatusBadge';
import Link from 'next/link';
import { toast } from 'sonner';

interface Device {
  id: string;
  hostname: string;
  osBuild: string;
  owner: string;
  status: 'online' | 'offline' | 'quarantined' | 'degraded';
  riskScore: number;
  compliance: 'compliant' | 'non_compliant' | 'drift';
  lastSeen: string;
  agentVersion: string;
  policySync: boolean;
  kernelGuard: boolean;
  ipAddress: string;
  sessionId: string | null;
}

interface DeviceDetailDrawerProps {
  device: Device;
  onClose: () => void;
}

const DRAWER_TABS = ['Overview', 'Telemetry', 'Commands', 'Security', 'Alerts', 'Audit'];

const recentCommands = [
  { id: 'CMD-7742', method: 'system-info',        state: 'completed' as const, time: '21:06:09', actor: 'chloe.dubois' },
  { id: 'CMD-7740', method: 'screenshot-capture', state: 'completed' as const, time: '21:04:54', actor: 'admin' },
  { id: 'CMD-7741', method: 'lock_screen',        state: 'failed' as const,    time: '21:01:58', actor: 'raj.mehta' },
  { id: 'CMD-7739', method: 'process-list',       state: 'completed' as const, time: '21:05:48', actor: 'ops.team' },
  { id: 'CMD-7737', method: 'filesystem',         state: 'completed' as const, time: '21:03:18', actor: 'sarah.chen' },
];

const QUICK_COMMANDS = [
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
  const [dispatchingCmd, setDispatchingCmd] = useState<string | null>(null);

  const riskColor = device.riskScore > 0.6 ? 'text-red-400' : device.riskScore > 0.3 ? 'text-amber-400' : 'text-green-400';

  const quickDispatch = (cmdId: string, cmdLabel: string) => {
    if (device.status !== 'online') {
      toast.error(`${device.hostname} is ${device.status} — cannot dispatch commands`);
      return;
    }
    setDispatchingCmd(cmdId);
    setTimeout(() => {
      setDispatchingCmd(null);
      toast.success(`${cmdLabel} dispatched to ${device.hostname}`);
    }, 1200);
  };

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
              <h2 className="font-semibold text-sm">{device.hostname}</h2>
              <p className="text-[11px] text-muted-foreground font-mono">{device.id} · {device.ipAddress}</p>
            </div>
          </div>
          <div className="flex items-center gap-2">
            <StatusBadge variant={device.status} pulse={device.status === 'online'} />
            <button onClick={onClose} className="p-1.5 rounded-md text-muted-foreground hover:text-foreground hover:bg-muted transition-colors">
              <X size={15} />
            </button>
          </div>
        </div>

        {/* CTA Banner — Deep link to full device page */}
        <div className="px-5 py-3 bg-primary/5 border-b border-primary/20 flex-shrink-0">
          <Link
            href={`/device-detail?device=${device.id}`}
            className="flex items-center justify-between group"
          >
            <div>
              <p className="text-xs font-semibold text-primary">Open Full Device Console</p>
              <p className="text-[11px] text-muted-foreground">Commands · Trace · Results · History · Telemetry · Alerts · Audit — everything in one place</p>
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

          {/* ── Overview ── */}
          {activeTab === 'Overview' && (
            <>
              <div className="grid grid-cols-2 gap-2">
                {[
                  { label: 'IP Address',    value: device.ipAddress,              mono: true },
                  { label: 'OS Build',      value: device.osBuild,                mono: true },
                  { label: 'Agent Version', value: device.agentVersion,           mono: true },
                  { label: 'Session ID',    value: device.sessionId ?? '—',       mono: true },
                  { label: 'Owner',         value: device.owner,                  mono: false },
                  { label: 'Kernel Guard',  value: device.kernelGuard ? '✓ Active' : '✗ Inactive', mono: false },
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
                    {(device.riskScore * 100).toFixed(0)}<span className="text-xs font-normal text-muted-foreground">/100</span>
                  </span>
                </div>
                <div className="h-1.5 bg-muted rounded-full overflow-hidden">
                  <div
                    className={`h-full rounded-full ${device.riskScore > 0.6 ? 'bg-red-500' : device.riskScore > 0.3 ? 'bg-amber-500' : 'bg-green-500'}`}
                    style={{ width: `${device.riskScore * 100}%` }}
                  />
                </div>
              </div>

              <div className="bg-muted/30 rounded-lg p-3">
                <p className="text-[10px] text-muted-foreground uppercase tracking-wide mb-2">Policy Sync</p>
                {device.policySync ? (
                  <p className="text-xs text-green-400 font-medium">✓ Policy hash synchronized — policy-2026-04</p>
                ) : (
                  <p className="text-xs text-amber-400 font-medium">⚠ Hash mismatch — policy-2026-04 vs reported</p>
                )}
              </div>

              {/* Recent activity summary */}
              <div className="bg-muted/30 rounded-lg p-3">
                <p className="text-[10px] text-muted-foreground uppercase tracking-wide mb-2">Recent Activity</p>
                <div className="space-y-1.5">
                  {recentCommands.slice(0, 3).map(cmd => (
                    <div key={cmd.id} className="flex items-center gap-2">
                      {stateIcon(cmd.state)}
                      <span className="text-[11px] font-mono text-muted-foreground">{cmd.id}</span>
                      <span className="text-[11px] flex-1">{cmd.method}</span>
                      <span className="text-[11px] text-muted-foreground tabular-nums">{cmd.time}</span>
                    </div>
                  ))}
                </div>
              </div>
            </>
          )}

          {/* ── Telemetry ── */}
          {activeTab === 'Telemetry' && (
            <div className="space-y-3">
              {[
                { label: 'CPU Usage',   icon: Cpu,      value: '12%', bar: 12, color: 'bg-green-500' },
                { label: 'RAM Usage',   icon: Activity, value: '45%', bar: 45, color: 'bg-blue-500' },
                { label: 'Disk Usage',  icon: HardDrive,value: '60%', bar: 60, color: 'bg-amber-500' },
                { label: 'Network TX',  icon: Wifi,     value: '2.3 Mbps', bar: 23, color: 'bg-cyan-400' },
                { label: 'Network RX',  icon: Wifi,     value: '1.1 Mbps', bar: 11, color: 'bg-violet-400' },
              ].map((metric) => (
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
              <p className="text-[11px] text-muted-foreground text-center">Last snapshot: {device.lastSeen} UTC</p>
              <Link href={`/telemetry-monitoring?device=${device.id}`} className="flex items-center justify-center gap-1.5 w-full py-2 text-xs text-primary border border-primary/20 rounded-lg hover:bg-primary/5 transition-colors">
                Full telemetry history <ChevronRight size={12} />
              </Link>
            </div>
          )}

          {/* ── Commands ── */}
          {activeTab === 'Commands' && (
            <div className="space-y-3">
              <p className="text-[11px] text-muted-foreground">Quick-dispatch common commands. For the full command library with all {'>'}40 commands, open the device console.</p>
              <div className="grid grid-cols-2 gap-2">
                {QUICK_COMMANDS.map(cmd => (
                  <button
                    key={cmd.id}
                    onClick={() => quickDispatch(cmd.id, cmd.label)}
                    disabled={dispatchingCmd === cmd.id || device.status !== 'online'}
                    className={`flex items-center gap-2 px-3 py-2.5 text-xs font-medium border rounded-lg transition-colors hover:opacity-80 disabled:opacity-50 disabled:cursor-not-allowed ${cmd.color}`}
                  >
                    {dispatchingCmd === cmd.id ? <Loader2 size={12} className="animate-spin" /> : <cmd.icon size={12} />}
                    {cmd.label}
                  </button>
                ))}
              </div>
              <div className="space-y-1.5">
                <p className="text-[10px] text-muted-foreground uppercase tracking-wide">Recent Commands</p>
                {recentCommands.map((cmd) => (
                  <div key={`drawer-cmd-${cmd.id}`} className="flex items-center gap-3 bg-muted/30 rounded-lg px-3 py-2.5">
                    {stateIcon(cmd.state)}
                    <span className="font-mono text-[11px] text-muted-foreground">{cmd.id}</span>
                    <span className="text-xs font-medium flex-1">{cmd.method}</span>
                    <span className="text-[11px] text-muted-foreground tabular-nums">{cmd.time}</span>
                    <button
                      onClick={() => toast.promise(new Promise(r => setTimeout(r, 1000)), { loading: `Replaying ${cmd.method}…`, success: 'Replayed', error: 'Failed' })}
                      className="p-1 text-muted-foreground hover:text-primary transition-colors"
                      title="Replay"
                    >
                      <RotateCcw size={10} />
                    </button>
                  </div>
                ))}
              </div>
              <Link href={`/device-detail?device=${device.id}`} className="flex items-center justify-center gap-1.5 w-full py-2.5 text-xs font-medium bg-primary/10 border border-primary/20 text-primary rounded-lg hover:bg-primary/20 transition-colors">
                <Terminal size={12} /> Open Full Command Library (40+ commands)
              </Link>
            </div>
          )}

          {/* ── Security ── */}
          {activeTab === 'Security' && (
            <div className="space-y-3">
              <div className="bg-muted/30 rounded-lg p-3 space-y-2">
                <p className="text-[10px] text-muted-foreground uppercase tracking-wide mb-2">Compliance Status</p>
                <StatusBadge variant={device.compliance} size="md" />
                {device.compliance !== 'compliant' && (
                  <p className="text-[11px] text-amber-400 mt-2">Policy hash mismatch detected. Last attestation: 20:14:00 UTC</p>
                )}
              </div>
              <div className="bg-muted/30 rounded-lg p-3">
                <p className="text-[10px] text-muted-foreground uppercase tracking-wide mb-2">Kernel Guard</p>
                <p className={`text-xs font-medium ${device.kernelGuard ? 'text-green-400' : 'text-red-400'}`}>
                  {device.kernelGuard ? '✓ KMDF driver active — IOCTL interface available' : '✗ Driver not detected — falling back to named pipe'}
                </p>
              </div>
              <div className="bg-muted/30 rounded-lg p-3">
                <p className="text-[10px] text-muted-foreground uppercase tracking-wide mb-2">Risk Score</p>
                <div className="flex items-center gap-3">
                  <span className={`text-2xl font-bold tabular-nums ${riskColor}`}>{(device.riskScore * 100).toFixed(0)}</span>
                  <div className="flex-1">
                    <div className="h-2 bg-muted rounded-full overflow-hidden">
                      <div className={`h-full rounded-full ${device.riskScore > 0.6 ? 'bg-red-500' : device.riskScore > 0.3 ? 'bg-amber-500' : 'bg-green-500'}`} style={{ width: `${device.riskScore * 100}%` }} />
                    </div>
                    <p className="text-[10px] text-muted-foreground mt-1">{device.riskScore > 0.6 ? 'High risk — immediate attention required' : device.riskScore > 0.3 ? 'Medium risk — monitor closely' : 'Low risk — within acceptable range'}</p>
                  </div>
                </div>
              </div>
              {device.status === 'quarantined' && (
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

          {/* ── Alerts ── */}
          {activeTab === 'Alerts' && (
            <div className="space-y-2">
              {[
                { id: 'ALT-001', severity: 'high', message: 'Policy hash mismatch detected', time: '20:14:22' },
                { id: 'ALT-002', severity: 'medium', message: 'Unusual process activity: svchost.exe high CPU', time: '19:45:11' },
                { id: 'ALT-003', severity: 'low', message: 'Agent version outdated', time: '18:00:00' },
              ].map(alert => (
                <div key={alert.id} className={`flex items-start gap-3 bg-muted/20 border rounded-lg p-3 ${alert.severity === 'high' ? 'border-red-500/30' : alert.severity === 'medium' ? 'border-amber-500/30' : 'border-border'}`}>
                  <AlertTriangle size={13} className={alert.severity === 'high' ? 'text-red-400' : alert.severity === 'medium' ? 'text-amber-400' : 'text-muted-foreground'} />
                  <div>
                    <p className="text-xs font-medium">{alert.message}</p>
                    <p className="text-[11px] text-muted-foreground">{alert.id} · {alert.time} UTC</p>
                  </div>
                </div>
              ))}
              <Link href={`/alerts?device=${device.id}`} className="flex items-center justify-center gap-1.5 w-full py-2 text-xs text-primary border border-primary/20 rounded-lg hover:bg-primary/5 transition-colors">
                All alerts for this device <ChevronRight size={12} />
              </Link>
            </div>
          )}

          {/* ── Audit ── */}
          {activeTab === 'Audit' && (
            <div className="space-y-2">
              {[
                { id: 'AUD-001', type: 'command', actor: 'chloe.dubois', action: 'Executed system-info', time: '21:06:01', ok: true },
                { id: 'AUD-002', type: 'command', actor: 'admin', action: 'Executed screenshot-capture', time: '21:04:50', ok: true },
                { id: 'AUD-003', type: 'policy', actor: 'admin', action: 'Policy hash updated', time: '20:30:00', ok: true },
                { id: 'AUD-004', type: 'command', actor: 'raj.mehta', action: 'lock_screen — FAILED', time: '21:01:55', ok: false },
              ].map(entry => (
                <div key={entry.id} className="flex items-center gap-3 bg-muted/20 rounded-lg px-3 py-2.5">
                  <div className={`w-1.5 h-1.5 rounded-full flex-shrink-0 ${entry.ok ? 'bg-green-500' : 'bg-red-500'}`} />
                  <span className={`text-[10px] font-semibold px-1.5 py-0.5 rounded-full ${entry.type === 'command' ? 'bg-blue-500/10 text-blue-400' : 'bg-violet-500/10 text-violet-400'}`}>{entry.type}</span>
                  <span className="text-[11px] flex-1">{entry.action}</span>
                  <span className="text-[11px] text-muted-foreground">{entry.actor}</span>
                  <span className="text-[11px] text-muted-foreground tabular-nums">{entry.time}</span>
                </div>
              ))}
              <Link href="/audit" className="flex items-center justify-center gap-1.5 w-full py-2 text-xs text-primary border border-primary/20 rounded-lg hover:bg-primary/5 transition-colors">
                Full audit trail <ChevronRight size={12} />
              </Link>
            </div>
          )}
        </div>

        {/* Footer — CTA row */}
        <div className="border-t border-border px-5 py-3 flex-shrink-0">
          <Link
            href={`/device-detail?device=${device.id}`}
            className="w-full flex items-center justify-center gap-2 py-2.5 text-sm font-semibold bg-primary text-primary-foreground rounded-lg hover:bg-primary/90 transition-colors"
          >
            <Monitor size={14} />
            Open Full Device Console
            <ExternalLink size={12} className="ml-1" />
          </Link>
          <div className="flex items-center gap-2 mt-2">
            <Link href={`/telemetry-monitoring?device=${device.id}`} className="flex-1 flex items-center justify-center gap-1.5 py-1.5 text-xs border border-border rounded-md text-muted-foreground hover:text-foreground hover:bg-muted/60 transition-colors">
              <Activity size={11} /> Telemetry
            </Link>
            <Link href={`/command-dispatch?device=${device.id}`} className="flex-1 flex items-center justify-center gap-1.5 py-1.5 text-xs border border-border rounded-md text-muted-foreground hover:text-foreground hover:bg-muted/60 transition-colors">
              <Terminal size={11} /> Dispatch
            </Link>
            <Link href="/command-history" className="flex-1 flex items-center justify-center gap-1.5 py-1.5 text-xs border border-border rounded-md text-muted-foreground hover:text-foreground hover:bg-muted/60 transition-colors">
              <Clock size={11} /> History
            </Link>
            <Link href={`/alerts?device=${device.id}`} className="flex-1 flex items-center justify-center gap-1.5 py-1.5 text-xs border border-border rounded-md text-muted-foreground hover:text-foreground hover:bg-muted/60 transition-colors">
              <Bell size={11} /> Alerts
            </Link>
          </div>
        </div>
      </div>
    </>
  );
}