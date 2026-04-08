'use client';
import React, { useState, useEffect, useRef } from 'react';
import { Bell, CheckCheck, Trash2, Clock, AlertTriangle, Terminal, Monitor, Wifi, X, Search } from 'lucide-react';
import { toast } from 'sonner';
import Icon from '@/components/ui/AppIcon';


type EventType = 'alert' | 'command' | 'device_state' | 'system';
type ReadState = 'all' | 'unread' | 'read';

interface NotificationEvent {
  id: string;
  type: EventType;
  title: string;
  message: string;
  device?: string;
  actor?: string;
  timestamp: string;
  read: boolean;
  severity?: 'critical' | 'high' | 'medium' | 'low' | 'info';
}

const mockEvents: NotificationEvent[] = [
  { id: 'n-1',  type: 'alert',        title: 'Critical: Kernel Guard Disabled',      message: 'SRV-PROD-04 kernel guard has been disabled. Immediate remediation required.',  device: 'SRV-PROD-04', actor: 'system',                    timestamp: '21:06:11', read: false, severity: 'critical' },
  { id: 'n-2',  type: 'command',      title: 'Command Completed: ping',              message: 'CMD-7742 executed successfully on WKSTN-055.',                                   device: 'WKSTN-055',   actor: 'chloe.dubois@quoodle.io',   timestamp: '21:06:09', read: false, severity: 'info' },
  { id: 'n-3',  type: 'device_state', title: 'Device Went Offline',                  message: 'WKSTN-019 lost connection. Last seen 21:05:44.',                                  device: 'WKSTN-019',   actor: 'system',                    timestamp: '21:05:44', read: false, severity: 'high' },
  { id: 'n-4',  type: 'alert',        title: 'Policy Drift Detected',                message: 'SRV-PROD-01 policy hash mismatch. Expected sha256:policy123, got sha256:abc.',   device: 'SRV-PROD-01', actor: 'system',                    timestamp: '21:05:30', read: true,  severity: 'medium' },
  { id: 'n-5',  type: 'command',      title: 'Command Failed: lock_screen',          message: 'CMD-7741 failed on WKSTN-042. Kernel opcode not supported (4004).',              device: 'WKSTN-042',   actor: 'raj.mehta@quoodle.io',      timestamp: '21:01:55', read: true,  severity: 'high' },
  { id: 'n-6',  type: 'system',       title: 'Agent Version Mismatch',               message: 'WKSTN-103 running agent v0.0.1-beta. Upgrade recommended.',                      device: 'WKSTN-103',   actor: 'system',                    timestamp: '21:00:00', read: true,  severity: 'medium' },
  { id: 'n-7',  type: 'command',      title: 'Command Dispatched: lock_screen',      message: 'CMD-7740 dispatched to WKSTN-042. Awaiting acknowledgment.',                     device: 'WKSTN-042',   actor: 'ops.team@quoodle.io',       timestamp: '21:04:50', read: false, severity: 'info' },
  { id: 'n-8',  type: 'alert',        title: 'High Risk Score Threshold Exceeded',   message: 'SRV-PROD-04 risk score reached 89/100. Quarantine policy triggered.',            device: 'SRV-PROD-04', actor: 'system',                    timestamp: '20:58:00', read: true,  severity: 'critical' },
  { id: 'n-9',  type: 'device_state', title: 'Device Quarantined',                   message: 'SRV-PROD-04 moved to quarantine state by automated policy enforcement.',         device: 'SRV-PROD-04', actor: 'policy-engine',             timestamp: '20:57:45', read: true,  severity: 'critical' },
  { id: 'n-10', type: 'command',      title: 'Command Expired: ping',                message: 'CMD-7738 TTL exceeded on SRV-PROD-01. Device unreachable during dispatch.',      device: 'SRV-PROD-01', actor: 'devops@quoodle.io',         timestamp: '20:55:00', read: true,  severity: 'medium' },
  { id: 'n-11', type: 'system',       title: 'Compliance Drift: 3 Devices',          message: 'WKSTN-007, WKSTN-011, WKSTN-103 have drifted from baseline compliance.',        device: undefined,     actor: 'compliance-engine',         timestamp: '20:50:00', read: true,  severity: 'medium' },
  { id: 'n-12', type: 'device_state', title: 'New Device Paired',                    message: 'WKSTN-088 successfully paired by tom.brennan@quoodle.io.',                       device: 'WKSTN-088',   actor: 'tom.brennan@quoodle.io',    timestamp: '20:45:00', read: true,  severity: 'info' },
];

const typeConfig: Record<EventType, { icon: React.ElementType; color: string; label: string }> = {
  alert:        { icon: AlertTriangle, color: 'text-red-400',    label: 'Alert' },
  command:      { icon: Terminal,      color: 'text-blue-400',   label: 'Command' },
  device_state: { icon: Monitor,       color: 'text-amber-400',  label: 'Device' },
  system:       { icon: Wifi,          color: 'text-violet-400', label: 'System' },
};

