import { NextRequest, NextResponse } from 'next/server';
import { proxyAuthedGet } from '../../../../devices/_shared';

interface Params {
  params: Promise<{ deviceId: string }>;
}

export async function GET(request: NextRequest, context: Params): Promise<NextResponse> {
  const { deviceId } = await context.params;
  return proxyAuthedGet(request, `/telemetry/devices/${encodeURIComponent(deviceId)}/latest`);
}

