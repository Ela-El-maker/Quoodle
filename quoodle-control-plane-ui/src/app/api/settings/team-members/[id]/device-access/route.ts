import { NextRequest, NextResponse } from 'next/server';
import { proxyAuthedGet, proxyAuthedRequest } from '../../../../devices/_shared';

interface RouteContext {
  params: Promise<{ id: string }>;
}

export async function GET(request: NextRequest, context: RouteContext): Promise<NextResponse> {
  const { id } = await context.params;
  return proxyAuthedGet(request, `/settings/team-members/${encodeURIComponent(id)}/device-access`);
}

export async function POST(request: NextRequest, context: RouteContext): Promise<NextResponse> {
  const { id } = await context.params;
  const contentType = request.headers.get('content-type') ?? 'application/json';
  const body = await request.text();
  return proxyAuthedRequest(request, `/settings/team-members/${encodeURIComponent(id)}/device-access`, {
    method: 'POST',
    body,
    headers: { 'Content-Type': contentType },
  });
}
