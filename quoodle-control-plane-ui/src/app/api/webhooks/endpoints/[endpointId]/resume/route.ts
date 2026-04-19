import { NextRequest, NextResponse } from 'next/server';
import { proxyAuthedRequest } from '../../../../devices/_shared';

interface RouteContext {
  params: Promise<{ endpointId: string }>;
}

export async function POST(request: NextRequest, context: RouteContext): Promise<NextResponse> {
  const { endpointId } = await context.params;
  return proxyAuthedRequest(request, `/integrations/webhooks/endpoints/${encodeURIComponent(endpointId)}/resume`, {
    method: 'POST',
    body: '{}',
    headers: { 'Content-Type': 'application/json' },
  });
}

