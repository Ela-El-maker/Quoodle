import { NextRequest, NextResponse } from 'next/server';
import { proxyAuthedGet, proxyAuthedRequest } from '../../devices/_shared';

function upstreamPath(request: NextRequest): string {
  const deviceId = request.nextUrl.searchParams.get('device_id')?.trim();
  if (!deviceId) return '/policy/app-lock';
  return `/policy/app-lock?device_id=${encodeURIComponent(deviceId)}`;
}

export async function GET(request: NextRequest): Promise<NextResponse> {
  return proxyAuthedGet(request, upstreamPath(request));
}

export async function PUT(request: NextRequest): Promise<NextResponse> {
  const contentType = request.headers.get('content-type') ?? 'application/json';
  const body = await request.text();
  return proxyAuthedRequest(request, upstreamPath(request), {
    method: 'PUT',
    headers: { 'Content-Type': contentType },
    body,
  });
}

export async function DELETE(request: NextRequest): Promise<NextResponse> {
  return proxyAuthedRequest(request, upstreamPath(request), {
    method: 'DELETE',
  });
}
