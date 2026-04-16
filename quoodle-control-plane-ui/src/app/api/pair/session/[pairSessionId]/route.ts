import { NextRequest, NextResponse } from 'next/server';
import { proxyAuthedGet } from '../../../devices/_shared';

interface Params {
  pairSessionId: string;
}

export async function GET(
  request: NextRequest,
  { params }: { params: Promise<Params> },
): Promise<NextResponse> {
  const { pairSessionId } = await params;
  const sessionId = encodeURIComponent(pairSessionId ?? '');
  return proxyAuthedGet(request, `/pair/session/${sessionId}`);
}
