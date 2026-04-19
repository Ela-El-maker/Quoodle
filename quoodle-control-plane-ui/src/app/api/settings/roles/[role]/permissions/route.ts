import { NextRequest, NextResponse } from 'next/server';
import { proxyAuthedGet, proxyAuthedRequest } from '../../../../devices/_shared';

interface RouteContext {
  params: Promise<{ role: string }>;
}

export async function GET(request: NextRequest, context: RouteContext): Promise<NextResponse> {
  const { role } = await context.params;
  return proxyAuthedGet(request, `/settings/roles/${encodeURIComponent(role)}/permissions`);
}

export async function PATCH(request: NextRequest, context: RouteContext): Promise<NextResponse> {
  const { role } = await context.params;
  const contentType = request.headers.get('content-type') ?? 'application/json';
  const body = await request.text();
  return proxyAuthedRequest(request, `/settings/roles/${encodeURIComponent(role)}/permissions`, {
    method: 'PATCH',
    body,
    headers: { 'Content-Type': contentType },
  });
}
