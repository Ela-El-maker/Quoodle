'use client';
import React, { useState, useEffect, useRef } from 'react';
import { Monitor, Terminal, Activity, Shield, Clock, Cpu, HardDrive, Wifi, ChevronRight, ArrowLeft, Play, CheckCircle, XCircle, AlertTriangle, RefreshCw, ScrollText, Search, ChevronDown, ChevronUp, Download, RotateCcw, Layers, Globe, Lock, Users, Power, Camera, Folder, File, List, Network, Database, Server, Wrench, BarChart2, Calendar, Clipboard, Volume2, Monitor as DisplayIcon, Package, Rocket, Hash, Info, X, Send, Radio, Loader2 } from 'lucide-react';
import { useSearchParams } from 'next/navigation';
import Link from 'next/link';
import StatusBadge from '@/components/ui/StatusBadge';
import { toast } from 'sonner';

// ─── Types ────────────────────────────────────────────────────────────────────
type DeviceStatus = 'online' | 'offline' | 'quarantined' | 'degraded';
type CommandState = 'queued' | 'dispatched' | 'ack_received' | 'executing' | 'completed' | 'failed' | 'expired' | 'rejected';

interface Device {
  id: string;
  hostname: string;
  osBuild: string;
  owner: string;
  status: DeviceStatus;
  riskScore: number;
  compliance: 'compliant' | 'non_compliant' | 'drift';
  lastSeen: string;
  agentVersion: string;
  policySync: boolean;
  kernelGuard: boolean;
  ipAddress: string;
  sessionId: string | null;
  cpu: string;
  ram: string;
  disk: string;
  uptime: string;
  location: string;
  department: string;
}

interface CommandEntry {
  id: string;
  method: string;
  state: CommandState;
  actor: string;
  queuedAt: string;
  completedAt: string | null;
  duration: string | null;
  resultPreview: string | null;
}

interface TraceStep {
  label: string;
  detail: string;
  status: 'done' | 'active' | 'pending' | 'error';
  time: string | null;
}

