'use client';
import React from 'react';
import Link from 'next/link';
import { XCircle, Shield, ChevronRight } from 'lucide-react';
import StatusBadge from '@/components/ui/StatusBadge';

// Backend integration point: GET /api/dashboard/attention-items
const failingCommands = [
  { id: 'CMD-7741', device: 'WKSTN-042', method: 'lock_screen', errorCode: 4004, errorMsg: 'Kernel opcode not supported', failedAt: '21:02:11' },
  { id: 'CMD-7738', device: 'SRV-PROD-01', method: 'ping', errorCode: null, errorMsg: 'TTL exceeded — dispatch timeout', failedAt: '20:58:44' },
  { id: 'CMD-7729', device: 'WKSTN-019', method: 'lock_screen', errorCode: null, errorMsg: 'Agent disconnected during execution', failedAt: '20:47:22' },
];

const degradedDevices = [
  { id: 'dev-quarantined-04', name: 'SRV-PROD-04', status: 'quarantined' as const, reason: 'Attestation hash mismatch detected', since: '19:14:00' },
  { id: 'dev-degraded-07', name: 'WKSTN-007', status: 'degraded' as const, reason: 'CPU sustained >90% for 12 min', since: '20:51:33' },
  { id: 'dev-degraded-11', name: 'WKSTN-011', status: 'degraded' as const, reason: 'Policy hash out of sync (drift)', since: '21:00:05' },
];

export default function DashboardNeedsAttention() {
  return (
    <div className="space-y-4">
      {/* Failing commands */}
      <div className="bg-card border border-red-500/20 rounded-lg overflow-hidden">
        <div className="flex items-center justify-between px-4 py-3 border-b border-border">
          <div className="flex items-center gap-2">
            <XCircle size={14} className="text-red-400" />
            <h3 className="text-sm font-semibold text-red-400">Failing Commands</h3>
            <span className="text-[10px] bg-red-500/20 text-red-400 px-1.5 py-0.5 rounded-full font-semibold">
              {failingCommands.length}
            </span>
          </div>
          <Link href="/command-dispatch?state=failed" className="text-[11px] text-muted-foreground hover:text-foreground flex items-center gap-0.5 transition-colors">
            View all <ChevronRight size={11} />
          </Link>
        </div>
        <div className="divide-y divide-border">
          {failingCommands.map((cmd) => (
            <div key={`failing-${cmd.id}`} className="flex items-center gap-3 px-4 py-3 hover:bg-muted/30 transition-colors group">
              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-2 mb-0.5">
                  <span className="font-mono text-[11px] text-muted-foreground">{cmd.id}</span>
                  <span className="text-xs font-medium">{cmd.device}</span>
                  <span className="text-[11px] text-muted-foreground">·</span>
                  <span className="text-[11px] text-blue-400 font-mono">{cmd.method}</span>
                </div>
                <p className="text-[11px] text-red-400 truncate">{cmd.errorMsg}</p>
              </div>
              <div className="flex items-center gap-2 flex-shrink-0">
                {cmd.errorCode && (
                  <span className="font-mono text-[10px] text-muted-foreground bg-muted px-1.5 py-0.5 rounded">
                    {cmd.errorCode}
                  </span>
                )}
                <span className="text-[10px] text-muted-foreground tabular-nums">{cmd.failedAt}</span>
                <Link
                  href={`/command-dispatch?id=${cmd.id}`}
                  className="opacity-0 group-hover:opacity-100 text-[11px] text-primary transition-opacity"
                >
                  <ChevronRight size={13} />
                </Link>
              </div>
            </div>
          ))}
        </div>
      </div>

      {/* Degraded/quarantined devices */}
      <div className="bg-card border border-amber-500/20 rounded-lg overflow-hidden">
        <div className="flex items-center justify-between px-4 py-3 border-b border-border">
          <div className="flex items-center gap-2">
            <Shield size={14} className="text-amber-400" />
            <h3 className="text-sm font-semibold text-amber-400">Devices Needing Attention</h3>
            <span className="text-[10px] bg-amber-500/20 text-amber-400 px-1.5 py-0.5 rounded-full font-semibold">
              {degradedDevices.length}
            </span>
          </div>
          <Link href="/device-management?status=degraded,quarantined" className="text-[11px] text-muted-foreground hover:text-foreground flex items-center gap-0.5 transition-colors">
            View all <ChevronRight size={11} />
          </Link>
        </div>
        <div className="divide-y divide-border">
          {degradedDevices.map((device) => (
            <div key={`attention-${device.id}`} className="flex items-center gap-3 px-4 py-3 hover:bg-muted/30 transition-colors group">
              <StatusBadge variant={device.status} />
              <div className="flex-1 min-w-0">
                <p className="text-xs font-medium">{device.name}</p>
                <p className="text-[11px] text-muted-foreground truncate">{device.reason}</p>
              </div>
              <div className="flex items-center gap-2 flex-shrink-0">
                <span className="text-[10px] text-muted-foreground tabular-nums">since {device.since}</span>
                <Link
                  href={`/device-management?id=${device.id}`}
                  className="opacity-0 group-hover:opacity-100 text-[11px] text-primary transition-opacity"
                >
                  <ChevronRight size={13} />
                </Link>
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}