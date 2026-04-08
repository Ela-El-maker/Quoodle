'use client';
import React, { useState } from 'react';
import { useForm } from 'react-hook-form';
import { X, Terminal, Shield, AlertTriangle, Loader2, CheckCircle2 } from 'lucide-react';
import { toast } from 'sonner';

interface DispatchCommandModalProps {
  onClose: () => void;
}

interface FormValues {
  deviceId: string;
  method: string;
  twoFactorCode: string;
}

// Backend integration point: POST /api/commands
const devices = [
  { id: 'PC001',      label: 'WKSTN-001 — online' },
  { id: 'PC002',      label: 'WKSTN-002 — online' },
  { id: 'SRV-PROD-01',label: 'SRV-PROD-01 — online (drift)' },
  { id: 'WKSTN-042',  label: 'WKSTN-042 — online' },
  { id: 'WKSTN-055',  label: 'WKSTN-055 — online' },
  { id: 'WKSTN-088',  label: 'WKSTN-088 — online' },
];

const methods = [
  { id: 'ping',        label: 'ping',        risk: 'low',    requires2fa: false, desc: 'Send a ping to verify agent connectivity and kernel guard response.' },
  { id: 'lock_screen', label: 'lock_screen', risk: 'medium', requires2fa: false, desc: 'Lock the device screen immediately. User will need to re-authenticate.' },
];

const riskColors = {
  low:    { badge: 'bg-green-500/10 border-green-500/20 text-green-400',  icon: CheckCircle2 },
  medium: { badge: 'bg-amber-500/10 border-amber-500/20 text-amber-400',  icon: AlertTriangle },
  high:   { badge: 'bg-red-500/10 border-red-500/20 text-red-400',        icon: Shield },
};