// ─── Command Library ──────────────────────────────────────────────────────────
const COMMAND_CATEGORIES = [
  {
    category: 'System',
    icon: Server,
    color: 'text-blue-400',
    commands: [
      { id: 'system-info', label: 'System Info', desc: 'Full OS, hardware, and agent info', icon: Info, risk: 'low' },
      { id: 'hardware-info', label: 'Hardware Info', desc: 'CPU, RAM, GPU, motherboard details', icon: Cpu, risk: 'low' },
      { id: 'performance-metrics', label: 'Performance Metrics', desc: 'Real-time CPU, RAM, disk, network usage', icon: BarChart2, risk: 'low' },
      { id: 'uptime', label: 'Uptime', desc: 'System uptime and boot time', icon: Clock, risk: 'low' },
    ],
  },
  {
    category: 'Screen & Display',
    icon: DisplayIcon,
    color: 'text-purple-400',
    commands: [
      { id: 'screenshot-capture', label: 'Screenshot', desc: 'Capture current screen state', icon: Camera, risk: 'medium' },
      { id: 'display-info', label: 'Display Info', desc: 'Monitor resolution, refresh rate, DPI', icon: DisplayIcon, risk: 'low' },
      { id: 'lock_screen', label: 'Lock Screen', desc: 'Immediately lock the workstation', icon: Lock, risk: 'high' },
    ],
  },
  {
    category: 'Filesystem',
    icon: Folder,
    color: 'text-amber-400',
    commands: [
      { id: 'filesystem', label: 'Browse Filesystem', desc: 'Interactive file tree explorer', icon: Folder, risk: 'low' },
      { id: 'download-file', label: 'Download File', desc: 'Retrieve a file from the device', icon: Download, risk: 'medium' },
      { id: 'upload-file', label: 'Upload File', desc: 'Push a file to the device', icon: Send, risk: 'high' },
      { id: 'create-file', label: 'Create File', desc: 'Create a new file at a path', icon: File, risk: 'medium' },
      { id: 'create-folder', label: 'Create Folder', desc: 'Create a new directory', icon: Folder, risk: 'medium' },
      { id: 'delete-file', label: 'Delete File', desc: 'Remove a file from the device', icon: X, risk: 'high' },
      { id: 'delete-folder', label: 'Delete Folder', desc: 'Remove a directory recursively', icon: X, risk: 'high' },
    ],
  },
  {
    category: 'Processes',
    icon: Layers,
    color: 'text-green-400',
    commands: [
      { id: 'process-list', label: 'Process List', desc: 'All running processes with CPU/RAM', icon: List, risk: 'low' },
      { id: 'kill-process', label: 'Kill Process', desc: 'Terminate a process by PID or name', icon: X, risk: 'high' },
      { id: 'start-process', label: 'Start Process', desc: 'Launch an executable on the device', icon: Play, risk: 'high' },
    ],
  },
  {
    category: 'Network',
    icon: Network,
    color: 'text-cyan-400',
    commands: [
      { id: 'network-info', label: 'Network Info', desc: 'Interfaces, IPs, DNS, gateway', icon: Network, risk: 'low' },
      { id: 'ping', label: 'Ping', desc: 'Connectivity check to the agent', icon: Radio, risk: 'low' },
      { id: 'netstat', label: 'Netstat', desc: 'Active connections and listening ports', icon: Globe, risk: 'low' },
      { id: 'dns-lookup', label: 'DNS Lookup', desc: 'Resolve a hostname from the device', icon: Globe, risk: 'low' },
    ],
  },
  {
    category: 'Registry',
    icon: Database,
    color: 'text-orange-400',
    commands: [
      { id: 'registry-read', label: 'Registry Read', desc: 'Read a registry key value', icon: Database, risk: 'medium' },
      { id: 'registry-write', label: 'Registry Write', desc: 'Write a value to the registry', icon: Database, risk: 'high' },
      { id: 'registry-delete', label: 'Registry Delete', desc: 'Delete a registry key', icon: Database, risk: 'high' },
    ],
  },
  {
    category: 'Services',
    icon: Wrench,
    color: 'text-indigo-400',
    commands: [
      { id: 'services-list', label: 'Services List', desc: 'All Windows services and their states', icon: List, risk: 'low' },
      { id: 'service-start', label: 'Start Service', desc: 'Start a stopped Windows service', icon: Play, risk: 'high' },
      { id: 'service-stop', label: 'Stop Service', desc: 'Stop a running Windows service', icon: X, risk: 'high' },
      { id: 'service-restart', label: 'Restart Service', desc: 'Restart a Windows service', icon: RotateCcw, risk: 'high' },
    ],
  },
  {
    category: 'Event Logs',
    icon: ScrollText,
    color: 'text-rose-400',
    commands: [
      { id: 'event-logs', label: 'Event Logs', desc: 'Windows event log entries', icon: ScrollText, risk: 'low' },
      { id: 'security-logs', label: 'Security Logs', desc: 'Security audit log entries', icon: Shield, risk: 'low' },
      { id: 'application-logs', label: 'Application Logs', desc: 'Application event log entries', icon: ScrollText, risk: 'low' },
    ],
  },
  {
    category: 'Scheduled Tasks',
    icon: Calendar,
    color: 'text-teal-400',
    commands: [
      { id: 'scheduled-tasks', label: 'Scheduled Tasks', desc: 'All Windows scheduled tasks', icon: Calendar, risk: 'low' },
      { id: 'create-task', label: 'Create Task', desc: 'Create a new scheduled task', icon: Calendar, risk: 'high' },
      { id: 'delete-task', label: 'Delete Task', desc: 'Remove a scheduled task', icon: X, risk: 'high' },
    ],
  },
  {
    category: 'Users & Sessions',
    icon: Users,
    color: 'text-pink-400',
    commands: [
      { id: 'users-list', label: 'Users List', desc: 'Local and domain user accounts', icon: Users, risk: 'low' },
      { id: 'active-sessions', label: 'Active Sessions', desc: 'Currently logged-in users', icon: Users, risk: 'low' },
      { id: 'logoff-user', label: 'Log Off User', desc: 'Force log off a user session', icon: X, risk: 'high' },
    ],
  },
  {
    category: 'Power',
    icon: Power,
    color: 'text-yellow-400',
    commands: [
      { id: 'power-info', label: 'Power Info', desc: 'Battery, power plan, sleep settings', icon: Power, risk: 'low' },
      { id: 'shutdown', label: 'Shutdown', desc: 'Gracefully shut down the device', icon: Power, risk: 'critical' },
      { id: 'reboot', label: 'Reboot', desc: 'Restart the device', icon: RotateCcw, risk: 'critical' },
      { id: 'sleep', label: 'Sleep', desc: 'Put the device to sleep', icon: Power, risk: 'high' },
    ],
  },
  {
    category: 'Clipboard & Audio',
    icon: Clipboard,
    color: 'text-lime-400',
    commands: [
      { id: 'clipboard-read', label: 'Read Clipboard', desc: 'Get current clipboard contents', icon: Clipboard, risk: 'medium' },
      { id: 'clipboard-write', label: 'Write Clipboard', desc: 'Set clipboard contents', icon: Clipboard, risk: 'medium' },
      { id: 'audio-info', label: 'Audio Info', desc: 'Audio devices and volume levels', icon: Volume2, risk: 'low' },
      { id: 'set-volume', label: 'Set Volume', desc: 'Adjust system volume level', icon: Volume2, risk: 'medium' },
    ],
  },
  {
    category: 'Software',
    icon: Package,
    color: 'text-violet-400',
    commands: [
      { id: 'installed-apps', label: 'Installed Apps', desc: 'All installed applications', icon: Package, risk: 'low' },
      { id: 'startup-items', label: 'Startup Items', desc: 'Programs that run at startup', icon: Rocket, risk: 'low' },
      { id: 'uninstall-app', label: 'Uninstall App', desc: 'Remove an installed application', icon: X, risk: 'high' },
    ],
  },
];

// ─── Mock data ────────────────────────────────────────────────────────────────
const mockDevices: Record<string, Device> = {
  'PC001': { id: 'PC001', hostname: 'WKSTN-001', osBuild: '19045.4170', owner: 'sarah.chen@quoodle.io', status: 'online', riskScore: 0.12, compliance: 'compliant', lastSeen: '21:06:11', agentVersion: '0.0.1', policySync: true, kernelGuard: true, ipAddress: '10.0.1.11', sessionId: 'sess-7a2f', cpu: 'Intel Core i7-12700K', ram: '32 GB', disk: '512 GB SSD', uptime: '4d 6h 22m', location: 'HQ Floor 2', department: 'Engineering' },
  'WKSTN-055': { id: 'WKSTN-055', hostname: 'WKSTN-055', osBuild: '19045.4170', owner: 'chloe.dubois@quoodle.io', status: 'online', riskScore: 0.06, compliance: 'compliant', lastSeen: '21:06:12', agentVersion: '0.0.1', policySync: true, kernelGuard: true, ipAddress: '10.0.1.65', sessionId: 'sess-1k2l', cpu: 'Intel Core i5-11400', ram: '16 GB', disk: '256 GB SSD', uptime: '2d 14h 5m', location: 'HQ Floor 3', department: 'Marketing' },
};

