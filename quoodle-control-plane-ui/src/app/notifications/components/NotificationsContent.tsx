'use client';

import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { Bell, CheckCheck, Trash2, Clock, AlertTriangle, Terminal, Monitor, Wifi, X, Search, RefreshCw } from 'lucide-react';
import { toast } from 'sonner';
import { formatLocalTime } from '@/lib/dateTime';

type EventType = 'alert' | 'command' | 'device_state' | 'system';
type ReadState = 'all' | 'unread' | 'read';

interface NotificationEvent {
  id: string;
  type: EventType;
  title: string;
  message: string;
  device_id?: string;
  actor?: string;
  timestamp: string;
  read: boolean;
  dismissed: boolean;
  severity?: 'critical' | 'high' | 'warning' | 'medium' | 'low' | 'info';
}

interface NotificationsResponse {
  notifications?: Array<{
    id?: string;
    type?: string;
    title?: string;
    message?: string;
    device_id?: string;
    actor?: string;
    timestamp?: string;
    read?: boolean;
    dismissed?: boolean;
    severity?: string;
  }>;
  summary?: {
    unread?: number;
  };
}

const typeConfig: Record<EventType, { icon: React.ElementType; color: string; label: string }> = {
  alert: { icon: AlertTriangle, color: 'text-red-400', label: 'Alert' },
  command: { icon: Terminal, color: 'text-blue-400', label: 'Command' },
  device_state: { icon: Monitor, color: 'text-amber-400', label: 'Device' },
  system: { icon: Wifi, color: 'text-violet-400', label: 'System' },
};

const severityColors: Record<string, string> = {
  critical: 'bg-red-500/10 text-red-400 border-red-500/20',
  high: 'bg-orange-500/10 text-orange-400 border-orange-500/20',
  warning: 'bg-amber-500/10 text-amber-400 border-amber-500/20',
  medium: 'bg-amber-500/10 text-amber-300 border-amber-500/20',
  low: 'bg-blue-500/10 text-blue-400 border-blue-500/20',
  info: 'bg-muted text-muted-foreground border-border',
};

function normalizeType(value: string | null | undefined): EventType {
  const normalized = String(value ?? '').toLowerCase();
  if (normalized === 'alert') return 'alert';
  if (normalized === 'command') return 'command';
  if (normalized === 'device_state') return 'device_state';
  return 'system';
}

function normalizeSeverity(value: string | null | undefined): NotificationEvent['severity'] {
  const normalized = String(value ?? '').toLowerCase();
  if (['critical', 'high', 'warning', 'medium', 'low', 'info'].includes(normalized)) {
    return normalized as NotificationEvent['severity'];
  }
  return 'info';
}

