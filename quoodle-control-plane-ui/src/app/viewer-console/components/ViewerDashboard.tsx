'use client';
import React, { useState } from 'react';
import { Monitor, Bell, ShieldCheck, ChevronRight, Search, AlertTriangle, CheckCircle2, Info, Lock,  } from 'lucide-react';
import StatusBadge from '@/components/ui/StatusBadge';
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
  owner: string;
}

interface Alert {
  id: string;
  title: string;
  severity: 'critical' | 'warning' | 'info';
  deviceName: string;
  time: string;
}

interface ComplianceItem {
  control: string;
  status: 'pass' | 'fail' | 'warning';
  score: number;
  lastChecked: string;
}

// ─── Mock data (viewer-scoped — read-only view of fleet) ──────────────────────
const viewableDevices: Device[] = [
  { id: 'PC001', hostname: 'WKSTN-001', status: 'online', riskScore: 0.12, compliance: 'compliant', lastSeen: '1 min ago', os: 'Windows 11', owner: 'sarah.chen@quoodle.io' },
  { id: 'PC002', hostname: 'WKSTN-002', status: 'online', riskScore: 0.08, compliance: 'compliant', lastSeen: '2 min ago', os: 'Windows 11', owner: 'james.wright@quoodle.io' },
  { id: 'SRV-PROD-01', hostname: 'SRV-PROD-01', status: 'online', riskScore: 0.19, compliance: 'drift', lastSeen: '2 min ago', os: 'Windows Server 2022', owner: 'devops@quoodle.io' },
  { id: 'WKSTN-007', hostname: 'WKSTN-007', status: 'degraded', riskScore: 0.61, compliance: 'drift', lastSeen: '5 min ago', os: 'Windows 11', owner: 'mike.torres@quoodle.io' },
  { id: 'WKSTN-019', hostname: 'WKSTN-019', status: 'offline', riskScore: 0.15, compliance: 'compliant', lastSeen: '25 min ago', os: 'Windows 10', owner: 'alex.kumar@quoodle.io' },
  { id: 'SRV-PROD-04', hostname: 'SRV-PROD-04', status: 'quarantined', riskScore: 0.89, compliance: 'non_compliant', lastSeen: '2h ago', os: 'Windows Server 2022', owner: 'devops@quoodle.io' },
];

const viewableAlerts: Alert[] = [
  { id: 'ALT-301', title: 'Attestation failure on SRV-PROD-04', severity: 'critical', deviceName: 'SRV-PROD-04', time: '19:14:02' },
  { id: 'ALT-302', title: 'Risk score elevated', severity: 'warning', deviceName: 'WKSTN-007', time: '21:05:58' },
  { id: 'ALT-303', title: 'Policy drift detected', severity: 'warning', deviceName: 'SRV-PROD-01', time: '20:51:12' },
  { id: 'ALT-304', title: 'Device offline', severity: 'info', deviceName: 'WKSTN-019', time: '20:41:17' },
];

const complianceItems: ComplianceItem[] = [
  { control: 'Risk Score Threshold', status: 'fail', score: 62, lastChecked: '21:06:00' },
  { control: 'Policy Hash Sync', status: 'warning', score: 78, lastChecked: '21:06:00' },
  { control: 'Kernel Guard Coverage', status: 'warning', score: 83, lastChecked: '21:06:00' },
  { control: 'Device Compliance Rate', status: 'pass', score: 91, lastChecked: '21:06:00' },
  { control: 'Command Success Rate', status: 'pass', score: 99, lastChecked: '21:06:00' },
];

const severityColors: Record<string, string> = {
  critical: 'text-red-400 bg-red-500/10 border-red-500/20',
  warning: 'text-amber-400 bg-amber-500/10 border-amber-500/20',
  info: 'text-blue-400 bg-blue-500/10 border-blue-500/20',
};

const complianceStatusColors: Record<string, string> = {
  pass: 'text-green-400',
  warning: 'text-amber-400',
  fail: 'text-red-400',
};

