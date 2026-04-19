import { NextRequest, NextResponse } from 'next/server';
import { proxyAuthedRequest } from '../../../../../devices/_shared';

interface RouteContext {
  params: Promise<{ id: string; deviceId: string }>;
}

export async function DELETE(request: NextRequest, context: RouteContext): Promise<NextResponse> {
  const { id, deviceId } = await context.params;
  return proxyAuthedRequest(
    request,
    `/settings/team-members/${encodeURIComponent(id)}/device-access/${encodeURIComponent(deviceId)}`,
    { method: 'DELETE' },
  );
}
