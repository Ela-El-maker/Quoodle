'use client';
import React, { useState, useEffect, useRef, useCallback } from 'react';
import { Wifi, WifiOff, Bell, Terminal, AlertTriangle, CheckCircle2, X, Zap, Activity } from 'lucide-react';
import Icon from '@/components/ui/AppIcon';


export type WsEventType = 'alert' | 'command_status' | 'device_state' | 'system';

export interface WsEvent {
  id: string;
  type: WsEventType;
  severity?: 'critical' | 'warning' | 'info';
  title: string;
  detail: string;
  device?: string;
  timestamp: string;
  read: boolean;
}

// Simulated push events pool
const EVENT_POOL: Omit<WsEvent, 'id' | 'timestamp' | 'read'>[] = [
  { type: 'alert', severity: 'critical', title: 'Attestation Failure', detail: 'WKSTN-055 — kernel guard state mismatch detected', device: 'WKSTN-055' },
  { type: 'command_status', severity: 'info', title: 'CMD-7745 Completed', detail: 'ping completed on WKSTN-001 — 12ms RTT', device: 'WKSTN-001' },
  { type: 'alert', severity: 'warning', title: 'Policy Drift', detail: 'WKSTN-011 reports policy-2025-11, expected policy-2026-04', device: 'WKSTN-011' },
  { type: 'command_status', severity: 'warning', title: 'CMD-7746 Failed', detail: 'lock_screen failed on WKSTN-007 — agent timeout', device: 'WKSTN-007' },
  { type: 'device_state', severity: 'warning', title: 'Device Degraded', detail: 'WKSTN-019 risk score elevated to 0.72', device: 'WKSTN-019' },
  { type: 'command_status', severity: 'info', title: 'CMD-7747 Dispatched', detail: 'get_system_info queued for SRV-PROD-04', device: 'SRV-PROD-04' },
  { type: 'alert', severity: 'critical', title: 'Compliance Violation', detail: 'SRV-PROD-04 — compliance score dropped to 42%', device: 'SRV-PROD-04' },
  { type: 'system', severity: 'info', title: 'Policy Sync Complete', detail: 'Fleet policy-2026-04 propagated to 47/50 devices' },
  { type: 'command_status', severity: 'info', title: 'CMD-7748 ACK', detail: 'Agent acknowledged lock_screen on WKSTN-042', device: 'WKSTN-042' },
  { type: 'device_state', severity: 'info', title: 'Device Online', detail: 'WKSTN-033 reconnected after 8 min offline', device: 'WKSTN-033' },
];

let eventCounter = 1000;

function generateEvent(): WsEvent {
  const pool = EVENT_POOL[Math.floor(Math.random() * EVENT_POOL.length)];
  const now = new Date();
  const ts = `${String(now.getHours()).padStart(2, '0')}:${String(now.getMinutes()).padStart(2, '0')}:${String(now.getSeconds()).padStart(2, '0')}`;
  return {
    ...pool,
    id: `WS-${++eventCounter}`,
    timestamp: ts,
    read: false,
  };
}

const typeIcon: Record<WsEventType, React.ElementType> = {
  alert: Bell,
  command_status: Terminal,
  device_state: Activity,
  system: Zap,
};

const severityStyle: Record<string, string> = {
  critical: 'border-red-500/30 bg-red-500/5',
  warning: 'border-amber-500/30 bg-amber-500/5',
  info: 'border-border bg-muted/10',
};

const severityIconColor: Record<string, string> = {
  critical: 'text-red-400',
  warning: 'text-amber-400',
  info: 'text-blue-400',
};

interface LiveAlertFeedProps {
  /** Interval in ms between simulated push events (default: 8000) */
  pushInterval?: number;
  /** Max events to keep in feed (default: 12) */
  maxEvents?: number;
  className?: string;
}

