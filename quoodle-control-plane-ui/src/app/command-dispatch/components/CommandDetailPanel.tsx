'use client';
import React from 'react';
import { X, Clock, CheckCircle2, XCircle, RotateCcw, Hash } from 'lucide-react';
import StatusBadge from '@/components/ui/StatusBadge';
import { toast } from 'sonner';

interface Command {
  id: string;
  traceId: string;
  deviceId: string;
  hostname: string;
  method: string;
  state: 'queued' | 'dispatched' | 'ack_received' | 'executing' | 'completed' | 'failed' | 'expired' | 'rejected';
  actor: string;
  queuedAt: string;
  ackAt: string | null;
  completedAt: string | null;
  errorCode: number | null;
  errorMessage: string | null;
  priority: string;
  requires2fa: boolean;
}

interface CommandDetailPanelProps {
  command: Command;
  onClose: () => void;
}

const stateOrder: Command['state'][] = ['queued', 'dispatched', 'ack_received', 'executing', 'completed'];

export default function CommandDetailPanel({ command, onClose }: CommandDetailPanelProps) {
  const currentIndex = stateOrder.indexOf(command.state);
  const isFailed = command.state === 'failed' || command.state === 'expired' || command.state === 'rejected';

  const timelineSteps = [
    { state: 'queued' as const,      label: 'Queued',      time: command.queuedAt, desc: `Dispatched by ${command.actor}` },
    { state: 'dispatched' as const,  label: 'Dispatched',  time: command.queuedAt ? '—' : null, desc: 'Sent to FastAPI gateway' },
    { state: 'ack_received' as const,label: 'ACK Received',time: command.ackAt, desc: 'Agent acknowledged receipt' },
    { state: 'executing' as const,   label: 'Executing',   time: null, desc: 'Running on device' },
    { state: 'completed' as const,   label: 'Completed',   time: command.completedAt, desc: 'Terminal state' },
  ];

  return (
    <>
      <div className="fixed inset-0 bg-black/40 z-40" onClick={onClose} />
      <div className="fixed inset-y-0 right-0 w-fullmax-w-md bg-zinc-950 border-l border-border z-50 flex flex-col slide-in-right">
        {/* Header */}
        <div className="flex items-start justify-between px-5 py-4 border-b border-border">
          <div>
            <div className="flex items-center gap-2 mb-1">
              <h2 className="font-semibold text-sm font-mono">{command.id}</h2>
              <StatusBadge variant={command.state} />
            </div>
            <p className="text-[11px] text-muted-foreground font-mono">Trace: {command.traceId}</p>
          </div>
          <button onClick={onClose} className="p-1.5 rounded-md text-muted-foreground hover:text-foreground hover:bg-muted transition-colors">
            <X size={15} />
          </button>
        </div>

        <div className="flex-1 overflow-y-auto scrollbar-thin p-5 space-y-5">
          {/* Meta */}
          <div className="grid grid-cols-2 gap-2">
            {[
              { label: 'Device', value: command.hostname },
              { label: 'Method', value: command.method, mono: true },
              { label: 'Actor', value: command.actor },
              { label: 'Priority', value: command.priority },
              { label: 'Requires 2FA', value: command.requires2fa ? 'Yes' : 'No' },
              { label: 'Device ID', value: command.deviceId, mono: true },
            ].map((item) => (
              <div key={`meta-${item.label}`} className="bg-muted/30 rounded-lg p-2.5">
                <p className="text-[10px] text-muted-foreground uppercase tracking-wide mb-1">{item.label}</p>
                <p className={`text-xs font-medium truncate ${item.mono ? 'font-mono' : ''}`}>{item.value}</p>
              </div>
            ))}
          </div>

          {/* Timeline */}
          <div>
            <h3 className="text-xs font-semibold mb-3 text-muted-foreground uppercase tracking-wide">Execution Timeline</h3>
            <div className="space-y-0">
              {timelineSteps.map((step, index) => {
                const isReached = !isFailed && currentIndex >= index;
                const isActive = !isFailed && currentIndex === index;
                const isFinalFailed = isFailed && index === currentIndex;

                return (
                  <div key={`timeline-${step.state}`} className="flex gap-3">
                    {/* Line + dot */}
                    <div className="flex flex-col items-center">
                      <div className={`w-6 h-6 rounded-full border-2 flex items-center justify-center flex-shrink-0 ${
                        isFinalFailed
                          ? 'border-red-500 bg-red-500/10'
                          : isActive
                          ? 'border-primary bg-primary/10'
                          : isReached
                          ? 'border-green-500 bg-green-500/10' :'border-border bg-muted/20'
                      }`}>
                        {isReached && !isActive ? (
                          <CheckCircle2 size={12} className="text-green-400" />
                        ) : isActive ? (
                          <span className="w-2 h-2 rounded-full bg-primary pulse-dot" />
                        ) : isFinalFailed ? (
                          <XCircle size={12} className="text-red-400" />
                        ) : (
                          <Clock size={10} className="text-muted-foreground/40" />
                        )}
                      </div>
                      {index < timelineSteps.length - 1 && (
                        <div className={`w-0.5 h-8 ${isReached ? 'bg-green-500/40' : 'bg-border'}`} />
                      )}
                    </div>

                    {/* Content */}
                    <div className="pb-4 flex-1 min-w-0">
                      <div className="flex items-center justify-between">
                        <p className={`text-xs font-semibold ${
                          isActive ? 'text-primary' : isReached ? 'text-foreground' : 'text-muted-foreground/50'
                        }`}>
                          {step.label}
                        </p>
                        {step.time && step.time !== '—' && (
                          <span className="text-[10px] text-muted-foreground tabular-nums">{step.time}</span>
                        )}
                      </div>
                      <p className={`text-[11px] mt-0.5 ${isReached ? 'text-muted-foreground' : 'text-muted-foreground/40'}`}>
                        {step.desc}
                      </p>
                    </div>
                  </div>
                );
              })}

              {/* Failed terminal node */}
              {isFailed && (
                <div className="flex gap-3">
                  <div className="flex flex-col items-center">
                    <div className="w-6 h-6 rounded-full border-2 border-red-500 bg-red-500/10 flex items-center justify-center flex-shrink-0">
                      <XCircle size={12} className="text-red-400" />
                    </div>
                  </div>
                  <div className="flex-1 min-w-0">
                    <p className="text-xs font-semibold text-red-400 capitalize">{command.state}</p>
                    {command.errorCode && (
                      <span className="inline-block font-mono text-[10px] text-red-400 bg-red-500/10 px-1.5 py-0.5 rounded mt-1">
                        Error {command.errorCode}
                      </span>
                    )}
                    {command.errorMessage && (
                      <p className="text-[11px] text-red-400/80 mt-1">{command.errorMessage}</p>
                    )}
                  </div>
                </div>
              )}
            </div>
          </div>

          {/* Signed envelope metadata */}
          <div className="bg-muted/20 border border-border rounded-lg p-3">
            <div className="flex items-center gap-2 mb-2">
              <Hash size={12} className="text-muted-foreground" />
              <h3 className="text-[11px] font-semibold text-muted-foreground uppercase tracking-wide">Envelope Metadata</h3>
            </div>
            <div className="space-y-1">
              {[
                { k: 'command_id', v: command.id },
                { k: 'trace_id', v: command.traceId },
                { k: 'policy_version', v: 'policy-2026-04' },
                { k: 'policy_hash', v: 'sha256:policy123' },
                { k: 'enc', v: 'none' },
                { k: 'ttl_seconds', v: '300' },
                { k: 'sig', v: 'ed25519:3a7f…c92b' },
              ].map((row) => (
                <div key={`env-${row.k}`} className="flex items-center gap-2">
                  <span className="text-[10px] text-muted-foreground font-mono w-28 flex-shrink-0">{row.k}</span>
                  <span className="text-[10px] text-foreground font-mono truncate">{row.v}</span>
                </div>
              ))}
            </div>
          </div>

          {/* Policy gate */}
          <div className="bg-green-500/5 border border-green-500/20 rounded-lg p-3">
            <p className="text-[10px] text-muted-foreground uppercase tracking-wide mb-1.5">Policy Gate</p>
            <div className="flex items-center gap-2">
              <CheckCircle2 size={13} className="text-green-400" />
              <span className="text-xs text-green-400 font-medium">Allow — policy-2026-04</span>
            </div>
            <p className="text-[11px] text-muted-foreground mt-1">Compliance: compliant · No failed rules</p>
          </div>
        </div>

        {/* Footer */}
        <div className="border-t border-border px-5 py-3 flex items-center gap-2">
          {(command.state === 'failed' || command.state === 'expired') && (
            <button
              onClick={() => toast.success(`Retrying ${command.id}`)}
              className="flex-1 flex items-center justify-center gap-2 py-2 text-xs font-medium bg-blue-500/10 border border-blue-500/20 text-blue-400 rounded-md hover:bg-blue-500/20 transition-colors"
            >
              <RotateCcw size={13} /> Retry Command
            </button>
          )}
          {command.state === 'queued' && (
            <button
              onClick={() => toast.warning(`Cancelled ${command.id}`)}
              className="flex-1 flex items-center justify-center gap-2 py-2 text-xs font-medium bg-red-500/10 border border-red-500/20 text-red-400 rounded-md hover:bg-red-500/20 transition-colors"
            >
              <X size={13} /> Cancel Command
            </button>
          )}
          <button
            onClick={() => { toast.info('Copied trace ID'); }}
            className="flex items-center gap-1.5 px-3 py-2 text-xs border border-border rounded-md text-muted-foreground hover:text-foreground hover:bg-muted/60 transition-colors"
          >
            <Hash size={12} /> Copy Trace ID
          </button>
        </div>
      </div>
    </>
  );
}