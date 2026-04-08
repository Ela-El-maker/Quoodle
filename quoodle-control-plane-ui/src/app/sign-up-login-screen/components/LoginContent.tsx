'use client';

import React, { useEffect, useMemo, useState } from 'react';
import { CheckCircle2, Loader2, Shield, Terminal } from 'lucide-react';
import { toast } from 'sonner';
import AppLogo from '@/components/ui/AppLogo';
import { roleHomePath } from '@/lib/auth';

type LoginUser = {
  id: string;
  email: string;
  name: string;
  role: 'admin' | 'operator' | 'viewer';
};

export default function LoginContent() {
  const [email, setEmail] = useState('');
  const [otp, setOtp] = useState('');
  const [challengeId, setChallengeId] = useState('');
  const [resendAfter, setResendAfter] = useState(0);
  const [sendingOtp, setSendingOtp] = useState(false);
  const [verifyingOtp, setVerifyingOtp] = useState(false);

  const canRequestOtp = email.trim().length > 0 && !sendingOtp;
  const canVerifyOtp = email.trim().length > 0 && otp.trim().length > 0 && challengeId.length > 0 && !verifyingOtp;
  const otpSent = challengeId.length > 0;

  useEffect(() => {
    if (resendAfter <= 0) return;
    const timer = setInterval(() => {
      setResendAfter((value) => (value > 0 ? value - 1 : 0));
    }, 1000);
    return () => clearInterval(timer);
  }, [resendAfter]);

  useEffect(() => {
    const params = new URLSearchParams(window.location.search);
    const error = params.get('error');
    if (error) {
      toast.error('Authentication failed', { description: error.replace(/_/g, ' ') });
      params.delete('error');
      const next = params.toString();
      window.history.replaceState({}, '', next ? `?${next}` : window.location.pathname);
    }
  }, []);

  const resendLabel = useMemo(() => {
    if (resendAfter <= 0) return 'Resend OTP';
    return `Resend in 0:${String(resendAfter).padStart(2, '0')}`;
  }, [resendAfter]);

  async function requestOtp() {
    if (!canRequestOtp) return;

    setSendingOtp(true);
    try {
      const response = await fetch('/api/auth/request-otp', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        credentials: 'include',
        body: JSON.stringify({ email: email.trim() }),
      });

      const payload = (await response.json().catch(() => ({}))) as {
        message?: string;
        challenge_id?: string;
        resend_after_seconds?: number;
      };

      if (!response.ok) {
        toast.error('Could not send OTP', {
          description: payload.message === 'rate_limited'
            ? 'Too many requests. Please wait a minute and try again.'
            : 'Please check your email and try again.',
        });
        return;
      }

      const nextChallengeId = String(payload.challenge_id ?? '');
      if (!nextChallengeId) {
        toast.error('Could not send OTP', { description: 'Unexpected server response.' });
        return;
      }

      setChallengeId(nextChallengeId);
      setResendAfter(Math.max(0, Number(payload.resend_after_seconds ?? 60)));
      toast.success('OTP sent', {
        description: "If this email is allowed, you'll receive a verification code shortly.",
      });
    } finally {
      setSendingOtp(false);
    }
  }

  async function verifyOtp() {
    if (!canVerifyOtp) return;

    setVerifyingOtp(true);
    try {
      const response = await fetch('/api/auth/verify-otp', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        credentials: 'include',
        body: JSON.stringify({
          email: email.trim(),
          challengeId,
          otp: otp.trim(),
        }),
      });

      const payload = (await response.json().catch(() => ({}))) as {
        message?: string;
        user?: LoginUser;
      };

      if (!response.ok) {
        toast.error('Invalid OTP', {
          description: payload.message === 'invalid_otp'
            ? 'Code is invalid or expired. Request a new OTP and try again.'
            : 'Unable to complete sign in.',
        });
        return;
      }

      const role = payload.user?.role ?? 'viewer';
      toast.success('Authenticated successfully');
      window.location.href = roleHomePath(role);
    } finally {
      setVerifyingOtp(false);
    }
  }

  function continueWithGoogle() {
    const next = window.location.search ? window.location.search : '';
    window.location.href = `/api/auth/google/start${next}`;
  }

  return (
    <div className="min-h-screen bg-background flex">
      <div className="hidden lg:flex lg:w-1/2 xl:w-[55%] 2xl:w-[60%] relative bg-zinc-950 flex-col justify-between p-10 overflow-hidden">
        <div
          className="absolute inset-0 opacity-10"
          style={{
            backgroundImage: `linear-gradient(hsl(240 5% 16%) 1px, transparent 1px), linear-gradient(90deg, hsl(240 5% 16%) 1px, transparent 1px)`,
            backgroundSize: '40px 40px',
          }}
        />
        <div className="absolute inset-0 bg-gradient-to-br from-primary/5 via-transparent to-transparent pointer-events-none" />

        <div className="relative flex items-center gap-3">
          <AppLogo size={36} />
          <span className="text-xl font-semibold tracking-tight">Quoodle</span>
        </div>

        <div className="relative">
          <div className="inline-flex items-center gap-2 px-3 py-1.5 bg-primary/10 border border-primary/20 rounded-full text-xs text-primary font-medium mb-6">
            <span className="w-1.5 h-1.5 rounded-full bg-primary pulse-dot" />
            Push-first device management
          </div>
          <h1 className="text-4xl font-bold leading-tight tracking-tight mb-4">
            Real-time control plane
            <br />
            for Windows fleets
          </h1>
          <p className="text-muted-foreground text-base leading-relaxed max-w-md">
            Monitor device health, dispatch signed commands, and respond to security alerts from one operator console.
          </p>

          <div className="flex flex-wrap gap-2 mt-6">
            {[
              { icon: Shield, label: 'Ed25519 signed commands' },
              { icon: Terminal, label: 'Kernel Guard integration' },
              { icon: CheckCircle2, label: 'RBAC: viewer/operator/admin' },
            ].map((feat) => (
              <div key={feat.label} className="flex items-center gap-2 px-3 py-1.5 bg-muted/40 border border-border rounded-lg text-xs text-muted-foreground">
                <feat.icon size={12} />
                {feat.label}
              </div>
            ))}
          </div>
        </div>
      </div>

      <div className="flex-1 flex flex-col items-center justify-center px-6 py-10 overflow-y-auto">
        <div className="lg:hidden flex items-center gap-2 mb-8">
          <AppLogo size={32} />
          <span className="text-lg font-semibold">Quoodle</span>
        </div>

        <div className="w-full max-w-sm">
          <div className="mb-7 text-center">
            <h2 className="text-3xl font-semibold tracking-tight">Sign in / Sign up</h2>
            <p className="text-sm text-muted-foreground mt-2">
              We&apos;ll sign you in if your email is authorized in this control plane.
            </p>
          </div>

          <div className="space-y-4">
            <button
              type="button"
              onClick={continueWithGoogle}
              className="w-full h-12 rounded-xl bg-muted/80 border border-border text-sm font-medium hover:bg-muted transition-colors"
            >
              Continue with Google
            </button>

            <div className="relative py-2">
              <div className="absolute inset-0 flex items-center">
                <span className="w-full border-t border-border" />
              </div>
              <div className="relative flex justify-center text-xs uppercase">
                <span className="bg-background px-3 text-muted-foreground">Or</span>
              </div>
            </div>

            <div className="space-y-3">
              <div className="flex items-center gap-2 bg-muted/60 border border-border rounded-xl p-1.5">
                <input
                  type="email"
                  placeholder="Enter your work or personal email"
                  value={email}
                  onChange={(event) => setEmail(event.target.value)}
                  className="flex-1 bg-transparent px-3 py-2 text-sm focus:outline-none placeholder:text-muted-foreground"
                />
                <button
                  type="button"
                  onClick={requestOtp}
                  disabled={!canRequestOtp || resendAfter > 0}
                  className="rounded-lg px-3 py-2 text-xs font-medium bg-card border border-border disabled:opacity-50 disabled:cursor-not-allowed"
                >
                  {sendingOtp ? 'Sending...' : otpSent ? resendLabel : 'Send OTP'}
                </button>
              </div>

              <input
                type="text"
                placeholder="Enter OTP"
                value={otp}
                onChange={(event) => setOtp(event.target.value.replace(/\D/g, '').slice(0, 6))}
                className="w-full bg-muted/40 border border-border rounded-xl px-4 py-3 text-sm focus:outline-none placeholder:text-muted-foreground"
              />

              <button
                type="button"
                onClick={verifyOtp}
                disabled={!canVerifyOtp}
                className="w-full h-12 rounded-xl bg-muted border border-border text-sm font-semibold disabled:opacity-50 disabled:cursor-not-allowed"
              >
                {verifyingOtp ? (
                  <span className="inline-flex items-center gap-2">
                    <Loader2 size={14} className="animate-spin" />
                    Continuing...
                  </span>
                ) : (
                  'Continue'
                )}
              </button>
            </div>
          </div>

          <p className="text-xs text-muted-foreground mt-4">
            If you can&apos;t see the OTP email, check your spam or junk folder.
          </p>
          <p className="text-xs text-muted-foreground mt-4">
            By signing up or signing in, you agree to our{' '}
            <a href="#" className="text-primary hover:underline">Terms</a>
            {' '}and{' '}
            <a href="#" className="text-primary hover:underline">Privacy Policy</a>.
          </p>
        </div>
      </div>
    </div>
  );
}
