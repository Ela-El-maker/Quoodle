import { NextRequest, NextResponse } from 'next/server';
import { proxyAuthedRequest } from '../../../devices/_shared';

interface RouteContext {
  params: Promise<{ id: string }>;
}

export async function PATCH(request: NextRequest, context: RouteContext): Promise<NextResponse> {
  const { id } = await context.params;
  const contentType = request.headers.get('content-type') ?? 'application/json';
  const body = await request.text();
  return proxyAuthedRequest(request, `/settings/compliance-thresholds/${encodeURIComponent(id)}`, {
    method: 'PATCH',
    body,
    headers: { 'Content-Type': contentType },
  });
}

export async function DELETE(request: NextRequest, context: RouteContext): Promise<NextResponse> {
  const { id } = await context.params;
  return proxyAuthedRequest(request, `/settings/compliance-thresholds/${encodeURIComponent(id)}`, {
    method: 'DELETE',
  });
}

