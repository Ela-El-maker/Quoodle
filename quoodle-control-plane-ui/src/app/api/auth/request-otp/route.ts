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

  const upstreamResponse = await fetch(controlPlaneApiUrl('/auth/request-otp'), {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email }),
    cache: 'no-store',
  });

  const upstreamJson = (await upstreamResponse.json().catch(() => ({}))) as Record<string, unknown>;
  if (!upstreamResponse.ok) {
    return NextResponse.json(
      {
        message: String(upstreamJson.message ?? 'otp_request_failed'),
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

