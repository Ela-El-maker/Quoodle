'use client';
import React from 'react';
import { Terminal, Bell, Monitor, Shield, Activity } from 'lucide-react';

const ICON_BY_TYPE = {
  command: Terminal,
  alert: Bell,
  device: Monitor,
  policy: Shield,
  telemetry: Activity,
} as const;

const COLOR_BY_TYPE = {
  command: 'text-blue-400 bg-blue-500/10',
  alert: 'text-red-400 bg-red-500/10',
  device: 'text-zinc-400 bg-zinc-500/10',
  policy: 'text-amber-400 bg-amber-500/10',
  telemetry: 'text-cyan-400 bg-cyan-500/10',
} as const;

export interface DashboardActivityItem {
  id: string;
  type: keyof typeof ICON_BY_TYPE;
  title: string;
  detail: string;
  time: string;
}

interface DashboardActivityFeedProps {
  items?: DashboardActivityItem[];
  loading?: boolean;
  error?: string | null;
}

export default function DashboardActivityFeed({ items, loading, error }: DashboardActivityFeedProps) {
  const feedItems = items ?? [];

  return (
    <div className="bg-card border border-border rounded-lg overflow-hidden h-full">
      <div className="flex items-center justify-between px-4 py-3 border-b border-border">
        <div className="flex items-center gap-2">
          <h3 className="text-sm font-semibold">Live Activity</h3>
          <span className="w-1.5 h-1.5 rounded-full bg-green-400 pulse-dot" />
        </div>
        <span className="text-[10px] text-muted-foreground">Local</span>
      </div>
      <div className="divide-y divide-border overflow-y-auto max-h-[420px] scrollbar-thin">
        {loading && (
          <div className="px-4 py-10 text-center">
            <p className="text-sm text-muted-foreground">Loading data...</p>
          </div>
        )}
        {!loading && error && (
          <div className="px-4 py-10 text-center">
            <p className="text-sm text-red-400">Failed to load data</p>
          </div>
        )}
        {!loading && !error && feedItems.length === 0 && (
          <div className="px-4 py-10 text-center">
            <p className="text-sm text-muted-foreground">No recent activity</p>
          </div>
        )}
        {!loading && !error && feedItems.map((item) => {
          const Icon = ICON_BY_TYPE[item.type] ?? Activity;
          const color = COLOR_BY_TYPE[item.type] ?? 'text-muted-foreground bg-muted';

          return (
            <div key={item.id} className="flex items-start gap-3 px-4 py-3 hover:bg-muted/20 transition-colors">
              <div className={`w-6 h-6 rounded-md flex items-center justify-center flex-shrink-0 mt-0.5 ${color}`}>
                <Icon size={12} />
              </div>
              <div className="flex-1 min-w-0">
                <p className="text-xs font-medium leading-tight">{item.title}</p>
                <p className="text-[11px] text-muted-foreground truncate mt-0.5">{item.detail}</p>
              </div>
              <span className="text-[10px] text-muted-foreground tabular-nums flex-shrink-0">{item.time}</span>
            </div>
          );
        })}
      </div>
    </div>
  );
}
