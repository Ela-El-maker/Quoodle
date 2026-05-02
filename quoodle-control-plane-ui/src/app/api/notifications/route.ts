import { NextRequest, NextResponse } from 'next/server';
import { proxyAuthedGet, proxyAuthedRequest } from '../devices/_shared';

export async function GET(request: NextRequest): Promise<NextResponse> {
  const query = request.nextUrl.searchParams.toString();
  const upstreamPath = query ? `/notifications?${query}` : '/notifications';
  return proxyAuthedGet(request, upstreamPath);
}

export async function POST(request: NextRequest): Promise<NextResponse> {
  const bodyText = await request.text();
  return proxyAuthedRequest(request, '/notifications/read-all', {
    method: 'POST',
    body: bodyText,
    headers: { 'Content-Type': 'application/json' },
  });
}
