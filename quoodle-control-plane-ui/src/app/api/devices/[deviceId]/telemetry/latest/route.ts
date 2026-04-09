import { NextRequest, NextResponse } from 'next/server';
import { proxyAuthedGet } from '../../../_shared';

interface Params {
  params: Promise<{ deviceId: string }>;
}

export async function GET(request: NextRequest, context: Params): Promise<NextResponse> {
  const { deviceId } = await context.params;
  return proxyAuthedGet(request, `/devices/${encodeURIComponent(deviceId)}/telemetry/latest`);
}
