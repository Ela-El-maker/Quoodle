'use client';
import React from 'react';
import { AreaChart, Area, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, ReferenceLine } from 'recharts';

type RiskPoint = { time: string; score: number; event: string | null };

const CustomTooltip = ({ active, payload, label }: { active?: boolean; payload?: Array<{ value: number }>; label?: string }) => {
  if (!active || !payload?.length) return null;
  const point = (payload as Array<{ payload?: RiskPoint }>)[0]?.payload;
  return (
    <div className="bg-zinc-900 border border-border rounded-lg px-3 py-2 shadow-xl text-xs">
      <p className="text-muted-foreground mb-0.5">{label}</p>
      <p className="font-semibold tabular-nums">Risk: {payload[0].value} / 100</p>
      {point?.event && <p className="text-[11px] text-blue-400 mt-0.5">Event: {point.event}</p>}
    </div>
  );
};

interface Props {
  deviceId: string;
  timeWindow: string;
  data: RiskPoint[];
  loading?: boolean;
  error?: string | null;
}

export default function TelemetryRiskChart({ data, loading, error }: Props) {
  return (
    <div className="bg-card border border-border rounded-lg p-4">
      <div className="flex items-center justify-between mb-3">
        <div>
          <h3 className="text-sm font-semibold">Risk Score Over Time</h3>
          <p className="text-[11px] text-muted-foreground mt-0.5">Composite risk scoring with correlated events</p>
        </div>
        <div className="flex items-center gap-3 text-[11px] text-muted-foreground">
          <span className="flex items-center gap-1"><span className="w-6 border-t border-dashed border-amber-500" />Warning threshold (50)</span>
          <span className="flex items-center gap-1"><span className="w-6 border-t border-dashed border-red-500" />Critical threshold (75)</span>
        </div>
      </div>
      <ResponsiveContainer width="100%" height={180}>
        <AreaChart data={data}>
          <defs>
            <linearGradient id="riskGrad" x1="0" y1="0" x2="0" y2="1">
              <stop offset="5%"  stopColor="hsl(217 91% 60%)" stopOpacity={0.25} />
              <stop offset="95%" stopColor="hsl(217 91% 60%)" stopOpacity={0} />
            </linearGradient>
          </defs>
          <CartesianGrid strokeDasharray="3 3" stroke="hsl(240 5% 16%)" vertical={false} />
          <XAxis dataKey="time" tick={{ fontSize: 10, fill: 'hsl(240 5% 55%)' }} axisLine={false} tickLine={false} />
          <YAxis tick={{ fontSize: 10, fill: 'hsl(240 5% 55%)' }} axisLine={false} tickLine={false} width={28} domain={[0, 100]} />
          <Tooltip content={<CustomTooltip />} />
          <ReferenceLine y={50} stroke="hsl(38 92% 50%)"  strokeDasharray="4 4" strokeWidth={1} />
          <ReferenceLine y={75} stroke="hsl(0 72% 51%)"   strokeDasharray="4 4" strokeWidth={1} />
          <Area type="monotone" dataKey="score" stroke="hsl(217 91% 60%)" strokeWidth={2} fill="url(#riskGrad)" />
        </AreaChart>
      </ResponsiveContainer>
      {error ? <p className="text-[11px] text-red-400 mt-2">Failed to load data</p> : null}
      {!error && !loading && data.length === 0 ? <p className="text-[11px] text-muted-foreground mt-2">No data available</p> : null}
    </div>
  );
}
