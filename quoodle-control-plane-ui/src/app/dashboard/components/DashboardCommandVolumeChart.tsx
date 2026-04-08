'use client';
import React from 'react';
import {
  BarChart,
  Bar,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
  Legend,
} from 'recharts';

// Backend integration point: fetch from GET /api/commands/stats?window=7d
const commandVolumeData = [
  { day: 'Mar 30', completed: 34, failed: 4, expired: 2 },
  { day: 'Mar 31', completed: 41, failed: 2, expired: 1 },
  { day: 'Apr 1',  completed: 28, failed: 7, expired: 3 },
  { day: 'Apr 2',  completed: 52, failed: 3, expired: 0 },
  { day: 'Apr 3',  completed: 38, failed: 5, expired: 2 },
  { day: 'Apr 4',  completed: 45, failed: 2, expired: 1 },
  { day: 'Apr 5',  completed: 19, failed: 3, expired: 0 },
];

const CustomTooltip = ({ active, payload, label }: { active?: boolean; payload?: Array<{ name: string; value: number; color: string }>; label?: string }) => {
  if (!active || !payload?.length) return null;
  return (
    <div className="bg-zinc-900 border border-border rounded-lg px-3 py-2 shadow-xl text-xs">
      <p className="font-semibold text-foreground mb-1.5">{label}</p>
      {payload.map((entry) => (
        <div key={`tooltip-${entry.name}`} className="flex items-center gap-2 mb-0.5">
          <span className="w-2 h-2 rounded-full" style={{ background: entry.color }} />
          <span className="text-muted-foreground capitalize">{entry.name}:</span>
          <span className="font-medium tabular-nums">{entry.value}</span>
        </div>
      ))}
    </div>
  );
};

export default function DashboardCommandVolumeChart() {
  return (
    <div className="bg-card border border-border rounded-lg p-5 h-full">
      <div className="flex items-center justify-between mb-4">
        <div>
          <h3 className="text-sm font-semibold">Command Volume</h3>
          <p className="text-xs text-muted-foreground mt-0.5">Last 7 days — all methods</p>
        </div>
        <span className="text-[11px] text-muted-foreground bg-muted/60 px-2 py-0.5 rounded">7d</span>
      </div>
      <ResponsiveContainer width="100%" height={200}>
        <BarChart data={commandVolumeData} barSize={10} barGap={2}>
          <CartesianGrid strokeDasharray="3 3" stroke="hsl(240 5% 16%)" vertical={false} />
          <XAxis
            dataKey="day"
            tick={{ fontSize: 11, fill: 'hsl(240 5% 55%)' }}
            axisLine={false}
            tickLine={false}
          />
          <YAxis
            tick={{ fontSize: 11, fill: 'hsl(240 5% 55%)' }}
            axisLine={false}
            tickLine={false}
            width={28}
          />
          <Tooltip content={<CustomTooltip />} cursor={{ fill: 'hsl(240 5% 14%)' }} />
          <Legend
            wrapperStyle={{ fontSize: '11px', color: 'hsl(240 5% 55%)', paddingTop: '8px' }}
            iconType="circle"
            iconSize={7}
          />
          <Bar dataKey="completed" fill="hsl(142 71% 45%)" radius={[2, 2, 0, 0]} />
          <Bar dataKey="failed" fill="hsl(0 72% 51%)" radius={[2, 2, 0, 0]} />
          <Bar dataKey="expired" fill="hsl(38 92% 50%)" radius={[2, 2, 0, 0]} />
        </BarChart>
      </ResponsiveContainer>
    </div>
  );
}