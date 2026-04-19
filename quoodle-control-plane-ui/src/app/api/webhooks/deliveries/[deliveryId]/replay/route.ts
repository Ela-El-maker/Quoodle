import { NextRequest, NextResponse } from 'next/server';
import { proxyAuthedRequest } from '../../../../devices/_shared';

interface RouteContext {
  params: Promise<{ deliveryId: string }>;
}

export async function POST(request: NextRequest, context: RouteContext): Promise<NextResponse> {
  const { deliveryId } = await context.params;
  return proxyAuthedRequest(
    request,
    `/integrations/webhooks/deliveries/${encodeURIComponent(deliveryId)}/replay`,
    {
      method: 'POST',
      body: '{}',
      headers: { 'Content-Type': 'application/json' },
    },
  );
}

