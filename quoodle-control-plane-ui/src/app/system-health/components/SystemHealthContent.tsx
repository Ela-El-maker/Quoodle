'use client';
import React, { useState, useEffect } from 'react';
import { HeartPulse, Server, Database, Shield, Activity, Wifi, CheckCircle2, XCircle, AlertTriangle, RefreshCw, Clock } from 'lucide-react';
import StatusBadge from '@/components/ui/StatusBadge';
import AuditTrailSection from '@/components/AuditTrailSection';
import Icon from '@/components/ui/AppIcon';


interface ServiceHealth {
  id: string;
  name: string;
  category: string;
  status: 'healthy' | 'degraded' | 'offline';
  latencyMs: number;
  uptime: string;
  lastCheck: string;
  description: string;
  icon: React.ElementType;
}

const services: ServiceHealth[] = [
  { id: 'svc-001', name: 'Command Controller', category: 'Core', status: 'healthy',  latencyMs: 12,  uptime: '99.98%', lastCheck: '21:06:08', description: 'Ed25519 command signing and dispatch engine', icon: Shield },
  { id: 'svc-002', name: 'Agent Gateway',      category: 'Core', status: 'healthy',  latencyMs: 8,   uptime: '99.95%', lastCheck: '21:06:07', description: 'Named pipe and kernel transport broker', icon: Wifi },
  { id: 'svc-003', name: 'Policy Engine',      category: 'Core', status: 'degraded', latencyMs: 340, uptime: '98.12%', lastCheck: '21:06:06', description: 'Policy hash validation and sync service', icon: Shield },
  { id: 'svc-004', name: 'Telemetry Ingestor', category: 'Monitoring', status: 'healthy',  latencyMs: 22,  uptime: '99.90%', lastCheck: '21:06:05', description: 'Kernel event stream and metric aggregation', icon: Activity },
  { id: 'svc-005', name: 'Attestation Service',category: 'Security', status: 'degraded', latencyMs: 520, uptime: '96.40%', lastCheck: '21:06:04', description: 'TPM attestation verification and PCR validation', icon: Shield },
  { id: 'svc-006', name: 'Alert Processor',    category: 'Monitoring', status: 'healthy',  latencyMs: 15,  uptime: '99.99%', lastCheck: '21:06:03', description: 'Real-time alert correlation and routing', icon: Activity },
  { id: 'svc-007', name: 'Primary Database',   category: 'Infrastructure', status: 'healthy',  latencyMs: 4,   uptime: '99.99%', lastCheck: '21:06:02', description: 'PostgreSQL primary — command and event store', icon: Database },
  { id: 'svc-008', name: 'Redis Cache',         category: 'Infrastructure', status: 'healthy',  latencyMs: 1,   uptime: '100%',   lastCheck: '21:06:01', description: 'Session tokens and rate-limit counters', icon: Database },
  { id: 'svc-009', name: 'Audit Log Store',     category: 'Infrastructure', status: 'healthy',  latencyMs: 6,   uptime: '99.99%', lastCheck: '21:06:00', description: 'Immutable append-only audit event store', icon: Server },
  { id: 'svc-010', name: 'Auth Service',        category: 'Security', status: 'healthy',  latencyMs: 18,  uptime: '99.97%', lastCheck: '21:05:59', description: 'JWT issuance, MFA verification, RBAC enforcement', icon: Shield },
];

const infraMetrics = [
  { label: 'API Requests / min', value: '2,847', trend: '+12%', trendUp: true },
  { label: 'Avg Response Time', value: '94ms', trend: '-8ms', trendUp: true },
  { label: 'Active Connections', value: '312', trend: '+24', trendUp: false },
  { label: 'Queue Depth', value: '7', trend: '-3', trendUp: true },
  { label: 'Error Rate', value: '0.04%', trend: '-0.01%', trendUp: true },
  { label: 'Cache Hit Rate', value: '97.2%', trend: '+0.3%', trendUp: true },
];

const statusIcon = {
  healthy:  <CheckCircle2 size={14} className="text-green-400" />,
  degraded: <AlertTriangle size={14} className="text-amber-400" />,
  offline:  <XCircle size={14} className="text-red-400" />,
};

const latencyColor = (ms: number) =>
  ms < 50 ? 'text-green-400' : ms < 200 ? 'text-amber-400' : 'text-red-400';

