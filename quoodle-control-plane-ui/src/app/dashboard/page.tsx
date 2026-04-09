'use client';
import React, { useState, useEffect, useCallback } from 'react';
import AppLayout from '@/components/AppLayout';
import DashboardKPIGrid, { type DashboardKpiData } from './components/DashboardKPIGrid';
import DashboardActivityFeed, { type DashboardActivityItem } from './components/DashboardActivityFeed';
import DashboardCommandVolumeChart from './components/DashboardCommandVolumeChart';
import DashboardFleetStatusChart from './components/DashboardFleetStatusChart';
import DashboardNeedsAttention from './components/DashboardNeedsAttention';
import AuditTrailSection from '@/components/AuditTrailSection';
import LiveAlertFeed from '@/components/LiveAlertFeed';
import { Bell, Shield, RefreshCw, X, Download } from 'lucide-react';
import Link from 'next/link';
import ExportModal from '@/components/ExportModal';

const AUTO_REFRESH_INTERVAL = 30000;

interface DevicesApiResponse {
  devices?: Array<{
    device_id?: string;
    device_name?: string | null;
    lifecycle_state?: string | null;
    compliance_status?: string | null;
    risk_score?: number | string | null;
    last_seen?: string | null;
    agent_version?: string | null;
  }>;
}

interface AlertsApiResponse {
  alerts?: Array<{
    alert_id?: string;
    severity?: string | null;
    message?: string | null;
    timestamp?: string | null;
    device_id?: string | null;
  }>;
}

interface CommandsApiResponse {
  commands?: Array<{
    command_id?: string;
    method?: string;
    state?: string;
    queued_at?: string | null;
    completed_at?: string | null;
    device_id?: string;
    error_message?: string | null;
  }>;
}

