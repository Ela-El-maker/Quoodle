'use client';
import React from 'react';
import { AreaChart, Area, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer } from 'recharts';

// Backend integration point: GET /api/telemetry/history?device_id={deviceId}&window={timeWindow}&metric=disk
const diskData = [
  { time: '20:00', value: 58 },
  { time: '20:30', value: 58 },
  { time: '21:00', value: 59 },
  { time: '21:30', value: 60 },
  { time: '22:00', value: 60 },
  { time: '22:30', value: 60 },
  { time: '23:00', value: 61 },
  { time: '23:30', value: 61 },
  { time: '00:00', value: 61 },
  { time: '00:30', value: 62 },
  { time: '01:00', value: 62 },
  { time: '01:30', value: 60 },
];

const CustomTooltip = ({ active, payload, label }: { active?: boolean; payload?: Array<{ value: number }>; label?: string }) => {
  if (!active || !payload?.length) return null;
  return (
    <div className="bg-zinc-900 border border-border rounded-lg px-3 py-2 shadow-xl text-xs">
      <p className="text-muted-foreground mb-0.5">{label}</p>
      <p className="font-semibold tabular-nums">{payload[0].value}% Disk</p>
    </div>
  );
};

interface Props { deviceId: string; timeWindow: string; }

export default function TelemetryDiskChart({ deviceId: _deviceId }: Props) {
  return (
    <div className="bg-card border border-border rounded-lg p-4">
      <div className="flex items-center justify-between mb-3">
        <div>
          <h3 className="text-sm font-semibold">Disk Usage</h3>
          <p className="text-[11px] text-muted-foreground mt-0.5">% capacity used</p>
        </div>
        <span className="text-[10px] text-muted-foreground">Slow growth trend</span>
      </div>
      <ResponsiveContainer width="100%" height={160}>
        <AreaChart data={diskData}>
          <defs>
            <linearGradient id="diskGrad" x1="0" y1="0" x2="0" y2="1">
              <stop offset="5%"  stopColor="hsl(38 92% 50%)" stopOpacity={0.3} />
              <stop offset="95%" stopColor="hsl(38 92% 50%)" stopOpacity={0} />
            </linearGradient>
          </defs>
          <CartesianGrid strokeDasharray="3 3" stroke="hsl(240 5% 16%)" vertical={false} />
          <XAxis dataKey="time" tick={{ fontSize: 10, fill: 'hsl(240 5% 55%)' }} axisLine={false} tickLine={false} />
          <YAxis tick={{ fontSize: 10, fill: 'hsl(240 5% 55%)' }} axisLine={false} tickLine={false} width={28} domain={[0, 100]} unit="%" />
          <Tooltip content={<CustomTooltip />} />
          <Area type="monotone" dataKey="value" stroke="hsl(38 92% 50%)" strokeWidth={1.5} fill="url(#diskGrad)" />
        </AreaChart>
      </ResponsiveContainer>
    </div>
  );
}