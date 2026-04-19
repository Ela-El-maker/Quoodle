import { NextRequest, NextResponse } from 'next/server';
import { proxyAuthedRequest } from '../../../../devices/_shared';

interface RouteContext {
  params: Promise<{ endpointId: string }>;
}

export async function POST(request: NextRequest, context: RouteContext): Promise<NextResponse> {
  const { endpointId } = await context.params;
  const contentType = request.headers.get('content-type') ?? 'application/json';
  const body = await request.text();
  return proxyAuthedRequest(request, `/integrations/webhooks/endpoints/${encodeURIComponent(endpointId)}/test`, {
    method: 'POST',
    body,
    headers: { 'Content-Type': contentType },
  });
}

