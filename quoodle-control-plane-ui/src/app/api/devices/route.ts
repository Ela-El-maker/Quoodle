import { NextRequest, NextResponse } from 'next/server';
import { proxyAuthedGet } from './_shared';

export async function GET(request: NextRequest): Promise<NextResponse> {
  const query = request.nextUrl.searchParams.toString();
  const upstreamPath = query ? `/devices?${query}` : '/devices';
  return proxyAuthedGet(request, upstreamPath);
}