const EMPTY_KPI: DashboardKpiData = {
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

function normalizeStatus(value: string | null | undefined): 'online' | 'offline' | 'quarantined' | 'degraded' {
  const normalized = String(value ?? '').toLowerCase();
  if (normalized === 'active' || normalized === 'online') return 'online';
  if (normalized === 'quarantined') return 'quarantined';
  if (normalized === 'degraded') return 'degraded';
  return 'offline';
}

function normalizeRisk(value: number | string | null | undefined): number {
  const parsed = typeof value === 'number' ? value : Number(value ?? 0);
  if (!Number.isFinite(parsed) || parsed <= 0) return 0;
  if (parsed > 1) return Math.max(0, Math.min(1, parsed / 100));
  return Math.max(0, Math.min(1, parsed));
}

function formatUtcTime(iso: string | null | undefined): string {
  if (!iso) return '--:--:--';
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return '--:--:--';
  return date.toISOString().slice(11, 19);
}

function nowTimeString(): string {
  const now = new Date();
  return `${String(now.getHours()).padStart(2, '0')}:${String(now.getMinutes()).padStart(2, '0')}:${String(now.getSeconds()).padStart(2, '0')}`;
}

export default function DashboardPage() {
  const [lastRefresh, setLastRefresh] = useState('');
  const [refreshing, setRefreshing] = useState(false);
  const [newAlertBanner, setNewAlertBanner] = useState(true);
  const [alertPulse, setAlertPulse] = useState(false);
  const [showExport, setShowExport] = useState(false);
  const [kpiData, setKpiData] = useState<DashboardKpiData>(EMPTY_KPI);
  const [activityItems, setActivityItems] = useState<DashboardActivityItem[]>([]);

  const loadDashboardData = useCallback(async () => {
    const [devicesRes, alertsRes, commandsRes] = await Promise.all([
      fetch('/api/devices?per_page=200', { credentials: 'include', cache: 'no-store' }),
      fetch('/api/alerts?limit=100', { credentials: 'include', cache: 'no-store' }),
      fetch('/api/commands?limit=50', { credentials: 'include', cache: 'no-store' }),
    ]);

    const devicesPayload = devicesRes.ok
      ? ((await devicesRes.json()) as DevicesApiResponse)
      : { devices: [] as DevicesApiResponse['devices'] };
    const alertsPayload = alertsRes.ok
      ? ((await alertsRes.json()) as AlertsApiResponse)
      : { alerts: [] as AlertsApiResponse['alerts'] };
    const commandsPayload = commandsRes.ok
      ? ((await commandsRes.json()) as CommandsApiResponse)
      : { commands: [] as CommandsApiResponse['commands'] };

    const devices = devicesPayload.devices ?? [];
    const alerts = alertsPayload.alerts ?? [];
    const commands = commandsPayload.commands ?? [];

    const totalDevices = devices.length;
    const onlineDevices = devices.filter((device) => normalizeStatus(device.lifecycle_state) === 'online').length;
    const quarantinedDevices = devices.filter((device) => normalizeStatus(device.lifecycle_state) === 'quarantined').length;
    const offlineDevices = Math.max(totalDevices - onlineDevices - quarantinedDevices, 0);
    const fleetOnlineRate = totalDevices > 0 ? Number(((onlineDevices / totalDevices) * 100).toFixed(1)) : 0;

    const riskValues = devices
      .map((device) => normalizeRisk(device.risk_score))
      .filter((value) => Number.isFinite(value));
    const avgRiskScore = riskValues.length > 0
      ? Number((riskValues.reduce((sum, value) => sum + value, 0) / riskValues.length).toFixed(4))
      : 0;

    const activeStates = new Set(['queued', 'dispatched', 'ack_received', 'executing']);
    const failedStates = new Set(['failed', 'expired', 'rejected']);

    const activeCommands = commands.filter((command) => activeStates.has(String(command.state ?? '').toLowerCase())).length;
    const failingCommands = commands.filter((command) => failedStates.has(String(command.state ?? '').toLowerCase())).length;

    const criticalAlerts = alerts.filter((alert) => String(alert.severity ?? '').toLowerCase() === 'critical').length;
    const complianceDrift = devices.filter((device) => {
      const status = String(device.compliance_status ?? '').toLowerCase();
      return status === 'drift' || status === 'non_compliant';
    }).length;

    setKpiData({
      totalDevices,
      onlineDevices,
      offlineDevices,
      quarantinedDevices,
      activeCommands,
      failingCommands,
      criticalAlerts,
      complianceDrift,
      avgRiskScore,
      fleetOnlineRate,
    });

    const commandEvents = commands.map((command) => {
      const ts = command.completed_at ?? command.queued_at;
      const state = String(command.state ?? 'queued').toLowerCase();
      return {
        id: command.command_id ?? crypto.randomUUID(),
        type: 'command' as const,
        title: `${command.command_id ?? 'command'} ${state}`,
        detail: `${command.method ?? 'unknown'} on ${command.device_id ?? 'device'}`,
        sortAt: ts ? Date.parse(ts) : 0,
        time: formatUtcTime(ts),
      };
    });

    const alertEvents = alerts.map((alert) => ({
      id: alert.alert_id ?? crypto.randomUUID(),
      type: 'alert' as const,
      title: `${String(alert.severity ?? 'alert').toUpperCase()} alert`,
      detail: alert.message ?? 'Alert event',
      sortAt: alert.timestamp ? Date.parse(alert.timestamp) : 0,
      time: formatUtcTime(alert.timestamp),
    }));

    const deviceEvents = devices
      .filter((device) => Boolean(device.last_seen))
      .map((device) => ({
        id: `device-${device.device_id}`,
        type: 'device' as const,
        title: `${device.device_name?.trim() || device.device_id || 'Device'} heartbeat`,
        detail: `${normalizeStatus(device.lifecycle_state)} · Agent ${device.agent_version ?? '-'}`,
        sortAt: device.last_seen ? Date.parse(device.last_seen) : 0,
        time: formatUtcTime(device.last_seen),
      }));

    const merged = [...commandEvents, ...alertEvents, ...deviceEvents]
      .filter((event) => Number.isFinite(event.sortAt))
      .sort((a, b) => b.sortAt - a.sortAt)
      .slice(0, 12)
      .map(({ id, type, title, detail, time }) => ({ id, type, title, detail, time }));

    setActivityItems(merged);
  }, []);

  const doRefresh = useCallback(async () => {
    setRefreshing(true);
    setAlertPulse(true);
    try {
      await loadDashboardData();
      setLastRefresh(nowTimeString());
    } finally {
      setRefreshing(false);
      setTimeout(() => setAlertPulse(false), 2000);
    }
  }, [loadDashboardData]);

  useEffect(() => {
    setLastRefresh(nowTimeString());
    void loadDashboardData();
    const timer = setInterval(() => {
      void doRefresh();
    }, AUTO_REFRESH_INTERVAL);
    return () => clearInterval(timer);
  }, [doRefresh, loadDashboardData]);

  return (
    <AppLayout currentPath="/dashboard">
      <div className="space-y-6 fade-in">
        {newAlertBanner && kpiData.criticalAlerts > 0 && (
          <div
            className={`relative flex items-start gap-3 px-4 py-3 bg-red-500/10 border border-red-500/30 rounded-lg overflow-hidden transition-all duration-300 ${
              alertPulse ? 'border-red-500/60 bg-red-500/15' : ''
            }`}
          >
            {alertPulse && (
              <div className="absolute inset-0 bg-gradient-to-r from-transparent via-red-500/10 to-transparent animate-[sweep_0.8s_ease-out]" />
            )}
            <div className={`w-6 h-6 rounded-full bg-red-500/20 flex items-center justify-center flex-shrink-0 mt-0.5 ${alertPulse ? 'pulse-dot' : ''}`}>
              <Shield size={13} className="text-red-400" />
            </div>
            <div className="flex-1 min-w-0">
              <p className="text-sm font-semibold text-red-400">
                {kpiData.criticalAlerts} Critical Alert{kpiData.criticalAlerts !== 1 ? 's' : ''} - Immediate Action Required
              </p>
              <p className="text-xs text-muted-foreground mt-0.5">
                Review the alerts inbox for affected devices.
              </p>
            </div>
            <Link
              href="/alerts"
              className="flex items-center gap-1 text-xs text-red-400 hover:text-red-300 transition-colors flex-shrink-0 mr-4"
            >
              View Alerts
            </Link>
            <button
              onClick={() => setNewAlertBanner(false)}
              className="p-1 rounded text-muted-foreground hover:text-foreground transition-colors flex-shrink-0"
              aria-label="Dismiss banner"
            >
              <X size={13} />
            </button>
          </div>
        )}

        <div className="flex items-center justify-between">
          <div>
            <h1 className="text-2xl font-semibold tracking-tight">Fleet Overview</h1>
            <p className="text-sm text-muted-foreground mt-0.5">
              Real-time posture across all managed Windows devices
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
            <Link
              href="/alerts"
              className={`flex items-center gap-1.5 px-2.5 py-1.5 rounded-md border text-xs font-medium transition-all ${
                alertPulse
                  ? 'bg-red-500/20 border-red-500/40 text-red-400'
                  : 'bg-red-500/10 border-red-500/20 text-red-400 hover:border-red-500/40'
              }`}
            >
              <Bell size={12} className={alertPulse ? 'pulse-dot' : ''} />
              <span className="tabular-nums">{kpiData.criticalAlerts}</span>
              <span className="hidden sm:inline">Critical</span>
            </Link>
            <button
              onClick={() => void doRefresh()}
              className="flex items-center gap-1.5 text-xs text-muted-foreground bg-muted/40 border border-border rounded-md px-3 py-1.5 hover:bg-muted/60 transition-colors"
              title="Click to refresh now"
            >
              <RefreshCw size={12} className={refreshing ? 'animate-spin' : ''} />
              <span className="w-1.5 h-1.5 rounded-full bg-green-400 pulse-dot" />
              {lastRefresh ? `${lastRefresh} UTC` : 'Live'}
            </button>
          </div>
        </div>

        <DashboardKPIGrid data={kpiData} />

        <div className="grid grid-cols-1 lg:grid-cols-3 xl:grid-cols-3 2xl:grid-cols-3 gap-4">
          <div className="lg:col-span-2">
            <DashboardCommandVolumeChart />
          </div>
          <div className="lg:col-span-1">
            <DashboardFleetStatusChart />
          </div>
        </div>

        <div className="grid grid-cols-1 lg:grid-cols-3 xl:grid-cols-3 2xl:grid-cols-3 gap-4">
          <div className="lg:col-span-2">
            <DashboardNeedsAttention />
          </div>
          <div className="lg:col-span-1">
            <DashboardActivityFeed items={activityItems} />
          </div>
        </div>

        <AuditTrailSection title="Dashboard Audit Trail" maxRows={5} />

        <LiveAlertFeed pushInterval={9000} maxEvents={12} />
      </div>

      {showExport && (
        <ExportModal
          title="Dashboard"
          fields={[
            { key: 'fleet_online_rate', label: 'Fleet Online Rate' },
            { key: 'total_devices', label: 'Total Devices' },
            { key: 'online_devices', label: 'Online Devices' },
            { key: 'offline_devices', label: 'Offline Devices' },
            { key: 'quarantined_devices', label: 'Quarantined' },
            { key: 'active_commands', label: 'Active Commands' },
            { key: 'failing_commands', label: 'Failing Commands' },
            { key: 'critical_alerts', label: 'Critical Alerts' },
            { key: 'compliance_drift', label: 'Compliance Drift' },
            { key: 'avg_risk_score', label: 'Avg Risk Score' },
            { key: 'timestamp', label: 'Timestamp' },
          ]}
          onClose={() => setShowExport(false)}
        />
      )}
    </AppLayout>
  );
}
