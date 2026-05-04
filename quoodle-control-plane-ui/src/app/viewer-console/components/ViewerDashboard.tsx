'use client';

import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { Monitor, ShieldCheck, ChevronRight, Search, CheckCircle2, Info, Lock, Link2 } from 'lucide-react';
import StatusBadge from '@/components/ui/StatusBadge';
import DevicePairingModal from '@/components/DevicePairingModal';
import { useAuth } from '@/contexts/AuthContext';
import { roleHomePath } from '@/lib/auth';
import { formatNowLocalTime } from '@/lib/dateTime';
import Link from 'next/link';

type DeviceStatus = 'online' | 'offline' | 'quarantined' | 'degraded';
type ComplianceStatus = 'compliant' | 'non_compliant' | 'drift';
type ComplianceSignal = 'pass' | 'fail' | 'warning';

interface DeviceApiRow {
  device_id?: string;
  owner_email?: string | null;
  device_name?: string | null;
  lifecycle_state?: string | null;
  compliance_status?: string | null;
  resolved_compliance_status?: string | null;
  resolved_presence_state?: string | null;
  risk_score?: number | string | null;
  last_seen?: string | null;
  os_build?: string | null;
  resolved_os_build?: string | null;
}

interface DevicesApiResponse {
  devices?: DeviceApiRow[];
}

interface Device {
  id: string;
  hostname: string;
  status: DeviceStatus;
  riskScore: number;
  compliance: ComplianceStatus;
  lastSeenIso: string | null;
  os: string;
  owner: string;
}

interface ComplianceItem {
  control: string;
  status: ComplianceSignal;
  score: number;
  lastChecked: string;
}

const complianceStatusColors: Record<ComplianceSignal, string> = {
  pass: 'text-green-400',
  warning: 'text-amber-400',
  fail: 'text-red-400',
};

function normalizeStatus(value: string | null | undefined): DeviceStatus {
  const normalized = String(value ?? '').toLowerCase();
  if (normalized === 'online' || normalized === 'active') return 'online';
  if (normalized === 'quarantined') return 'quarantined';
  if (normalized === 'degraded' || normalized === 'stale') return 'degraded';
  return 'offline';
}

function normalizeCompliance(value: string | null | undefined): ComplianceStatus {
  const normalized = String(value ?? '').toLowerCase();
  if (normalized === 'compliant') return 'compliant';
  if (normalized === 'drift' || normalized === 'non_compliant') return 'drift';
  return 'non_compliant';
}

function normalizeRisk(value: number | string | null | undefined): number {
  const parsed = typeof value === 'number' ? value : Number(value ?? 0);
  if (!Number.isFinite(parsed) || parsed <= 0) return 0;
  if (parsed > 1) return Math.max(0, Math.min(1, parsed / 100));
  return Math.max(0, Math.min(1, parsed));
}

function toRelativeTime(iso: string | null | undefined): string {
  if (!iso) return 'Never';
  const ts = Date.parse(iso);
  if (!Number.isFinite(ts)) return '-';
  const diffSeconds = Math.max(0, Math.floor((Date.now() - ts) / 1000));
  if (diffSeconds < 60) return `${diffSeconds}s ago`;
  const diffMinutes = Math.floor(diffSeconds / 60);
  if (diffMinutes < 60) return `${diffMinutes}m ago`;
  const diffHours = Math.floor(diffMinutes / 60);
  if (diffHours < 24) return `${diffHours}h ago`;
  const diffDays = Math.floor(diffHours / 24);
  return `${diffDays}d ago`;
}

function scoreToSignal(score: number): ComplianceSignal {
  if (score >= 90) return 'pass';
  if (score >= 70) return 'warning';
  return 'fail';
}

function percent(part: number, whole: number): number {
  if (whole <= 0) return 0;
  return Math.round((part / whole) * 100);
}