const getDevice = (id: string): Device => mockDevices[id] ?? {
  id, hostname: id, osBuild: '19045.4170', owner: 'admin@quoodle.io', status: 'online', riskScore: 0.15, compliance: 'compliant', lastSeen: '21:06:00', agentVersion: '0.0.1', policySync: true, kernelGuard: true, ipAddress: '10.0.1.100', sessionId: 'sess-demo', cpu: 'Intel Core i7', ram: '16 GB', disk: '512 GB SSD', uptime: '1d 2h', location: 'HQ', department: 'IT',
};

const mockCommandHistory: CommandEntry[] = [
  { id: 'CMD-7742', method: 'system-info', state: 'completed', actor: 'chloe.dubois@quoodle.io', queuedAt: '21:06:01', completedAt: '21:06:09', duration: '8s', resultPreview: 'Windows 11 Pro 22H2 · 12-core · 32GB RAM' },
  { id: 'CMD-7740', method: 'screenshot-capture', state: 'completed', actor: 'admin@quoodle.io', queuedAt: '21:04:50', completedAt: '21:04:54', duration: '4s', resultPreview: '1920×1080 PNG · 2.4 MB' },
  { id: 'CMD-7739', method: 'process-list', state: 'completed', actor: 'ops.team@quoodle.io', queuedAt: '21:05:40', completedAt: '21:05:48', duration: '8s', resultPreview: '142 processes · 8 high-CPU' },
  { id: 'CMD-7737', method: 'filesystem', state: 'completed', actor: 'sarah.chen@quoodle.io', queuedAt: '21:03:10', completedAt: '21:03:18', duration: '8s', resultPreview: 'C:\\ · 512 GB · 187 GB used' },
  { id: 'CMD-7741', method: 'lock_screen', state: 'failed', actor: 'raj.mehta@quoodle.io', queuedAt: '21:01:55', completedAt: '21:01:58', duration: '3s', resultPreview: null },
  { id: 'CMD-7736', method: 'network-info', state: 'completed', actor: 'alex.kumar@quoodle.io', queuedAt: '20:45:00', completedAt: '20:45:06', duration: '6s', resultPreview: '3 interfaces · IPv4 10.0.1.29' },
];

const buildTraceSteps = (method: string, state: CommandState): TraceStep[] => {
  const steps: TraceStep[] = [
    { label: 'Web UI', detail: 'Command submitted via control plane', status: 'done', time: '21:06:01' },
    { label: 'Laravel API', detail: 'Validated, authorized, signed payload', status: 'done', time: '21:06:01' },
    { label: 'FastAPI Gateway', detail: 'Signature verified, dispatched to agent channel', status: state === 'queued' ? 'pending' : 'done', time: state === 'queued' ? null : '21:06:02' },
    { label: 'Windows Agent', detail: `Executing: ${method}`, status: ['queued', 'dispatched'].includes(state) ? 'pending' : state === 'executing' ? 'active' : state === 'failed' ? 'error' : 'done', time: ['queued', 'dispatched'].includes(state) ? null : '21:06:03' },
    { label: 'Result Return', detail: 'Agent → FastAPI → Laravel → UI', status: ['queued', 'dispatched', 'ack_received', 'executing'].includes(state) ? 'pending' : state === 'failed' ? 'error' : 'done', time: ['queued', 'dispatched', 'ack_received', 'executing'].includes(state) ? null : '21:06:09' },
  ];
  return steps;
};

const MAIN_TABS = ['Overview', 'Commands', 'Trace', 'Results', 'History', 'Telemetry', 'Alerts', 'Audit'];

