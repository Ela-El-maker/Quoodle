'use client';
import React, { useState, useEffect, useCallback } from 'react';
import {
  X,
  Monitor,
  Loader2,
  CheckCircle2,
  AlertTriangle,
  RefreshCw,
  Copy,
  Clock,
  Link2,
  ShieldCheck,
} from 'lucide-react';
import { toast } from 'sonner';

type PairingStep = 'init' | 'pending_agent' | 'pending_confirmation' | 'paired' | 'expired' | 'error';

interface PendingDevice {
  deviceId: string;
  deviceName: string;
  deviceIdSuffix: string;
  os: string;
  agentVersion: string;
  detectedAt: string;
}

interface DevicePairingModalProps {
  onClose: () => void;
  onPaired?: (device: PendingDevice) => void;
}

interface PairSessionPayload {
  status?: string;
  pair_code?: string;
  pair_token?: string;
  pair_session_id?: string;
  expires_at?: string;
  device_id?: string;
  device_name?: string;
  device_id_suffix?: string;
  detected_at?: string;
  reason?: string;
  message?: string;
}

const DEFAULT_TTL_SECONDS = 300;

function parseApiError(payload: unknown, fallback: string): string {
  if (!payload || typeof payload !== 'object') return fallback;
  const map = payload as Record<string, unknown>;
  const reason = String(map.reason ?? '').trim();
  const message = String(map.message ?? '').trim();
  const status = String(map.status ?? '').trim();
  if (reason && message) return `${reason}: ${message}`;
  if (reason) return reason;
  if (message) return message;
  if (status) return status;
  return fallback;
}

function toPendingDevice(payload: PairSessionPayload): PendingDevice | null {
  const deviceId = String(payload.device_id ?? '').trim();
  const deviceName = String(payload.device_name ?? '').trim();
  if (!deviceId || !deviceName) return null;

  const suffixRaw = String(payload.device_id_suffix ?? '').trim();
  return {
    deviceId,
    deviceName,
    deviceIdSuffix: (suffixRaw || deviceId.slice(-6)).toUpperCase(),
    os: 'Windows',
    agentVersion: 'unknown',
    detectedAt: String(payload.detected_at ?? new Date().toISOString()),
  };
}

