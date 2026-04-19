import { NextRequest, NextResponse } from 'next/server';
import { proxyAuthedRequest } from '../../../devices/_shared';

interface RouteContext {
  params: Promise<{ id: string }>;
}

export async function PATCH(request: NextRequest, context: RouteContext): Promise<NextResponse> {
  const { id } = await context.params;
  const contentType = request.headers.get('content-type') ?? 'application/json';
  const body = await request.text();
  return proxyAuthedRequest(request, `/settings/team-members/${encodeURIComponent(id)}`, {
    method: 'PATCH',
    body,
    headers: { 'Content-Type': contentType },
  });
}

