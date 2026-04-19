import { NextRequest, NextResponse } from 'next/server';
import { proxyAuthedGet } from '../../devices/_shared';

export async function GET(request: NextRequest): Promise<NextResponse> {
  const query = request.nextUrl.searchParams.toString();
  const upstreamPath = query
    ? `/integrations/webhooks/deliveries?${query}`
    : '/integrations/webhooks/deliveries';
  return proxyAuthedGet(request, upstreamPath);
}

