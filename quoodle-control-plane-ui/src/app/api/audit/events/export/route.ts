import { NextRequest, NextResponse } from 'next/server';
import { proxyAuthedBinaryGet } from '../../../devices/_shared';

export async function GET(request: NextRequest): Promise<NextResponse> {
  const query = request.nextUrl.searchParams.toString();
  const upstreamPath = query ? `/audit/events/export?${query}` : '/audit/events/export';
  return proxyAuthedBinaryGet(request, upstreamPath);
}

