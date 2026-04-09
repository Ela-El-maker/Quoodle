import { NextRequest, NextResponse } from 'next/server';
import { controlPlaneApiUrl } from '../_shared';

export async function POST(request: NextRequest): Promise<NextResponse> {
  let body: Record<string, unknown>;
  try {
    body = (await request.json()) as Record<string, unknown>;
  } catch {
    return NextResponse.json({ message: 'invalid_request_body' }, { status: 400 });
  }

  const email = String(body.email ?? '').trim();
  if (!email) {
    return NextResponse.json({ message: 'email_required' }, { status: 422 });
  }

  let upstreamResponse: Response;
  try {
    upstreamResponse = await fetch(controlPlaneApiUrl('/auth/request-otp'), {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email }),
      cache: 'no-store',
    });
  } catch {
    return NextResponse.json({ message: 'control_plane_unreachable' }, { status: 503 });
  }

  const upstreamJson = (await upstreamResponse.json().catch(() => ({}))) as Record<string, unknown>;
  if (!upstreamResponse.ok) {
    const fallbackMessage = upstreamResponse.status >= 500 ? 'auth_service_unavailable' : 'otp_request_failed';
    return NextResponse.json(
      {
        message: String(upstreamJson.message ?? fallbackMessage),
        errors: upstreamJson.errors ?? null,
      },
      { status: upstreamResponse.status },
    );
  }

  return NextResponse.json(
    {
      status: String(upstreamJson.status ?? 'otp_sent'),
      challenge_id: String(upstreamJson.challenge_id ?? ''),
      resend_after_seconds: Number(upstreamJson.resend_after_seconds ?? 60),
    },
    { status: 200 },
  );
}
