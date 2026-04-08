import { NextRequest, NextResponse } from 'next/server';
import { AUTH_COOKIE, normalizeRole } from '@/lib/auth';
import { attachTokenCookies, clearAuthCookies, controlPlaneApiUrl } from '../_shared';

export async function POST(request: NextRequest): Promise<NextResponse> {
  const refreshToken = request.cookies.get(AUTH_COOKIE.refreshToken)?.value ?? '';
  const sessionId = request.cookies.get(AUTH_COOKIE.sessionId)?.value ?? '';
  const roleValue = normalizeRole(request.cookies.get(AUTH_COOKIE.role)?.value);

  if (!refreshToken || !sessionId) {
    const response = NextResponse.json({ authenticated: false, message: 'missing_refresh_token' }, { status: 401 });
    clearAuthCookies(response);
    return response;
  }

  const refreshResponse = await fetch(controlPlaneApiUrl('/token/refresh'), {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ refresh_token: refreshToken }),
    cache: 'no-store',
  });

  const refreshJson = (await refreshResponse.json().catch(() => ({}))) as Record<string, unknown>;
  if (!refreshResponse.ok) {
    const response = NextResponse.json(
      { authenticated: false, message: String(refreshJson.message ?? 'refresh_failed') },
      { status: 401 },
    );
    clearAuthCookies(response);
    return response;
  }

  const nextJwt = String(refreshJson.jwt ?? '');
  const nextRefreshToken = String(refreshJson.refresh_token ?? '');
  if (!nextJwt || !nextRefreshToken) {
    const response = NextResponse.json({ authenticated: false, message: 'invalid_refresh_response' }, { status: 502 });
    clearAuthCookies(response);
    return response;
  }

  const response = NextResponse.json({ authenticated: true }, { status: 200 });
  attachTokenCookies(response, {
    jwt: nextJwt,
    refreshToken: nextRefreshToken,
    sessionId,
    role: roleValue,
  });
  return response;
}
