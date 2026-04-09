import { NextRequest, NextResponse } from 'next/server';
import { proxyAuthedGet } from '../../../devices/_shared';

interface Params {
  params: Promise<{ deviceId: string }>;
}

export async function GET(request: NextRequest, context: Params): Promise<NextResponse> {
  const { deviceId } = await context.params;
  const query = request.nextUrl.searchParams.toString();
  const upstreamPath = query
    ? `/audit/device/${encodeURIComponent(deviceId)}?${query}`
    : `/audit/device/${encodeURIComponent(deviceId)}`;
  return proxyAuthedGet(request, upstreamPath);
}
