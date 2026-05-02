'use client';
import React from 'react';
import Link from 'next/link';
import {
  Monitor,
  Terminal,
  Bell,
  ShieldCheck,
  TrendingUp,
  AlertTriangle,
  Wifi,
  ArrowUpRight,
} from 'lucide-react';

export interface DashboardKpiData {
  totalDevices: number;
  onlineDevices: number;
  offlineDevices: number;
  quarantinedDevices: number;
  activeCommands: number;
  failingCommands: number;
  criticalAlerts: number;
  complianceDrift: number;
  avgRiskScore: number;
  fleetOnlineRate: number;
}

const DEFAULT_KPI_DATA: DashboardKpiData = {
  totalDevices: 0,
  onlineDevices: 0,
  offlineDevices: 0,
  quarantinedDevices: 0,
  activeCommands: 0,
  failingCommands: 0,
  criticalAlerts: 0,
  complianceDrift: 0,
  avgRiskScore: 0,
  fleetOnlineRate: 0,
};

interface DashboardKPIGridProps {
  data?: DashboardKpiData;
  loading?: boolean;
  error?: string | null;
}

export default function DashboardKPIGrid({ data, loading, error }: DashboardKPIGridProps) {
  const kpiData = data ?? DEFAULT_KPI_DATA;

  return (
    <div>
      {loading && <p className="text-[11px] text-muted-foreground mb-2">Loading data...</p>}
      {!loading && error && <p className="text-[11px] text-red-400 mb-2">{error}</p>}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 xl:grid-cols-4 2xl:grid-cols-4 gap-4">
        <Link
          href="/device-management"
          className="sm:col-span-2 lg:col-span-2 xl:col-span-2 2xl:col-span-2 group relative bg-card border border-border rounded-lg p-5 hover:border-primary/40 transition-all duration-200 overflow-hidden"
        >
          <div className="absolute inset-0 bg-gradient-to-br from-primary/5 to-transparent pointer-events-none" />
          <div className="flex items-start justify-between mb-3">
            <div className="flex items-center gap-2">
              <div className="w-8 h-8 rounded-lg bg-primary/10 flex items-center justify-center">
                <Wifi size={16} className="text-primary" />
              </div>
              <span className="text-xs font-medium text-muted-foreground tracking-wide uppercase">Fleet Online Rate</span>
            </div>
            <ArrowUpRight size={14} className="text-muted-foreground group-hover:text-primary transition-colors" />
          </div>
          <div className="flex items-end gap-4">
            <div>
              <p className="text-4xl font-bold tabular-nums text-foreground">{kpiData.fleetOnlineRate}%</p>
              <p className="text-sm text-muted-foreground mt-1">
                <span className="text-green-400 font-semibold">{kpiData.onlineDevices} online</span>
                {' - '}
                <span className="text-muted-foreground">{kpiData.offlineDevices} offline</span>
                {' - '}
                <span className="text-red-400">{kpiData.quarantinedDevices} quarantined</span>
              </p>
            </div>
            <div className="flex-1 min-w-0">
              <div className="h-2 bg-muted rounded-full overflow-hidden">
                <div
                  className="h-full bg-green-500 rounded-full transition-all duration-500"
                  style={{ width: `${kpiData.fleetOnlineRate}%` }}
                />
              </div>
              <p className="text-[11px] text-muted-foreground mt-1">{kpiData.totalDevices} total devices</p>
            </div>
          </div>
        </Link>

        <Link
          href="/command-dispatch"
          className="group bg-card border border-border rounded-lg p-5 hover:border-blue-500/40 transition-all duration-200"
        >
          <div className="flex items-start justify-between mb-3">
            <div className="w-8 h-8 rounded-lg bg-blue-500/10 flex items-center justify-center">
              <Terminal size={16} className="text-blue-400" />
            </div>
            <ArrowUpRight size={14} className="text-muted-foreground group-hover:text-blue-400 transition-colors" />
          </div>
          <p className="text-3xl font-bold tabular-nums">{kpiData.activeCommands}</p>
          <p className="text-xs font-medium text-muted-foreground mt-1 tracking-wide uppercase">Active Commands</p>
          {kpiData.failingCommands > 0 && (
            <p className="text-[11px] text-red-400 mt-2 flex items-center gap-1">
              <AlertTriangle size={10} />
              {kpiData.failingCommands} failing
            </p>
          )}
        </Link>

        <Link
          href="/alerts"
          className="group bg-red-500/5 border border-red-500/20 rounded-lg p-5 hover:border-red-500/40 transition-all duration-200"
        >
          <div className="flex items-start justify-between mb-3">
            <div className="w-8 h-8 rounded-lg bg-red-500/10 flex items-center justify-center">
              <Bell size={16} className="text-red-400" />
            </div>
            <span className="w-2 h-2 rounded-full bg-red-500 pulse-dot" />
          </div>
          <p className="text-3xl font-bold tabular-nums text-red-400">{kpiData.criticalAlerts}</p>
          <p className="text-xs font-medium text-red-400/70 mt-1 tracking-wide uppercase">Critical Alerts</p>
          <p className="text-[11px] text-muted-foreground mt-2">Requires immediate action</p>
        </Link>

        <Link
          href="/device-management"
          className="group bg-card border border-border rounded-lg p-5 hover:border-primary/40 transition-all duration-200"
        >
          <div className="flex items-start justify-between mb-3">
            <div className="w-8 h-8 rounded-lg bg-muted flex items-center justify-center">
              <Monitor size={16} className="text-muted-foreground" />
            </div>
            <ArrowUpRight size={14} className="text-muted-foreground group-hover:text-primary transition-colors" />
          </div>
          <p className="text-3xl font-bold tabular-nums">{kpiData.totalDevices}</p>
          <p className="text-xs font-medium text-muted-foreground mt-1 tracking-wide uppercase">Total Devices</p>
          <p className="text-[11px] text-muted-foreground mt-2">Live fleet count</p>
        </Link>

        <Link
          href="/compliance"
          className="group bg-amber-500/5 border border-amber-500/20 rounded-lg p-5 hover:border-amber-500/40 transition-all duration-200"
        >
          <div className="flex items-start justify-between mb-3">
            <div className="w-8 h-8 rounded-lg bg-amber-500/10 flex items-center justify-center">
              <ShieldCheck size={16} className="text-amber-400" />
            </div>
            <AlertTriangle size={13} className="text-amber-400" />
          </div>
          <p className="text-3xl font-bold tabular-nums text-amber-400">{kpiData.complianceDrift}</p>
          <p className="text-xs font-medium text-amber-400/70 mt-1 tracking-wide uppercase">Compliance Drift</p>
          <p className="text-[11px] text-muted-foreground mt-2">Policy hash mismatch</p>
        </Link>

        <div className="group bg-card border border-border rounded-lg p-5">
          <div className="flex items-start justify-between mb-3">
            <div className="w-8 h-8 rounded-lg bg-muted flex items-center justify-center">
              <TrendingUp size={16} className="text-muted-foreground" />
            </div>
          </div>
          <p className="text-3xl font-bold tabular-nums">
            <span className={kpiData.avgRiskScore > 0.5 ? 'text-red-400' : kpiData.avgRiskScore > 0.25 ? 'text-amber-400' : 'text-green-400'}>
              {(kpiData.avgRiskScore * 100).toFixed(1)}
            </span>
            <span className="text-lg text-muted-foreground font-normal"> / 100</span>
          </p>
          <p className="text-xs font-medium text-muted-foreground mt-1 tracking-wide uppercase">Avg Risk Score</p>
          <p className="text-[11px] text-muted-foreground mt-2">Live fleet average</p>
        </div>
      </div>
    </div>
  );
}

