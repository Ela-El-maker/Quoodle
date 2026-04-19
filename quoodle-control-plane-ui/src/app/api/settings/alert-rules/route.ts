import { NextRequest, NextResponse } from 'next/server';
import { proxyAuthedGet, proxyAuthedRequest } from '../../devices/_shared';

export async function GET(request: NextRequest): Promise<NextResponse> {
  return proxyAuthedGet(request, '/settings/alert-rules');
}

export async function POST(request: NextRequest): Promise<NextResponse> {
  const contentType = request.headers.get('content-type') ?? 'application/json';
  const body = await request.text();
  return proxyAuthedRequest(request, '/settings/alert-rules', {
    method: 'POST',
    body,
    headers: { 'Content-Type': contentType },
  });
}

