import { NextRequest, NextResponse } from 'next/server';
import { AUTH_COOKIE, normalizeRole, type AuthUser, type UserRole } from '@/lib/auth';

const CONTROL_PLANE_API_URL =
  process.env.CONTROL_PLANE_API_URL ??
  process.env.NEXT_PUBLIC_CONTROL_PLANE_API_URL ??
  'http://localhost:8088/api';

const SECURE_COOKIE = process.env.NODE_ENV === 'production';

export interface AuthTokenPayload {
  jwt: string;
  refresh_token: string;
  session_id: string;
  user_id: string;
  user_role: string;
}

export interface MePayload {
  user_id: string;
  email: string;
  display_name: string;
  user_role: string;
  two_factor_enabled: boolean;
}

export function controlPlaneApiUrl(path: string): string {
  const normalized = path.startsWith('/') ? path.slice(1) : path;
  return `${CONTROL_PLANE_API_URL.replace(/\/+$/, '')}/${normalized}`;
}

export function authCookiesFromPayload(payload: Record<string, unknown> | AuthTokenPayload): {
  jwt: string;
  refreshToken: string;
  sessionId: string;
  role: UserRole;
} | null {
  const jwt = String(payload.jwt ?? '');
  const refreshToken = String(payload.refresh_token ?? '');
  const sessionId = String(payload.session_id ?? '');
  const role = normalizeRole(String(payload.user_role ?? ''));
  if (!jwt || !refreshToken || !sessionId || !role) {
    return null;
  }

  return {
    jwt,
    refreshToken,
    sessionId,
    role,
  };
}

export function deriveDeviceFingerprint(request: NextRequest): string {
  const userAgent = request.headers.get('user-agent') ?? 'unknown-agent';
  const forwardedFor = request.headers.get('x-forwarded-for') ?? 'unknown-ip';
  return `${userAgent}|${forwardedFor}`.slice(0, 255);
}

export function mapMePayload(payload: MePayload): AuthUser | null {
  const role = normalizeRole(payload.user_role);
  if (!role || !payload.user_id || !payload.email || !payload.display_name) {
    return null;
  }

  return {
    id: payload.user_id,
    email: payload.email,
    name: payload.display_name,
    role,
    twoFactorEnabled: Boolean(payload.two_factor_enabled),
  };
}

export function attachAuthCookies(
  response: NextResponse,
  cookies: { jwt: string; refreshToken: string; sessionId: string; role: UserRole },
): void {
  response.cookies.set({
    name: AUTH_COOKIE.jwt,
    value: cookies.jwt,
    httpOnly: true,
    sameSite: 'lax',
    secure: SECURE_COOKIE,
    path: '/',
  });
  response.cookies.set({
    name: AUTH_COOKIE.refreshToken,
    value: cookies.refreshToken,
    httpOnly: true,
    sameSite: 'lax',
    secure: SECURE_COOKIE,
    path: '/',
  });
  response.cookies.set({
    name: AUTH_COOKIE.sessionId,
    value: cookies.sessionId,
    httpOnly: true,
    sameSite: 'lax',
    secure: SECURE_COOKIE,
    path: '/',
  });
  response.cookies.set({
    name: AUTH_COOKIE.role,
    value: cookies.role,
    httpOnly: false,
    sameSite: 'lax',
    secure: SECURE_COOKIE,
    path: '/',
  });
}

export function attachTokenCookies(
  response: NextResponse,
  cookies: { jwt: string; refreshToken: string; sessionId: string; role?: UserRole | null },
): void {
  response.cookies.set({
    name: AUTH_COOKIE.jwt,
    value: cookies.jwt,
    httpOnly: true,
    sameSite: 'lax',
    secure: SECURE_COOKIE,
    path: '/',
  });
  response.cookies.set({
    name: AUTH_COOKIE.refreshToken,
    value: cookies.refreshToken,
    httpOnly: true,
    sameSite: 'lax',
    secure: SECURE_COOKIE,
    path: '/',
  });
  response.cookies.set({
    name: AUTH_COOKIE.sessionId,
    value: cookies.sessionId,
    httpOnly: true,
    sameSite: 'lax',
    secure: SECURE_COOKIE,
    path: '/',
  });
  if (cookies.role) {
    response.cookies.set({
      name: AUTH_COOKIE.role,
      value: cookies.role,
      httpOnly: false,
      sameSite: 'lax',
      secure: SECURE_COOKIE,
      path: '/',
    });
  }
}

export function clearAuthCookies(response: NextResponse): void {
  response.cookies.delete(AUTH_COOKIE.jwt);
  response.cookies.delete(AUTH_COOKIE.refreshToken);
  response.cookies.delete(AUTH_COOKIE.sessionId);
  response.cookies.delete(AUTH_COOKIE.role);
}
