'use client';
import React from 'react';
import { PieChart, Pie, Cell, Tooltip, ResponsiveContainer } from 'recharts';

// Backend integration point: GET /api/devices/stats
const fleetData = [
  { name: 'Online',      value: 71, color: 'hsl(142 71% 45%)' },
  { name: 'Offline',     value: 9,  color: 'hsl(240 5% 45%)' },
  { name: 'Degraded',    value: 4,  color: 'hsl(38 92% 50%)' },
  { name: 'Quarantined', value: 4,  color: 'hsl(0 72% 51%)' },
];

const CustomTooltip = ({ active, payload }: { active?: boolean; payload?: Array<{ name: string; value: number; payload: { color: string } }> }) => {
  if (!active || !payload?.length) return null;
  const item = payload[0];
  return (
    <div className="bg-zinc-900 border border-border rounded-lg px-3 py-2 shadow-xl text-xs">
      <div className="flex items-center gap-2">
        <span className="w-2 h-2 rounded-full" style={{ background: item.payload.color }} />
        <span className="text-muted-foreground">{item.name}:</span>
        <span className="font-medium tabular-nums">{item.value}</span>
      </div>
    </div>
  );
};

export default function DashboardFleetStatusChart() {
  const total = fleetData.reduce((s, d) => s + d.value, 0);

  return (
    <div className="bg-card border border-border rounded-lg p-5 h-full">
      <div className="mb-4">
        <h3 className="text-sm font-semibold">Fleet Status</h3>
        <p className="text-xs text-muted-foreground mt-0.5">{total} managed devices</p>
      </div>
      <div className="relative">
        <ResponsiveContainer width="100%" height={160}>
          <PieChart>
            <Pie
              data={fleetData}
              cx="50%"
              cy="50%"
              innerRadius={50}
              outerRadius={72}
              paddingAngle={2}
              dataKey="value"
              strokeWidth={0}
            >
              {fleetData.map((entry, index) => (
                <Cell key={`cell-fleet-${index}`} fill={entry.color} />
              ))}
            </Pie>
            <Tooltip content={<CustomTooltip />} />
          </PieChart>
        </ResponsiveContainer>
        <div className="absolute inset-0 flex flex-col items-center justify-center pointer-events-none">
          <p className="text-2xl font-bold tabular-nums">84.5%</p>
          <p className="text-[10px] text-muted-foreground">online</p>
        </div>
      </div>
      <div className="space-y-1.5 mt-2">
        {fleetData.map((item) => (
          <div key={`fleet-legend-${item.name}`} className="flex items-center justify-between">
            <div className="flex items-center gap-2">
              <span className="w-2 h-2 rounded-full flex-shrink-0" style={{ background: item.color }} />
              <span className="text-xs text-muted-foreground">{item.name}</span>
            </div>
            <span className="text-xs font-medium tabular-nums">{item.value}</span>
          </div>
        ))}
      </div>
    </div>
  );
}