import React from 'react';

type Variant =
  | 'online' |'offline' |'quarantined' |'degraded' |'queued' |'dispatched' |'ack_received' |'executing' |'completed' |'failed' |'expired' |'rejected' |'active' |'acknowledged' |'resolved' |'compliant' |'non_compliant' |'drift' |'critical' |'warning' |'info' |'healthy' |'pending';

interface StatusBadgeProps {
  variant: Variant;
  label?: string;
  pulse?: boolean;
  size?: 'sm' | 'md';
}

const variantConfig: Record<Variant, { dot: string; text: string; bg: string; border: string }> = {
  online:       { dot: 'bg-green-400',  text: 'text-green-400',  bg: 'bg-green-500/10',  border: 'border-green-500/20' },
  offline:      { dot: 'bg-zinc-400',   text: 'text-zinc-400',   bg: 'bg-zinc-500/10',   border: 'border-zinc-500/20' },
  quarantined:  { dot: 'bg-red-400',    text: 'text-red-400',    bg: 'bg-red-500/10',    border: 'border-red-500/20' },
  degraded:     { dot: 'bg-amber-400',  text: 'text-amber-400',  bg: 'bg-amber-500/10',  border: 'border-amber-500/20' },
  queued:       { dot: 'bg-zinc-400',   text: 'text-zinc-300',   bg: 'bg-zinc-500/10',   border: 'border-zinc-500/20' },
  dispatched:   { dot: 'bg-blue-400',   text: 'text-blue-400',   bg: 'bg-blue-500/10',   border: 'border-blue-500/20' },
  ack_received: { dot: 'bg-blue-300',   text: 'text-blue-300',   bg: 'bg-blue-500/10',   border: 'border-blue-500/20' },
  executing:    { dot: 'bg-blue-400',   text: 'text-blue-400',   bg: 'bg-blue-500/15',   border: 'border-blue-500/30' },
  completed:    { dot: 'bg-green-400',  text: 'text-green-400',  bg: 'bg-green-500/10',  border: 'border-green-500/20' },
  failed:       { dot: 'bg-red-400',    text: 'text-red-400',    bg: 'bg-red-500/10',    border: 'border-red-500/20' },
  expired:      { dot: 'bg-amber-400',  text: 'text-amber-400',  bg: 'bg-amber-500/10',  border: 'border-amber-500/20' },
  rejected:     { dot: 'bg-red-500',    text: 'text-red-400',    bg: 'bg-red-500/10',    border: 'border-red-500/20' },
  active:       { dot: 'bg-red-400',    text: 'text-red-400',    bg: 'bg-red-500/10',    border: 'border-red-500/20' },
  acknowledged: { dot: 'bg-amber-400',  text: 'text-amber-400',  bg: 'bg-amber-500/10',  border: 'border-amber-500/20' },
  resolved:     { dot: 'bg-green-400',  text: 'text-green-400',  bg: 'bg-green-500/10',  border: 'border-green-500/20' },
  compliant:    { dot: 'bg-green-400',  text: 'text-green-400',  bg: 'bg-green-500/10',  border: 'border-green-500/20' },
  non_compliant:{ dot: 'bg-red-400',    text: 'text-red-400',    bg: 'bg-red-500/10',    border: 'border-red-500/20' },
  drift:        { dot: 'bg-amber-400',  text: 'text-amber-400',  bg: 'bg-amber-500/10',  border: 'border-amber-500/20' },
  critical:     { dot: 'bg-red-400',    text: 'text-red-400',    bg: 'bg-red-500/10',    border: 'border-red-500/20' },
  warning:      { dot: 'bg-amber-400',  text: 'text-amber-400',  bg: 'bg-amber-500/10',  border: 'border-amber-500/20' },
  info:         { dot: 'bg-blue-400',   text: 'text-blue-400',   bg: 'bg-blue-500/10',   border: 'border-blue-500/20' },
  healthy:      { dot: 'bg-green-400',  text: 'text-green-400',  bg: 'bg-green-500/10',  border: 'border-green-500/20' },
  pending:      { dot: 'bg-zinc-400',   text: 'text-zinc-300',   bg: 'bg-zinc-500/10',   border: 'border-zinc-500/20' },
};

const labelMap: Record<Variant, string> = {
  online: 'Online', offline: 'Offline', quarantined: 'Quarantined', degraded: 'Degraded',
  queued: 'Queued', dispatched: 'Dispatched', ack_received: 'ACK Received', executing: 'Executing',
  completed: 'Completed', failed: 'Failed', expired: 'Expired', rejected: 'Rejected',
  active: 'Active', acknowledged: 'Acknowledged', resolved: 'Resolved',
  compliant: 'Compliant', non_compliant: 'Non-Compliant', drift: 'Drift',
  critical: 'Critical', warning: 'Warning', info: 'Info', healthy: 'Healthy', pending: 'Pending',
};

export default function StatusBadge({ variant, label, pulse, size = 'sm' }: StatusBadgeProps) {
  const cfg = variantConfig[variant];
  const displayLabel = label ?? labelMap[variant];

  return (
    <span
      className={`inline-flex items-center gap-1.5 rounded-full border font-medium ${cfg.bg} ${cfg.border} ${cfg.text} ${
        size === 'sm' ? 'text-[11px] px-2 py-0.5' : 'text-xs px-2.5 py-1'
      }`}
    >
      <span className={`w-1.5 h-1.5 rounded-full flex-shrink-0 ${cfg.dot} ${pulse ? 'pulse-dot' : ''}`} />
      {displayLabel}
    </span>
  );
}