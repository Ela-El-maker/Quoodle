'use client';
import React from 'react';
import { AreaChart, Area, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer } from 'recharts';

type RamPoint = { time: string; value: number };

const CustomTooltip = ({ active, payload, label }: { active?: boolean; payload?: Array<{ value: number }>; label?: string }) => {
  if (!active || !payload?.length) return null;
  return (
    <div className="bg-popover border border-border rounded-lg px-3 py-2 shadow-xl text-xs">
      <p className="text-muted-foreground mb-0.5">{label}</p>
      <p className="font-semibold tabular-nums">{payload[0].value}% RAM</p>
    </div>
  );
};

interface Props {
  deviceId: string;
  timeWindow: string;
  data: RamPoint[];
  loading?: boolean;
  error?: string | null;
}

export default function TelemetryRamChart({ data, loading, error }: Props) {
  return (
    <div className="bg-card border border-border rounded-lg p-4">
      <div className="flex items-center justify-between mb-3">
        <div>
          <h3 className="text-sm font-semibold">RAM Utilization</h3>
          <p className="text-[11px] text-muted-foreground mt-0.5">% usage over time</p>
        </div>
      </div>
      <ResponsiveContainer width="100%" height={160}>
        <AreaChart data={data}>
          <defs>
            <linearGradient id="ramGrad" x1="0" y1="0" x2="0" y2="1">
              <stop offset="5%"  stopColor="hsl(142 71% 45%)" stopOpacity={0.3} />
              <stop offset="95%" stopColor="hsl(142 71% 45%)" stopOpacity={0} />
            </linearGradient>
          </defs>
          <CartesianGrid strokeDasharray="3 3" stroke="hsl(240 5% 16%)" vertical={false} />
          <XAxis dataKey="time" tick={{ fontSize: 10, fill: 'hsl(240 5% 55%)' }} axisLine={false} tickLine={false} />
          <YAxis tick={{ fontSize: 10, fill: 'hsl(240 5% 55%)' }} axisLine={false} tickLine={false} width={28} domain={[0, 100]} unit="%" />
          <Tooltip content={<CustomTooltip />} />
          <Area type="monotone" dataKey="value" stroke="hsl(142 71% 45%)" strokeWidth={1.5} fill="url(#ramGrad)" />
        </AreaChart>
      </ResponsiveContainer>
      {error ? <p className="text-[11px] text-red-400 mt-2">Failed to load data</p> : null}
      {!error && !loading && data.length === 0 ? <p className="text-[11px] text-muted-foreground mt-2">No data available</p> : null}
    </div>
  );
}

