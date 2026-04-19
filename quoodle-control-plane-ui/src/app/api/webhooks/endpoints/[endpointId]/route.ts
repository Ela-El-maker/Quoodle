import { NextRequest, NextResponse } from 'next/server';
import { proxyAuthedGet, proxyAuthedRequest } from '../../../devices/_shared';

interface RouteContext {
  params: Promise<{ endpointId: string }>;
}

export async function GET(request: NextRequest, context: RouteContext): Promise<NextResponse> {
  const { endpointId } = await context.params;
  return proxyAuthedGet(request, `/integrations/webhooks/endpoints/${encodeURIComponent(endpointId)}`);
}

export async function PATCH(request: NextRequest, context: RouteContext): Promise<NextResponse> {
  const { endpointId } = await context.params;
  const contentType = request.headers.get('content-type') ?? 'application/json';
  const body = await request.text();
  return proxyAuthedRequest(request, `/integrations/webhooks/endpoints/${encodeURIComponent(endpointId)}`, {
    method: 'PATCH',
    body,
    headers: { 'Content-Type': contentType },
  });
}

export async function DELETE(request: NextRequest, context: RouteContext): Promise<NextResponse> {
  const { endpointId } = await context.params;
  return proxyAuthedRequest(request, `/integrations/webhooks/endpoints/${encodeURIComponent(endpointId)}`, {
    method: 'DELETE',
  });
}

