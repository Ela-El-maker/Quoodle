import { NextRequest, NextResponse } from 'next/server';
import { proxyAuthedGet, proxyAuthedRequest } from '../devices/_shared';

export async function GET(request: NextRequest): Promise<NextResponse> {
  const query = request.nextUrl.searchParams.toString();
  const upstreamPath = query ? `/commands?${query}` : '/commands';
  return proxyAuthedGet(request, upstreamPath);
}

export async function POST(request: NextRequest): Promise<NextResponse> {
  const contentType = request.headers.get('content-type') ?? 'application/json';
  const rawBody = await request.text();
  let body = rawBody;

  if (contentType.toLowerCase().includes('application/json')) {
    try {
      const parsed = JSON.parse(rawBody) as {
        method?: unknown;
        params?: Record<string, unknown> | null;
      };

      if (String(parsed?.method ?? '').trim().toLowerCase() === 'list_files' && parsed && typeof parsed === 'object') {
        const params =
          parsed.params && typeof parsed.params === 'object' && !Array.isArray(parsed.params)
            ? { ...parsed.params }
            : {};

        const limitRaw = Number(params.limit);
        if (Number.isFinite(limitRaw)) {
          params.limit = Math.min(Math.max(Math.trunc(limitRaw), 1), 1000);
        } else {
          params.limit = 200;
        }

        const depthRaw = Number(params.max_depth);
        if (Number.isFinite(depthRaw)) {
          params.max_depth = Math.min(Math.max(Math.trunc(depthRaw), 1), 8);
        } else {
          params.max_depth = 1;
        }

        params.recursive = params.recursive === true;
        if (typeof params.path !== 'string' || params.path.trim() === '') {
          params.path = 'C:\\Users';
        }

        parsed.params = params;
        body = JSON.stringify(parsed);
      }
    } catch {
      body = rawBody;
    }
  }

  return proxyAuthedRequest(request, '/commands', {
    method: 'POST',
    body,
    headers: { 'Content-Type': contentType },
  });
}
