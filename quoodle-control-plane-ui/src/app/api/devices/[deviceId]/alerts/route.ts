import { NextRequest, NextResponse } from 'next/server';
import { proxyAuthedGet } from '../../_shared';

interface DeviceAlertsResponse {
  alerts?: Array<{
    alert_id?: string;
    device_id?: string;
    severity?: string;
    category?: string;
    message?: string;
    timestamp?: string | null;
    acknowledged?: boolean;
  }>;
}

interface Params {
  params: Promise<{ deviceId: string }>;
}

export async function GET(request: NextRequest, context: Params): Promise<NextResponse> {
  const { deviceId } = await context.params;
  const query = request.nextUrl.searchParams;
  const limit = Math.min(Math.max(Number(query.get('limit') ?? '100'), 1), 200);
  const severity = query.get('severity');
  const upstream = severity ? `/alerts?limit=${limit}&severity=${encodeURIComponent(severity)}` : `/alerts?limit=${limit}`;

  const upstreamResponse = await proxyAuthedGet(request, upstream);
  if (!upstreamResponse.ok) {
    return upstreamResponse;
  }

  const payload = (await upstreamResponse.json().catch(() => ({}))) as DeviceAlertsResponse;
  const alerts = (payload.alerts ?? []).filter((alert) => alert.device_id === deviceId);
  return NextResponse.json({ alerts }, { status: 200 });
}