export default function ViewerDashboard() {
  const { refreshUser } = useAuth();
  const [search, setSearch] = useState('');
  const [devices, setDevices] = useState<Device[]>([]);
  const [activeTab, setActiveTab] = useState<'devices' | 'compliance'>('devices');
  const [loading, setLoading] = useState(true);
  const [showPairModal, setShowPairModal] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const loadDevices = useCallback(async () => {
    setLoading(true);
    try {
      const response = await fetch('/api/devices?per_page=200', {
        credentials: 'include',
        cache: 'no-store',
      });
      if (!response.ok) {
        throw new Error(`devices_fetch_failed_${response.status}`);
      }
      const payload = (await response.json()) as DevicesApiResponse;
      const mapped = (payload.devices ?? [])
        .map((row): Device | null => {
          const id = String(row.device_id ?? '').trim();
          if (!id) return null;
          return {
            id,
            hostname: row.device_name?.trim() || id,
            status: normalizeStatus(row.resolved_presence_state ?? row.lifecycle_state),
            riskScore: normalizeRisk(row.risk_score),
            compliance: normalizeCompliance(row.resolved_compliance_status ?? row.compliance_status),
            lastSeenIso: row.last_seen ?? null,
            os: row.resolved_os_build?.trim() || row.os_build?.trim() || 'Unknown',
            owner: row.owner_email?.trim() || 'Unknown',
          };
        })
        .filter((row): row is Device => row !== null);
      setDevices(mapped);
      setError(null);
    } catch (loadError) {
      console.error('viewer-dashboard-devices-load-failed', loadError);
      setDevices([]);
      setError('Failed to load data');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void loadDevices();
  }, [loadDevices]);

  const filteredDevices = useMemo(
    () =>
      devices.filter((d) =>
        !search ||
        d.hostname.toLowerCase().includes(search.toLowerCase()) ||
        d.id.toLowerCase().includes(search.toLowerCase()) ||
        d.owner.toLowerCase().includes(search.toLowerCase()),
      ),
    [devices, search],
  );

  const onlineCount = devices.filter((d) => d.status === 'online').length;
  const compliantCount = devices.filter((d) => d.compliance === 'compliant').length;
  const driftCount = devices.filter((d) => d.compliance !== 'compliant').length;
  const highRiskCount = devices.filter((d) => d.riskScore >= 0.6).length;
  const checkedInRecentlyCount = devices.filter((d) => {
    if (!d.lastSeenIso) return false;
    const ts = Date.parse(d.lastSeenIso);
    if (!Number.isFinite(ts)) return false;
    return Date.now() - ts <= 30 * 60 * 1000;
  }).length;
  const complianceRate = percent(compliantCount, devices.length);

  const complianceItems = useMemo<ComplianceItem[]>(() => {
    const lastChecked = formatNowLocalTime();
    const driftExposureScore = 100 - percent(driftCount, devices.length);
    const highRiskExposureScore = 100 - percent(highRiskCount, devices.length);
    const onlineCoverageScore = percent(onlineCount, devices.length);
    const checkinCoverageScore = percent(checkedInRecentlyCount, devices.length);

    return [
      {
        control: 'Device Compliance Rate',
        score: complianceRate,
        status: scoreToSignal(complianceRate),
        lastChecked,
      },
      {
        control: 'Policy Drift Exposure',
        score: driftExposureScore,
        status: scoreToSignal(driftExposureScore),
        lastChecked,
      },
      {
        control: 'High Risk Device Exposure',
        score: highRiskExposureScore,
        status: scoreToSignal(highRiskExposureScore),
        lastChecked,
      },
      {
        control: 'Fleet Online Coverage',
        score: onlineCoverageScore,
        status: scoreToSignal(onlineCoverageScore),
        lastChecked,
      },
      {
        control: 'Recent Check-in Coverage',
        score: checkinCoverageScore,
        status: scoreToSignal(checkinCoverageScore),
        lastChecked,
      },
    ];
  }, [checkedInRecentlyCount, complianceRate, devices.length, driftCount, highRiskCount, onlineCount]);

  const riskColor = (score: number) =>
    score > 0.6 ? 'text-red-400' : score > 0.3 ? 'text-amber-400' : 'text-green-400';

  return (
    <div className="space-y-6 fade-in">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">Viewer Console</h1>
          <p className="text-sm text-muted-foreground mt-0.5">Read-only fleet overview · Pair to unlock operator actions</p>
        </div>
        <div className="flex items-center gap-2">
          <button
            onClick={() => setShowPairModal(true)}
            className="flex items-center gap-1.5 px-3 py-1.5 text-xs border border-border rounded-md text-muted-foreground hover:text-foreground hover:bg-muted/60 transition-colors"
          >
            <Link2 size={13} />
            Pair Device
          </button>
          <div className="flex items-center gap-1.5 px-3 py-1.5 bg-muted/30 border border-border rounded-md text-[11px] text-muted-foreground">
            <Lock size={11} />
            Read-only access
          </div>
        </div>
      </div>

      <div className="grid grid-cols-2 lg:grid-cols-4 gap-3">
        {[
          { label: 'Total Devices', value: devices.length, icon: Monitor, color: 'text-primary' },
          { label: 'Online', value: onlineCount, icon: CheckCircle2, color: 'text-green-400' },
          { label: 'Compliant', value: `${compliantCount}/${devices.length}`, icon: ShieldCheck, color: 'text-green-400' },
          { label: 'Policy Drift', value: driftCount, icon: ShieldCheck, color: driftCount > 0 ? 'text-amber-400' : 'text-muted-foreground' },
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

      <div className="bg-blue-500/5 border border-blue-500/20 rounded-lg px-4 py-3 flex items-center gap-2.5">
        <Info size={14} className="text-blue-400 flex-shrink-0" />
        <p className="text-[11px] text-blue-400">
          You have <strong>viewer access</strong>. You can monitor devices and compliance, and pair a device to be promoted to
          operator.
        </p>
      </div>

      <div className="flex items-center gap-1 bg-muted/20 rounded-lg p-1 w-fit">
        {[
          { id: 'devices', label: 'Devices', icon: Monitor },
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

      {error && (
        <div className="bg-red-500/10 border border-red-500/20 rounded-lg px-4 py-3 text-xs text-red-400">
          {error}
        </div>
      )}

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
                placeholder="Search devices..."
                className="pl-7 pr-3 py-1.5 text-xs bg-muted/60 border border-border rounded-md text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-1 focus:ring-primary/50 w-48"
              />
            </div>
          </div>
          {loading ? (
            <div className="px-4 py-6 text-xs text-muted-foreground">Loading devices...</div>
          ) : filteredDevices.length === 0 ? (
            <div className="px-4 py-6 text-xs text-muted-foreground">No devices available</div>
          ) : (
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
                      <td className="px-4 py-3 text-muted-foreground tabular-nums">{toRelativeTime(device.lastSeenIso)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>
      )}

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

      {showPairModal && (
        <DevicePairingModal
          onClose={() => setShowPairModal(false)}
          onPaired={async () => {
            const refreshedUser = await refreshUser();
            const nextRole = refreshedUser?.role;
            if (nextRole) {
              window.location.href = roleHomePath(nextRole);
              return;
            }
            setShowPairModal(false);
            await loadDevices();
          }}
        />
      )}
    </div>
  );
}


