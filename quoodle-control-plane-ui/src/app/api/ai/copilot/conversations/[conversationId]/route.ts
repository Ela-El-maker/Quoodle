import { NextRequest, NextResponse } from 'next/server';
import { proxyAuthedGet } from '../../../../devices/_shared';

interface RouteParams {
  params: Promise<{ conversationId: string }>;
}

export async function GET(request: NextRequest, context: RouteParams): Promise<NextResponse> {
  const { conversationId } = await context.params;
  return proxyAuthedGet(request, `/ai/copilot/conversations/${encodeURIComponent(conversationId)}`);
}
