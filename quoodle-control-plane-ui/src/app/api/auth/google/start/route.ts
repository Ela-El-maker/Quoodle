import { NextRequest, NextResponse } from 'next/server';

function base64Url(input: string): string {
  return Buffer.from(input, 'utf-8').toString('base64url');
}

function publicOrigin(request: NextRequest): string {
  const forwardedProto = request.headers.get('x-forwarded-proto');
  const forwardedHost = request.headers.get('x-forwarded-host');
  const host = forwardedHost ?? request.headers.get('host') ?? request.nextUrl.host;
  const proto = forwardedProto ?? request.nextUrl.protocol.replace(':', '');
  return `${proto}://${host}`;
}

function configuredUiOrigin(): string | null {
  const candidates = [
    process.env.GOOGLE_OAUTH_REDIRECT_BASE_URL,
    process.env.CONTROL_PLANE_UI_URL,
    process.env.NEXT_PUBLIC_CONTROL_PLANE_UI_URL,
  ];
  for (const candidate of candidates) {
    const value = (candidate ?? '').trim();
    if (!value) continue;
    try {
      return new URL(value).origin;
    } catch {
      continue;
    }
  }
  return null;
}

function googleRedirectUri(request: NextRequest): string {
  const explicit = (process.env.GOOGLE_OAUTH_REDIRECT_URI ?? '').trim();
  if (explicit) return explicit;
  const origin = configuredUiOrigin() ?? publicOrigin(request);
  return `${origin.replace(/\/+$/, '')}/api/auth/google/callback`;
}

function shouldUseSecureCookie(request: NextRequest): boolean {
  const override = (process.env.AUTH_COOKIE_SECURE ?? '').trim().toLowerCase();
  if (override === '1' || override === 'true' || override === 'yes' || override === 'on') return true;
  if (override === '0' || override === 'false' || override === 'no' || override === 'off') return false;

  const forwardedProto = request.headers.get('x-forwarded-proto');
  const protocol = (forwardedProto ?? request.nextUrl.protocol.replace(':', '')).toLowerCase();
  return protocol === 'https';
}

export async function GET(request: NextRequest): Promise<NextResponse> {
  const clientId = process.env.GOOGLE_CLIENT_ID ?? process.env.NEXT_PUBLIC_GOOGLE_CLIENT_ID ?? '';
  if (!clientId) {
    const loginUrl = new URL('/sign-up-login-screen', publicOrigin(request));
    loginUrl.searchParams.set('error', 'google_not_configured');
    return NextResponse.redirect(loginUrl);
  }

  const redirectUri = googleRedirectUri(request);
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
    secure: shouldUseSecureCookie(request),
    path: '/',
    maxAge: 10 * 60,
  });
  return response;
}
