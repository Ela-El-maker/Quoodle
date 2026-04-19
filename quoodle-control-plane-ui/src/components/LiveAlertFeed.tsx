'use client';
import React, { useState, useEffect, useRef } from 'react';
import { Wifi, WifiOff, Bell, Terminal, AlertTriangle, CheckCircle2, X, Zap, Activity } from 'lucide-react';

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
  pushInterval?: number;
  maxEvents?: number;
  className?: string;
  events?: WsEvent[];
  loading?: boolean;
  error?: string | null;
}

export default function LiveAlertFeed({
  maxEvents = 12,
  className = '',
  events,
  loading = false,
  error = null,
}: LiveAlertFeedProps) {
  const usingExternalEvents = events !== undefined;
  const [connected, setConnected] = useState(false);
  const [feedEvents, setFeedEvents] = useState<WsEvent[]>([]);
  const [unreadCount, setUnreadCount] = useState(0);
  const [collapsed, setCollapsed] = useState(false);
  const [connecting, setConnecting] = useState(true);
  const previousIdsRef = useRef<Set<string>>(new Set());
  const effectiveConnecting = usingExternalEvents ? false : connecting;
  const effectiveConnected = usingExternalEvents ? true : connected;

  useEffect(() => {
    if (usingExternalEvents) return;
    setConnecting(false);
    setConnected(false);
    setFeedEvents([]);
    setUnreadCount(0);
    return () => {};
  }, [usingExternalEvents]);

  useEffect(() => {
    if (!usingExternalEvents) return;

    const incoming = (events ?? []).slice(0, maxEvents);
    const previous = previousIdsRef.current;
    let nextUnread = 0;
    const next = incoming.map((evt) => {
      const isNew = !previous.has(evt.id);
      const read = !isNew;
      if (!read) nextUnread += 1;
      return { ...evt, read };
    });

    previousIdsRef.current = new Set(incoming.map((evt) => evt.id));
    setFeedEvents(next);
    setUnreadCount(nextUnread);
  }, [usingExternalEvents, events, maxEvents]);

  const markAllRead = () => {
    setFeedEvents((prev) => prev.map((e) => ({ ...e, read: true })));
    setUnreadCount(0);
  };

  const dismissEvent = (id: string) => {
    setFeedEvents((prev) => {
      const evt = prev.find((e) => e.id === id);
      const next = prev.filter((e) => e.id !== id);
      if (evt && !evt.read) setUnreadCount((c) => Math.max(0, c - 1));
      return next;
    });
  };

  return (
    <div className={`bg-card border border-border rounded-lg overflow-hidden ${className}`}>
      <div className="flex items-center justify-between px-4 py-3 border-b border-border">
        <div className="flex items-center gap-2">
          <div className="relative">
            {effectiveConnecting ? (
              <WifiOff size={14} className="text-muted-foreground animate-pulse" />
            ) : effectiveConnected ? (
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
            effectiveConnecting ? 'border-amber-500/30 text-amber-400 bg-amber-500/10' : effectiveConnected
              ? 'border-green-500/30 text-green-400 bg-green-500/10'
              : 'border-red-500/30 text-red-400 bg-red-500/10'
          }`}>
            <span className={`w-1.5 h-1.5 rounded-full ${effectiveConnecting ? 'bg-amber-400 animate-pulse' : effectiveConnected ? 'bg-green-400 pulse-dot' : 'bg-red-400'}`} />
            {effectiveConnecting ? 'Connecting...' : effectiveConnected ? 'Connected' : 'Disconnected'}
          </div>
          <button
            onClick={() => setCollapsed(!collapsed)}
            className="p-1 rounded text-muted-foreground hover:text-foreground hover:bg-muted transition-colors"
          >
            {collapsed ? <CheckCircle2 size={13} /> : <AlertTriangle size={13} />}
          </button>
        </div>
      </div>

      {!collapsed && (
        <div className="divide-y divide-border max-h-72 overflow-y-auto scrollbar-thin">
          {(loading || effectiveConnecting) && (
            <div className="flex items-center justify-center py-8 gap-2 text-xs text-muted-foreground">
              <div className="w-4 h-4 border-2 border-primary/30 border-t-primary rounded-full animate-spin" />
              {loading ? 'Loading data...' : 'Establishing WebSocket connection to FastAPI...'}
            </div>
          )}
          {!loading && !effectiveConnecting && error && (
            <div className="flex items-center justify-center py-8 text-xs text-red-400">
              Failed to load data
            </div>
          )}
          {!loading && !effectiveConnecting && !error && feedEvents.length === 0 && (
            <div className="flex items-center justify-center py-8 text-xs text-muted-foreground">
              {usingExternalEvents ? 'No data available' : 'No live feed source configured'}
            </div>
          )}
          {!loading && !effectiveConnecting && !error && feedEvents.map((evt) => {
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
                  <p className="font-mono text-[10px] text-muted-foreground/60 mt-0.5">{evt.timestamp}</p>
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
          Feed collapsed - {feedEvents.length} events buffered
        </div>
      )}
    </div>
  );
}
