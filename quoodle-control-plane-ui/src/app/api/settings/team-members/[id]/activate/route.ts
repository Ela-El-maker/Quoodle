import { NextRequest, NextResponse } from 'next/server';
import { proxyAuthedRequest } from '../../../../devices/_shared';

interface RouteContext {
  params: Promise<{ id: string }>;
}

export async function POST(request: NextRequest, context: RouteContext): Promise<NextResponse> {
  const { id } = await context.params;
  return proxyAuthedRequest(request, `/settings/team-members/${encodeURIComponent(id)}/activate`, {
    method: 'POST',
    body: '{}',
    headers: { 'Content-Type': 'application/json' },
  });
}

