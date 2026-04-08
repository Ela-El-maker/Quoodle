'use client';
import React from 'react';
import { Terminal, Bell, Monitor, Shield, Activity } from 'lucide-react';

// Backend integration point: SSE/WebSocket subscription to realtime event stream
const feedItems = [
  { id: 'feed-001', type: 'command', icon: Terminal, color: 'text-green-400 bg-green-500/10', title: 'CMD-7742 completed', detail: 'ping on WKSTN-055', time: '21:06:09' },
  { id: 'feed-002', type: 'alert',   icon: Bell,     color: 'text-red-400 bg-red-500/10',     title: 'Critical alert raised', detail: 'Attestation failure — SRV-PROD-04', time: '21:05:47' },
  { id: 'feed-003', type: 'device',  icon: Monitor,  color: 'text-zinc-400 bg-zinc-500/10',   title: 'WKSTN-031 went offline', detail: 'Last heartbeat 21:05:12', time: '21:05:33' },
  { id: 'feed-004', type: 'command', icon: Terminal, color: 'text-blue-400 bg-blue-500/10',   title: 'CMD-7740 dispatched', detail: 'lock_screen on WKSTN-042', time: '21:04:58' },
  { id: 'feed-005', type: 'policy',  icon: Shield,   color: 'text-amber-400 bg-amber-500/10', title: 'Policy drift detected', detail: 'WKSTN-011 — hash mismatch', time: '21:04:22' },
  { id: 'feed-006', type: 'device',  icon: Monitor,  color: 'text-green-400 bg-green-500/10', title: 'WKSTN-088 came online', detail: 'Agent v0.0.1 — OS 19045', time: '21:03:44' },
  { id: 'feed-007', type: 'command', icon: Terminal, color: 'text-red-400 bg-red-500/10',     title: 'CMD-7741 failed', detail: 'lock_screen — error 4004', time: '21:02:11' },
  { id: 'feed-008', type: 'telemetry', icon: Activity, color: 'text-blue-400 bg-blue-500/10', title: 'Telemetry anomaly', detail: 'WKSTN-007 CPU 91% sustained', time: '21:01:55' },
];

export default function DashboardActivityFeed() {
  return (
    <div className="bg-card border border-border rounded-lg overflow-hidden h-full">
      <div className="flex items-center justify-between px-4 py-3 border-b border-border">
        <div className="flex items-center gap-2">
          <h3 className="text-sm font-semibold">Live Activity</h3>
          <span className="w-1.5 h-1.5 rounded-full bg-green-400 pulse-dot" />
        </div>
        <span className="text-[10px] text-muted-foreground">UTC</span>
      </div>
      <div className="divide-y divide-border overflow-y-auto max-h-[420px] scrollbar-thin">
        {feedItems?.map((item) => (
          <div key={item?.id} className="flex items-start gap-3 px-4 py-3 hover:bg-muted/20 transition-colors">
            <div className={`w-6 h-6 rounded-md flex items-center justify-center flex-shrink-0 mt-0.5 ${item?.color}`}>
              <item.icon size={12} />
            </div>
            <div className="flex-1 min-w-0">
              <p className="text-xs font-medium leading-tight">{item?.title}</p>
              <p className="text-[11px] text-muted-foreground truncate mt-0.5">{item?.detail}</p>
            </div>
            <span className="text-[10px] text-muted-foreground tabular-nums flex-shrink-0">{item?.time}</span>
          </div>
        ))}
      </div>
    </div>
  );
}