export default function DispatchCommandModal({ onClose }: DispatchCommandModalProps) {
  const [loading, setLoading] = useState(false);
  const [submitted, setSubmitted] = useState(false);

  const {
    register,
    handleSubmit,
    watch,
    formState: { errors },
  } = useForm<FormValues>({
    defaultValues: { deviceId: '', method: '', twoFactorCode: '' },
  });

  const selectedMethod = watch('method');
  const methodMeta = methods.find((m) => m.id === selectedMethod);
  const requires2fa = methodMeta?.requires2fa ?? false;

  const onSubmit = async (data: FormValues) => {
    setLoading(true);
    // Backend integration point: POST /api/commands with body { device_id, method, params, two_factor_code }
    await new Promise((r) => setTimeout(r, 1400));
    setLoading(false);
    setSubmitted(true);
    toast.success(`Command ${data.method} queued for ${data.deviceId}`, { description: 'CMD-7743 · Awaiting dispatch' });
    setTimeout(onClose, 1200);
  };

  return (
    <>
      <div className="fixed inset-0 bg-black/60 z-50 flex items-center justify-center p-4">
        <div className="bg-zinc-950 border border-border rounded-xl w-full max-w-lg shadow-2xl fade-in">
          {/* Header */}
          <div className="flex items-center justify-between px-5 py-4 border-b border-border">
            <div className="flex items-center gap-2">
              <div className="w-7 h-7 rounded-lg bg-primary/10 flex items-center justify-center">
                <Terminal size={14} className="text-primary" />
              </div>
              <h2 className="font-semibold text-sm">Dispatch Command</h2>
            </div>
            <button onClick={onClose} className="p-1.5 rounded-md text-muted-foreground hover:text-foreground hover:bg-muted transition-colors">
              <X size={15} />
            </button>
          </div>

          {submitted ? (
            <div className="flex flex-col items-center justify-center py-12 px-5">
              <div className="w-12 h-12 rounded-full bg-green-500/10 flex items-center justify-center mb-3">
                <CheckCircle2 size={24} className="text-green-400" />
              </div>
              <p className="font-semibold text-sm">Command Queued</p>
              <p className="text-xs text-muted-foreground mt-1">CMD-7743 · Dispatching to gateway…</p>
            </div>
          ) : (
            <form onSubmit={handleSubmit(onSubmit)} className="p-5 space-y-4">
              {/* Device selector */}
              <div>
                <label className="block text-xs font-medium mb-1.5">
                  Target Device <span className="text-red-400">*</span>
                </label>
                <p className="text-[11px] text-muted-foreground mb-2">Select the device to dispatch the command to.</p>
                <select
                  {...register('deviceId', { required: 'Device is required' })}
                  className="w-full text-xs bg-muted/60 border border-border rounded-md px-3 py-2 text-foreground focus:outline-none focus:ring-1 focus:ring-primary/50"
                >
                  <option value="">Select a device…</option>
                  {devices.map((d) => (
                    <option key={`dispatch-dev-${d.id}`} value={d.id}>{d.label}</option>
                  ))}
                </select>
                {errors.deviceId && (
                  <p className="text-[11px] text-red-400 mt-1">{errors.deviceId.message}</p>
                )}
              </div>

              {/* Method selector */}
              <div>
                <label className="block text-xs font-medium mb-1.5">
                  Command Method <span className="text-red-400">*</span>
                </label>
                <p className="text-[11px] text-muted-foreground mb-2">Only methods approved by policy are shown.</p>
                <div className="space-y-2">
                  {methods.map((m) => {
                    const riskCfg = riskColors[m.risk as keyof typeof riskColors];
                    return (
                      <label
                        key={`method-opt-${m.id}`}
                        className={`flex items-start gap-3 p-3 border rounded-lg cursor-pointer transition-all ${
                          selectedMethod === m.id
                            ? 'border-primary/50 bg-primary/5' :'border-border hover:border-border/80 hover:bg-muted/20'
                        }`}
                      >
                        <input
                          type="radio"
                          value={m.id}
                          {...register('method', { required: 'Method is required' })}
                          className="mt-0.5 accent-blue-500"
                        />
                        <div className="flex-1 min-w-0">
                          <div className="flex items-center gap-2 mb-0.5">
                            <span className="font-mono text-xs font-semibold">{m.label}</span>
                            <span className={`text-[10px] px-1.5 py-0.5 rounded-full border font-medium ${riskCfg.badge}`}>
                              {m.risk} risk
                            </span>
                          </div>
                          <p className="text-[11px] text-muted-foreground">{m.desc}</p>
                        </div>
                      </label>
                    );
                  })}
                </div>
                {errors.method && (
                  <p className="text-[11px] text-red-400 mt-1">{errors.method.message}</p>
                )}
              </div>

              {/* Policy preview */}
              {selectedMethod && (
                <div className="bg-green-500/5 border border-green-500/20 rounded-lg p-3">
                  <div className="flex items-center gap-2 mb-1">
                    <CheckCircle2 size={12} className="text-green-400" />
                    <p className="text-[11px] font-semibold text-green-400">Policy Gate: Allow</p>
                  </div>
                  <p className="text-[11px] text-muted-foreground">
                    policy-2026-04 · Compliance: compliant · No failed rules
                    {requires2fa && ' · 2FA required'}
                  </p>
                </div>
              )}

              {/* 2FA field (conditional) */}
              {requires2fa && (
                <div>
                  <label className="block text-xs font-medium mb-1.5">
                    Two-Factor Code <span className="text-red-400">*</span>
                  </label>
                  <p className="text-[11px] text-muted-foreground mb-2">This command requires 2FA verification. Enter your current TOTP code.</p>
                  <input
                    type="text"
                    maxLength={6}
                    placeholder="000000"
                    {...register('twoFactorCode', {
                      validate: (v) => !requires2fa || v.length === 6 || '2FA code must be 6 digits',
                    })}
                    className="w-full text-xs bg-muted/60 border border-border rounded-md px-3 py-2 text-foreground font-mono tracking-widest placeholder:text-muted-foreground focus:outline-none focus:ring-1 focus:ring-primary/50"
                  />
                  {errors.twoFactorCode && (
                    <p className="text-[11px] text-red-400 mt-1">{errors.twoFactorCode.message}</p>
                  )}
                </div>
              )}

              {/* Actions */}
              <div className="flex items-center gap-2 pt-1">
                <button
                  type="button"
                  onClick={onClose}
                  className="flex-1 py-2 text-xs border border-border rounded-md text-muted-foreground hover:text-foreground hover:bg-muted/60 transition-colors"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={loading}
                  className="flex-1 flex items-center justify-center gap-2 py-2 text-xs font-medium bg-primary text-primary-foreground rounded-md hover:bg-primary/90 disabled:opacity-60 active:scale-95 transition-all duration-150"
                  style={{ minWidth: '120px' }}
                >
                  {loading ? (
                    <>
                      <Loader2 size={13} className="animate-spin" />
                      Dispatching…
                    </>
                  ) : (
                    <>
                      <Terminal size={13} />
                      Dispatch Command
                    </>
                  )}
                </button>
              </div>
            </form>
          )}
        </div>
      </div>
    </>
  );
}