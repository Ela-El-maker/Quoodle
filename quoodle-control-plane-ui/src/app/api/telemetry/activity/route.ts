import { NextRequest, NextResponse } from 'next/server';
import { proxyAuthedGet } from '../../devices/_shared';

export async function GET(request: NextRequest): Promise<NextResponse> {
  const query = request.nextUrl.searchParams.toString();
  const upstream = query ? `/telemetry/activity?${query}` : '/telemetry/activity';
  return proxyAuthedGet(request, upstream);
}