export default function DeviceDetailPageContent() {
  const searchParams = useSearchParams();
  const deviceId = searchParams.get('device') ?? 'WKSTN-055';
  const device = getDevice(deviceId);

  const [activeTab, setActiveTab] = useState('Overview');
  const [commandSearch, setCommandSearch] = useState('');
  const [selectedCategory, setSelectedCategory] = useState<string | null>(null);
  const [activeCommand, setActiveCommand] = useState<{ id: string; label: string; risk: string } | null>(null);
  const [commandParams, setCommandParams] = useState('');
  const [isDispatching, setIsDispatching] = useState(false);
  const [liveResults, setLiveResults] = useState<{ commandId: string; method: string; state: CommandState; output: string; traceSteps: TraceStep[] } | null>(null);
  const [expandedHistoryId, setExpandedHistoryId] = useState<string | null>(null);
  const liveRef = useRef<HTMLDivElement>(null);

  const riskColor = device.riskScore > 0.6 ? 'text-red-400' : device.riskScore > 0.3 ? 'text-amber-400' : 'text-green-400';

  const filteredCategories = COMMAND_CATEGORIES.map(cat => ({
    ...cat,
    commands: cat.commands.filter(cmd =>
      !commandSearch || cmd.label.toLowerCase().includes(commandSearch.toLowerCase()) || cmd.desc.toLowerCase().includes(commandSearch.toLowerCase())
    ),
  })).filter(cat => !commandSearch || cat.commands.length > 0);

  const riskBadge = (risk: string) => {
    const map: Record<string, string> = {
      low: 'text-green-400 bg-green-500/10 border-green-500/20',
      medium: 'text-amber-400 bg-amber-500/10 border-amber-500/20',
      high: 'text-red-400 bg-red-500/10 border-red-500/20',
      critical: 'text-red-500 bg-red-500/20 border-red-500/40',
    };
    return map[risk] ?? 'text-muted-foreground bg-muted border-border';
  };

  const dispatchCommand = () => {
    if (!activeCommand) return;
    setIsDispatching(true);
    const cmdId = 'CMD-' + Math.floor(Math.random() * 9000 + 1000);
    const traceSteps = buildTraceSteps(activeCommand.id, 'executing');

    setTimeout(() => {
      setIsDispatching(false);
      setLiveResults({
        commandId: cmdId,
        method: activeCommand.id,
        state: 'executing',
        output: '',
        traceSteps,
      });
      setActiveTab('Trace');
      toast.success(`${activeCommand.label} dispatched — ${cmdId}`);

      // Simulate result arriving
      setTimeout(() => {
        setLiveResults(prev => prev ? {
          ...prev,
          state: 'completed',
          traceSteps: buildTraceSteps(activeCommand.id, 'completed'),
          output: `{"status":"ok","command":"${activeCommand.id}","device":"${device.hostname}","timestamp":"${new Date().toISOString()}","result":{"data":"Command executed successfully on ${device.hostname}"}}`,
        } : null);
      }, 3000);
    }, 1200);
  };

  const stateIcon = (s: CommandState) => {
    if (s === 'completed') return <CheckCircle size={12} className="text-green-400 flex-shrink-0" />;
    if (['failed', 'expired', 'rejected'].includes(s)) return <XCircle size={12} className="text-red-400 flex-shrink-0" />;
    if (['executing', 'ack_received'].includes(s)) return <Loader2 size={12} className="text-blue-400 flex-shrink-0 animate-spin" />;
    return <Clock size={12} className="text-amber-400 flex-shrink-0" />;
  };

  return (
    <div className="space-y-4 fade-in">
      {/* Back + Header */}
      <div className="flex items-start gap-4">
        <Link href="/device-management" className="flex items-center gap-1.5 text-xs text-muted-foreground hover:text-foreground transition-colors mt-1">
          <ArrowLeft size={13} /> Devices
        </Link>
        <div className="flex-1">
          <div className="flex items-center gap-3 flex-wrap">
            <div className="w-10 h-10 rounded-lg bg-muted flex items-center justify-center flex-shrink-0">
              <Monitor size={18} className="text-muted-foreground" />
            </div>
            <div>
              <div className="flex items-center gap-2">
                <h1 className="text-2xl font-semibold tracking-tight">{device.hostname}</h1>
                <StatusBadge variant={device.status} pulse={device.status === 'online'} />
              </div>
              <p className="text-sm text-muted-foreground font-mono">{device.id} · {device.ipAddress} · {device.department} · {device.location}</p>
            </div>
            <div className="ml-auto flex items-center gap-2">
              <button onClick={() => toast.info('Device refreshed')} className="flex items-center gap-1.5 px-3 py-1.5 text-xs text-muted-foreground border border-border rounded-md hover:bg-muted/60 transition-colors">
                <RefreshCw size={12} /> Refresh
              </button>
              <Link href="/command-results" className="flex items-center gap-1.5 px-3 py-1.5 text-xs bg-primary/10 border border-primary/20 text-primary rounded-md hover:bg-primary/20 transition-colors">
                <BarChart2 size={12} /> View Results
              </Link>
            </div>
          </div>
        </div>
      </div>

      {/* Quick stats */}
      <div className="grid grid-cols-2 md:grid-cols-4 lg:grid-cols-6 gap-2">
        {[
          { label: 'Risk Score', value: `${(device.riskScore * 100).toFixed(0)}/100`, color: riskColor },
          { label: 'Compliance', value: device.compliance.replace('_', ' '), color: device.compliance === 'compliant' ? 'text-green-400' : 'text-amber-400' },
          { label: 'CPU', value: device.cpu.split(' ').slice(0, 3).join(' '), color: 'text-foreground' },
          { label: 'RAM', value: device.ram, color: 'text-foreground' },
          { label: 'Uptime', value: device.uptime, color: 'text-foreground' },
          { label: 'Agent', value: `v${device.agentVersion}`, color: 'text-green-400' },
        ].map(s => (
          <div key={s.label} className="bg-card border border-border rounded-lg px-3 py-2.5">
            <p className="text-[10px] text-muted-foreground uppercase tracking-wide mb-0.5">{s.label}</p>
            <p className={`text-xs font-semibold truncate ${s.color}`}>{s.value}</p>
          </div>
        ))}
      </div>

      {/* Main tabs */}
      <div className="flex items-center gap-0.5 border-b border-border overflow-x-auto scrollbar-thin">
        {MAIN_TABS.map(tab => (
          <button
            key={tab}
            onClick={() => setActiveTab(tab)}
            className={`px-4 py-2.5 text-xs font-medium border-b-2 transition-colors whitespace-nowrap ${
              activeTab === tab ? 'border-primary text-primary' : 'border-transparent text-muted-foreground hover:text-foreground'
            }`}
          >
            {tab}
          </button>
        ))}
      </div>

      {/* ── Overview ── */}
      {activeTab === 'Overview' && (
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
          <div className="space-y-3">
            <div className="bg-card border border-border rounded-lg p-4">
              <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wide mb-3">Device Identity</p>
              <div className="grid grid-cols-2 gap-2">
                {[
                  { label: 'Hostname', value: device.hostname },
                  { label: 'Device ID', value: device.id },
                  { label: 'IP Address', value: device.ipAddress },
                  { label: 'OS Build', value: device.osBuild },
                  { label: 'Agent Version', value: device.agentVersion },
                  { label: 'Session ID', value: device.sessionId ?? '—' },
                  { label: 'Owner', value: device.owner },
                  { label: 'Department', value: device.department },
                  { label: 'Location', value: device.location },
                  { label: 'Last Seen', value: device.lastSeen + ' UTC' },
                ].map(item => (
                  <div key={item.label} className="bg-muted/30 rounded-lg p-2.5">
                    <p className="text-[10px] text-muted-foreground uppercase tracking-wide mb-0.5">{item.label}</p>
                    <p className="text-xs font-medium font-mono truncate">{item.value}</p>
                  </div>
                ))}
              </div>
            </div>
          </div>
          <div className="space-y-3">
            <div className="bg-card border border-border rounded-lg p-4">
              <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wide mb-3">Security Posture</p>
              <div className="space-y-3">
                <div>
                  <div className="flex items-center justify-between mb-1">
                    <p className="text-xs text-muted-foreground">Risk Score</p>
                    <span className={`text-lg font-bold tabular-nums ${riskColor}`}>{(device.riskScore * 100).toFixed(0)}<span className="text-xs font-normal text-muted-foreground">/100</span></span>
                  </div>
                  <div className="h-2 bg-muted rounded-full overflow-hidden">
                    <div className={`h-full rounded-full ${device.riskScore > 0.6 ? 'bg-red-500' : device.riskScore > 0.3 ? 'bg-amber-500' : 'bg-green-500'}`} style={{ width: `${device.riskScore * 100}%` }} />
                  </div>
                </div>
                {[
                  { label: 'Compliance', value: device.compliance.replace('_', ' '), ok: device.compliance === 'compliant' },
                  { label: 'Policy Sync', value: device.policySync ? 'Synchronized' : 'Hash mismatch', ok: device.policySync },
                  { label: 'Kernel Guard', value: device.kernelGuard ? 'KMDF driver active' : 'Driver not detected', ok: device.kernelGuard },
                ].map(item => (
                  <div key={item.label} className="flex items-center justify-between py-2 border-b border-border/50 last:border-0">
                    <p className="text-xs text-muted-foreground">{item.label}</p>
                    <span className={`text-xs font-medium ${item.ok ? 'text-green-400' : 'text-amber-400'}`}>{item.ok ? '✓' : '⚠'} {item.value}</span>
                  </div>
                ))}
              </div>
            </div>
            <div className="bg-card border border-border rounded-lg p-4">
              <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wide mb-3">Quick Actions</p>
              <div className="grid grid-cols-2 gap-2">
                {[
                  { label: 'System Info', icon: Info, tab: 'Commands', color: 'text-blue-400 bg-blue-500/10 border-blue-500/20' },
                  { label: 'Screenshot', icon: Camera, tab: 'Commands', color: 'text-purple-400 bg-purple-500/10 border-purple-500/20' },
                  { label: 'Process List', icon: List, tab: 'Commands', color: 'text-green-400 bg-green-500/10 border-green-500/20' },
                  { label: 'View History', icon: Clock, tab: 'History', color: 'text-amber-400 bg-amber-500/10 border-amber-500/20' },
                ].map(action => (
                  <button
                    key={action.label}
                    onClick={() => setActiveTab(action.tab)}
                    className={`flex items-center gap-2 px-3 py-2.5 text-xs font-medium border rounded-lg transition-colors hover:opacity-80 ${action.color}`}
                  >
                    <action.icon size={13} /> {action.label}
                  </button>
                ))}
              </div>
            </div>
          </div>
        </div>
      )}

      {/* ── Commands ── */}
      {activeTab === 'Commands' && (
        <div className="grid grid-cols-1 xl:grid-cols-3 gap-4">
          {/* Command library */}
          <div className="xl:col-span-2 space-y-3">
            <div className="relative">
              <Search size={13} className="absolute left-3 top-1/2 -translate-y-1/2 text-muted-foreground" />
              <input
                type="text"
                placeholder="Search commands…"
                value={commandSearch}
                onChange={e => setCommandSearch(e.target.value)}
                className="w-full pl-9 pr-3 py-2 text-sm bg-muted/60 border border-border rounded-md text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-1 focus:ring-primary/50"
              />
            </div>
            <div className="space-y-2 max-h-[60vh] overflow-y-auto scrollbar-thin pr-1">
              {filteredCategories.map(cat => (
                <div key={cat.category} className="bg-card border border-border rounded-lg overflow-hidden">
                  <button
                    className="w-full flex items-center gap-2 px-4 py-3 hover:bg-muted/30 transition-colors"
                    onClick={() => setSelectedCategory(selectedCategory === cat.category ? null : cat.category)}
                  >
                    <cat.icon size={14} className={cat.color} />
                    <span className="text-sm font-semibold flex-1 text-left">{cat.category}</span>
                    <span className="text-[11px] text-muted-foreground">{cat.commands.length} commands</span>
                    {selectedCategory === cat.category ? <ChevronUp size={13} className="text-muted-foreground" /> : <ChevronDown size={13} className="text-muted-foreground" />}
                  </button>
                  {(selectedCategory === cat.category || commandSearch) && (
                    <div className="border-t border-border divide-y divide-border/50">
                      {cat.commands.map(cmd => (
                        <div
                          key={cmd.id}
                          onClick={() => setActiveCommand({ id: cmd.id, label: cmd.label, risk: cmd.risk })}
                          className={`flex items-center gap-3 px-4 py-3 cursor-pointer transition-colors hover:bg-muted/20 ${activeCommand?.id === cmd.id ? 'bg-primary/5 border-l-2 border-primary' : ''}`}
                        >
                          <cmd.icon size={14} className="text-muted-foreground flex-shrink-0" />
                          <div className="flex-1 min-w-0">
                            <p className="text-sm font-medium">{cmd.label}</p>
                            <p className="text-[11px] text-muted-foreground">{cmd.desc}</p>
                          </div>
                          <span className={`text-[10px] font-semibold px-1.5 py-0.5 rounded-full border ${riskBadge(cmd.risk)}`}>{cmd.risk}</span>
                        </div>
                      ))}
                    </div>
                  )}
                </div>
              ))}
            </div>
          </div>

          {/* Dispatch panel */}
          <div className="xl:col-span-1">
            <div className="bg-card border border-border rounded-lg sticky top-4">
              <div className="px-4 py-3 border-b border-border">
                <p className="text-sm font-semibold">Dispatch Command</p>
                <p className="text-[11px] text-muted-foreground">Target: {device.hostname} ({device.id})</p>
              </div>
              <div className="p-4 space-y-3">
                {activeCommand ? (
                  <>
                    <div className="bg-muted/30 rounded-lg p-3">
                      <div className="flex items-center justify-between mb-1">
                        <p className="text-sm font-semibold">{activeCommand.label}</p>
                        <span className={`text-[10px] font-semibold px-1.5 py-0.5 rounded-full border ${riskBadge(activeCommand.risk)}`}>{activeCommand.risk}</span>
                      </div>
                      <p className="text-[11px] font-mono text-muted-foreground">{activeCommand.id}</p>
                    </div>
                    <div>
                      <label className="text-[11px] text-muted-foreground mb-1 block">Parameters (JSON, optional)</label>
                      <textarea
                        value={commandParams}
                        onChange={e => setCommandParams(e.target.value)}
                        placeholder='{}'
                        rows={3}
                        className="w-full px-3 py-2 text-xs font-mono bg-muted/60 border border-border rounded-md text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-1 focus:ring-primary/50 resize-none"
                      />
                    </div>
                    {['high', 'critical'].includes(activeCommand.risk) && (
                      <div className="flex items-start gap-2 bg-red-500/10 border border-red-500/20 rounded-lg p-3">
                        <AlertTriangle size={13} className="text-red-400 flex-shrink-0 mt-0.5" />
                        <p className="text-[11px] text-red-400">This is a {activeCommand.risk}-risk command. It will take immediate effect on {device.hostname}.</p>
                      </div>
                    )}
                    <button
                      onClick={dispatchCommand}
                      disabled={isDispatching || device.status !== 'online'}
                      className="w-full flex items-center justify-center gap-2 py-2.5 text-sm font-medium bg-primary text-primary-foreground rounded-md hover:bg-primary/90 disabled:opacity-50 disabled:cursor-not-allowed transition-all"
                    >
                      {isDispatching ? <><Loader2 size={14} className="animate-spin" /> Dispatching…</> : <><Send size={14} /> Execute {activeCommand.label}</>}
                    </button>
                    {device.status !== 'online' && (
                      <p className="text-[11px] text-amber-400 text-center">Device is {device.status} — commands unavailable</p>
                    )}
                  </>
                ) : (
                  <div className="py-8 text-center">
                    <Terminal size={28} className="mx-auto text-muted-foreground/30 mb-2" />
                    <p className="text-sm text-muted-foreground">Select a command from the library</p>
                    <p className="text-[11px] text-muted-foreground/60 mt-1">Browse categories or search above</p>
                  </div>
                )}
              </div>
            </div>
          </div>
        </div>
      )}

      {/* ── Trace ── */}
      {activeTab === 'Trace' && (
        <div className="space-y-4">
          {liveResults ? (
            <div className="bg-card border border-border rounded-lg p-5">
              <div className="flex items-center justify-between mb-4">
                <div>
                  <p className="text-sm font-semibold">{liveResults.commandId} — {liveResults.method}</p>
                  <p className="text-[11px] text-muted-foreground">Live trace path: Web → Laravel → FastAPI → Agent → Back</p>
                </div>
                <StatusBadge variant={liveResults.state} />
              </div>
              <div className="relative">
                {liveResults.traceSteps.map((step, i) => (
                  <div key={step.label} className="flex items-start gap-4 mb-4 last:mb-0">
                    <div className="flex flex-col items-center">
                      <div className={`w-8 h-8 rounded-full flex items-center justify-center flex-shrink-0 ${
                        step.status === 'done' ? 'bg-green-500/20 border border-green-500/40' :
                        step.status === 'active' ? 'bg-blue-500/20 border border-blue-500/40 animate-pulse' :
                        step.status === 'error'? 'bg-red-500/20 border border-red-500/40' : 'bg-muted/40 border border-border'
                      }`}>
                        {step.status === 'done' ? <CheckCircle size={14} className="text-green-400" /> :
                         step.status === 'active' ? <Loader2 size={14} className="text-blue-400 animate-spin" /> :
                         step.status === 'error' ? <XCircle size={14} className="text-red-400" /> :
                         <Clock size={14} className="text-muted-foreground" />}
                      </div>
                      {i < liveResults.traceSteps.length - 1 && (
                        <div className={`w-0.5 h-8 mt-1 ${step.status === 'done' ? 'bg-green-500/40' : 'bg-border'}`} />
                      )}
                    </div>
                    <div className="flex-1 pt-1">
                      <div className="flex items-center gap-2">
                        <p className="text-sm font-semibold">{step.label}</p>
                        {step.time && <span className="text-[11px] text-muted-foreground tabular-nums">{step.time}</span>}
                      </div>
                      <p className="text-[11px] text-muted-foreground">{step.detail}</p>
                    </div>
                  </div>
                ))}
              </div>
              {liveResults.output && (
                <div className="mt-4 border-t border-border pt-4">
                  <p className="text-[10px] text-muted-foreground uppercase tracking-wide mb-2">Live Result Output</p>
                  <pre className="text-xs font-mono bg-muted/40 rounded-lg p-3 overflow-x-auto text-green-400">{liveResults.output}</pre>
                </div>
              )}
            </div>
          ) : (
            <div className="bg-card border border-border rounded-lg p-8 text-center">
              <Radio size={32} className="mx-auto text-muted-foreground/30 mb-3" />
              <p className="text-sm font-medium text-muted-foreground">No active trace</p>
              <p className="text-xs text-muted-foreground/60 mt-1">Dispatch a command from the Commands tab to see the live trace path</p>
              <button onClick={() => setActiveTab('Commands')} className="mt-4 flex items-center gap-1.5 px-4 py-2 text-xs bg-primary/10 border border-primary/20 text-primary rounded-md hover:bg-primary/20 transition-colors mx-auto">
                <Terminal size={12} /> Go to Commands
              </button>
            </div>
          )}

          {/* Static trace diagram */}
          <div className="bg-card border border-border rounded-lg p-5">
            <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wide mb-4">Architecture: Command Flow</p>
            <div className="flex items-center gap-2 flex-wrap">
              {[
                { label: 'Web UI', color: 'bg-blue-500/20 border-blue-500/40 text-blue-400' },
                { label: '→', color: '' },
                { label: 'Laravel API', color: 'bg-violet-500/20 border-violet-500/40 text-violet-400' },
                { label: '→', color: '' },
                { label: 'FastAPI Gateway', color: 'bg-amber-500/20 border-amber-500/40 text-amber-400' },
                { label: '→', color: '' },
                { label: 'Windows Agent', color: 'bg-green-500/20 border-green-500/40 text-green-400' },
                { label: '→', color: '' },
                { label: 'Result Return', color: 'bg-cyan-500/20 border-cyan-500/40 text-cyan-400' },
              ].map((node, i) => (
                node.label === '→' ? (
                  <ChevronRight key={i} size={16} className="text-muted-foreground" />
                ) : (
                  <div key={i} className={`px-3 py-1.5 rounded-lg border text-xs font-semibold ${node.color}`}>{node.label}</div>
                )
              ))}
            </div>
          </div>
        </div>
      )}

      {/* ── Results ── */}
      {activeTab === 'Results' && (
        <div className="space-y-3">
          <div className="flex items-center justify-between">
            <p className="text-sm text-muted-foreground">Live command results for {device.hostname}</p>
            <Link href="/command-results" className="flex items-center gap-1.5 text-xs text-primary hover:underline">
              View all results <ChevronRight size={12} />
            </Link>
          </div>
          {liveResults?.output ? (
            <div className="bg-card border border-border rounded-lg p-4">
              <div className="flex items-center justify-between mb-3">
                <p className="text-sm font-semibold">{liveResults.commandId} — {liveResults.method}</p>
                <StatusBadge variant={liveResults.state} />
              </div>
              <pre className="text-xs font-mono bg-muted/40 rounded-lg p-3 overflow-x-auto text-green-400">{liveResults.output}</pre>
            </div>
          ) : (
            <div className="bg-card border border-border rounded-lg p-8 text-center">
              <BarChart2 size={32} className="mx-auto text-muted-foreground/30 mb-3" />
              <p className="text-sm font-medium text-muted-foreground">No results yet</p>
              <p className="text-xs text-muted-foreground/60 mt-1">Dispatch a command to see results here in real-time</p>
            </div>
          )}
        </div>
      )}

      {/* ── History ── */}
      {activeTab === 'History' && (
        <div className="space-y-3">
          <div className="flex items-center justify-between">
            <p className="text-sm text-muted-foreground">{mockCommandHistory.length} commands for {device.hostname}</p>
            <Link href="/command-history" className="flex items-center gap-1.5 text-xs text-primary hover:underline">
              Full history <ChevronRight size={12} />
            </Link>
          </div>
          <div className="bg-card border border-border rounded-lg overflow-hidden">
            <div className="divide-y divide-border">
              {mockCommandHistory.map(cmd => (
                <React.Fragment key={cmd.id}>
                  <div
                    className="flex items-center gap-3 px-4 py-3 cursor-pointer hover:bg-muted/20 transition-colors"
                    onClick={() => setExpandedHistoryId(expandedHistoryId === cmd.id ? null : cmd.id)}
                  >
                    {stateIcon(cmd.state)}
                    <span className="font-mono text-[11px] text-primary font-semibold w-20">{cmd.id}</span>
                    <span className="text-xs font-medium flex-1">{cmd.method}</span>
                    <StatusBadge variant={cmd.state} size="sm" />
                    <span className="text-[11px] text-muted-foreground tabular-nums">{cmd.queuedAt}</span>
                    <span className="text-[11px] text-muted-foreground">{cmd.duration ?? '—'}</span>
                    <button
                      onClick={e => { e.stopPropagation(); toast.promise(new Promise(r => setTimeout(r, 1000)), { loading: `Replaying ${cmd.method}…`, success: 'Command replayed', error: 'Failed' }); }}
                      className="flex items-center gap-1 px-2 py-0.5 text-[11px] bg-primary/10 border border-primary/20 text-primary rounded hover:bg-primary/20 transition-colors"
                    >
                      <RotateCcw size={9} /> Replay
                    </button>
                  </div>
                  {expandedHistoryId === cmd.id && (
                    <div className="px-4 py-3 bg-muted/10 border-t border-border/50">
                      <div className="grid grid-cols-2 md:grid-cols-4 gap-2">
                        <div className="bg-muted/30 rounded p-2"><p className="text-[10px] text-muted-foreground mb-0.5">Actor</p><p className="text-xs">{cmd.actor}</p></div>
                        <div className="bg-muted/30 rounded p-2"><p className="text-[10px] text-muted-foreground mb-0.5">Completed</p><p className="text-xs">{cmd.completedAt ?? '—'}</p></div>
                        {cmd.resultPreview && <div className="bg-muted/30 rounded p-2 col-span-2"><p className="text-[10px] text-muted-foreground mb-0.5">Result</p><p className="text-xs">{cmd.resultPreview}</p></div>}
                      </div>
                    </div>
                  )}
                </React.Fragment>
              ))}
            </div>
          </div>
        </div>
      )}

      {/* ── Telemetry ── */}
      {activeTab === 'Telemetry' && (
        <div className="space-y-3">
          <div className="flex items-center justify-between">
            <p className="text-sm text-muted-foreground">Live telemetry for {device.hostname}</p>
            <Link href={`/telemetry-monitoring?device=${device.id}`} className="flex items-center gap-1.5 text-xs text-primary hover:underline">
              Full telemetry <ChevronRight size={12} />
            </Link>
          </div>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
            {[
              { label: 'CPU Usage', value: '12%', bar: 12, color: 'bg-green-500', icon: Cpu },
              { label: 'RAM Usage', value: '45%', bar: 45, color: 'bg-blue-500', icon: Activity },
              { label: 'Disk Usage', value: '60%', bar: 60, color: 'bg-amber-500', icon: HardDrive },
              { label: 'Network TX', value: '2.3 Mbps', bar: 23, color: 'bg-cyan-500', icon: Wifi },
              { label: 'Network RX', value: '1.1 Mbps', bar: 11, color: 'bg-violet-500', icon: Wifi },
              { label: 'GPU Usage', value: '8%', bar: 8, color: 'bg-pink-500', icon: BarChart2 },
            ].map(metric => (
              <div key={metric.label} className="bg-card border border-border rounded-lg p-4">
                <div className="flex items-center justify-between mb-2">
                  <div className="flex items-center gap-2">
                    <metric.icon size={13} className="text-muted-foreground" />
                    <p className="text-sm font-medium">{metric.label}</p>
                  </div>
                  <span className="text-sm font-bold tabular-nums">{metric.value}</span>
                </div>
                <div className="h-2 bg-muted rounded-full overflow-hidden">
                  <div className={`h-full rounded-full ${metric.color} transition-all`} style={{ width: `${metric.bar}%` }} />
                </div>
              </div>
            ))}
          </div>
          <p className="text-[11px] text-muted-foreground text-center">Last snapshot: {device.lastSeen} UTC</p>
        </div>
      )}

      {/* ── Alerts ── */}
      {activeTab === 'Alerts' && (
        <div className="space-y-3">
          <div className="flex items-center justify-between">
            <p className="text-sm text-muted-foreground">Alerts for {device.hostname}</p>
            <Link href={`/alerts?device=${device.id}`} className="flex items-center gap-1.5 text-xs text-primary hover:underline">
              All alerts <ChevronRight size={12} />
            </Link>
          </div>
          <div className="space-y-2">
            {[
              { id: 'ALT-001', severity: 'high', message: 'Policy hash mismatch detected', time: '20:14:22', status: 'open' },
              { id: 'ALT-002', severity: 'medium', message: 'Unusual process activity: svchost.exe high CPU', time: '19:45:11', status: 'acknowledged' },
              { id: 'ALT-003', severity: 'low', message: 'Agent version outdated — v0.0.1 → v0.0.2 available', time: '18:00:00', status: 'open' },
            ].map(alert => (
              <div key={alert.id} className={`flex items-start gap-3 bg-card border rounded-lg p-4 ${alert.severity === 'high' ? 'border-red-500/30' : alert.severity === 'medium' ? 'border-amber-500/30' : 'border-border'}`}>
                <AlertTriangle size={14} className={alert.severity === 'high' ? 'text-red-400' : alert.severity === 'medium' ? 'text-amber-400' : 'text-muted-foreground'} />
                <div className="flex-1">
                  <div className="flex items-center gap-2">
                    <span className={`text-[10px] font-semibold uppercase px-1.5 py-0.5 rounded-full ${alert.severity === 'high' ? 'bg-red-500/10 text-red-400' : alert.severity === 'medium' ? 'bg-amber-500/10 text-amber-400' : 'bg-muted text-muted-foreground'}`}>{alert.severity}</span>
                    <span className="text-[11px] text-muted-foreground">{alert.id}</span>
                  </div>
                  <p className="text-sm mt-1">{alert.message}</p>
                  <p className="text-[11px] text-muted-foreground mt-0.5">{alert.time} UTC · {alert.status}</p>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* ── Audit ── */}
      {activeTab === 'Audit' && (
        <div className="space-y-3">
          <div className="flex items-center justify-between">
            <p className="text-sm text-muted-foreground">Audit trail for {device.hostname}</p>
            <Link href="/audit" className="flex items-center gap-1.5 text-xs text-primary hover:underline">
              Full audit log <ChevronRight size={12} />
            </Link>
          </div>
          <div className="bg-card border border-border rounded-lg overflow-hidden">
            <div className="divide-y divide-border">
              {[
                { id: 'AUD-001', type: 'command', actor: 'chloe.dubois@quoodle.io', action: 'Executed system-info', time: '21:06:01', outcome: 'success' },
                { id: 'AUD-002', type: 'command', actor: 'admin@quoodle.io', action: 'Executed screenshot-capture', time: '21:04:50', outcome: 'success' },
                { id: 'AUD-003', type: 'policy', actor: 'admin@quoodle.io', action: 'Policy hash updated', time: '20:30:00', outcome: 'success' },
                { id: 'AUD-004', type: 'command', actor: 'raj.mehta@quoodle.io', action: 'Executed lock_screen — FAILED', time: '21:01:55', outcome: 'failure' },
                { id: 'AUD-005', type: 'access', actor: 'sarah.chen@quoodle.io', action: 'Device detail viewed', time: '20:00:00', outcome: 'success' },
              ].map(entry => (
                <div key={entry.id} className="flex items-center gap-3 px-4 py-3">
                  <div className={`w-2 h-2 rounded-full flex-shrink-0 ${entry.outcome === 'success' ? 'bg-green-500' : 'bg-red-500'}`} />
                  <span className="text-[11px] font-mono text-muted-foreground w-20">{entry.id}</span>
                  <span className={`text-[10px] font-semibold px-1.5 py-0.5 rounded-full ${entry.type === 'command' ? 'bg-blue-500/10 text-blue-400' : entry.type === 'policy' ? 'bg-violet-500/10 text-violet-400' : 'bg-muted text-muted-foreground'}`}>{entry.type}</span>
                  <span className="text-xs flex-1">{entry.action}</span>
                  <span className="text-[11px] text-muted-foreground">{entry.actor.split('@')[0]}</span>
                  <span className="text-[11px] text-muted-foreground tabular-nums">{entry.time}</span>
                </div>
              ))}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