function toTimeValue(value: string | null | undefined): number {
  if (!value) return 0;
  const parsed = Date.parse(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

export default function NotificationsContent() {
  const [events, setEvents] = useState<NotificationEvent[]>([]);
  const [typeFilter, setTypeFilter] = useState<EventType | 'all'>('all');
  const [readFilter, setReadFilter] = useState<ReadState>('all');
  const [search, setSearch] = useState('');
  const [dateFrom, setDateFrom] = useState('');
  const [dateTo, setDateTo] = useState('');
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [unreadCount, setUnreadCount] = useState(0);

  const loadNotifications = useCallback(async (mode: 'initial' | 'refresh' | 'silent' = 'initial') => {
    if (mode === 'initial') setLoading(true);
    if (mode === 'refresh') setRefreshing(true);
    try {
      const response = await fetch('/api/notifications?limit=120', { credentials: 'include', cache: 'no-store' });
      if (!response.ok) {
        throw new Error(`http_${response.status}`);
      }

      const payload = (await response.json()) as NotificationsResponse;
      const mapped = (payload.notifications ?? [])
        .map((item): NotificationEvent => ({
          id: String(item.id ?? '').trim(),
          type: normalizeType(item.type),
          title: String(item.title ?? 'Notification').trim() || 'Notification',
          message: String(item.message ?? '').trim() || 'No details available.',
          device_id: String(item.device_id ?? '').trim() || undefined,
          actor: String(item.actor ?? '').trim() || 'system',
          timestamp: String(item.timestamp ?? '').trim(),
          read: Boolean(item.read),
          dismissed: Boolean(item.dismissed),
          severity: normalizeSeverity(item.severity),
        }))
        .filter((item) => item.id !== '')
        .sort((a, b) => toTimeValue(b.timestamp) - toTimeValue(a.timestamp));

      setEvents(mapped);
      setUnreadCount(typeof payload.summary?.unread === 'number' ? payload.summary.unread : mapped.filter((item) => !item.read).length);
      setLoadError(null);
    } catch (error) {
      console.error('notifications-load-failed', error);
      setLoadError('Failed to load notifications');
    } finally {
      if (mode === 'initial') setLoading(false);
      if (mode === 'refresh') setRefreshing(false);
    }
  }, []);

  useEffect(() => {
    void loadNotifications('initial');
  }, [loadNotifications]);

  useEffect(() => {
    const interval = setInterval(() => {
      void loadNotifications('silent');
    }, 15000);
    return () => clearInterval(interval);
  }, [loadNotifications]);

  const filtered = useMemo(() => {
    return events.filter((event) => {
      if (event.dismissed) return false;
      if (typeFilter !== 'all' && event.type !== typeFilter) return false;
      if (readFilter === 'unread' && event.read) return false;
      if (readFilter === 'read' && !event.read) return false;
      if (search) {
        const q = search.toLowerCase();
        const blob = `${event.title} ${event.message} ${event.device_id ?? ''} ${event.actor ?? ''}`.toLowerCase();
        if (!blob.includes(q)) return false;
      }

      if (dateFrom || dateTo) {
        const iso = event.timestamp;
        const parsed = new Date(iso);
        if (Number.isNaN(parsed.getTime())) return false;
        const hhmm = `${String(parsed.getHours()).padStart(2, '0')}:${String(parsed.getMinutes()).padStart(2, '0')}`;
        if (dateFrom && hhmm < dateFrom) return false;
        if (dateTo && hhmm > dateTo) return false;
      }

      return true;
    });
  }, [events, typeFilter, readFilter, search, dateFrom, dateTo]);

  const markRead = async (id: string) => {
    setEvents((prev) => prev.map((event) => (event.id === id ? { ...event, read: true } : event)));
    setUnreadCount((prev) => Math.max(0, prev - 1));
    try {
      const response = await fetch(`/api/notifications/${encodeURIComponent(id)}/read`, {
        method: 'POST',
        credentials: 'include',
      });
      if (!response.ok) {
        throw new Error(`http_${response.status}`);
      }
    } catch (error) {
      console.error('notification-mark-read-failed', error);
      toast.error('Failed to mark notification as read');
      void loadNotifications('silent');
    }
  };

  const markAllRead = async () => {
    try {
      const response = await fetch('/api/notifications', {
        method: 'POST',
        credentials: 'include',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ type: typeFilter, q: search }),
      });
      if (!response.ok) {
        throw new Error(`http_${response.status}`);
      }
      setEvents((prev) => prev.map((event) => ({ ...event, read: true })));
      setUnreadCount(0);
      toast.success('Notifications marked as read');
    } catch (error) {
      console.error('notification-mark-all-read-failed', error);
      toast.error('Failed to mark notifications as read');
      void loadNotifications('silent');
    }
  };

  const dismiss = async (id: string) => {
    setEvents((prev) => prev.filter((event) => event.id !== id));
    try {
      const response = await fetch(`/api/notifications/${encodeURIComponent(id)}`, {
        method: 'DELETE',
        credentials: 'include',
      });
      if (!response.ok) {
        throw new Error(`http_${response.status}`);
      }
    } catch (error) {
      console.error('notification-dismiss-failed', error);
      toast.error('Failed to dismiss notification');
      void loadNotifications('silent');
    }
  };

  const bulkDismiss = async () => {
    const ids = filtered.map((event) => event.id);
    if (ids.length === 0) return;

    setEvents((prev) => prev.filter((event) => !ids.includes(event.id)));
    try {
      await Promise.all(ids.map((id) => fetch(`/api/notifications/${encodeURIComponent(id)}`, {
        method: 'DELETE',
        credentials: 'include',
      })));
      toast.success(`Dismissed ${ids.length} notification${ids.length === 1 ? '' : 's'}`);
    } catch (error) {
      console.error('notification-bulk-dismiss-failed', error);
      toast.error('Failed to dismiss one or more notifications');
      void loadNotifications('silent');
    }
  };

  return (
    <div className="space-y-4 fade-in">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-3">
          <h1 className="text-2xl font-semibold tracking-tight">Notifications</h1>
          {unreadCount > 0 && (
            <span className="text-xs font-semibold px-2 py-0.5 bg-red-500/20 text-red-400 rounded-full">{unreadCount} unread</span>
          )}
        </div>
        <div className="flex items-center gap-2">
          <button
            onClick={() => void loadNotifications('refresh')}
            className="flex items-center gap-1.5 px-3 py-1.5 text-xs text-muted-foreground border border-border rounded-md hover:bg-muted/60 transition-colors"
          >
            <RefreshCw size={13} className={refreshing ? 'animate-spin' : ''} />
            Refresh
          </button>
          <button onClick={() => void markAllRead()} className="flex items-center gap-1.5 px-3 py-1.5 text-xs text-muted-foreground border border-border rounded-md hover:bg-muted/60 transition-colors">
            <CheckCheck size={13} /> Mark All Read
          </button>
          <button onClick={() => void bulkDismiss()} className="flex items-center gap-1.5 px-3 py-1.5 text-xs text-red-400 border border-red-500/20 rounded-md hover:bg-red-500/10 transition-colors">
            <Trash2 size={13} /> Dismiss Filtered
          </button>
        </div>
      </div>

      <div className="flex flex-wrap items-center gap-2">
        <div className="relative">
          <Search size={13} className="absolute left-2.5 top-1/2 -translate-y-1/2 text-muted-foreground" />
          <input
            placeholder="Search notifications..."
            value={search}
            onChange={(event) => setSearch(event.target.value)}
            className="pl-8 pr-3 py-1.5 text-xs bg-muted/60 border border-border rounded-md text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-1 focus:ring-primary/50 w-52"
          />
        </div>

        <div className="flex items-center gap-1">
          {(['all', 'alert', 'command', 'device_state', 'system'] as const).map((type) => (
            <button
              key={type}
              onClick={() => setTypeFilter(type)}
              className={`px-2.5 py-1 text-xs rounded-md transition-colors ${
                typeFilter === type ? 'bg-primary/20 text-primary' : 'text-muted-foreground hover:text-foreground hover:bg-muted/60'
              }`}
            >
              {type === 'all' ? 'All' : type === 'device_state' ? 'Device' : type.charAt(0).toUpperCase() + type.slice(1)}
            </button>
          ))}
        </div>

        <div className="h-4 w-px bg-border" />

        <div className="flex items-center gap-1 bg-muted/30 rounded-md p-0.5">
          {(['all', 'unread', 'read'] as const).map((state) => (
            <button
              key={state}
              onClick={() => setReadFilter(state)}
              className={`px-2.5 py-1 text-xs rounded transition-colors ${
                readFilter === state ? 'bg-card text-foreground shadow-sm' : 'text-muted-foreground hover:text-foreground'
              }`}
            >
              {state.charAt(0).toUpperCase() + state.slice(1)}
            </button>
          ))}
        </div>

        <div className="flex items-center gap-1.5 text-xs text-muted-foreground">
          <Clock size={12} />
          <input
            type="time"
            value={dateFrom}
            onChange={(event) => setDateFrom(event.target.value)}
            className="bg-muted/60 border border-border rounded px-2 py-1 text-xs text-foreground focus:outline-none focus:ring-1 focus:ring-primary/50"
          />
          <span>-</span>
          <input
            type="time"
            value={dateTo}
            onChange={(event) => setDateTo(event.target.value)}
            className="bg-muted/60 border border-border rounded px-2 py-1 text-xs text-foreground focus:outline-none focus:ring-1 focus:ring-primary/50"
          />
        </div>

        {(search || typeFilter !== 'all' || readFilter !== 'all' || dateFrom || dateTo) && (
          <button
            onClick={() => { setSearch(''); setTypeFilter('all'); setReadFilter('all'); setDateFrom(''); setDateTo(''); }}
            className="flex items-center gap-1 text-xs text-muted-foreground hover:text-foreground"
          >
            <X size={12} /> Clear
          </button>
        )}
      </div>

      <div className="space-y-2">
        {loading ? (
          <div className="bg-card border border-border rounded-lg px-4 py-12 text-center text-sm text-muted-foreground">
            Loading notifications...
          </div>
        ) : null}
        {!loading && loadError ? (
          <div className="bg-card border border-red-500/20 rounded-lg px-4 py-3 text-sm text-red-300">
            {loadError}
          </div>
        ) : null}
        {!loading && !loadError && filtered.length === 0 ? (
          <div className="bg-card border border-border rounded-lg px-4 py-12 text-center">
            <Bell size={32} className="mx-auto text-muted-foreground/30 mb-3" />
            <p className="text-sm font-medium text-muted-foreground">No notifications match your filters</p>
          </div>
        ) : null}

        {!loading && !loadError && filtered.map((event) => {
          const cfg = typeConfig[event.type];
          const Icon = cfg.icon;
          return (
            <div
              key={event.id}
              className={`group flex items-start gap-3 bg-card border rounded-lg px-4 py-3 transition-colors cursor-pointer hover:bg-muted/20 ${
                !event.read ? 'border-primary/20 bg-primary/5' : 'border-border'
              }`}
              onClick={() => { if (!event.read) void markRead(event.id); }}
            >
              <div className={`w-8 h-8 rounded-md border flex items-center justify-center ${event.read ? 'border-border bg-muted/20' : 'border-primary/30 bg-primary/10'}`}>
                <Icon size={15} className={cfg.color} />
              </div>

              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-2 flex-wrap">
                  <span className="text-sm font-medium">{event.title}</span>
                  {event.severity && (
                    <span className={`text-[10px] font-semibold px-1.5 py-0.5 rounded border ${severityColors[event.severity] ?? severityColors.info}`}>
                      {event.severity}
                    </span>
                  )}
                  {!event.read && <span className="text-[10px] px-1.5 py-0.5 rounded bg-primary/15 text-primary font-semibold">new</span>}
                </div>
                <p className="text-xs text-muted-foreground mt-0.5">{event.message}</p>
                <div className="mt-1 flex items-center gap-2 text-[11px] text-muted-foreground">
                  <span>{cfg.label}</span>
                  {event.device_id ? <span className="font-mono">{event.device_id}</span> : null}
                  <span>{formatLocalTime(event.timestamp, '--:--:--')}</span>
                </div>
              </div>

              <button
                onClick={(uiEvent) => {
                  uiEvent.stopPropagation();
                  void dismiss(event.id);
                }}
                className="p-1 rounded text-muted-foreground hover:text-foreground hover:bg-muted transition-colors"
              >
                <X size={12} />
              </button>
            </div>
          );
        })}
      </div>
    </div>
  );
}
