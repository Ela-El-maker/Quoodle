import { NextRequest, NextResponse } from 'next/server';
import { proxyAuthedRequest } from '../../../devices/_shared';

interface Params {
  params: Promise<{ notificationId: string }>;
}

export async function POST(request: NextRequest, context: Params): Promise<NextResponse> {
  const { notificationId } = await context.params;
  return proxyAuthedRequest(request, `/notifications/${encodeURIComponent(notificationId)}/read`, {
    method: 'POST',
  });
}