const severityColors: Record<string, string> = {
  critical: 'bg-red-500/10 text-red-400 border-red-500/20',
  high:     'bg-orange-500/10 text-orange-400 border-orange-500/20',
  medium:   'bg-amber-500/10 text-amber-400 border-amber-500/20',
  low:      'bg-blue-500/10 text-blue-400 border-blue-500/20',
  info:     'bg-muted text-muted-foreground border-border',
};

export default function NotificationsContent() {
  const [events, setEvents] = useState<NotificationEvent[]>(mockEvents);
  const [typeFilter, setTypeFilter] = useState<EventType | 'all'>('all');
  const [readFilter, setReadFilter] = useState<ReadState>('all');
  const [search, setSearch] = useState('');
  const [dateFrom, setDateFrom] = useState('');
  const [dateTo, setDateTo] = useState('');
  const [wsConnected, setWsConnected] = useState(true);
  const intervalRef = useRef<ReturnType<typeof setInterval> | null>(null);

  // Simulate live WebSocket feed
  useEffect(() => {
    intervalRef.current = setInterval(() => {
      const types: EventType[] = ['alert', 'command', 'device_state', 'system'];
      const t = types[Math.floor(Math.random() * types.length)];
      const newEvent: NotificationEvent = {
        id: `n-live-${Date.now()}`,
        type: t,
        title: t === 'command' ? 'Command Status Update' : t === 'alert' ? 'New Alert Received' : t === 'device_state' ? 'Device State Changed' : 'System Event',
        message: `Live event from WebSocket feed at ${new Date().toLocaleTimeString()}`,
        device: 'WKSTN-042',
        actor: 'system',
        timestamp: new Date().toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit', second: '2-digit' }),
        read: false,
        severity: 'info',
      };
      setEvents((prev) => [newEvent, ...prev.slice(0, 49)]);
    }, 15000);
    return () => { if (intervalRef.current) clearInterval(intervalRef.current); };
  }, []);

  const filtered = events.filter((e) => {
    if (typeFilter !== 'all' && e.type !== typeFilter) return false;
    if (readFilter === 'unread' && e.read) return false;
    if (readFilter === 'read' && !e.read) return false;
    if (search && !e.title.toLowerCase().includes(search.toLowerCase()) && !e.message.toLowerCase().includes(search.toLowerCase())) return false;
    return true;
  });

  const unreadCount = events.filter((e) => !e.read).length;

  const markRead = (id: string) => setEvents((prev) => prev.map((e) => e.id === id ? { ...e, read: true } : e));
  const markAllRead = () => setEvents((prev) => prev.map((e) => ({ ...e, read: true })));
  const dismiss = (id: string) => setEvents((prev) => prev.filter((e) => e.id !== id));
  const bulkDismiss = () => {
    const ids = new Set(filtered.map((e) => e.id));
    setEvents((prev) => prev.filter((e) => !ids.has(e.id)));
    toast.success(`Dismissed ${ids.size} notification${ids.size !== 1 ? 's' : ''}`);
  };

  return (
    <div className="space-y-4 fade-in">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-3">
          <h1 className="text-2xl font-semibold tracking-tight">Notifications</h1>
          {unreadCount > 0 && (
            <span className="text-xs font-semibold px-2 py-0.5 bg-red-500/20 text-red-400 rounded-full">{unreadCount} unread</span>
          )}
        </div>
        <div className="flex items-center gap-2">
          <div className={`flex items-center gap-1.5 text-xs px-2 py-1 rounded-md ${wsConnected ? 'text-green-400 bg-green-500/10' : 'text-muted-foreground bg-muted/60'}`}>
            <span className={`w-1.5 h-1.5 rounded-full ${wsConnected ? 'bg-green-400 animate-pulse' : 'bg-muted-foreground'}`} />
            {wsConnected ? 'Live Feed' : 'Disconnected'}
          </div>
          <button onClick={markAllRead} className="flex items-center gap-1.5 px-3 py-1.5 text-xs text-muted-foreground border border-border rounded-md hover:bg-muted/60 transition-colors">
            <CheckCheck size={13} /> Mark All Read
          </button>
          <button onClick={bulkDismiss} className="flex items-center gap-1.5 px-3 py-1.5 text-xs text-red-400 border border-red-500/20 rounded-md hover:bg-red-500/10 transition-colors">
            <Trash2 size={13} /> Dismiss Filtered
          </button>
        </div>
      </div>

      {/* Filters */}
      <div className="flex flex-wrap items-center gap-2">
        <div className="relative">
          <Search size={13} className="absolute left-2.5 top-1/2 -translate-y-1/2 text-muted-foreground" />
          <input
            placeholder="Search notifications…"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="pl-8 pr-3 py-1.5 text-xs bg-muted/60 border border-border rounded-md text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-1 focus:ring-primary/50 w-52"
          />
        </div>

        {/* Type facets */}
        <div className="flex items-center gap-1">
          {(['all', 'alert', 'command', 'device_state', 'system'] as const).map((t) => (
            <button
              key={t}
              onClick={() => setTypeFilter(t)}
              className={`px-2.5 py-1 text-xs rounded-md transition-colors ${
                typeFilter === t ? 'bg-primary/20 text-primary' : 'text-muted-foreground hover:text-foreground hover:bg-muted/60'
              }`}
            >
              {t === 'all' ? 'All' : t === 'device_state' ? 'Device' : t.charAt(0).toUpperCase() + t.slice(1)}
              <span className="ml-1 text-[10px] tabular-nums">
                ({t === 'all' ? events.length : events.filter((e) => e.type === t).length})
              </span>
            </button>
          ))}
        </div>

        <div className="h-4 w-px bg-border" />

        {/* Read state toggle */}
        <div className="flex items-center gap-1 bg-muted/30 rounded-md p-0.5">
          {(['all', 'unread', 'read'] as ReadState[]).map((r) => (
            <button
              key={r}
              onClick={() => setReadFilter(r)}
              className={`px-2.5 py-1 text-xs rounded transition-colors ${
                readFilter === r ? 'bg-card text-foreground shadow-sm' : 'text-muted-foreground hover:text-foreground'
              }`}
            >
              {r.charAt(0).toUpperCase() + r.slice(1)}
            </button>
          ))}
        </div>

        {/* Time range */}
        <div className="flex items-center gap-1.5 text-xs text-muted-foreground">
          <Clock size={12} />
          <input
            type="time"
            value={dateFrom}
            onChange={(e) => setDateFrom(e.target.value)}
            className="bg-muted/60 border border-border rounded px-2 py-1 text-xs text-foreground focus:outline-none focus:ring-1 focus:ring-primary/50"
          />
          <span>–</span>
          <input
            type="time"
            value={dateTo}
            onChange={(e) => setDateTo(e.target.value)}
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

      {/* Event stream */}
      <div className="space-y-2">
        {filtered.length === 0 ? (
          <div className="bg-card border border-border rounded-lg px-4 py-12 text-center">
            <Bell size={32} className="mx-auto text-muted-foreground/30 mb-3" />
            <p className="text-sm font-medium text-muted-foreground">No notifications match your filters</p>
          </div>
        ) : (
          filtered.map((event) => {
            const cfg = typeConfig[event.type];
            const Icon = cfg.icon;
            return (
              <div
                key={event.id}
                className={`group flex items-start gap-3 bg-card border rounded-lg px-4 py-3 transition-colors cursor-pointer hover:bg-muted/20 ${
                  !event.read ? 'border-primary/20 bg-primary/5' : 'border-border'
                }`}
                onClick={() => markRead(event.id)}
              >
                <div className={`w-8 h-8 rounded-lg flex items-center justify-center flex-shrink-0 mt-0.5 ${
                  event.type === 'alert' ? 'bg-red-500/10' :
                  event.type === 'command' ? 'bg-blue-500/10' :
                  event.type === 'device_state' ? 'bg-amber-500/10' : 'bg-violet-500/10'
                }`}>
                  <Icon size={14} className={cfg.color} />
                </div>
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2 flex-wrap">
                    <span className="text-sm font-medium">{event.title}</span>
                    {event.severity && (
                      <span className={`text-[10px] font-semibold uppercase tracking-wider px-1.5 py-0.5 rounded-full border ${severityColors[event.severity]}`}>
                        {event.severity}
                      </span>
                    )}
                    {!event.read && <span className="w-1.5 h-1.5 rounded-full bg-primary flex-shrink-0" />}
                  </div>
                  <p className="text-xs text-muted-foreground mt-0.5 line-clamp-2">{event.message}</p>
                  <div className="flex items-center gap-3 mt-1.5 text-[11px] text-muted-foreground">
                    {event.device && <span className="font-mono">{event.device}</span>}
                    {event.actor && <span>{event.actor}</span>}
                    <span className="flex items-center gap-1"><Clock size={10} /> {event.timestamp}</span>
                  </div>
                </div>
                <button
                  onClick={(e) => { e.stopPropagation(); dismiss(event.id); }}
                  className="p-1 text-muted-foreground hover:text-foreground opacity-0 group-hover:opacity-100 transition-all flex-shrink-0"
                >
                  <X size={13} />
                </button>
              </div>
            );
          })
        )}
      </div>
    </div>
  );
}
