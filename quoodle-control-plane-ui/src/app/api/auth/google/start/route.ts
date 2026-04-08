import { NextRequest, NextResponse } from 'next/server';

function base64Url(input: string): string {
  return Buffer.from(input, 'utf-8').toString('base64url');
}

export async function GET(request: NextRequest): Promise<NextResponse> {
  const clientId = process.env.GOOGLE_CLIENT_ID ?? '';
  if (!clientId) {
    return NextResponse.json({ message: 'google_client_id_missing' }, { status: 500 });
  }

  const origin = request.nextUrl.origin;
  const redirectUri = `${origin}/api/auth/google/callback`;
  const statePayload = {
    nonce: crypto.randomUUID(),
    next: request.nextUrl.searchParams.get('next') ?? '',
  };
  const state = base64Url(JSON.stringify(statePayload));

  const googleUrl = new URL('https://accounts.google.com/o/oauth2/v2/auth');
  googleUrl.searchParams.set('client_id', clientId);
  googleUrl.searchParams.set('redirect_uri', redirectUri);
  googleUrl.searchParams.set('response_type', 'code');
  googleUrl.searchParams.set('scope', 'openid email profile');
  googleUrl.searchParams.set('prompt', 'select_account');
  googleUrl.searchParams.set('state', state);

  const response = NextResponse.redirect(googleUrl);
  response.cookies.set({
    name: 'quoodle_google_oauth_state',
    value: state,
    httpOnly: true,
    sameSite: 'lax',
    secure: process.env.NODE_ENV === 'production',
    path: '/',
    maxAge: 10 * 60,
  });
  return response;
}

