'use client';

import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Activity, RefreshCw, Monitor, ChevronDown, ChevronUp } from 'lucide-react';
import { useSearchParams } from 'next/navigation';
import TelemetryCpuChart from './TelemetryCpuChart';
import TelemetryRamChart from './TelemetryRamChart';
import TelemetryDiskChart from './TelemetryDiskChart';
import TelemetryNetworkChart from './TelemetryNetworkChart';
import TelemetryRiskChart from './TelemetryRiskChart';
import { toast } from 'sonner';
import {
  telemetryBooleanStatus,
  telemetryMaskedFields,
  telemetryNumber,
  parseKernelTelemetryEvent,
  telemetryPercent,
  type ParsedKernelTelemetryEvent,
  telemetryRisk,
  telemetryText,
} from '@/lib/telemetry';

type DeviceOption = { id: string; label: string };

type TelemetryLatestResponse = {
  device_id: string;
  timestamp: string | null;
  schema_version?: string | null;
  session_id?: string | null;
  seq?: number | string | null;
  telemetry_scope?: string | null;
  policy_hash?: string | null;
  masked_fields?: unknown[];
  presence_state?: string | null;
  connection_mode?: string | null;
  resolved_os_build?: string | null;
  resolved_presence_state?: string | null;
  resolved_connection_mode?: string | null;
  resolved_compliance_status?: string | null;
  resolved_policy_in_sync?: boolean | null;
  metrics?: Record<string, unknown>;
};

type TelemetryHistoryPoint = {
  timestamp: string;
  avg_cpu?: number;
  avg_ram?: number;
  avg_disk_usage?: number;
  network_tx?: number;
  network_rx?: number;
  risk_score_avg?: number;
  risk_score?: number;
  metrics?: Record<string, unknown>;
};

type TelemetryHistoryResponse = {
  points?: TelemetryHistoryPoint[];
};

type TelemetryActivityResponse = {
  events?: Array<{
    id: string;
    event_type: string;
    timestamp?: string;
    detail?: Record<string, unknown>;
  }>;
};

type ChartPoint = { time: string; value: number };
type NetworkPoint = { time: string; tx: number; rx: number };
type RiskPoint = { time: string; score: number; event: string | null };

const timeWindows = [
  { key: '1h', label: '1h', hours: 1 },
  { key: '6h', label: '6h', hours: 6 },
  { key: '24h', label: '24h', hours: 24 },
  { key: '7d', label: '7d', hours: 24 * 7 },
];

function toTimeLabel(timestamp: string): string {
  const date = new Date(timestamp);
  return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
}

function toIsoHoursAgo(hours: number): string {
  return new Date(Date.now() - hours * 60 * 60 * 1000).toISOString();
}

