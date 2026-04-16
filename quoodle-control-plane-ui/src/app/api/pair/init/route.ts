import { NextRequest, NextResponse } from 'next/server';
import { proxyAuthedRequest } from '../../devices/_shared';

export async function POST(request: NextRequest): Promise<NextResponse> {
  const contentType = request.headers.get('content-type') ?? 'application/json';
  const body = await request.text();

  return proxyAuthedRequest(request, '/pair/init', {
    method: 'POST',
    body,
    headers: { 'Content-Type': contentType },
  });
}
