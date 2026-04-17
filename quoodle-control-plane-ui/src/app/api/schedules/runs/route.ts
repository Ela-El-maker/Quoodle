import { NextRequest, NextResponse } from 'next/server';
import { proxyAuthedGet } from '../../devices/_shared';

export async function GET(request: NextRequest): Promise<NextResponse> {
  const query = request.nextUrl.searchParams.toString();
  const upstreamPath = query ? `/schedules/runs?${query}` : '/schedules/runs';
  return proxyAuthedGet(request, upstreamPath);
}