export default function ViewerDashboard() {
  const [search, setSearch] = useState('');
  const [activeTab, setActiveTab] = useState<'devices' | 'alerts' | 'compliance'>('devices');

  const filteredDevices = viewableDevices.filter((d) =>
    !search ||
    d.hostname.toLowerCase().includes(search.toLowerCase()) ||
    d.id.toLowerCase().includes(search.toLowerCase()) ||
    d.owner.toLowerCase().includes(search.toLowerCase())
  );

  const riskColor = (score: number) =>
    score > 0.6 ? 'text-red-400' : score > 0.3 ? 'text-amber-400' : 'text-green-400';

  const onlineCount = viewableDevices.filter((d) => d.status === 'online').length;
  const criticalAlerts = viewableAlerts.filter((a) => a.severity === 'critical').length;
  const compliantCount = viewableDevices.filter((d) => d.compliance === 'compliant').length;

  return (
    <div className="space-y-6 fade-in">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">Viewer Console</h1>
          <p className="text-sm text-muted-foreground mt-0.5">Read-only fleet overview · No command access</p>
        </div>
        {/* Read-only badge */}
        <div className="flex items-center gap-1.5 px-3 py-1.5 bg-muted/30 border border-border rounded-md text-[11px] text-muted-foreground">
          <Lock size={11} />
          Read-only access
        </div>
      </div>

      {/* KPI row */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-3">
        {[
          { label: 'Total Devices', value: viewableDevices.length, icon: Monitor, color: 'text-primary' },
          { label: 'Online', value: onlineCount, icon: CheckCircle2, color: 'text-green-400' },
          { label: 'Critical Alerts', value: criticalAlerts, icon: AlertTriangle, color: criticalAlerts > 0 ? 'text-red-400' : 'text-muted-foreground' },
          { label: 'Compliant', value: `${compliantCount}/${viewableDevices.length}`, icon: ShieldCheck, color: 'text-green-400' },
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

      {/* Read-only notice */}
      <div className="bg-blue-500/5 border border-blue-500/20 rounded-lg px-4 py-3 flex items-center gap-2.5">
        <Info size={14} className="text-blue-400 flex-shrink-0" />
        <p className="text-[11px] text-blue-400">
          You have <strong>viewer access</strong>. You can monitor devices, alerts, and compliance — but cannot dispatch commands, acknowledge alerts, or modify any settings.
          Contact an operator or admin to take action.
        </p>
      </div>

      {/* Tab navigation */}
      <div className="flex items-center gap-1 bg-muted/20 rounded-lg p-1 w-fit">
        {[
          { id: 'devices', label: 'Devices', icon: Monitor },
          { id: 'alerts', label: 'Alerts', icon: Bell },
          { id: 'compliance', label: 'Compliance', icon: ShieldCheck },
        ].map((tab) => (
          <button
            key={tab.id}
            onClick={() => setActiveTab(tab.id as typeof activeTab)}
            className={`flex items-center gap-1.5 px-3 py-1.5 rounded-md text-xs font-medium transition-all ${
              activeTab === tab.id ? 'bg-card text-foreground shadow-sm' : 'text-muted-foreground hover:text-foreground'
            }`}
          >
            <tab.icon size={12} />
            {tab.label}
          </button>
        ))}
      </div>

      {/* ── Devices tab ─────────────────────────────────────────────────────── */}
      {activeTab === 'devices' && (
        <div className="bg-card border border-border rounded-lg overflow-hidden">
          <div className="flex items-center justify-between px-4 py-3 border-b border-border">
            <div className="flex items-center gap-2">
              <Monitor size={14} className="text-primary" />
              <h2 className="text-sm font-semibold">Fleet Devices</h2>
              <span className="text-[10px] px-1.5 py-0.5 rounded-full bg-muted text-muted-foreground">{filteredDevices.length}</span>
            </div>
            <div className="relative">
              <Search size={12} className="absolute left-2.5 top-1/2 -translate-y-1/2 text-muted-foreground" />
              <input
                type="text"
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                placeholder="Search devices…"
                className="pl-7 pr-3 py-1.5 text-xs bg-muted/60 border border-border rounded-md text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-1 focus:ring-primary/50 w-48"
              />
            </div>
          </div>
          <div className="overflow-x-auto">
            <table className="w-full text-xs">
              <thead>
                <tr className="border-b border-border bg-muted/20">
                  {['Hostname', 'Status', 'Risk', 'Compliance', 'OS', 'Owner', 'Last Seen'].map((h) => (
                    <th key={h} className="text-left px-4 py-2.5 text-[10px] font-semibold text-muted-foreground uppercase tracking-wider">{h}</th>
                  ))}
                </tr>
              </thead>
              <tbody className="divide-y divide-border">
                {filteredDevices.map((device) => (
                  <tr key={device.id} className="hover:bg-muted/20 transition-colors">
                    <td className="px-4 py-3">
                      <p className="font-mono font-medium">{device.hostname}</p>
                      <p className="text-[10px] text-muted-foreground">{device.id}</p>
                    </td>
                    <td className="px-4 py-3"><StatusBadge variant={device.status} /></td>
                    <td className="px-4 py-3">
                      <span className={`font-mono font-semibold ${riskColor(device.riskScore)}`}>
                        {(device.riskScore * 100).toFixed(0)}
                      </span>
                    </td>
                    <td className="px-4 py-3">
                      <span className={`capitalize text-[11px] font-medium ${
                        device.compliance === 'compliant' ? 'text-green-400' :
                        device.compliance === 'drift' ? 'text-amber-400' : 'text-red-400'
                      }`}>
                        {device.compliance.replace('_', ' ')}
                      </span>
                    </td>
                    <td className="px-4 py-3 text-muted-foreground">{device.os}</td>
                    <td className="px-4 py-3 text-muted-foreground truncate max-w-[140px]">{device.owner}</td>
                    <td className="px-4 py-3 text-muted-foreground tabular-nums">{device.lastSeen}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* ── Alerts tab ──────────────────────────────────────────────────────── */}
      {activeTab === 'alerts' && (
        <div className="bg-card border border-border rounded-lg overflow-hidden">
          <div className="flex items-center justify-between px-4 py-3 border-b border-border">
            <div className="flex items-center gap-2">
              <Bell size={14} className="text-primary" />
              <h2 className="text-sm font-semibold">Active Alerts</h2>
              {criticalAlerts > 0 && (
                <span className="text-[10px] px-1.5 py-0.5 rounded-full bg-red-500/20 text-red-400 font-semibold">{criticalAlerts} critical</span>
              )}
            </div>
            <Link href="/alerts" className="flex items-center gap-1 text-[11px] text-muted-foreground hover:text-foreground transition-colors">
              Full view <ChevronRight size={11} />
            </Link>
          </div>
          <div className="divide-y divide-border">
            {viewableAlerts.map((alert) => (
              <div key={alert.id} className="flex items-start gap-3 px-4 py-3">
                <div className={`flex-shrink-0 mt-0.5 w-5 h-5 rounded-full flex items-center justify-center ${
                  alert.severity === 'critical' ? 'bg-red-500/10' : alert.severity === 'warning' ? 'bg-amber-500/10' : 'bg-blue-500/10'
                }`}>
                  {alert.severity === 'critical' ? <AlertTriangle size={11} className="text-red-400" /> :
                   alert.severity === 'warning' ? <AlertTriangle size={11} className="text-amber-400" /> :
                   <Info size={11} className="text-blue-400" />}
                </div>
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2 mb-0.5">
                    <span className={`text-[10px] px-1.5 py-0.5 rounded-full border font-medium ${severityColors[alert.severity]}`}>
                      {alert.severity}
                    </span>
                  </div>
                  <p className="text-xs font-medium">{alert.title}</p>
                  <p className="text-[10px] text-muted-foreground mt-0.5">{alert.deviceName} · {alert.time}</p>
                </div>
                {/* Viewer cannot acknowledge — show lock indicator */}
                <div className="flex-shrink-0 p-1.5 rounded-md text-muted-foreground/40 cursor-not-allowed" title="Acknowledgment requires operator or admin role">
                  <Lock size={12} />
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* ── Compliance tab ──────────────────────────────────────────────────── */}
      {activeTab === 'compliance' && (
        <div className="bg-card border border-border rounded-lg overflow-hidden">
          <div className="flex items-center justify-between px-4 py-3 border-b border-border">
            <div className="flex items-center gap-2">
              <ShieldCheck size={14} className="text-primary" />
              <h2 className="text-sm font-semibold">Compliance Overview</h2>
            </div>
            <Link href="/compliance" className="flex items-center gap-1 text-[11px] text-muted-foreground hover:text-foreground transition-colors">
              Full report <ChevronRight size={11} />
            </Link>
          </div>
          <div className="divide-y divide-border">
            {complianceItems.map((item) => (
              <div key={item.control} className="flex items-center gap-3 px-4 py-3">
                <div className={`w-2 h-2 rounded-full flex-shrink-0 ${
                  item.status === 'pass' ? 'bg-green-400' : item.status === 'warning' ? 'bg-amber-400' : 'bg-red-400'
                }`} />
                <div className="flex-1 min-w-0">
                  <p className="text-xs font-medium">{item.control}</p>
                  <p className="text-[10px] text-muted-foreground">Last checked: {item.lastChecked}</p>
                </div>
                <div className="flex items-center gap-3 flex-shrink-0">
                  <div className="w-20 h-1.5 bg-muted rounded-full overflow-hidden">
                    <div
                      className={`h-full rounded-full ${
                        item.status === 'pass' ? 'bg-green-400' : item.status === 'warning' ? 'bg-amber-400' : 'bg-red-400'
                      }`}
                      style={{ width: `${item.score}%` }}
                    />
                  </div>
                  <span className={`text-xs font-semibold tabular-nums w-8 text-right ${complianceStatusColors[item.status]}`}>
                    {item.score}%
                  </span>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
