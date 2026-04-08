import { NextRequest, NextResponse } from 'next/server';
import { AUTH_COOKIE } from '@/lib/auth';
import { clearAuthCookies, controlPlaneApiUrl } from '../_shared';

export async function POST(request: NextRequest): Promise<NextResponse> {
  const jwt = request.cookies.get(AUTH_COOKIE.jwt)?.value ?? '';
  const sessionId = request.cookies.get(AUTH_COOKIE.sessionId)?.value ?? '';

  if (jwt && sessionId) {
    await fetch(controlPlaneApiUrl('/logout'), {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${jwt}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ session_id: sessionId, all_devices: false }),
      cache: 'no-store',
    }).catch(() => null);
  }

  const response = NextResponse.json({ ok: true }, { status: 200 });
  clearAuthCookies(response);
  return response;
}