export default function SystemHealthContent() {
  const [lastRefresh, setLastRefresh] = useState('21:06:09');
  const [refreshing, setRefreshing] = useState(false);

  const handleRefresh = () => {
    setRefreshing(true);
    setTimeout(() => {
      setRefreshing(false);
      const now = new Date();
      setLastRefresh(`${String(now.getHours()).padStart(2,'0')}:${String(now.getMinutes()).padStart(2,'0')}:${String(now.getSeconds()).padStart(2,'0')}`);
    }, 800);
  };

  const summary = {
    healthy:  services.filter((s) => s.status === 'healthy').length,
    degraded: services.filter((s) => s.status === 'degraded').length,
    offline:  services.filter((s) => s.status === 'offline').length,
  };

  const overallStatus = summary.offline > 0 ? 'offline' : summary.degraded > 0 ? 'degraded' : 'healthy';
  const overallColor = overallStatus === 'healthy' ? 'text-green-400' : overallStatus === 'degraded' ? 'text-amber-400' : 'text-red-400';
  const overallBg = overallStatus === 'healthy' ? 'bg-green-500/10 border-green-500/20' : overallStatus === 'degraded' ? 'bg-amber-500/10 border-amber-500/20' : 'bg-red-500/10 border-red-500/20';

  const categories = [...new Set(services.map((s) => s.category))];

  return (
    <div className="space-y-6 fade-in">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">System Health</h1>
          <p className="text-sm text-muted-foreground mt-0.5">Infrastructure services, latency, and operational metrics</p>
        </div>
        <button
          onClick={handleRefresh}
          className="flex items-center gap-1.5 px-3 py-1.5 text-xs text-muted-foreground border border-border rounded-md hover:bg-muted/60 transition-colors"
        >
          <RefreshCw size={13} className={refreshing ? 'animate-spin' : ''} />
          Refresh
        </button>
      </div>

      {/* Overall status banner */}
      <div className={`flex items-center gap-4 px-4 py-3 border rounded-lg ${overallBg}`}>
        <HeartPulse size={20} className={overallColor} />
        <div className="flex-1">
          <p className={`text-sm font-semibold ${overallColor}`}>
            System {overallStatus === 'healthy' ? 'Operational' : overallStatus === 'degraded' ? 'Degraded — Some Services Impacted' : 'Outage Detected'}
          </p>
          <p className="text-xs text-muted-foreground mt-0.5">
            {summary.healthy} healthy · {summary.degraded} degraded · {summary.offline} offline
          </p>
        </div>
        <div className="flex items-center gap-1.5 text-[11px] text-muted-foreground">
          <Clock size={11} />
          Last checked {lastRefresh} UTC
        </div>
      </div>

      {/* Summary cards */}
      <div className="grid grid-cols-2 sm:grid-cols-3 gap-4">
        <div className="bg-green-500/5 border border-green-500/20 rounded-lg p-4 text-center">
          <p className="text-3xl font-bold tabular-nums text-green-400">{summary.healthy}</p>
          <p className="text-xs text-green-400/70 mt-1 uppercase tracking-wide font-medium">Healthy</p>
        </div>
        <div className="bg-amber-500/5 border border-amber-500/20 rounded-lg p-4 text-center">
          <p className="text-3xl font-bold tabular-nums text-amber-400">{summary.degraded}</p>
          <p className="text-xs text-amber-400/70 mt-1 uppercase tracking-wide font-medium">Degraded</p>
        </div>
        <div className="bg-card border border-border rounded-lg p-4 text-center">
          <p className="text-3xl font-bold tabular-nums text-zinc-400">{summary.offline}</p>
          <p className="text-xs text-muted-foreground mt-1 uppercase tracking-wide font-medium">Offline</p>
        </div>
      </div>

      {/* Infrastructure metrics */}
      <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-3">
        {infraMetrics.map((m) => (
          <div key={m.label} className="bg-card border border-border rounded-lg p-3">
            <p className="text-lg font-bold tabular-nums">{m.value}</p>
            <p className="text-[10px] text-muted-foreground mt-0.5 leading-tight">{m.label}</p>
            <p className={`text-[10px] mt-1 font-medium ${m.trendUp ? 'text-green-400' : 'text-amber-400'}`}>{m.trend}</p>
          </div>
        ))}
      </div>

      {/* Services by category */}
      {categories.map((cat) => (
        <div key={cat}>
          <h3 className="text-xs font-semibold text-muted-foreground uppercase tracking-widest mb-2">{cat}</h3>
          <div className="space-y-2">
            {services.filter((s) => s.category === cat).map((svc) => {
              const Icon = svc.icon;
              return (
                <div
                  key={svc.id}
                  className="bg-card border border-border rounded-lg px-4 py-3 flex items-center gap-4 hover:bg-muted/10 transition-colors"
                >
                  <div className="w-8 h-8 rounded-lg bg-muted flex items-center justify-center flex-shrink-0">
                    <Icon size={14} className="text-muted-foreground" />
                  </div>
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-medium">{svc.name}</p>
                    <p className="text-[11px] text-muted-foreground truncate">{svc.description}</p>
                  </div>
                  <div className="flex items-center gap-6 flex-shrink-0">
                    <div className="text-right hidden sm:block">
                      <p className={`text-xs font-semibold tabular-nums ${latencyColor(svc.latencyMs)}`}>{svc.latencyMs}ms</p>
                      <p className="text-[10px] text-muted-foreground">latency</p>
                    </div>
                    <div className="text-right hidden md:block">
                      <p className="text-xs font-semibold text-green-400">{svc.uptime}</p>
                      <p className="text-[10px] text-muted-foreground">uptime</p>
                    </div>
                    <div className="text-right hidden lg:block">
                      <p className="font-mono text-[11px] text-muted-foreground">{svc.lastCheck}</p>
                      <p className="text-[10px] text-muted-foreground">last check</p>
                    </div>
                    <div className="flex items-center gap-2">
                      {statusIcon[svc.status]}
                      <StatusBadge variant={svc.status} />
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      ))}

      {/* Audit trail */}
      <AuditTrailSection title="System Health Audit Trail" maxRows={4} />
    </div>
  );
}
