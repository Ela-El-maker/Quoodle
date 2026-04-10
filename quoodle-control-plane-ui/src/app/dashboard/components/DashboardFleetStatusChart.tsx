'use client';
import React from 'react';
import { PieChart, Pie, Cell, Tooltip, ResponsiveContainer } from 'recharts';

export interface FleetStatusDatum {
  name: string;
  value: number;
  color: string;
}

interface DashboardFleetStatusChartProps {
  data?: FleetStatusDatum[];
  loading?: boolean;
  error?: string | null;
}

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

const DEFAULT_DATA: FleetStatusDatum[] = [
  { name: 'Online', value: 0, color: 'hsl(142 71% 45%)' },
  { name: 'Offline', value: 0, color: 'hsl(240 5% 45%)' },
  { name: 'Degraded', value: 0, color: 'hsl(38 92% 50%)' },
  { name: 'Quarantined', value: 0, color: 'hsl(0 72% 51%)' },
];

export default function DashboardFleetStatusChart({ data, loading, error }: DashboardFleetStatusChartProps) {
  const fleetData = data && data.length > 0 ? data : DEFAULT_DATA;
  const total = fleetData.reduce((s, d) => s + d.value, 0);
  const onlineCount = fleetData.find((row) => row.name === 'Online')?.value ?? 0;
  const onlineRate = total > 0 ? Number(((onlineCount / total) * 100).toFixed(1)) : 0;
  const showEmpty = !loading && !error && total === 0;

  return (
    <div className="bg-card border border-border rounded-lg p-5 h-full">
      <div className="mb-4">
        <h3 className="text-sm font-semibold">Fleet Status</h3>
        <p className="text-xs text-muted-foreground mt-0.5">{total} managed devices</p>
        {loading && <p className="text-[11px] text-muted-foreground mt-1">Loading data...</p>}
        {!loading && error && <p className="text-[11px] text-red-400 mt-1">{error}</p>}
        {showEmpty && <p className="text-[11px] text-muted-foreground mt-1">No data available</p>}
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
          <p className="text-2xl font-bold tabular-nums">{onlineRate}%</p>
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
