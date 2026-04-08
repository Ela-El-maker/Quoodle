'use client';
import React, { useState } from 'react';
import { X, Shield, AlertTriangle, Activity, Bell, Info, CheckCheck, ChevronRight, Terminal } from 'lucide-react';
import StatusBadge from '@/components/ui/StatusBadge';
import Link from 'next/link';
import { toast } from 'sonner';

interface Alert {
  id: string;
  severity: 'critical' | 'warning' | 'info';
  type: string;
  deviceId: string;
  hostname: string;
  description: string;
  triggeredAt: string;
  status: 'active' | 'acknowledged' | 'resolved';
  acknowledgedBy: string | null;
  correlationId: string;
}

interface AlertDetailDrawerProps {
  alert: Alert;
  onClose: () => void;
  onAcknowledge: (alert: Alert) => void;
}

export default function AlertDetailDrawer({ alert, onClose, onAcknowledge }: AlertDetailDrawerProps) {
  const [rationale, setRationale] = useState('');
  const [acknowledging, setAcknowledging] = useState(false);

  const handleAcknowledge = async () => {
    if (!rationale.trim()) {
      toast.error('Please provide a rationale before acknowledging');
      return;
    }
    setAcknowledging(true);
    await new Promise((r) => setTimeout(r, 800));
    setAcknowledging(false);
    onAcknowledge(alert);
    onClose();
  };

  const iconMap: Record<string, React.ElementType> = {
    attestation_failure: Shield,
    compliance_violation: Shield,
    policy_drift: Shield,
    telemetry_anomaly: Activity,
    device_offline: Bell,
    command_failure: AlertTriangle,
    command_expired: AlertTriangle,
    device_online: Info,
    policy_sync: Info,
    kernel_guard_missing: AlertTriangle,
  };
  const IconComp = iconMap[alert.type] ?? Bell;

  const severityBg = alert.severity === 'critical' ? 'border-red-500/30 bg-red-500/5' :
                     alert.severity === 'warning'? 'border-amber-500/30 bg-amber-500/5' : 'border-blue-500/30 bg-blue-500/5';

  return (
    <>
      <div className="fixed inset-0 bg-black/40 z-40" onClick={onClose} />
      <div className="fixed inset-y-0 right-0 w-full max-w-md bg-zinc-950 border-l border-border z-50 flex flex-col slide-in-right">
        {/* Header */}
        <div className={`flex items-start justify-between px-5 py-4 border-b border-border ${severityBg}`}>
          <div className="flex items-start gap-3">
            <div className={`w-9 h-9 rounded-lg flex items-center justify-center flex-shrink-0 ${
              alert.severity === 'critical' ? 'bg-red-500/20' :
              alert.severity === 'warning'  ? 'bg-amber-500/20' : 'bg-blue-500/20'
            }`}>
              <IconComp size={16} className={
                alert.severity === 'critical' ? 'text-red-400' :
                alert.severity === 'warning'  ? 'text-amber-400' : 'text-blue-400'
              } />
            </div>
            <div>
              <div className="flex items-center gap-2 mb-0.5">
                <h2 className="font-semibold text-sm font-mono">{alert.id}</h2>
                <StatusBadge variant={alert.severity} />
              </div>
              <p className="text-[11px] text-muted-foreground">{alert.type.replace(/_/g, ' ')}</p>
            </div>
          </div>
          <button onClick={onClose} className="p-1.5 rounded-md text-muted-foreground hover:text-foreground hover:bg-muted/40 transition-colors">
            <X size={15} />
          </button>
        </div>

        <div className="flex-1 overflow-y-auto scrollbar-thin p-5 space-y-4">
          {/* Description */}
          <div className="bg-muted/30 rounded-lg p-3">
            <p className="text-[10px] text-muted-foreground uppercase tracking-wide mb-1.5">Description</p>
            <p className="text-xs leading-relaxed">{alert.description}</p>
          </div>

          {/* Context */}
          <div className="grid grid-cols-2 gap-2">
            {[
              { label: 'Device', value: alert.hostname },
              { label: 'Device ID', value: alert.deviceId, mono: true },
              { label: 'Triggered', value: alert.triggeredAt + ' UTC' },
              { label: 'Correlation ID', value: alert.correlationId, mono: true },
              { label: 'Status', value: alert.status },
              { label: 'Acknowledged By', value: alert.acknowledgedBy ?? '—' },
            ].map((item) => (
              <div key={`alert-meta-${item.label}`} className="bg-muted/30 rounded-lg p-2.5">
                <p className="text-[10px] text-muted-foreground uppercase tracking-wide mb-1">{item.label}</p>
                <p className={`text-xs font-medium truncate ${item.mono ? 'font-mono' : ''}`}>{item.value}</p>
              </div>
            ))}
          </div>

          {/* Device context links */}
          <div className="space-y-1.5">
            <p className="text-[10px] text-muted-foreground uppercase tracking-wide">Investigate</p>
            <Link
              href={`/device-management?id=${alert.deviceId}`}
              className="flex items-center justify-between px-3 py-2.5 bg-muted/30 rounded-lg hover:bg-muted/50 transition-colors group"
            >
              <span className="text-xs font-medium">View Device Detail — {alert.hostname}</span>
              <ChevronRight size={13} className="text-muted-foreground group-hover:text-foreground transition-colors" />
            </Link>
            <Link
              href={`/telemetry-monitoring?device=${alert.deviceId}`}
              className="flex items-center justify-between px-3 py-2.5 bg-muted/30 rounded-lg hover:bg-muted/50 transition-colors group"
            >
              <span className="text-xs font-medium">Telemetry Timeline</span>
              <ChevronRight size={13} className="text-muted-foreground group-hover:text-foreground transition-colors" />
            </Link>
            <Link
              href={`/command-dispatch?device=${alert.deviceId}`}
              className="flex items-center justify-between px-3 py-2.5 bg-muted/30 rounded-lg hover:bg-muted/50 transition-colors group"
            >
              <div className="flex items-center gap-2">
                <Terminal size={12} className="text-muted-foreground" />
                <span className="text-xs font-medium">Dispatch Remediation Command</span>
              </div>
              <ChevronRight size={13} className="text-muted-foreground group-hover:text-foreground transition-colors" />
            </Link>
          </div>

          {/* Acknowledge form */}
          {alert.status === 'active' && (
            <div className="bg-muted/20 border border-border rounded-lg p-3 space-y-3">
              <p className="text-xs font-semibold">Acknowledge Alert</p>
              <div>
                <label className="block text-[11px] text-muted-foreground mb-1.5">
                  Rationale <span className="text-red-400">*</span>
                </label>
                <textarea
                  value={rationale}
                  onChange={(e) => setRationale(e.target.value)}
                  rows={3}
                  placeholder="Describe your investigation finding or remediation action…"
                  className="w-full text-xs bg-muted/60 border border-border rounded-md px-3 py-2 text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-1 focus:ring-primary/50 resize-none"
                />
              </div>
              <button
                onClick={handleAcknowledge}
                disabled={acknowledging || !rationale.trim()}
                className="w-full flex items-center justify-center gap-2 py-2 text-xs font-medium bg-green-500/10 border border-green-500/20 text-green-400 rounded-md hover:bg-green-500/20 disabled:opacity-50 transition-colors"
              >
                {acknowledging ? (
                  <span className="w-3 h-3 border border-green-400 border-t-transparent rounded-full animate-spin" />
                ) : (
                  <CheckCheck size={13} />
                )}
                {acknowledging ? 'Acknowledging…' : 'Acknowledge Alert'}
              </button>
            </div>
          )}
        </div>
      </div>
    </>
  );
}