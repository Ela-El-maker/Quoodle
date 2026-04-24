import { NextRequest, NextResponse } from 'next/server';
import { proxyAuthedRequest } from '../../../devices/_shared';

export async function POST(request: NextRequest): Promise<NextResponse> {
  const contentType = request.headers.get('content-type') ?? 'application/json';
  const body = await request.text();

  return proxyAuthedRequest(request, '/ai/copilot/ask', {
    method: 'POST',
    body,
    headers: {
      'Content-Type': contentType,
      'X-Quoodle-Client-Channel': 'control_ui',
    },
  });
}