export default function TelemetryContent() {
  const searchParams = useSearchParams();
  const initialDevice = searchParams?.get('device') ?? '';

  const [devices, setDevices] = useState<DeviceOption[]>([]);
  const [selectedDevice, setSelectedDevice] = useState(initialDevice);
  const [timeWindow, setTimeWindow] = useState('24h');
  const [latest, setLatest] = useState<TelemetryLatestResponse | null>(null);
  const [history, setHistory] = useState<TelemetryHistoryPoint[]>([]);
  const [activity, setActivity] = useState<TelemetryActivityResponse['events']>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [activityError, setActivityError] = useState<string | null>(null);
  const [lastUpdated, setLastUpdated] = useState<string | null>(null);
  const [kernelCategoryFilter, setKernelCategoryFilter] = useState<'all' | ParsedKernelTelemetryEvent['category']>('all');
  const [advancedOpen, setAdvancedOpen] = useState(false);
  const pollRef = useRef<ReturnType<typeof setInterval> | null>(null);

  const loadDevices = useCallback(async (): Promise<DeviceOption[]> => {
    const response = await fetch('/api/devices?per_page=200', { credentials: 'include', cache: 'no-store' });
    if (!response.ok) throw new Error('Failed to load device list');
    const payload = (await response.json()) as { devices?: Array<{ device_id: string; device_name?: string }> };
    return (payload.devices ?? []).map((device) => ({
      id: String(device.device_id),
      label: String(device.device_name ?? device.device_id),
    }));
  }, []);

  const loadTelemetryBundle = useCallback(
    async (mode: 'initial' | 'refresh' | 'silent' = 'initial') => {
      if (mode === 'initial') setLoading(true);
      if (mode === 'refresh') setRefreshing(true);
      if (mode !== 'silent') setError(null);
      if (mode !== 'silent') setActivityError(null);

      try {
        const nextDevices = await loadDevices();
        setDevices(nextDevices);
        const effectiveDevice =
          selectedDevice && nextDevices.some((device) => device.id === selectedDevice)
            ? selectedDevice
            : nextDevices[0]?.id ?? '';

        setSelectedDevice(effectiveDevice);
        if (!effectiveDevice) {
          setLatest(null);
          setHistory([]);
          setActivity([]);
          setActivityError(null);
          setLastUpdated(new Date().toISOString());
          return;
        }

        const selectedWindow = timeWindows.find((window) => window.key === timeWindow) ?? timeWindows[2];
        const from = toIsoHoursAgo(selectedWindow.hours);
        const [latestResult, historyResult, activityResult] = await Promise.allSettled([
          fetch(`/api/telemetry/devices/${encodeURIComponent(effectiveDevice)}/latest`, { credentials: 'include', cache: 'no-store' }),
          fetch(
            `/api/telemetry/devices/${encodeURIComponent(effectiveDevice)}/history?from=${encodeURIComponent(from)}&to=${encodeURIComponent(new Date().toISOString())}&bucket=raw`,
            { credentials: 'include', cache: 'no-store' },
          ),
          fetch(`/api/telemetry/activity?device_id=${encodeURIComponent(effectiveDevice)}&limit=100`, { credentials: 'include', cache: 'no-store' }),
        ]);

        if (latestResult.status !== 'fulfilled' || historyResult.status !== 'fulfilled') {
          throw new Error('Failed to load telemetry');
        }
        const latestRes = latestResult.value;
        const historyRes = historyResult.value;

        if (!latestRes.ok || !historyRes.ok) {
          throw new Error('Failed to load telemetry');
        }

        const latestPayload = (await latestRes.json()) as TelemetryLatestResponse;
        const historyPayload = (await historyRes.json()) as TelemetryHistoryResponse;

        setLatest(latestPayload);
        setHistory(historyPayload.points ?? []);

        if (activityResult.status === 'fulfilled' && activityResult.value.ok) {
          const activityPayload = (await activityResult.value.json()) as TelemetryActivityResponse;
          setActivity(activityPayload.events ?? []);
          setActivityError(null);
        } else {
          setActivity([]);
          setActivityError('Activity feed is temporarily unavailable.');
        }

        setLastUpdated(new Date().toISOString());
      } catch (fetchError) {
        console.error('Telemetry load failed', fetchError);
        setError('Failed to load telemetry snapshot.');
      } finally {
        if (mode === 'initial') setLoading(false);
        if (mode === 'refresh') setRefreshing(false);
      }
    },
    [loadDevices, selectedDevice, timeWindow],
  );

  useEffect(() => {
    void loadTelemetryBundle('initial');
  }, [loadTelemetryBundle]);

  useEffect(() => {
    if (pollRef.current) clearInterval(pollRef.current);
    pollRef.current = setInterval(() => {
      void loadTelemetryBundle('silent');
    }, 15000);

    return () => {
      if (pollRef.current) clearInterval(pollRef.current);
    };
  }, [loadTelemetryBundle]);

  const deviceLabel = devices.find((device) => device.id === selectedDevice)?.label ?? selectedDevice;
  const latestMetrics = useMemo(() => latest?.metrics ?? {}, [latest?.metrics]);

  const summaryStats = useMemo(() => {
    const cpu = telemetryNumber(latestMetrics.cpu);
    const ram = telemetryNumber(latestMetrics.ram);
    const disk = telemetryNumber(latestMetrics.disk_usage);
    const risk = telemetryRisk(latestMetrics.risk_score);
    const battery = telemetryNumber(latestMetrics.battery_pct);
    const policySync = telemetryBooleanStatus(
      latestMetrics.policy_in_sync ?? latest?.resolved_policy_in_sync,
      'Synchronized',
      'Mismatch',
      'Unknown',
    );
    const compliance = telemetryText(
      latestMetrics.compliance_status ?? latest?.resolved_compliance_status,
      'Unknown',
    ).replace('_', ' ');
    const presence = telemetryText(latest?.resolved_presence_state ?? latest?.presence_state, 'Unknown');
    const connection = telemetryText(latest?.resolved_connection_mode ?? latest?.connection_mode, 'Unknown');
    const riskColor = risk != null && risk >= 75 ? 'text-red-400' : 'text-green-400';

    return [
      { label: 'CPU (current)', value: cpu == null ? 'No data available' : `${cpu.toFixed(0)}%`, color: 'text-green-400' },
      { label: 'RAM (current)', value: ram == null ? 'No data available' : `${ram.toFixed(0)}%`, color: 'text-blue-400' },
      { label: 'Disk Usage', value: disk == null ? 'No data available' : `${disk.toFixed(0)}%`, color: 'text-amber-400' },
      { label: 'Risk Score', value: risk == null ? 'No data available' : `${risk.toFixed(0)} / 100`, color: riskColor },
      { label: 'Battery', value: battery == null ? 'No data available' : `${Math.max(0, Math.min(100, battery)).toFixed(0)}%`, color: 'text-cyan-400' },
      { label: 'Policy Sync', value: policySync, color: policySync === 'Synchronized' ? 'text-green-400' : policySync === 'Mismatch' ? 'text-amber-400' : 'text-muted-foreground' },
      { label: 'Compliance', value: compliance, color: compliance === 'compliant' ? 'text-green-400' : 'text-amber-400' },
      { label: 'Presence', value: presence, color: presence === 'online' ? 'text-green-400' : 'text-amber-400' },
      { label: 'Connection', value: connection, color: connection === 'wss' ? 'text-green-400' : 'text-muted-foreground' },
    ];
  }, [
    latestMetrics,
    latest?.connection_mode,
    latest?.presence_state,
    latest?.resolved_compliance_status,
    latest?.resolved_connection_mode,
    latest?.resolved_policy_in_sync,
    latest?.resolved_presence_state,
  ]);

  const metadataRows = useMemo(
    () => [
      { label: 'Schema', value: telemetryText(latest?.schema_version, 'Unknown') },
      { label: 'Session', value: telemetryText(latest?.session_id, 'Unknown') },
      { label: 'Seq', value: telemetryText(latest?.seq, 'Unknown') },
      { label: 'Scope', value: telemetryText(latest?.telemetry_scope, 'Unknown') },
      { label: 'Policy Hash', value: telemetryText(latest?.policy_hash, 'Unknown') },
      { label: 'Masked Fields', value: telemetryMaskedFields(latest?.masked_fields) },
      { label: 'Agent Version', value: telemetryText(latestMetrics.agent_version, 'Unknown') },
      { label: 'OS Build', value: telemetryText(latestMetrics.os_build ?? latest?.resolved_os_build, 'Unknown') },
      { label: 'OS Version', value: telemetryText(latestMetrics.os_version, 'Unknown') },
      { label: 'Patch Level', value: telemetryText(latestMetrics.patch_level, 'Unknown') },
      { label: 'Geo Hash', value: telemetryText(latestMetrics.geo_hash, 'Unknown') },
      { label: 'Battery', value: telemetryPercent(latestMetrics.battery_pct, 'No data available') },
    ],
    [
      latest?.masked_fields,
      latest?.policy_hash,
      latest?.schema_version,
      latest?.seq,
      latest?.session_id,
      latest?.telemetry_scope,
      latestMetrics.agent_version,
      latestMetrics.battery_pct,
      latestMetrics.geo_hash,
      latest?.resolved_os_build,
      latestMetrics.os_build,
      latestMetrics.os_version,
      latestMetrics.patch_level,
    ],
  );

  const chartData = useMemo(() => {
    const cpu: ChartPoint[] = [];
    const ram: ChartPoint[] = [];
    const disk: ChartPoint[] = [];
    const network: NetworkPoint[] = [];
    const risk: RiskPoint[] = [];

    history.forEach((point) => {
      if (!point.timestamp) return;
      const label = toTimeLabel(point.timestamp);

      const cpuValue = telemetryNumber(point.avg_cpu ?? point.metrics?.cpu);
      const ramValue = telemetryNumber(point.avg_ram ?? point.metrics?.ram);
      const diskValue = telemetryNumber(point.avg_disk_usage ?? point.metrics?.disk_usage);
      const txValue = telemetryNumber(point.network_tx ?? point.metrics?.network_tx);
      const rxValue = telemetryNumber(point.network_rx ?? point.metrics?.network_rx);
      const riskValue = telemetryRisk(point.risk_score_avg ?? point.risk_score ?? point.metrics?.risk_score);

      if (cpuValue != null) cpu.push({ time: label, value: Math.max(0, Math.min(100, cpuValue)) });
      if (ramValue != null) ram.push({ time: label, value: Math.max(0, Math.min(100, ramValue)) });
      if (diskValue != null) disk.push({ time: label, value: Math.max(0, Math.min(100, diskValue)) });
      if (txValue != null || rxValue != null) network.push({ time: label, tx: Math.max(0, txValue ?? 0), rx: Math.max(0, rxValue ?? 0) });
      if (riskValue != null) {
        const event = activity?.find((item) => item.timestamp === point.timestamp)?.event_type ?? null;
        risk.push({ time: label, score: Math.max(0, Math.min(100, riskValue)), event });
      }
    });

    return { cpu, ram, disk, network, risk };
  }, [history, activity]);

  const kernelEvents = useMemo(() => {
    const fromHistory = history
      .map((point) => {
        const kernelEvent = point.metrics?.kernel_event as Record<string, unknown> | undefined;
        if (!kernelEvent || !point.timestamp) return null;
        const parsedKernel = parseKernelTelemetryEvent(kernelEvent);
        if (!parsedKernel) return null;

        return {
          id: `${kernelEvent.event_id ?? 'evt'}-${point.timestamp}`,
          eventId: parsedKernel.eventId,
          eventType: parsedKernel.eventType,
          category: parsedKernel.category,
          subtype: parsedKernel.subtype,
          severity: parsedKernel.severity,
          decision: parsedKernel.decision,
          reasonCode: parsedKernel.reasonCode,
          durationMs: parsedKernel.durationMs,
          queueDepth: parsedKernel.queueDepth,
          dropCount: parsedKernel.dropCount,
          opcode: parsedKernel.opcode,
          status: parsedKernel.status,
          errorCode: parsedKernel.errorCode,
          ts: toTimeLabel(point.timestamp),
          timestamp: point.timestamp,
          maskedFields: parsedKernel.maskedFields,
        };
      })
      .filter(Boolean) as Array<{
      id: string;
      eventId: number;
      eventType: number;
      category: ParsedKernelTelemetryEvent['category'];
      subtype: string;
      severity: string;
      decision: string;
      reasonCode: string;
      durationMs: number;
      queueDepth: number;
      dropCount: number;
      opcode: string;
      status: string;
      errorCode: number;
      ts: string;
      timestamp: string;
      maskedFields: string[];
    }>;

    const fromActivity = (activity ?? [])
      .map((item) => {
        if (item.event_type !== 'telemetry') return null;
        const detail = (item.detail ?? {}) as Record<string, unknown>;
        const kernelEvent = detail.kernel_event as Record<string, unknown> | undefined;
        if (!kernelEvent || !item.timestamp) return null;
        const parsedKernel = parseKernelTelemetryEvent(kernelEvent);
        if (!parsedKernel) return null;

        return {
          id: `${kernelEvent.event_id ?? 'evt'}-${item.timestamp}`,
          eventId: parsedKernel.eventId,
          eventType: parsedKernel.eventType,
          category: parsedKernel.category,
          subtype: parsedKernel.subtype,
          severity: parsedKernel.severity,
          decision: parsedKernel.decision,
          reasonCode: parsedKernel.reasonCode,
          durationMs: parsedKernel.durationMs,
          queueDepth: parsedKernel.queueDepth,
          dropCount: parsedKernel.dropCount,
          opcode: parsedKernel.opcode,
          status: parsedKernel.status,
          errorCode: parsedKernel.errorCode,
          ts: toTimeLabel(item.timestamp),
          timestamp: item.timestamp,
          maskedFields: parsedKernel.maskedFields,
        };
      })
      .filter(Boolean) as Array<{
      id: string;
      eventId: number;
      eventType: number;
      category: ParsedKernelTelemetryEvent['category'];
      subtype: string;
      severity: string;
      decision: string;
      reasonCode: string;
      durationMs: number;
      queueDepth: number;
      dropCount: number;
      opcode: string;
      status: string;
      errorCode: number;
      ts: string;
      timestamp: string;
      maskedFields: string[];
    }>;

    const merged = [...fromHistory, ...fromActivity];
    const deduped = new Map<string, (typeof merged)[number]>();
    merged.forEach((row) => {
      const key = `${row.eventId}-${row.timestamp}`;
      if (!deduped.has(key)) deduped.set(key, row);
    });

    return Array.from(deduped.values())
      .sort((a, b) => new Date(b.timestamp).getTime() - new Date(a.timestamp).getTime())
      .slice(0, 25);
  }, [history, activity]);

  const filteredKernelEvents = useMemo(() => {
    if (kernelCategoryFilter === 'all') return kernelEvents;
    return kernelEvents.filter((event) => event.category === kernelCategoryFilter);
  }, [kernelCategoryFilter, kernelEvents]);

  const kernelCategoryCounts = useMemo(() => {
    return kernelEvents.reduce<Record<string, number>>((acc, event) => {
      acc[event.category] = (acc[event.category] ?? 0) + 1;
      return acc;
    }, {});
  }, [kernelEvents]);

  const kernelSummary = useMemo(() => {
    const total = filteredKernelEvents.length;
    if (total === 0) {
      return {
        total,
        errorRate: null as number | null,
        avgLatency: null as number | null,
        maxQueueDepth: null as number | null,
        maxDropCount: null as number | null,
        byCategory: {} as Record<string, number>,
      };
    }

    const failures = filteredKernelEvents.filter((event) => event.status !== 'ok' || event.errorCode > 0).length;
    const latencyValues = filteredKernelEvents.map((event) => event.durationMs).filter((value) => Number.isFinite(value));
    const queueDepthValues = filteredKernelEvents.map((event) => event.queueDepth).filter((value) => Number.isFinite(value));
    const dropValues = filteredKernelEvents.map((event) => event.dropCount).filter((value) => Number.isFinite(value));
    const byCategory = filteredKernelEvents.reduce<Record<string, number>>((acc, event) => {
      acc[event.category] = (acc[event.category] ?? 0) + 1;
      return acc;
    }, {});

    return {
      total,
      errorRate: (failures / total) * 100,
      avgLatency: latencyValues.length > 0 ? latencyValues.reduce((sum, value) => sum + value, 0) / latencyValues.length : null,
      maxQueueDepth: queueDepthValues.length > 0 ? Math.max(...queueDepthValues) : null,
      maxDropCount: dropValues.length > 0 ? Math.max(...dropValues) : null,
      byCategory,
    };
  }, [filteredKernelEvents]);

  const receivingTelemetry = useMemo(() => {
    if (!latest?.timestamp) return false;
    const ageMs = Date.now() - new Date(latest.timestamp).getTime();
    return Number.isFinite(ageMs) && ageMs <= 120_000;
  }, [latest?.timestamp]);

  return (
    <div className="space-y-5 fade-in">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">Telemetry Monitoring</h1>
          <p className="text-sm text-muted-foreground mt-0.5">Health trends and degradation patterns - {deviceLabel || 'No devices found'}</p>
        </div>
        <button
          onClick={async () => {
            await loadTelemetryBundle('refresh');
            toast.info('Telemetry refreshed');
          }}
          className="flex items-center gap-1.5 px-3 py-1.5 text-xs text-muted-foreground border border-border rounded-md hover:bg-muted/60 transition-colors"
          title="Refresh telemetry"
        >
          <RefreshCw size={13} className={refreshing ? 'animate-spin' : ''} />
          Refresh
        </button>
      </div>

      <div className="flex flex-wrap items-center gap-3">
        <div className="flex items-center gap-2">
          <Monitor size={14} className="text-muted-foreground" />
          <select
            value={selectedDevice}
            onChange={(event) => setSelectedDevice(event.target.value)}
            className="text-xs bg-muted/60 border border-border rounded-md px-2.5 py-1.5 text-foreground focus:outline-none focus:ring-1 focus:ring-primary/50"
          >
            {devices.length > 0 ? (
              devices.map((device) => (
                <option key={`tel-dev-${device.id}`} value={device.id}>
                  {device.label}
                </option>
              ))
            ) : (
              <option value="">No devices found</option>
            )}
          </select>
        </div>

        <div className="flex items-center gap-1 bg-muted/30 rounded-lg p-1">
          {timeWindows.map((window) => (
            <button
              key={`tw-${window.key}`}
              onClick={() => setTimeWindow(window.key)}
              className={`px-3 py-1.5 rounded-md text-xs font-medium transition-all ${
                timeWindow === window.key ? 'bg-card text-foreground shadow-sm' : 'text-muted-foreground hover:text-foreground'
              }`}
            >
              {window.label}
            </button>
          ))}
        </div>

        <div className={`flex items-center gap-1.5 text-xs ml-auto ${receivingTelemetry ? 'text-green-400' : 'text-amber-400'}`}>
          <span className={`w-1.5 h-1.5 rounded-full ${receivingTelemetry ? 'bg-green-400 pulse-dot' : 'bg-amber-400'}`} />
          <Activity size={12} />
          <span className="font-medium">{receivingTelemetry ? 'Receiving telemetry' : 'Awaiting fresh telemetry'}</span>
        </div>
      </div>

      <div className="grid grid-cols-2 sm:grid-cols-4 xl:grid-cols-4 2xl:grid-cols-4 gap-3">
        {summaryStats.map((stat) => (
          <div key={`tel-stat-${stat.label}`} className="bg-card border border-border rounded-lg px-4 py-3">
            <p className="text-[10px] text-muted-foreground uppercase tracking-wide mb-1">{stat.label}</p>
            <p className={`text-xl font-bold tabular-nums ${stat.color}`}>{stat.value}</p>
          </div>
        ))}
      </div>

      <div className="text-[11px] text-muted-foreground grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-x-4 gap-y-1">
        {metadataRows.map((row) => (
          <p key={`telemetry-meta-${row.label}`} className="truncate">
            <span className="text-foreground/80">{row.label}:</span> {row.value}
          </p>
        ))}
      </div>

      {error ? <p className="text-xs text-red-400">{error}</p> : null}
      {!error && activityError ? <p className="text-xs text-amber-400">{activityError}</p> : null}
      {loading ? <p className="text-xs text-muted-foreground">Loading telemetry data...</p> : null}
      {!loading && !error && history.length === 0 ? <p className="text-xs text-muted-foreground">No data available</p> : null}

      <div className="grid grid-cols-1 lg:grid-cols-2 xl:grid-cols-2 2xl:grid-cols-2 gap-4">
        <TelemetryCpuChart deviceId={selectedDevice} timeWindow={timeWindow} data={chartData.cpu} loading={loading} error={error} />
        <TelemetryRamChart deviceId={selectedDevice} timeWindow={timeWindow} data={chartData.ram} loading={loading} error={error} />
        <TelemetryDiskChart deviceId={selectedDevice} timeWindow={timeWindow} data={chartData.disk} loading={loading} error={error} />
        <TelemetryNetworkChart deviceId={selectedDevice} timeWindow={timeWindow} data={chartData.network} loading={loading} error={error} />
      </div>

      <TelemetryRiskChart deviceId={selectedDevice} timeWindow={timeWindow} data={chartData.risk} loading={loading} error={error} />

      <div className="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-4 gap-3">
        {[
          {
            label: 'Kernel Event Volume',
            value: kernelSummary.total > 0 ? String(kernelSummary.total) : 'No data available',
            color: 'text-foreground',
          },
          {
            label: 'Kernel Error Rate',
            value: kernelSummary.errorRate == null ? 'No data available' : `${kernelSummary.errorRate.toFixed(1)}%`,
            color: kernelSummary.errorRate != null && kernelSummary.errorRate >= 25 ? 'text-red-400' : 'text-green-400',
          },
          {
            label: 'Avg Kernel Latency',
            value: kernelSummary.avgLatency == null ? 'No data available' : `${kernelSummary.avgLatency.toFixed(1)}ms`,
            color: kernelSummary.avgLatency != null && kernelSummary.avgLatency >= 250 ? 'text-amber-400' : 'text-blue-400',
          },
          {
            label: 'Kernel Queue Health',
            value:
              kernelSummary.maxQueueDepth == null
                ? 'No data available'
                : `Depth ${kernelSummary.maxQueueDepth.toFixed(0)} / Drop ${kernelSummary.maxDropCount?.toFixed(0) ?? '0'}`,
            color:
              (kernelSummary.maxDropCount ?? 0) > 0
                ? 'text-red-400'
                : (kernelSummary.maxQueueDepth ?? 0) > 0
                  ? 'text-amber-400'
                  : 'text-green-400',
          },
        ].map((item) => (
          <div key={`kernel-summary-${item.label}`} className="bg-card border border-border rounded-lg px-4 py-3">
            <p className="text-[10px] text-muted-foreground uppercase tracking-wide mb-1">{item.label}</p>
            <p className={`text-lg font-semibold tabular-nums ${item.color}`}>{item.value}</p>
          </div>
        ))}
      </div>

      <div className="bg-card border border-border rounded-lg overflow-hidden">
        <div className="px-4 py-3 border-b border-border flex items-center justify-between">
          <div className="flex items-center gap-2">
            <h3 className="text-sm font-semibold">Kernel Events</h3>
            <span className="text-[11px] text-muted-foreground">telemetry_scope: kernel_event</span>
          </div>
          <div className="flex items-center gap-2">
            {(['all', 'exec', 'integrity', 'attestation', 'update', 'runtime'] as const).map((category) => (
              <button
                key={`kernel-category-${category}`}
                onClick={() => setKernelCategoryFilter(category)}
                className={`px-2 py-1 rounded text-[10px] border transition-colors ${
                  kernelCategoryFilter === category
                    ? 'bg-primary/10 border-primary/20 text-primary'
                    : 'border-border text-muted-foreground hover:text-foreground hover:bg-muted/30'
                }`}
              >
                {category === 'all' ? `All (${kernelEvents.length})` : `${category} (${kernelCategoryCounts[category] ?? 0})`}
              </button>
            ))}
          </div>
        </div>

        <div className="px-4 py-2 border-b border-border bg-muted/10">
          <button
            onClick={() => setAdvancedOpen((open) => !open)}
            className="flex items-center gap-1.5 text-[11px] text-muted-foreground hover:text-foreground transition-colors"
          >
            {advancedOpen ? <ChevronUp size={12} /> : <ChevronDown size={12} />}
            Advanced kernel diagnostics
            {lastUpdated ? ` - refreshed ${new Date(lastUpdated).toLocaleTimeString()}` : ''}
          </button>
          {advancedOpen ? (
            <div className="mt-2 text-[11px] text-muted-foreground grid grid-cols-1 md:grid-cols-3 gap-2">
              <p>Decisions: allow {filteredKernelEvents.filter((event) => event.decision === 'allow').length} / deny {filteredKernelEvents.filter((event) => event.decision === 'deny').length}</p>
              <p>High severity: {filteredKernelEvents.filter((event) => event.severity === 'high').length}</p>
              <p>
                Masked fields observed: {filteredKernelEvents.reduce((acc, event) => acc + event.maskedFields.length, 0)}
              </p>
            </div>
          ) : null}
        </div>

        <table className="w-full text-xs">
          <thead>
            <tr className="border-b border-border bg-muted/20">
              {['Event ID', 'Category', 'Opcode', 'Decision', 'Status', 'Error', 'Latency', 'Queue', 'Timestamp'].map((col) => (
                <th key={`ke-col-${col}`} className="px-3 py-2.5 text-left font-semibold text-muted-foreground tracking-wide uppercase text-[10px] whitespace-nowrap">
                  {col}
                </th>
              ))}
            </tr>
          </thead>
          <tbody className="divide-y divide-border">
            {filteredKernelEvents.length > 0 ? (
              filteredKernelEvents.map((evt) => (
                <tr key={evt.id} className="hover:bg-muted/20 transition-colors">
                  <td className="px-3 py-2.5 font-mono text-muted-foreground">{evt.eventId}</td>
                  <td className="px-3 py-2.5">
                    <span className="text-[10px] font-medium px-1.5 py-0.5 rounded bg-muted text-foreground/90">{evt.category}</span>
                  </td>
                  <td className="px-3 py-2.5 font-mono text-[11px] text-blue-400">{evt.opcode}</td>
                  <td className="px-3 py-2.5 text-muted-foreground">{evt.decision}</td>
                  <td className="px-3 py-2.5">
                    <span className={`text-[11px] font-semibold ${evt.status === 'ok' ? 'text-green-400' : 'text-red-400'}`}>{evt.status}</span>
                  </td>
                  <td className="px-3 py-2.5 font-mono text-muted-foreground">
                    {evt.errorCode > 0 ? <span className="text-[10px] bg-red-500/10 text-red-400 px-1.5 py-0.5 rounded">{evt.errorCode}</span> : '-'}
                  </td>
                  <td className="px-3 py-2.5 tabular-nums text-muted-foreground">{evt.durationMs.toFixed(0)}ms</td>
                  <td className="px-3 py-2.5 tabular-nums text-muted-foreground">{evt.queueDepth.toFixed(0)}</td>
                  <td className="px-3 py-2.5 tabular-nums text-muted-foreground">{evt.ts}</td>
                </tr>
              ))
            ) : (
              <tr>
                <td colSpan={9} className="px-3 py-3 text-muted-foreground">
                  {loading ? 'Loading telemetry data...' : error ? error : activityError ?? 'No data available'}
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
