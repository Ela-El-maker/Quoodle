'use client';
import React, { useCallback, useState } from 'react';
import AppLayout from '@/components/AppLayout';
import DashboardKPIGrid from './components/DashboardKPIGrid';
import DashboardActivityFeed from './components/DashboardActivityFeed';
import DashboardCommandVolumeChart from './components/DashboardCommandVolumeChart';
import DashboardFleetStatusChart from './components/DashboardFleetStatusChart';
import DashboardNeedsAttention from './components/DashboardNeedsAttention';
import AuditTrailSection from '@/components/AuditTrailSection';
import LiveAlertFeed from '@/components/LiveAlertFeed';
import { Bell, Shield, RefreshCw, X, Download } from 'lucide-react';
import Link from 'next/link';
import ExportModal from '@/components/ExportModal';
import { useDashboardData } from './hooks/useDashboardData';

export default function DashboardPage() {
  const [newAlertBanner, setNewAlertBanner] = useState(true);
  const [alertPulse, setAlertPulse] = useState(false);
  const [showExport, setShowExport] = useState(false);

  const { data, loading, refreshing, errors, refresh, lastRefreshLabel } = useDashboardData();

  const doRefresh = useCallback(async () => {
    setAlertPulse(true);
    try {
      await refresh();
    } finally {
      setTimeout(() => setAlertPulse(false), 2000);
    }
  }, [refresh]);

  const anyError = errors.devices || errors.alerts || errors.commands ? 'Failed to load data' : null;
  const needsAttentionError = errors.devices || errors.commands ? 'Failed to load data' : null;
  const auditError = errors.alerts || errors.commands ? 'Failed to load data' : null;

  return (
    <AppLayout currentPath="/dashboard">
      <div className="space-y-6 fade-in">
        {newAlertBanner && data.kpi.criticalAlerts > 0 && (
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
                {data.kpi.criticalAlerts} Critical Alert{data.kpi.criticalAlerts !== 1 ? 's' : ''} - Immediate Action Required
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
              <span className="tabular-nums">{data.kpi.criticalAlerts}</span>
              <span className="hidden sm:inline">Critical</span>
            </Link>
            <button
              onClick={() => void doRefresh()}
              className="flex items-center gap-1.5 text-xs text-muted-foreground bg-muted/40 border border-border rounded-md px-3 py-1.5 hover:bg-muted/60 transition-colors"
              title="Click to refresh now"
            >
              <RefreshCw size={12} className={refreshing ? 'animate-spin' : ''} />
              <span className="w-1.5 h-1.5 rounded-full bg-green-400 pulse-dot" />
              {lastRefreshLabel || 'Live'}
            </button>
          </div>
        </div>

        <DashboardKPIGrid
          data={data.kpi}
          loading={loading}
          error={anyError}
        />

        <div className="grid grid-cols-1 lg:grid-cols-3 xl:grid-cols-3 2xl:grid-cols-3 gap-4">
          <div className="lg:col-span-2">
            <DashboardCommandVolumeChart
              data={data.commandVolume}
              loading={loading}
              error={errors.commands}
            />
          </div>
          <div className="lg:col-span-1">
            <DashboardFleetStatusChart
              data={data.fleetStatus}
              loading={loading}
              error={errors.devices}
            />
          </div>
        </div>

        <div className="grid grid-cols-1 lg:grid-cols-3 xl:grid-cols-3 2xl:grid-cols-3 gap-4">
          <div className="lg:col-span-2">
            <DashboardNeedsAttention
              failingCommands={data.failingCommands}
              attentionDevices={data.attentionDevices}
              loading={loading}
              error={needsAttentionError}
            />
          </div>
          <div className="lg:col-span-1">
            <DashboardActivityFeed
              items={data.activityItems}
              loading={loading}
              error={anyError}
            />
          </div>
        </div>

        <AuditTrailSection
          title="Dashboard Audit Trail"
          maxRows={5}
          entries={data.auditEntries}
          loading={loading}
          error={auditError}
        />

        <LiveAlertFeed
          pushInterval={9000}
          maxEvents={12}
          events={data.liveFeedEvents}
          loading={loading}
          error={anyError}
        />
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
