'use client';
import React, { useState } from 'react';
import { Activity, RefreshCw, Monitor } from 'lucide-react';
import TelemetryCpuChart from './TelemetryCpuChart';
import TelemetryRamChart from './TelemetryRamChart';
import TelemetryDiskChart from './TelemetryDiskChart';
import TelemetryNetworkChart from './TelemetryNetworkChart';
import TelemetryRiskChart from './TelemetryRiskChart';
import { toast } from 'sonner';

const devices = [
  { id: 'PC001',      label: 'WKSTN-001' },
  { id: 'PC002',      label: 'WKSTN-002' },
  { id: 'SRV-PROD-01',label: 'SRV-PROD-01' },
  { id: 'WKSTN-007',  label: 'WKSTN-007' },
  { id: 'WKSTN-042',  label: 'WKSTN-042' },
  { id: 'WKSTN-055',  label: 'WKSTN-055' },
];

const timeWindows = [
  { key: '1h',  label: '1h' },
  { key: '6h',  label: '6h' },
  { key: '24h', label: '24h' },
  { key: '7d',  label: '7d' },
];

export default function TelemetryContent() {
  const [selectedDevice, setSelectedDevice] = useState('PC001');
  const [timeWindow, setTimeWindow] = useState('24h');

  const deviceLabel = devices?.find((d) => d?.id === selectedDevice)?.label ?? selectedDevice;

  return (
    <div className="space-y-5 fade-in">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">Telemetry Monitoring</h1>
          <p className="text-sm text-muted-foreground mt-0.5">
            Health trends and degradation patterns — {deviceLabel}
          </p>
        </div>
        <button
          onClick={() => toast?.info('Telemetry refreshed')}
          className="flex items-center gap-1.5 px-3 py-1.5 text-xs text-muted-foreground border border-border rounded-md hover:bg-muted/60 transition-colors"
        >
          <RefreshCw size={13} />
          Refresh
        </button>
      </div>
      {/* Controls */}
      <div className="flex flex-wrap items-center gap-3">
        {/* Device selector */}
        <div className="flex items-center gap-2">
          <Monitor size={14} className="text-muted-foreground" />
          <select
            value={selectedDevice}
            onChange={(e) => setSelectedDevice(e?.target?.value)}
            className="text-xs bg-muted/60 border border-border rounded-md px-2.5 py-1.5 text-foreground focus:outline-none focus:ring-1 focus:ring-primary/50"
          >
            {devices?.map((d) => (
              <option key={`tel-dev-${d?.id}`} value={d?.id}>{d?.label}</option>
            ))}
          </select>
        </div>

        {/* Time window */}
        <div className="flex items-center gap-1 bg-muted/30 rounded-lg p-1">
          {timeWindows?.map((w) => (
            <button
              key={`tw-${w?.key}`}
              onClick={() => setTimeWindow(w?.key)}
              className={`px-3 py-1.5 rounded-md text-xs font-medium transition-all ${
                timeWindow === w?.key
                  ? 'bg-card text-foreground shadow-sm'
                  : 'text-muted-foreground hover:text-foreground'
              }`}
            >
              {w?.label}
            </button>
          ))}
        </div>

        {/* Live indicator */}
        <div className="flex items-center gap-1.5 text-xs text-green-400 ml-auto">
          <span className="w-1.5 h-1.5 rounded-full bg-green-400 pulse-dot" />
          <Activity size={12} />
          <span className="font-medium">Receiving telemetry</span>
        </div>
      </div>
      {/* Summary strip */}
      <div className="grid grid-cols-2 sm:grid-cols-4 xl:grid-cols-4 2xl:grid-cols-4 gap-3">
        {[
          { label: 'CPU (current)', value: '12%',      color: 'text-green-400' },
          { label: 'RAM (current)', value: '45%',      color: 'text-blue-400' },
          { label: 'Disk Usage',   value: '60%',       color: 'text-amber-400' },
          { label: 'Risk Score',   value: '23 / 100',  color: 'text-green-400' },
        ]?.map((stat) => (
          <div key={`tel-stat-${stat?.label}`} className="bg-card border border-border rounded-lg px-4 py-3">
            <p className="text-[10px] text-muted-foreground uppercase tracking-wide mb-1">{stat?.label}</p>
            <p className={`text-xl font-bold tabular-nums ${stat?.color}`}>{stat?.value}</p>
          </div>
        ))}
      </div>
      {/* Charts grid */}
      <div className="grid grid-cols-1 lg:grid-cols-2 xl:grid-cols-2 2xl:grid-cols-2 gap-4">
        <TelemetryCpuChart deviceId={selectedDevice} timeWindow={timeWindow} />
        <TelemetryRamChart deviceId={selectedDevice} timeWindow={timeWindow} />
        <TelemetryDiskChart deviceId={selectedDevice} timeWindow={timeWindow} />
        <TelemetryNetworkChart deviceId={selectedDevice} timeWindow={timeWindow} />
      </div>
      {/* Risk score full width */}
      <TelemetryRiskChart deviceId={selectedDevice} timeWindow={timeWindow} />
      {/* Kernel events table */}
      <div className="bg-card border border-border rounded-lg overflow-hidden">
        <div className="px-4 py-3 border-b border-border flex items-center justify-between">
          <h3 className="text-sm font-semibold">Kernel Events</h3>
          <span className="text-[11px] text-muted-foreground">telemetry_scope: kernel_event</span>
        </div>
        <table className="w-full text-xs">
          <thead>
            <tr className="border-b border-border bg-muted/20">
              {['Event ID', 'Event Type', 'Opcode', 'Status', 'Error Code', 'Timestamp']?.map((col) => (
                <th key={`ke-col-${col}`} className="px-3 py-2.5 text-left font-semibold text-muted-foreground tracking-wide uppercase text-[10px] whitespace-nowrap">
                  {col}
                </th>
              ))}
            </tr>
          </thead>
          <tbody className="divide-y divide-border">
            {[
              { id: 'ke-12', eventId: 12, eventType: 1, opcode: 'QOP_EXEC_PING',     status: 'ok',  errorCode: 0,    ts: '21:06:09' },
              { id: 'ke-11', eventId: 11, eventType: 1, opcode: 'QOP_EXEC_PING',     status: 'ok',  errorCode: 0,    ts: '21:03:44' },
              { id: 'ke-10', eventId: 10, eventType: 1, opcode: 'QOP_EXEC_PING',     status: 'err', errorCode: 4004, ts: '21:02:11' },
              { id: 'ke-09', eventId: 9,  eventType: 2, opcode: 'not_supported',     status: 'err', errorCode: 4004, ts: '20:58:44' },
              { id: 'ke-08', eventId: 8,  eventType: 1, opcode: 'QOP_EXEC_PING',     status: 'ok',  errorCode: 0,    ts: '20:44:33' },
            ]?.map((evt) => (
              <tr key={evt?.id} className="hover:bg-muted/20 transition-colors">
                <td className="px-3 py-2.5 font-mono text-muted-foreground">{evt?.eventId}</td>
                <td className="px-3 py-2.5 font-mono text-muted-foreground">{evt?.eventType}</td>
                <td className="px-3 py-2.5 font-mono text-[11px] text-blue-400">{evt?.opcode}</td>
                <td className="px-3 py-2.5">
                  <span className={`text-[11px] font-semibold ${evt?.status === 'ok' ? 'text-green-400' : 'text-red-400'}`}>
                    {evt?.status}
                  </span>
                </td>
                <td className="px-3 py-2.5 font-mono text-muted-foreground">
                  {evt?.errorCode > 0 ? (
                    <span className="text-[10px] bg-red-500/10 text-red-400 px-1.5 py-0.5 rounded">{evt?.errorCode}</span>
                  ) : '—'}
                </td>
                <td className="px-3 py-2.5 tabular-nums text-muted-foreground">{evt?.ts}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}