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

// ─── Types ────────────────────────────────────────────────────────────────────

type PairingStep = 'init' | 'pending_agent' | 'pending_confirmation' | 'confirming' | 'paired' | 'expired' | 'error';

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

// ─── Mock pair code generation ─────────────────────────────────────────────────
// Backend integration point: POST /api/pair/init → { pair_session_id, pair_code, expires_in_seconds }
const generatePairCode = () => Math.floor(100000 + Math.random() * 900000).toString();
const PAIR_CODE_TTL = 300; // 5 minutes in seconds

// Simulated pending device (backend integration: GET /api/pair/session/{id})
const mockPendingDevice: PendingDevice = {
  deviceId: 'WKSTN-' + Math.floor(100 + Math.random() * 900),
  deviceName: 'DESKTOP-' + Math.random().toString(36).substring(2, 7).toUpperCase(),
  deviceIdSuffix: '',
  os: 'Windows 11 Pro',
  agentVersion: '1.2.0',
  detectedAt: new Date().toISOString(),
};

export default function DevicePairingModal({ onClose, onPaired }: DevicePairingModalProps) {
  const [step, setStep] = useState<PairingStep>('init');
  const [pairCode] = useState(generatePairCode);
  const [pairSessionId] = useState(() => 'pair-sess-' + Math.random().toString(36).substring(2, 10));
  const [timeLeft, setTimeLeft] = useState(PAIR_CODE_TTL);
  const [pendingDevice, setPendingDevice] = useState<PendingDevice | null>(null);
  const [deviceNameInput, setDeviceNameInput] = useState('');
  const [deviceIdSuffixInput, setDeviceIdSuffixInput] = useState('');
  const [confirmError, setConfirmError] = useState('');
  const [confirming, setConfirming] = useState(false);
  const [pollCount, setPollCount] = useState(0);

  // ── Countdown timer ──────────────────────────────────────────────────────────
  useEffect(() => {
    if (step !== 'pending_agent') return;
    if (timeLeft <= 0) {
      setStep('expired');
      return;
    }
    const timer = setInterval(() => {
      setTimeLeft((t) => {
        if (t <= 1) {
          clearInterval(timer);
          setStep('expired');
          return 0;
        }
        return t - 1;
      });
    }, 1000);
    return () => clearInterval(timer);
  }, [step, timeLeft]);

  // ── Poll for pending device (simulated) ──────────────────────────────────────
  // Backend integration point: GET /api/pair/session/{pair_session_id} every 3s
  useEffect(() => {
    if (step !== 'pending_agent') return;
    const poll = setInterval(() => {
      setPollCount((c) => {
        const next = c + 1;
        // Simulate device appearing after ~9 seconds (3 polls)
        if (next >= 3) {
          clearInterval(poll);
          const detected = {
            ...mockPendingDevice,
            deviceIdSuffix: mockPendingDevice.deviceId.slice(-6),
          };
          setPendingDevice(detected);
          setStep('pending_confirmation');
        }
        return next;
      });
    }, 3000);
    return () => clearInterval(poll);
  }, [step]);

  const formatTime = (seconds: number) => {
    const m = Math.floor(seconds / 60).toString().padStart(2, '0');
    const s = (seconds % 60).toString().padStart(2, '0');
    return `${m}:${s}`;
  };

  const timerColor = timeLeft > 60 ? 'text-green-400' : timeLeft > 30 ? 'text-amber-400' : 'text-red-400';
  const timerBg = timeLeft > 60 ? 'bg-green-500/10 border-green-500/20' : timeLeft > 30 ? 'bg-amber-500/10 border-amber-500/20' : 'bg-red-500/10 border-red-500/20';

  const handleStartPairing = () => {
    setStep('pending_agent');
    setPollCount(0);
    toast.info('Pair code generated — enter it on your Windows agent');
  };

  const handleCopyCode = () => {
    navigator.clipboard.writeText(pairCode).then(() => toast.success('Pair code copied'));
  };

  const handleConfirm = async () => {
    if (!pendingDevice) return;
    setConfirmError('');

    // Validate device name
    if (deviceNameInput.trim() !== pendingDevice.deviceName) {
      setConfirmError('Device name does not match. Check the name shown above and try again.');
      return;
    }

    // Validate device ID suffix (last 6 chars)
    if (deviceIdSuffixInput.trim().toUpperCase() !== pendingDevice.deviceIdSuffix.toUpperCase()) {
      setConfirmError('Device ID suffix does not match. Enter the last 6 characters of the device ID shown above.');
      return;
    }

    setConfirming(true);
    // Backend integration point: POST /api/pair/confirm
    // { pair_session_id, device_name_confirmation, device_id_suffix_confirmation }
    await new Promise((r) => setTimeout(r, 1400));
    setConfirming(false);
    setStep('paired');
    toast.success(`Device ${pendingDevice.deviceName} paired successfully`);
    onPaired?.(pendingDevice);
  };

  const handleRestart = () => {
    setStep('init');
    setTimeLeft(PAIR_CODE_TTL);
    setPendingDevice(null);
    setDeviceNameInput('');
    setDeviceIdSuffixInput('');
    setConfirmError('');
    setPollCount(0);
  };

  return (
    <div className="fixed inset-0 bg-black/60 z-50 flex items-center justify-center p-4">
      <div className="bg-zinc-950 border border-border rounded-xl w-full max-w-md shadow-2xl fade-in">
        {/* Header */}
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

        {/* ── Step: Init ─────────────────────────────────────────────────────── */}
        {step === 'init' && (
          <div className="p-5 space-y-5">
            <div className="bg-muted/20 border border-border rounded-lg p-4 space-y-3">
              <p className="text-xs font-semibold text-foreground">How device pairing works</p>
              <ol className="space-y-2">
                {[
                  'Click "Generate Pair Code" to get a short-lived 6-digit code.',
                  'Open the Quoodle Windows Agent on your PC and enter the code.',
                  'The agent will connect and appear here for your confirmation.',
                  'Type the device name and last 6 chars of the device ID to confirm.',
                ].map((step, i) => (
                  <li key={i} className="flex items-start gap-2.5 text-[11px] text-muted-foreground">
                    <span className="flex-shrink-0 w-4 h-4 rounded-full bg-primary/10 text-primary text-[10px] font-bold flex items-center justify-center mt-0.5">
                      {i + 1}
                    </span>
                    {step}
                  </li>
                ))}
              </ol>
            </div>
            <button
              onClick={handleStartPairing}
              className="w-full flex items-center justify-center gap-2 py-2.5 text-xs font-medium bg-primary text-primary-foreground rounded-md hover:bg-primary/90 active:scale-95 transition-all"
            >
              <Link2 size={13} />
              Generate Pair Code
            </button>
          </div>
        )}

        {/* ── Step: Pending Agent (code display + countdown) ─────────────────── */}
        {step === 'pending_agent' && (
          <div className="p-5 space-y-5">
            {/* Pair code display */}
            <div className="text-center space-y-2">
              <p className="text-xs text-muted-foreground">Enter this code on your Windows Agent</p>
              <div className="flex items-center justify-center gap-3">
                <span className="text-4xl font-bold font-mono tracking-[0.3em] text-foreground select-all">
                  {pairCode}
                </span>
                <button
                  onClick={handleCopyCode}
                  className="p-1.5 rounded-md text-muted-foreground hover:text-foreground hover:bg-muted transition-colors"
                  title="Copy pair code"
                >
                  <Copy size={14} />
                </button>
              </div>
              {/* Countdown */}
              <div className={`inline-flex items-center gap-1.5 px-3 py-1.5 rounded-full border text-xs font-mono font-semibold ${timerBg} ${timerColor}`}>
                <Clock size={11} />
                Expires in {formatTime(timeLeft)}
              </div>
            </div>

            {/* Session ID */}
            <div className="bg-muted/20 border border-border rounded-lg px-3 py-2 flex items-center justify-between">
              <span className="text-[10px] text-muted-foreground font-mono">Session: {pairSessionId}</span>
              <span className="text-[10px] text-amber-400 font-medium">Waiting for agent…</span>
            </div>

            {/* Polling indicator */}
            <div className="flex items-center gap-2 text-[11px] text-muted-foreground">
              <Loader2 size={12} className="animate-spin text-primary flex-shrink-0" />
              Listening for device connection — keep this window open
            </div>

            {/* Progress dots */}
            <div className="flex items-center justify-center gap-1.5">
              {[0, 1, 2].map((i) => (
                <span
                  key={i}
                  className={`w-1.5 h-1.5 rounded-full transition-all duration-300 ${
                    pollCount > i ? 'bg-primary' : 'bg-muted'
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

        {/* ── Step: Pending Confirmation ─────────────────────────────────────── */}
        {step === 'pending_confirmation' && pendingDevice && (
          <div className="p-5 space-y-4">
            {/* Device detected banner */}
            <div className="bg-amber-500/5 border border-amber-500/20 rounded-lg p-3 flex items-start gap-2.5">
              <AlertTriangle size={14} className="text-amber-400 flex-shrink-0 mt-0.5" />
              <div>
                <p className="text-xs font-semibold text-amber-400">Device detected — confirm ownership</p>
                <p className="text-[11px] text-muted-foreground mt-0.5">
                  A device has connected using your pair code. Verify the details below before linking it to your account.
                </p>
              </div>
            </div>

            {/* Device identity panel */}
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

            {/* Confirmation fields */}
            <div className="space-y-3">
              <p className="text-[11px] text-muted-foreground">
                To confirm this is your device, type the device name and the last 6 characters of the device ID exactly as shown above.
              </p>

              {/* Device name */}
              <div>
                <label className="block text-xs font-medium mb-1.5">
                  Type device name <span className="text-red-400">*</span>
                </label>
                <input
                  type="text"
                  value={deviceNameInput}
                  onChange={(e) => { setDeviceNameInput(e.target.value); setConfirmError(''); }}
                  placeholder={pendingDevice.deviceName}
                  className="w-full text-xs bg-muted/60 border border-border rounded-md px-3 py-2.5 text-foreground font-mono placeholder:text-muted-foreground/50 focus:outline-none focus:ring-1 focus:ring-primary/50 transition-colors"
                  autoComplete="off"
                  spellCheck={false}
                />
              </div>

              {/* Device ID suffix */}
              <div>
                <label className="block text-xs font-medium mb-1.5">
                  Enter last 6 characters of device ID <span className="text-red-400">*</span>
                </label>
                <div className="relative">
                  <input
                    type="text"
                    value={deviceIdSuffixInput}
                    onChange={(e) => { setDeviceIdSuffixInput(e.target.value.toUpperCase()); setConfirmError(''); }}
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

              {/* Validation error */}
              {confirmError && (
                <div className="flex items-start gap-2 text-[11px] text-red-400 bg-red-500/5 border border-red-500/20 rounded-md px-3 py-2">
                  <AlertTriangle size={11} className="flex-shrink-0 mt-0.5" />
                  {confirmError}
                </div>
              )}
            </div>

            {/* Actions */}
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
                    Confirming…
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

        {/* ── Step: Paired ───────────────────────────────────────────────────── */}
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

        {/* ── Step: Expired ──────────────────────────────────────────────────── */}
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
      </div>
    </div>
  );
}