export default function LiveAlertFeed({
  pushInterval = 8000,
  maxEvents = 12,
  className = '',
}: LiveAlertFeedProps) {
  const [connected, setConnected] = useState(false);
  const [events, setEvents] = useState<WsEvent[]>([]);
  const [unreadCount, setUnreadCount] = useState(0);
  const [collapsed, setCollapsed] = useState(false);
  const [connecting, setConnecting] = useState(true);
  const intervalRef = useRef<ReturnType<typeof setInterval> | null>(null);

  // Simulate WebSocket connection
  useEffect(() => {
    const connectTimer = setTimeout(() => {
      setConnecting(false);
      setConnected(true);
      // Seed with 2 initial events
      const seed = [generateEvent(), generateEvent()];
      setEvents(seed);
      setUnreadCount(2);
    }, 1200);
    return () => clearTimeout(connectTimer);
  }, []);

  // Simulate push events
  const pushEvent = useCallback(() => {
    const evt = generateEvent();
    setEvents((prev) => [evt, ...prev].slice(0, maxEvents));
    setUnreadCount((c) => c + 1);
  }, [maxEvents]);

  useEffect(() => {
    if (!connected) return;
    intervalRef.current = setInterval(pushEvent, pushInterval);
    return () => {
      if (intervalRef.current) clearInterval(intervalRef.current);
    };
  }, [connected, pushEvent, pushInterval]);

  const markAllRead = () => {
    setEvents((prev) => prev.map((e) => ({ ...e, read: true })));
    setUnreadCount(0);
  };

  const dismissEvent = (id: string) => {
    setEvents((prev) => {
      const evt = prev.find((e) => e.id === id);
      const next = prev.filter((e) => e.id !== id);
      if (evt && !evt.read) setUnreadCount((c) => Math.max(0, c - 1));
      return next;
    });
  };

  return (
    <div className={`bg-card border border-border rounded-lg overflow-hidden ${className}`}>
      {/* Header */}
      <div className="flex items-center justify-between px-4 py-3 border-b border-border">
        <div className="flex items-center gap-2">
          <div className="relative">
            {connecting ? (
              <WifiOff size={14} className="text-muted-foreground animate-pulse" />
            ) : connected ? (
              <Wifi size={14} className="text-green-400" />
            ) : (
              <WifiOff size={14} className="text-red-400" />
            )}
          </div>
          <h3 className="text-sm font-semibold">Live Feed</h3>
          <span className="text-[10px] font-semibold px-1.5 py-0.5 rounded-full bg-muted text-muted-foreground">
            FastAPI WS
          </span>
          {unreadCount > 0 && (
            <span className="text-[10px] font-bold px-1.5 py-0.5 rounded-full bg-red-500/20 text-red-400 tabular-nums pulse-dot">
              {unreadCount} new
            </span>
          )}
        </div>
        <div className="flex items-center gap-1.5">
          {unreadCount > 0 && (
            <button
              onClick={markAllRead}
              className="text-[11px] text-muted-foreground hover:text-foreground transition-colors px-2 py-0.5 rounded border border-border hover:bg-muted/60"
            >
              Mark read
            </button>
          )}
          <div className={`flex items-center gap-1 text-[10px] px-1.5 py-0.5 rounded-full border ${
            connecting ? 'border-amber-500/30 text-amber-400 bg-amber-500/10' : connected ?'border-green-500/30 text-green-400 bg-green-500/10': 'border-red-500/30 text-red-400 bg-red-500/10'
          }`}>
            <span className={`w-1.5 h-1.5 rounded-full ${connecting ? 'bg-amber-400 animate-pulse' : connected ? 'bg-green-400 pulse-dot' : 'bg-red-400'}`} />
            {connecting ? 'Connecting…' : connected ? 'Connected' : 'Disconnected'}
          </div>
          <button
            onClick={() => setCollapsed(!collapsed)}
            className="p-1 rounded text-muted-foreground hover:text-foreground hover:bg-muted transition-colors"
          >
            {collapsed
              ? <CheckCircle2 size={13} />
              : <AlertTriangle size={13} />}
          </button>
        </div>
      </div>

      {!collapsed && (
        <div className="divide-y divide-border max-h-72 overflow-y-auto scrollbar-thin">
          {connecting && (
            <div className="flex items-center justify-center py-8 gap-2 text-xs text-muted-foreground">
              <div className="w-4 h-4 border-2 border-primary/30 border-t-primary rounded-full animate-spin" />
              Establishing WebSocket connection to FastAPI…
            </div>
          )}
          {!connecting && events.length === 0 && (
            <div className="flex items-center justify-center py-8 text-xs text-muted-foreground">
              No events yet — waiting for push…
            </div>
          )}
          {!connecting && events.map((evt) => {
            const Icon = typeIcon[evt.type];
            const sev = evt.severity || 'info';
            return (
              <div
                key={evt.id}
                className={`flex items-start gap-3 px-4 py-3 transition-all ${severityStyle[sev]} ${!evt.read ? 'border-l-2 border-l-primary' : ''}`}
              >
                <div className={`w-6 h-6 rounded-md flex items-center justify-center flex-shrink-0 mt-0.5 ${
                  sev === 'critical' ? 'bg-red-500/10' : sev === 'warning' ? 'bg-amber-500/10' : 'bg-blue-500/10'
                }`}>
                  <Icon size={12} className={severityIconColor[sev]} />
                </div>
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-1.5 flex-wrap">
                    <span className="text-xs font-semibold">{evt.title}</span>
                    {evt.device && (
                      <span className="font-mono text-[10px] text-primary">{evt.device}</span>
                    )}
                    {!evt.read && (
                      <span className="text-[9px] font-bold px-1 py-0.5 rounded bg-primary/10 text-primary">NEW</span>
                    )}
                  </div>
                  <p className="text-[11px] text-muted-foreground mt-0.5 truncate">{evt.detail}</p>
                  <p className="font-mono text-[10px] text-muted-foreground/60 mt-0.5">{evt.timestamp} UTC</p>
                </div>
                <button
                  onClick={() => dismissEvent(evt.id)}
                  className="p-1 rounded text-muted-foreground hover:text-foreground hover:bg-muted transition-colors flex-shrink-0"
                >
                  <X size={11} />
                </button>
              </div>
            );
          })}
        </div>
      )}

      {collapsed && (
        <div className="px-4 py-2 text-xs text-muted-foreground">
          Feed collapsed — {events.length} events buffered
        </div>
      )}
    </div>
  );
}
