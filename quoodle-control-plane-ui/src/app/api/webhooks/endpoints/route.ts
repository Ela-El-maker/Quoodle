import { NextRequest, NextResponse } from 'next/server';
import { proxyAuthedGet, proxyAuthedRequest } from '../../devices/_shared';

export async function GET(request: NextRequest): Promise<NextResponse> {
  const query = request.nextUrl.searchParams.toString();
  const upstreamPath = query
    ? `/integrations/webhooks/endpoints?${query}`
    : '/integrations/webhooks/endpoints';
  return proxyAuthedGet(request, upstreamPath);
}

export async function POST(request: NextRequest): Promise<NextResponse> {
  const contentType = request.headers.get('content-type') ?? 'application/json';
  const body = await request.text();
  return proxyAuthedRequest(request, '/integrations/webhooks/endpoints', {
    method: 'POST',
    body,
    headers: { 'Content-Type': contentType },
  });
}

