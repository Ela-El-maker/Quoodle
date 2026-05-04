'use client';
import React from 'react';
import Link from 'next/link';
import { XCircle, Shield, ChevronRight } from 'lucide-react';
import StatusBadge from '@/components/ui/StatusBadge';

export interface FailingCommandItem {
  id: string;
  device: string;
  method: string;
  errorCode: string | null;
  errorMsg: string;
  failedAt: string;
}

export interface AttentionDeviceItem {
  id: string;
  name: string;
  status: 'quarantined' | 'degraded';
  reason: string;
  since: string;
}

interface DashboardNeedsAttentionProps {
  failingCommands?: FailingCommandItem[];
  attentionDevices?: AttentionDeviceItem[];
  loading?: boolean;
  error?: string | null;
}

export default function DashboardNeedsAttention({
  failingCommands = [],
  attentionDevices = [],
  loading,
  error,
}: DashboardNeedsAttentionProps) {
  const showFailingEmpty = !loading && !error && failingCommands.length === 0;
  const showAttentionEmpty = !loading && !error && attentionDevices.length === 0;

  return (
    <div className="space-y-4">
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
          {loading && (
            <div className="px-4 py-6 text-[11px] text-muted-foreground">Loading data...</div>
          )}
          {!loading && error && (
            <div className="px-4 py-6 text-[11px] text-red-400">{error}</div>
          )}
          {showFailingEmpty && (
            <div className="px-4 py-6 text-[11px] text-muted-foreground">No failing commands</div>
          )}
          {!loading && !error && failingCommands.map((cmd) => (
            <div key={`failing-${cmd.id}`} className="flex items-center gap-3 px-4 py-3 hover:bg-muted/30 transition-colors group">
              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-2 mb-0.5">
                  <span className="font-mono text-[11px] text-muted-foreground">{cmd.id}</span>
                  <span className="text-xs font-medium">{cmd.device}</span>
                  <span className="text-[11px] text-muted-foreground">-</span>
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

      <div className="bg-card border border-amber-500/20 rounded-lg overflow-hidden">
        <div className="flex items-center justify-between px-4 py-3 border-b border-border">
          <div className="flex items-center gap-2">
            <Shield size={14} className="text-amber-400" />
            <h3 className="text-sm font-semibold text-amber-400">Devices Needing Attention</h3>
            <span className="text-[10px] bg-amber-500/20 text-amber-400 px-1.5 py-0.5 rounded-full font-semibold">
              {attentionDevices.length}
            </span>
          </div>
          <Link href="/device-management?status=degraded,quarantined" className="text-[11px] text-muted-foreground hover:text-foreground flex items-center gap-0.5 transition-colors">
            View all <ChevronRight size={11} />
          </Link>
        </div>
        <div className="divide-y divide-border">
          {loading && (
            <div className="px-4 py-6 text-[11px] text-muted-foreground">Loading data...</div>
          )}
          {!loading && error && (
            <div className="px-4 py-6 text-[11px] text-red-400">{error}</div>
          )}
          {showAttentionEmpty && (
            <div className="px-4 py-6 text-[11px] text-muted-foreground">No data available</div>
          )}
          {!loading && !error && attentionDevices.map((device) => (
            <div key={`attention-${device.id}`} className="flex items-center gap-3 px-4 py-3 hover:bg-muted/30 transition-colors group">
              <StatusBadge variant={device.status} />
              <div className="flex-1 min-w-0">
                <p className="text-xs font-medium">{device.name}</p>
                <p className="text-[11px] text-muted-foreground truncate">{device.reason}</p>
              </div>
              <div className="flex items-center gap-2 flex-shrink-0">
                <span className="text-[10px] text-muted-foreground tabular-nums">{device.since}</span>
                <Link
                  href={`/device-detail?device=${encodeURIComponent(device.id)}`}
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
