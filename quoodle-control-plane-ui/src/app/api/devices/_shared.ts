import { NextRequest, NextResponse } from 'next/server';
import { AUTH_COOKIE, normalizeRole } from '@/lib/auth';
import {
  attachTokenCookies,
  clearAuthCookies,
  controlPlaneApiUrl,
} from '../auth/_shared';

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

interface ProxyRequestOptions {
  method?: 'GET' | 'POST' | 'PUT' | 'PATCH' | 'DELETE';
  body?: string;
  headers?: Record<string, string>;
}

export async function proxyAuthedRequest(
  request: NextRequest,
  upstreamPath: string,
  options: ProxyRequestOptions = {},
): Promise<NextResponse> {
  const jwt = request.cookies.get(AUTH_COOKIE.jwt)?.value ?? '';
  const refreshToken = request.cookies.get(AUTH_COOKIE.refreshToken)?.value ?? '';
  const sessionId = request.cookies.get(AUTH_COOKIE.sessionId)?.value ?? '';
  const role = normalizeRole(request.cookies.get(AUTH_COOKIE.role)?.value);

  if (!jwt) {
    const response = NextResponse.json({ message: 'unauthenticated' }, { status: 401 });
    clearAuthCookies(response);
    return response;
  }

  let activeJwt = jwt;
  let activeRefreshToken = refreshToken;
  let didRefresh = false;
  const method = options.method ?? 'GET';
  const upstreamHeaders: Record<string, string> = {
    Authorization: `Bearer ${activeJwt}`,
    ...options.headers,
  };

  let upstreamResponse = await fetch(controlPlaneApiUrl(upstreamPath), {
    method,
    headers: upstreamHeaders,
    body: options.body,
    cache: 'no-store',
  });

  if (upstreamResponse.status === 401 && refreshToken && sessionId) {
    const refreshed = await refreshJwt(refreshToken);
    if (refreshed) {
      didRefresh = true;
      activeJwt = refreshed.jwt;
      activeRefreshToken = refreshed.refreshToken;
      const retryHeaders: Record<string, string> = {
        Authorization: `Bearer ${activeJwt}`,
        ...options.headers,
      };
      upstreamResponse = await fetch(controlPlaneApiUrl(upstreamPath), {
        method,
        headers: retryHeaders,
        body: options.body,
        cache: 'no-store',
      });
    }
  }

  if (upstreamResponse.status === 401) {
    const response = NextResponse.json({ message: 'unauthenticated' }, { status: 401 });
    clearAuthCookies(response);
    return response;
  }

  const payload = (await upstreamResponse.json().catch(() => null)) as unknown;
  const response = NextResponse.json(
    payload ?? { message: 'upstream_error' },
    { status: payload ? upstreamResponse.status : 502 },
  );

  if (didRefresh && activeRefreshToken && sessionId) {
    attachTokenCookies(response, {
      jwt: activeJwt,
      refreshToken: activeRefreshToken,
      sessionId,
      role,
    });
  }

  return response;
}

export async function proxyAuthedGet(request: NextRequest, upstreamPath: string): Promise<NextResponse> {
  return proxyAuthedRequest(request, upstreamPath, { method: 'GET' });
}

export async function proxyAuthedBinaryGet(request: NextRequest, upstreamPath: string): Promise<NextResponse> {
  const jwt = request.cookies.get(AUTH_COOKIE.jwt)?.value ?? '';
  const refreshToken = request.cookies.get(AUTH_COOKIE.refreshToken)?.value ?? '';
  const sessionId = request.cookies.get(AUTH_COOKIE.sessionId)?.value ?? '';
  const role = normalizeRole(request.cookies.get(AUTH_COOKIE.role)?.value);

  if (!jwt) {
    const response = NextResponse.json({ message: 'unauthenticated' }, { status: 401 });
    clearAuthCookies(response);
    return response;
  }

  let activeJwt = jwt;
  let activeRefreshToken = refreshToken;
  let didRefresh = false;

  let upstreamResponse = await fetch(controlPlaneApiUrl(upstreamPath), {
    method: 'GET',
    headers: {
      Authorization: `Bearer ${activeJwt}`,
    },
    cache: 'no-store',
  });

  if (upstreamResponse.status === 401 && refreshToken && sessionId) {
    const refreshed = await refreshJwt(refreshToken);
    if (refreshed) {
      didRefresh = true;
      activeJwt = refreshed.jwt;
      activeRefreshToken = refreshed.refreshToken;
      upstreamResponse = await fetch(controlPlaneApiUrl(upstreamPath), {
        method: 'GET',
        headers: {
          Authorization: `Bearer ${activeJwt}`,
        },
        cache: 'no-store',
      });
    }
  }

  if (upstreamResponse.status === 401) {
    const response = NextResponse.json({ message: 'unauthenticated' }, { status: 401 });
    clearAuthCookies(response);
    return response;
  }

  const body = await upstreamResponse.arrayBuffer();
  const response = new NextResponse(body, {
    status: upstreamResponse.status,
  });

  const contentType = upstreamResponse.headers.get('content-type');
  const contentDisposition = upstreamResponse.headers.get('content-disposition');
  const cacheControl = upstreamResponse.headers.get('cache-control');
  if (contentType) response.headers.set('content-type', contentType);
  if (contentDisposition) response.headers.set('content-disposition', contentDisposition);
  if (cacheControl) response.headers.set('cache-control', cacheControl);

  if (didRefresh && activeRefreshToken && sessionId) {
    attachTokenCookies(response, {
      jwt: activeJwt,
      refreshToken: activeRefreshToken,
      sessionId,
      role,
    });
  }

  return response;
}
