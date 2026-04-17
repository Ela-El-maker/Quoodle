import { NextRequest, NextResponse } from 'next/server';
import { proxyAuthedRequest } from '../../../devices/_shared';

interface Params {
  params: Promise<{ scheduleId: string }>;
}

export async function POST(request: NextRequest, context: Params): Promise<NextResponse> {
  const { scheduleId } = await context.params;
  return proxyAuthedRequest(request, `/schedules/${encodeURIComponent(scheduleId)}/run-now`, {
    method: 'POST',
    body: '{}',
    headers: { 'Content-Type': 'application/json' },
  });
}
