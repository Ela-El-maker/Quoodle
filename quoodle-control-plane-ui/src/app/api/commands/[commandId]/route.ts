import { NextRequest, NextResponse } from 'next/server';
import { proxyAuthedGet } from '../../devices/_shared';

interface Params {
  params: Promise<{ commandId: string }>;
}

export async function GET(request: NextRequest, context: Params): Promise<NextResponse> {
  const { commandId } = await context.params;
  return proxyAuthedGet(request, `/commands/${encodeURIComponent(commandId)}`);
}

