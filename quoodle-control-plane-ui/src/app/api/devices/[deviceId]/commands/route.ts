import { NextRequest, NextResponse } from 'next/server';
import { proxyAuthedGet } from '../../_shared';

interface Params {
  params: Promise<{ deviceId: string }>;
}

export async function GET(request: NextRequest, context: Params): Promise<NextResponse> {
  const { deviceId } = await context.params;
  const query = request.nextUrl.searchParams.toString();
  const upstreamPath = query
    ? `/devices/${encodeURIComponent(deviceId)}/commands?${query}`
    : `/devices/${encodeURIComponent(deviceId)}/commands`;
  return proxyAuthedGet(request, upstreamPath);
}
