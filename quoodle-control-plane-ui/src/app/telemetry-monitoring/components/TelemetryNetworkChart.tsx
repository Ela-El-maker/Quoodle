'use client';
import React from 'react';
import { LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, Legend } from 'recharts';

type NetworkPoint = { time: string; tx: number; rx: number };

const CustomTooltip = ({ active, payload, label }: { active?: boolean; payload?: Array<{ name: string; value: number; color: string }>; label?: string }) => {
  if (!active || !payload?.length) return null;
  return (
    <div className="bg-popover border border-border rounded-lg px-3 py-2 shadow-xl text-xs">
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

interface Props {
  deviceId: string;
  timeWindow: string;
  data: NetworkPoint[];
  loading?: boolean;
  error?: string | null;
}

export default function TelemetryNetworkChart({ data, loading, error }: Props) {
  return (
    <div className="bg-card border border-border rounded-lg p-4">
      <div className="flex items-center justify-between mb-3">
        <div>
          <h3 className="text-sm font-semibold">Network Throughput</h3>
          <p className="text-[11px] text-muted-foreground mt-0.5">TX / RX in Mbps</p>
        </div>
      </div>
      <ResponsiveContainer width="100%" height={160}>
        <LineChart data={data}>
          <CartesianGrid strokeDasharray="3 3" stroke="hsl(240 5% 16%)" vertical={false} />
          <XAxis dataKey="time" tick={{ fontSize: 10, fill: 'hsl(240 5% 55%)' }} axisLine={false} tickLine={false} />
          <YAxis tick={{ fontSize: 10, fill: 'hsl(240 5% 55%)' }} axisLine={false} tickLine={false} width={32} unit=" M" />
          <Tooltip content={<CustomTooltip />} />
          <Legend wrapperStyle={{ fontSize: '11px', color: 'hsl(240 5% 55%)' }} iconType="circle" iconSize={7} />
          <Line type="monotone" dataKey="tx" name="TX" stroke="hsl(217 91% 60%)" strokeWidth={1.5} dot={false} />
          <Line type="monotone" dataKey="rx" name="RX" stroke="hsl(142 71% 45%)" strokeWidth={1.5} dot={false} />
        </LineChart>
      </ResponsiveContainer>
      {error ? <p className="text-[11px] text-red-400 mt-2">Failed to load data</p> : null}
      {!error && !loading && data.length === 0 ? <p className="text-[11px] text-muted-foreground mt-2">No data available</p> : null}
    </div>
  );
}

