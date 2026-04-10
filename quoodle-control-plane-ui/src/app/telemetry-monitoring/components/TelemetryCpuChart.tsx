'use client';
import React from 'react';
import {
  AreaChart,
  Area,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
  ReferenceLine,
} from 'recharts';

type CpuPoint = { time: string; value: number };

const CustomTooltip = ({ active, payload, label }: { active?: boolean; payload?: Array<{ value: number }>; label?: string }) => {
  if (!active || !payload?.length) return null;
  return (
    <div className="bg-zinc-900 border border-border rounded-lg px-3 py-2 shadow-xl text-xs">
      <p className="text-muted-foreground mb-0.5">{label}</p>
      <p className="font-semibold tabular-nums">{payload[0].value}% CPU</p>
    </div>
  );
};

interface Props {
  deviceId: string;
  timeWindow: string;
  data: CpuPoint[];
  loading?: boolean;
  error?: string | null;
}

export default function TelemetryCpuChart({ data, loading, error }: Props) {
  const isElevated = data.some((point) => point.value >= 80);

  return (
    <div className="bg-card border border-border rounded-lg p-4">
      <div className="flex items-center justify-between mb-3">
        <div>
          <h3 className="text-sm font-semibold">CPU Utilization</h3>
          <p className="text-[11px] text-muted-foreground mt-0.5">% usage over time</p>
        </div>
        {isElevated && (
          <span className="text-[10px] bg-amber-500/10 border border-amber-500/20 text-amber-400 px-2 py-0.5 rounded-full">Elevated</span>
        )}
      </div>
      <ResponsiveContainer width="100%" height={160}>
        <AreaChart data={data}>
          <defs>
            <linearGradient id="cpuGrad" x1="0" y1="0" x2="0" y2="1">
              <stop offset="5%"  stopColor={isElevated ? 'hsl(38 92% 50%)' : 'hsl(217 91% 60%)'} stopOpacity={0.3} />
              <stop offset="95%" stopColor={isElevated ? 'hsl(38 92% 50%)' : 'hsl(217 91% 60%)'} stopOpacity={0} />
            </linearGradient>
          </defs>
          <CartesianGrid strokeDasharray="3 3" stroke="hsl(240 5% 16%)" vertical={false} />
          <XAxis dataKey="time" tick={{ fontSize: 10, fill: 'hsl(240 5% 55%)' }} axisLine={false} tickLine={false} />
          <YAxis tick={{ fontSize: 10, fill: 'hsl(240 5% 55%)' }} axisLine={false} tickLine={false} width={28} domain={[0, 100]} unit="%" />
          <Tooltip content={<CustomTooltip />} />
          <ReferenceLine y={80} stroke="hsl(0 72% 51%)" strokeDasharray="4 4" strokeWidth={1} />
          <Area
            type="monotone"
            dataKey="value"
            stroke={isElevated ? 'hsl(38 92% 50%)' : 'hsl(217 91% 60%)'}
            strokeWidth={1.5}
            fill="url(#cpuGrad)"
          />
        </AreaChart>
      </ResponsiveContainer>
      {error ? <p className="text-[11px] text-red-400 mt-2">Failed to load data</p> : null}
      {!error && !loading && data.length === 0 ? <p className="text-[11px] text-muted-foreground mt-2">No data available</p> : null}
    </div>
  );
}
