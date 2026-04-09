import { NextRequest, NextResponse } from 'next/server';
import { roleHomePath } from '@/lib/auth';
import {
  attachAuthCookies,
  authCookiesFromPayload,
  controlPlaneApiUrl,
} from '../../_shared';

function decodeState(state: string): { nonce?: string; next?: string } | null {
  try {
    const text = Buffer.from(state, 'base64url').toString('utf-8');
    const parsed = JSON.parse(text) as { nonce?: string; next?: string };
    return parsed;
  } catch {
    return null;
  }
}

function publicOrigin(request: NextRequest): string {
  const forwardedProto = request.headers.get('x-forwarded-proto');
  const forwardedHost = request.headers.get('x-forwarded-host');
  const host = forwardedHost ?? request.headers.get('host') ?? request.nextUrl.host;
  const proto = forwardedProto ?? request.nextUrl.protocol.replace(':', '');
  return `${proto}://${host}`;
}

function configuredUiOrigin(): string | null {
  const candidates = [
    process.env.GOOGLE_OAUTH_REDIRECT_BASE_URL,
    process.env.CONTROL_PLANE_UI_URL,
    process.env.NEXT_PUBLIC_CONTROL_PLANE_UI_URL,
  ];
  for (const candidate of candidates) {
    const value = (candidate ?? '').trim();
    if (!value) continue;
    try {
      return new URL(value).origin;
    } catch {
      continue;
    }
  }
  return null;
}

function googleRedirectUri(request: NextRequest): string {
  const explicit = (process.env.GOOGLE_OAUTH_REDIRECT_URI ?? '').trim();
  if (explicit) return explicit;
  const origin = configuredUiOrigin() ?? publicOrigin(request);
  return `${origin.replace(/\/+$/, '')}/api/auth/google/callback`;
}

export async function GET(request: NextRequest): Promise<NextResponse> {
  const code = request.nextUrl.searchParams.get('code') ?? '';
  const state = request.nextUrl.searchParams.get('state') ?? '';
  const storedState = request.cookies.get('quoodle_google_oauth_state')?.value ?? '';

  const loginUrl = new URL('/sign-up-login-screen', publicOrigin(request));
  if (!code || !state || !storedState || state !== storedState) {
    loginUrl.searchParams.set('error', 'google_state_invalid');
    const response = NextResponse.redirect(loginUrl);
    response.cookies.delete('quoodle_google_oauth_state');
    return response;
  }

  const redirectUri = googleRedirectUri(request);

  const exchangeResponse = await fetch(controlPlaneApiUrl('/auth/google/exchange'), {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      code,
      redirect_uri: redirectUri,
      device_fingerprint: `${request.headers.get('user-agent') ?? 'unknown-agent'}|${request.headers.get('x-forwarded-for') ?? 'unknown-ip'}`.slice(0, 255),
    }),
    cache: 'no-store',
  });

  const exchangeJson = (await exchangeResponse.json().catch(() => ({}))) as Record<string, unknown>;
  if (!exchangeResponse.ok) {
    loginUrl.searchParams.set('error', String(exchangeJson.message ?? 'google_exchange_failed'));
    const response = NextResponse.redirect(loginUrl);
    response.cookies.delete('quoodle_google_oauth_state');
    return response;
  }

  const cookieValues = authCookiesFromPayload(exchangeJson);
  if (!cookieValues) {
    loginUrl.searchParams.set('error', 'invalid_google_exchange_response');
    const response = NextResponse.redirect(loginUrl);
    response.cookies.delete('quoodle_google_oauth_state');
    return response;
  }

  const parsedState = decodeState(state);
  const nextFromState = typeof parsedState?.next === 'string' ? parsedState.next : '';
  const redirectPath = nextFromState && nextFromState.startsWith('/') ? nextFromState : roleHomePath(cookieValues.role);

  const response = NextResponse.redirect(new URL(redirectPath, publicOrigin(request)));
  attachAuthCookies(response, cookieValues, request);
  response.cookies.delete('quoodle_google_oauth_state');
  return response;
}
