'use client';
import React from 'react';
import { AreaChart, Area, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, ReferenceLine } from 'recharts';

// Backend integration point: GET /api/telemetry/history?device_id={deviceId}&window={timeWindow}&metric=risk_score
const riskData = [
  { time: '20:00', score: 18, event: null },
  { time: '20:30', score: 20, event: null },
  { time: '21:00', score: 19, event: 'CMD completed' },
  { time: '21:30', score: 35, event: 'Policy drift' },
  { time: '22:00', score: 42, event: 'CMD failed' },
  { time: '22:30', score: 38, event: null },
  { time: '23:00', score: 25, event: null },
  { time: '23:30', score: 22, event: null },
  { time: '00:00', score: 19, event: null },
  { time: '00:30', score: 21, event: null },
  { time: '01:00', score: 23, event: 'Attestation check' },
  { time: '01:30', score: 23, event: null },
];

const CustomTooltip = ({ active, payload, label }: { active?: boolean; payload?: Array<{ value: number }>; label?: string }) => {
  if (!active || !payload?.length) return null;
  const point = riskData.find((d) => d.time === label);
  return (
    <div className="bg-zinc-900 border border-border rounded-lg px-3 py-2 shadow-xl text-xs">
      <p className="text-muted-foreground mb-0.5">{label}</p>
      <p className="font-semibold tabular-nums">Risk: {payload[0].value} / 100</p>
      {point?.event && <p className="text-[11px] text-blue-400 mt-0.5">Event: {point.event}</p>}
    </div>
  );
};

interface Props { deviceId: string; timeWindow: string; }

export default function TelemetryRiskChart({ deviceId: _deviceId }: Props) {
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
        <AreaChart data={riskData}>
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
    </div>
  );
}