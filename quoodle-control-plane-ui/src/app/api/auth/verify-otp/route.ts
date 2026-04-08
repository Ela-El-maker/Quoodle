import { NextRequest, NextResponse } from 'next/server';
import {
  attachAuthCookies,
  authCookiesFromPayload,
  deriveDeviceFingerprint,
  controlPlaneApiUrl,
  type MePayload,
  mapMePayload,
} from '../_shared';

export async function POST(request: NextRequest): Promise<NextResponse> {
  let body: Record<string, unknown>;
  try {
    body = (await request.json()) as Record<string, unknown>;
  } catch {
    return NextResponse.json({ message: 'invalid_request_body' }, { status: 400 });
  }

  const email = String(body.email ?? '').trim();
  const challengeId = String(body.challengeId ?? body.challenge_id ?? '').trim();
  const otp = String(body.otp ?? '').trim();

  if (!email || !challengeId || !otp) {
    return NextResponse.json({ message: 'email_challenge_otp_required' }, { status: 422 });
  }

  const verifyResponse = await fetch(controlPlaneApiUrl('/auth/verify-otp'), {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      email,
      challenge_id: challengeId,
      otp,
      device_fingerprint: deriveDeviceFingerprint(request),
    }),
    cache: 'no-store',
  });

  const verifyJson = (await verifyResponse.json().catch(() => ({}))) as Record<string, unknown>;
  if (!verifyResponse.ok) {
    return NextResponse.json(
      {
        message: String(verifyJson.message ?? 'otp_verify_failed'),
        errors: verifyJson.errors ?? null,
      },
      { status: verifyResponse.status },
    );
  }

  const cookieValues = authCookiesFromPayload(verifyJson);
  if (!cookieValues) {
    return NextResponse.json({ message: 'invalid_verify_response' }, { status: 502 });
  }

  let user =
    mapMePayload({
      user_id: String(verifyJson.user_id ?? ''),
      email,
      display_name: String(verifyJson.display_name ?? email),
      user_role: String(verifyJson.user_role ?? cookieValues.role),
      two_factor_enabled: false,
    } as MePayload) ?? null;

  if (!user) {
    const meResponse = await fetch(controlPlaneApiUrl('/me'), {
      method: 'GET',
      headers: { Authorization: `Bearer ${cookieValues.jwt}` },
      cache: 'no-store',
    });
    if (meResponse.ok) {
      const meJson = (await meResponse.json().catch(() => null)) as Record<string, unknown> | null;
      if (meJson) {
        user = mapMePayload({
          user_id: String(meJson.user_id ?? ''),
          email: String(meJson.email ?? ''),
          display_name: String(meJson.display_name ?? ''),
          user_role: String(meJson.user_role ?? ''),
          two_factor_enabled: Boolean(meJson.two_factor_enabled),
        } as MePayload);
      }
    }
  }

  const response = NextResponse.json(
    {
      ok: true,
      user: user ?? {
        id: String(verifyJson.user_id ?? ''),
        email,
        name: email,
        role: cookieValues.role,
      },
    },
    { status: 200 },
  );

  attachAuthCookies(response, cookieValues);
  return response;
}

