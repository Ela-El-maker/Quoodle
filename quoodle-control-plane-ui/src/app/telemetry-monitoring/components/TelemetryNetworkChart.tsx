'use client';
import React from 'react';
import { LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, Legend } from 'recharts';

// Backend integration point: GET /api/telemetry/history?device_id={deviceId}&window={timeWindow}&metric=network
const networkData = [
  { time: '20:00', tx: 2.1, rx: 1.5 },
  { time: '20:30', tx: 3.4, rx: 2.2 },
  { time: '21:00', tx: 2.3, rx: 1.8 },
  { time: '21:30', tx: 5.1, rx: 3.4 },
  { time: '22:00', tx: 1.8, rx: 1.2 },
  { time: '22:30', tx: 2.7, rx: 1.9 },
  { time: '23:00', tx: 4.2, rx: 2.8 },
  { time: '23:30', tx: 2.9, rx: 2.1 },
  { time: '00:00', tx: 1.4, rx: 0.9 },
  { time: '00:30', tx: 2.3, rx: 1.6 },
  { time: '01:00', tx: 3.1, rx: 2.3 },
  { time: '01:30', tx: 2.3, rx: 1.8 },
];

const CustomTooltip = ({ active, payload, label }: { active?: boolean; payload?: Array<{ name: string; value: number; color: string }>; label?: string }) => {
  if (!active || !payload?.length) return null;
  return (
    <div className="bg-zinc-900 border border-border rounded-lg px-3 py-2 shadow-xl text-xs">
      <p className="text-muted-foreground mb-1">{label}</p>
      {payload.map((entry) => (
        <div key={`net-tip-${entry.name}`} className="flex items-center gap-2 mb-0.5">
          <span className="w-2 h-2 rounded-full" style={{ background: entry.color }} />
          <span className="text-muted-foreground">{entry.name}:</span>
          <span className="font-semibold tabular-nums">{entry.value} Mbps</span>
        </div>
      ))}
    </div>
  );
};

interface Props { deviceId: string; timeWindow: string; }

export default function TelemetryNetworkChart({ deviceId: _deviceId }: Props) {
  return (
    <div className="bg-card border border-border rounded-lg p-4">
      <div className="flex items-center justify-between mb-3">
        <div>
          <h3 className="text-sm font-semibold">Network Throughput</h3>
          <p className="text-[11px] text-muted-foreground mt-0.5">TX / RX in Mbps</p>
        </div>
      </div>
      <ResponsiveContainer width="100%" height={160}>
        <LineChart data={networkData}>
          <CartesianGrid strokeDasharray="3 3" stroke="hsl(240 5% 16%)" vertical={false} />
          <XAxis dataKey="time" tick={{ fontSize: 10, fill: 'hsl(240 5% 55%)' }} axisLine={false} tickLine={false} />
          <YAxis tick={{ fontSize: 10, fill: 'hsl(240 5% 55%)' }} axisLine={false} tickLine={false} width={32} unit=" M" />
          <Tooltip content={<CustomTooltip />} />
          <Legend wrapperStyle={{ fontSize: '11px', color: 'hsl(240 5% 55%)' }} iconType="circle" iconSize={7} />
          <Line type="monotone" dataKey="tx" name="TX" stroke="hsl(217 91% 60%)" strokeWidth={1.5} dot={false} />
          <Line type="monotone" dataKey="rx" name="RX" stroke="hsl(142 71% 45%)" strokeWidth={1.5} dot={false} />
        </LineChart>
      </ResponsiveContainer>
    </div>
  );
}