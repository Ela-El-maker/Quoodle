import { NextRequest, NextResponse } from 'next/server';
import { proxyAuthedRequest } from '../../devices/_shared';

interface Params {
  params: Promise<{ scheduleId: string }>;
}

export async function PATCH(request: NextRequest, context: Params): Promise<NextResponse> {
  const { scheduleId } = await context.params;
  const contentType = request.headers.get('content-type') ?? 'application/json';
  const body = await request.text();
  return proxyAuthedRequest(request, `/schedules/${encodeURIComponent(scheduleId)}`, {
    method: 'PATCH',
    body,
    headers: { 'Content-Type': contentType },
  });
}

export async function DELETE(request: NextRequest, context: Params): Promise<NextResponse> {
  const { scheduleId } = await context.params;
  return proxyAuthedRequest(request, `/schedules/${encodeURIComponent(scheduleId)}`, {
    method: 'DELETE',
  });
}
