import { NextRequest, NextResponse } from 'next/server';
import { proxyAuthedGet } from '../../../devices/_shared';

export async function GET(request: NextRequest): Promise<NextResponse> {
  const query = request.nextUrl.searchParams.toString();
  const upstream = query ? `/telemetry/fleet/timeseries?${query}` : '/telemetry/fleet/timeseries';
  return proxyAuthedGet(request, upstream);
}

