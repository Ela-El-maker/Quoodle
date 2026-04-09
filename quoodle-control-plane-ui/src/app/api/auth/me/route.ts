import { NextRequest, NextResponse } from 'next/server';
import { AUTH_COOKIE, normalizeRole } from '@/lib/auth';
import {
  attachTokenCookies,
  clearAuthCookies,
  controlPlaneApiUrl,
  shouldUseSecureCookies,
  type MePayload,
  mapMePayload,
} from '../_shared';

async function fetchMeWithJwt(jwt: string): Promise<Response> {
  return fetch(controlPlaneApiUrl('/me'), {
    method: 'GET',
    headers: { Authorization: `Bearer ${jwt}` },
    cache: 'no-store',
  });
}

async function refreshJwt(refreshToken: string): Promise<{ jwt: string; refreshToken: string } | null> {
  const response = await fetch(controlPlaneApiUrl('/token/refresh'), {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ refresh_token: refreshToken }),
    cache: 'no-store',
  });
  if (!response.ok) return null;

  const payload = (await response.json().catch(() => ({}))) as Record<string, unknown>;
  const jwt = String(payload.jwt ?? '');
  const nextRefreshToken = String(payload.refresh_token ?? '');
  if (!jwt || !nextRefreshToken) return null;

  return { jwt, refreshToken: nextRefreshToken };
}

export async function GET(request: NextRequest): Promise<NextResponse> {
  const jwt = request.cookies.get(AUTH_COOKIE.jwt)?.value ?? '';
  const refreshToken = request.cookies.get(AUTH_COOKIE.refreshToken)?.value ?? '';
  const sessionId = request.cookies.get(AUTH_COOKIE.sessionId)?.value ?? '';
  const roleCookie = normalizeRole(request.cookies.get(AUTH_COOKIE.role)?.value);

  if (!jwt) {
    const response = NextResponse.json({ authenticated: false }, { status: 401 });
    clearAuthCookies(response);
    return response;
  }

  let activeJwt = jwt;
  let activeRefreshToken = refreshToken;

  let meResponse = await fetchMeWithJwt(activeJwt);
  if (meResponse.status === 401 && refreshToken && sessionId) {
    const refreshed = await refreshJwt(refreshToken);
    if (refreshed) {
      activeJwt = refreshed.jwt;
      activeRefreshToken = refreshed.refreshToken;
      meResponse = await fetchMeWithJwt(activeJwt);
    }
  }

  if (!meResponse.ok) {
    const response = NextResponse.json({ authenticated: false }, { status: 401 });
    clearAuthCookies(response);
    return response;
  }

  const meJson = (await meResponse.json().catch(() => null)) as MePayload | null;
  const user = meJson ? mapMePayload(meJson) : null;
  if (!user) {
    const response = NextResponse.json({ authenticated: false }, { status: 502 });
    clearAuthCookies(response);
    return response;
  }

  const response = NextResponse.json({ authenticated: true, user }, { status: 200 });
  if (activeRefreshToken && sessionId) {
    attachTokenCookies(response, {
      jwt: activeJwt,
      refreshToken: activeRefreshToken,
      sessionId,
      role: normalizeRole(user.role) ?? roleCookie,
    }, request);
  } else {
    const secure = shouldUseSecureCookies(request);
    response.cookies.set({
      name: AUTH_COOKIE.role,
      value: user.role,
      httpOnly: false,
      sameSite: 'lax',
      secure,
      path: '/',
    });
  }

  return response;
}
