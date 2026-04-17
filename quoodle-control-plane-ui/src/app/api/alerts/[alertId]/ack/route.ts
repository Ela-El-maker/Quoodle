import { NextRequest, NextResponse } from 'next/server';
import { proxyAuthedRequest } from '../../../devices/_shared';

interface Params {
  params: Promise<{ alertId: string }>;
}

export async function POST(request: NextRequest, context: Params): Promise<NextResponse> {
  const { alertId } = await context.params;
  return proxyAuthedRequest(request, `/alerts/${encodeURIComponent(alertId)}/ack`, {
    method: 'POST',
  });
}