export default function DevicePairingModal({ onClose, onPaired }: DevicePairingModalProps) {
  const [step, setStep] = useState<PairingStep>('init');
  const [pairCode, setPairCode] = useState('');
  const [pairSessionId, setPairSessionId] = useState('');
  const [pairToken, setPairToken] = useState('');
  const [timeLeft, setTimeLeft] = useState(0);
  const [expiresAt, setExpiresAt] = useState<number>(0);
  const [pendingDevice, setPendingDevice] = useState<PendingDevice | null>(null);
  const [deviceNameInput, setDeviceNameInput] = useState('');
  const [deviceIdSuffixInput, setDeviceIdSuffixInput] = useState('');
  const [confirmError, setConfirmError] = useState('');
  const [confirming, setConfirming] = useState(false);
  const [pollCount, setPollCount] = useState(0);
  const [busy, setBusy] = useState(false);

  const resetState = useCallback(() => {
    setStep('init');
    setPairCode('');
    setPairSessionId('');
    setPairToken('');
    setTimeLeft(0);
    setExpiresAt(0);
    setPendingDevice(null);
    setDeviceNameInput('');
    setDeviceIdSuffixInput('');
    setConfirmError('');
    setConfirming(false);
    setPollCount(0);
    setBusy(false);
  }, []);

  const startPairing = useCallback(async () => {
    setBusy(true);
    setConfirmError('');
    setPollCount(0);
    try {
      const response = await fetch('/api/pair/init', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        credentials: 'include',
        body: JSON.stringify({}),
      });
      const payload = (await response.json().catch(() => ({}))) as Record<string, unknown>;
      if (!response.ok) {
        throw new Error(parseApiError(payload, `pair_init_failed_${response.status}`));
      }

      const sessionId = String(payload.pair_session_id ?? '').trim();
      const code = String(payload.pair_code ?? '').trim();
      const expiresAtRaw = String(payload.expires_at ?? '').trim();
      const expiresAtMs = Number.isFinite(Date.parse(expiresAtRaw))
        ? Date.parse(expiresAtRaw)
        : Date.now() + DEFAULT_TTL_SECONDS * 1000;

      if (!sessionId || !code) {
        throw new Error('pair_init_missing_fields');
      }

      setPairSessionId(sessionId);
      setPairCode(code);
      setPairToken('');
      setPendingDevice(null);
      setDeviceNameInput('');
      setDeviceIdSuffixInput('');
      setExpiresAt(expiresAtMs);
      setTimeLeft(Math.max(0, Math.ceil((expiresAtMs - Date.now()) / 1000)));
      setStep('pending_agent');
      toast.info('Pair code generated. Enter it on your Windows agent.');
    } catch (error) {
      const message = error instanceof Error ? error.message : 'pair_init_failed';
      setConfirmError(message);
      setStep('error');
      toast.error(`Failed to start pairing: ${message}`);
    } finally {
      setBusy(false);
    }
  }, []);

  useEffect(() => {
    if (step !== 'pending_agent' && step !== 'pending_confirmation') return;
    if (!expiresAt) return;

    const timer = setInterval(() => {
      const next = Math.max(0, Math.ceil((expiresAt - Date.now()) / 1000));
      setTimeLeft(next);
      if (next <= 0) {
        setStep('expired');
      }
    }, 1000);

    return () => clearInterval(timer);
  }, [step, expiresAt]);

  useEffect(() => {
    if (!pairSessionId) return;
    if (step !== 'pending_agent' && step !== 'pending_confirmation') return;

    let cancelled = false;
    const pollOnce = async () => {
      try {
        const response = await fetch(`/api/pair/session/${encodeURIComponent(pairSessionId)}`, {
          method: 'GET',
          credentials: 'include',
          cache: 'no-store',
        });
        const payload = (await response.json().catch(() => ({}))) as PairSessionPayload;

        if (cancelled) return;
        if (!response.ok) {
          if (response.status === 404) {
            setStep('expired');
            return;
          }
          return;
        }

        const nextCode = String(payload.pair_code ?? '').trim();
        if (nextCode) setPairCode(nextCode);

        const nextToken = String(payload.pair_token ?? '').trim();
        if (nextToken) setPairToken(nextToken);

        const expiryRaw = String(payload.expires_at ?? '').trim();
        if (expiryRaw) {
          const nextExpiry = Date.parse(expiryRaw);
          if (Number.isFinite(nextExpiry)) {
            setExpiresAt(nextExpiry);
            setTimeLeft(Math.max(0, Math.ceil((nextExpiry - Date.now()) / 1000)));
          }
        }

        const status = String(payload.status ?? '').toLowerCase();
        if (status === 'expired') {
          setStep('expired');
          return;
        }

        if (status === 'pending_confirmation') {
          const device = toPendingDevice(payload);
          if (device) {
            setPendingDevice(device);
            setStep('pending_confirmation');
          }
          return;
        }

        if (status === 'paired') {
          setStep('paired');
        }
      } finally {
        if (!cancelled) {
          setPollCount((count) => count + 1);
        }
      }
    };

    void pollOnce();
    const handle = setInterval(() => {
      void pollOnce();
    }, 3000);

    return () => {
      cancelled = true;
      clearInterval(handle);
    };
  }, [pairSessionId, step]);

  const formatTime = (seconds: number) => {
    const m = Math.floor(seconds / 60).toString().padStart(2, '0');
    const s = (seconds % 60).toString().padStart(2, '0');
    return `${m}:${s}`;
  };

  const timerColor = timeLeft > 60 ? 'text-green-400' : timeLeft > 30 ? 'text-amber-400' : 'text-red-400';
  const timerBg = timeLeft > 60 ? 'bg-green-500/10 border-green-500/20' : timeLeft > 30 ? 'bg-amber-500/10 border-amber-500/20' : 'bg-red-500/10 border-red-500/20';

  const handleCopyCode = () => {
    if (!pairCode) return;
    navigator.clipboard.writeText(pairCode).then(() => toast.success('Pair code copied'));
  };

  const handleConfirm = async () => {
    if (!pendingDevice) return;
    setConfirmError('');

    if (deviceNameInput.trim() !== pendingDevice.deviceName) {
      setConfirmError('Device name does not match. Check the name shown above and try again.');
      return;
    }

    if (deviceIdSuffixInput.trim().toUpperCase() !== pendingDevice.deviceIdSuffix.toUpperCase()) {
      setConfirmError('Device ID suffix does not match. Enter the last 6 characters of the device ID shown above.');
      return;
    }

    if (!pairToken) {
      setConfirmError('Pair token not available yet. Wait a few seconds and retry.');
      return;
    }

    setConfirming(true);
    try {
      const response = await fetch('/api/pair/confirm', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        credentials: 'include',
        body: JSON.stringify({
          pair_token: pairToken,
          pair_session_id: pairSessionId,
        }),
      });
      const payload = (await response.json().catch(() => ({}))) as Record<string, unknown>;
      if (!response.ok) {
        throw new Error(parseApiError(payload, `pair_confirm_failed_${response.status}`));
      }

      setStep('paired');
      toast.success(`Device ${pendingDevice.deviceName} paired successfully`);
      onPaired?.(pendingDevice);
    } catch (error) {
      const message = error instanceof Error ? error.message : 'pair_confirm_failed';
      setConfirmError(message);
      toast.error(`Pairing confirmation failed: ${message}`);
    } finally {
      setConfirming(false);
    }
  };

  const handleRestart = () => {
    resetState();
    void startPairing();
  };

  return (
    <div className="fixed inset-0 bg-black/60 z-50 flex items-center justify-center p-4">
      <div className="bg-card border border-border rounded-xl w-full max-w-md shadow-2xl fade-in">
        <div className="flex items-center justify-between px-5 py-4 border-b border-border">
          <div className="flex items-center gap-2">
            <div className="w-7 h-7 rounded-lg bg-primary/10 flex items-center justify-center">
              <Link2 size={14} className="text-primary" />
            </div>
            <h2 className="font-semibold text-sm">Pair New Device</h2>
          </div>
          <button
            onClick={onClose}
            className="p-1.5 rounded-md text-muted-foreground hover:text-foreground hover:bg-muted transition-colors"
          >
            <X size={15} />
          </button>
        </div>

        {step === 'init' && (
          <div className="p-5 space-y-5">
            <div className="bg-muted/20 border border-border rounded-lg p-4 space-y-3">
              <p className="text-xs font-semibold text-foreground">How device pairing works</p>
              <ol className="space-y-2">
                {[
                  'Click "Generate Pair Code" to get a short-lived 6-digit code.',
                  'Open the Windows agent UI and enter that code.',
                  'When the device appears here, verify details and confirm.',
                  'After confirmation, the runtime receives credentials and reconnects.',
                ].map((message, index) => (
                  <li key={message} className="flex items-start gap-2.5 text-[11px] text-muted-foreground">
                    <span className="flex-shrink-0 w-4 h-4 rounded-full bg-primary/10 text-primary text-[10px] font-bold flex items-center justify-center mt-0.5">
                      {index + 1}
                    </span>
                    {message}
                  </li>
                ))}
              </ol>
            </div>
            <button
              onClick={() => void startPairing()}
              disabled={busy}
              className="w-full flex items-center justify-center gap-2 py-2.5 text-xs font-medium bg-primary text-primary-foreground rounded-md hover:bg-primary/90 active:scale-95 transition-all disabled:opacity-60"
            >
              {busy ? <Loader2 size={13} className="animate-spin" /> : <Link2 size={13} />}
              Generate Pair Code
            </button>
          </div>
        )}

        {step === 'pending_agent' && (
          <div className="p-5 space-y-5">
            <div className="text-center space-y-2">
              <p className="text-xs text-muted-foreground">Enter this code on your Windows Agent</p>
              <div className="flex items-center justify-center gap-3">
                <span className="text-4xl font-bold font-mono tracking-[0.3em] text-foreground select-all">
                  {pairCode || '------'}
                </span>
                <button
                  onClick={handleCopyCode}
                  className="p-1.5 rounded-md text-muted-foreground hover:text-foreground hover:bg-muted transition-colors"
                  title="Copy pair code"
                >
                  <Copy size={14} />
                </button>
              </div>
              <div className={`inline-flex items-center gap-1.5 px-3 py-1.5 rounded-full border text-xs font-mono font-semibold ${timerBg} ${timerColor}`}>
                <Clock size={11} />
                Expires in {formatTime(timeLeft)}
              </div>
            </div>

            <div className="bg-muted/20 border border-border rounded-lg px-3 py-2 flex items-center justify-between">
              <span className="text-[10px] text-muted-foreground font-mono">Session: {pairSessionId}</span>
              <span className="text-[10px] text-amber-400 font-medium">Waiting for agent...</span>
            </div>

            <div className="flex items-center gap-2 text-[11px] text-muted-foreground">
              <Loader2 size={12} className="animate-spin text-primary flex-shrink-0" />
              Listening for device connection. Keep this window open.
            </div>

            <div className="flex items-center justify-center gap-1.5">
              {[0, 1, 2].map((index) => (
                <span
                  key={index}
                  className={`w-1.5 h-1.5 rounded-full transition-all duration-300 ${
                    pollCount % 3 > index ? 'bg-primary' : 'bg-muted'
                  }`}
                />
              ))}
            </div>

            <button
              onClick={onClose}
              className="w-full py-2 text-xs border border-border rounded-md text-muted-foreground hover:text-foreground hover:bg-muted/60 transition-colors"
            >
              Cancel
            </button>
          </div>
        )}

        {step === 'pending_confirmation' && pendingDevice && (
          <div className="p-5 space-y-4">
            <div className="bg-amber-500/5 border border-amber-500/20 rounded-lg p-3 flex items-start gap-2.5">
              <AlertTriangle size={14} className="text-amber-400 flex-shrink-0 mt-0.5" />
              <div>
                <p className="text-xs font-semibold text-amber-400">Device detected. Confirm ownership.</p>
                <p className="text-[11px] text-muted-foreground mt-0.5">
                  Verify the details below before linking the device to your account.
                </p>
              </div>
            </div>

            <div className="bg-muted/20 border border-border rounded-lg p-4 space-y-2.5">
              <div className="flex items-center gap-2 mb-1">
                <Monitor size={14} className="text-primary" />
                <p className="text-xs font-semibold">Pending Device</p>
              </div>
              <div className="grid grid-cols-2 gap-x-4 gap-y-2">
                {[
                  { label: 'Device Name', value: pendingDevice.deviceName },
                  { label: 'Device ID', value: pendingDevice.deviceId },
                  { label: 'OS', value: pendingDevice.os },
                  { label: 'Agent Version', value: `v${pendingDevice.agentVersion}` },
                ].map((row) => (
                  <div key={row.label}>
                    <p className="text-[10px] text-muted-foreground">{row.label}</p>
                    <p className="text-xs font-mono font-medium truncate">{row.value}</p>
                  </div>
                ))}
              </div>
            </div>

            <div className="space-y-3">
              <p className="text-[11px] text-muted-foreground">
                Type the device name and last 6 characters of device ID exactly as shown above.
              </p>

              <div>
                <label className="block text-xs font-medium mb-1.5">
                  Type device name <span className="text-red-400">*</span>
                </label>
                <input
                  type="text"
                  value={deviceNameInput}
                  onChange={(event) => { setDeviceNameInput(event.target.value); setConfirmError(''); }}
                  placeholder={pendingDevice.deviceName}
                  className="w-full text-xs bg-muted/60 border border-border rounded-md px-3 py-2.5 text-foreground font-mono placeholder:text-muted-foreground/50 focus:outline-none focus:ring-1 focus:ring-primary/50 transition-colors"
                  autoComplete="off"
                  spellCheck={false}
                />
              </div>

              <div>
                <label className="block text-xs font-medium mb-1.5">
                  Enter last 6 characters of device ID <span className="text-red-400">*</span>
                </label>
                <div className="relative">
                  <input
                    type="text"
                    value={deviceIdSuffixInput}
                    onChange={(event) => { setDeviceIdSuffixInput(event.target.value.toUpperCase()); setConfirmError(''); }}
                    placeholder={pendingDevice.deviceIdSuffix}
                    maxLength={6}
                    className="w-full text-xs bg-muted/60 border border-border rounded-md px-3 py-2.5 text-foreground font-mono tracking-widest uppercase placeholder:text-muted-foreground/50 focus:outline-none focus:ring-1 focus:ring-primary/50 transition-colors"
                    autoComplete="off"
                    spellCheck={false}
                  />
                  <span className="absolute right-3 top-1/2 -translate-y-1/2 text-[10px] text-muted-foreground tabular-nums">
                    {deviceIdSuffixInput.length}/6
                  </span>
                </div>
              </div>

              {confirmError && (
                <div className="flex items-start gap-2 text-[11px] text-red-400 bg-red-500/5 border border-red-500/20 rounded-md px-3 py-2">
                  <AlertTriangle size={11} className="flex-shrink-0 mt-0.5" />
                  {confirmError}
                </div>
              )}
            </div>

            <div className="flex items-center gap-2 pt-1">
              <button
                onClick={handleRestart}
                className="flex-1 py-2 text-xs border border-border rounded-md text-muted-foreground hover:text-foreground hover:bg-muted/60 transition-colors"
              >
                Reject & Restart
              </button>
              <button
                onClick={handleConfirm}
                disabled={confirming || !deviceNameInput || deviceIdSuffixInput.length < 6}
                className="flex-1 flex items-center justify-center gap-2 py-2 text-xs font-medium bg-primary text-primary-foreground rounded-md hover:bg-primary/90 disabled:opacity-50 active:scale-95 transition-all"
              >
                {confirming ? (
                  <>
                    <Loader2 size={12} className="animate-spin" />
                    Confirming...
                  </>
                ) : (
                  <>
                    <ShieldCheck size={12} />
                    Confirm & Link Device
                  </>
                )}
              </button>
            </div>
          </div>
        )}

        {step === 'paired' && pendingDevice && (
          <div className="p-5 flex flex-col items-center text-center space-y-4">
            <div className="w-14 h-14 rounded-full bg-green-500/10 flex items-center justify-center">
              <CheckCircle2 size={28} className="text-green-400" />
            </div>
            <div>
              <p className="font-semibold text-sm">Device Paired Successfully</p>
              <p className="text-xs text-muted-foreground mt-1">
                {pendingDevice.deviceName} is now linked to your account.
              </p>
            </div>
            <div className="w-full bg-muted/20 border border-border rounded-lg p-3 text-left space-y-1.5">
              <div className="flex justify-between text-[11px]">
                <span className="text-muted-foreground">Device</span>
                <span className="font-mono font-medium">{pendingDevice.deviceName}</span>
              </div>
              <div className="flex justify-between text-[11px]">
                <span className="text-muted-foreground">Device ID</span>
                <span className="font-mono font-medium">{pendingDevice.deviceId}</span>
              </div>
              <div className="flex justify-between text-[11px]">
                <span className="text-muted-foreground">Status</span>
                <span className="text-green-400 font-medium">Active</span>
              </div>
            </div>
            <button
              onClick={onClose}
              className="w-full py-2 text-xs font-medium bg-primary text-primary-foreground rounded-md hover:bg-primary/90 active:scale-95 transition-all"
            >
              Done
            </button>
          </div>
        )}

        {step === 'expired' && (
          <div className="p-5 flex flex-col items-center text-center space-y-4">
            <div className="w-14 h-14 rounded-full bg-amber-500/10 flex items-center justify-center">
              <Clock size={28} className="text-amber-400" />
            </div>
            <div>
              <p className="font-semibold text-sm">Pair Code Expired</p>
              <p className="text-xs text-muted-foreground mt-1">
                The pair code has expired. Generate a new one to try again.
              </p>
            </div>
            <div className="flex items-center gap-2 w-full">
              <button
                onClick={onClose}
                className="flex-1 py-2 text-xs border border-border rounded-md text-muted-foreground hover:text-foreground hover:bg-muted/60 transition-colors"
              >
                Cancel
              </button>
              <button
                onClick={handleRestart}
                className="flex-1 flex items-center justify-center gap-2 py-2 text-xs font-medium bg-primary text-primary-foreground rounded-md hover:bg-primary/90 active:scale-95 transition-all"
              >
                <RefreshCw size={12} />
                Generate New Code
              </button>
            </div>
          </div>
        )}

        {step === 'error' && (
          <div className="p-5 flex flex-col items-center text-center space-y-4">
            <div className="w-14 h-14 rounded-full bg-red-500/10 flex items-center justify-center">
              <AlertTriangle size={28} className="text-red-400" />
            </div>
            <div>
              <p className="font-semibold text-sm">Pairing Failed</p>
              <p className="text-xs text-muted-foreground mt-1">
                {confirmError || 'Unable to start pairing.'}
              </p>
            </div>
            <div className="flex items-center gap-2 w-full">
              <button
                onClick={onClose}
                className="flex-1 py-2 text-xs border border-border rounded-md text-muted-foreground hover:text-foreground hover:bg-muted/60 transition-colors"
              >
                Close
              </button>
              <button
                onClick={() => void handleRestart()}
                className="flex-1 flex items-center justify-center gap-2 py-2 text-xs font-medium bg-primary text-primary-foreground rounded-md hover:bg-primary/90 active:scale-95 transition-all"
              >
                <RefreshCw size={12} />
                Retry
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

