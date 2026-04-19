import { NextRequest, NextResponse } from 'next/server';
import { proxyAuthedGet } from '../../../../devices/_shared';

interface RouteContext {
  params: Promise<{ endpointId: string }>;
}

export async function GET(request: NextRequest, context: RouteContext): Promise<NextResponse> {
  const { endpointId } = await context.params;
  return proxyAuthedGet(
    request,
    `/integrations/webhooks/endpoints/${encodeURIComponent(endpointId)}/reveal-secret`,
  );
}

