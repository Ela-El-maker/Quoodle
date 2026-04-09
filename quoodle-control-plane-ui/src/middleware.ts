import { NextRequest, NextResponse } from 'next/server';
import {
  AUTH_COOKIE,
  normalizeRole,
  OPERATOR_ALLOWED_PREFIXES,
  roleHomePath,
  VIEWER_ALLOWED_PREFIXES,
} from '@/lib/auth';

const LOGIN_PATH = '/sign-up-login-screen';

function isAllowedPath(pathname: string, prefixes: readonly string[]): boolean {
  return prefixes.some((prefix) => pathname === prefix || pathname.startsWith(`${prefix}/`));
}

export function middleware(request: NextRequest): NextResponse {
  const { pathname } = request.nextUrl;

  if (pathname.startsWith('/api/')) {
    return NextResponse.next();
  }

  const jwt = request.cookies.get(AUTH_COOKIE.jwt)?.value ?? '';
  const role = normalizeRole(request.cookies.get(AUTH_COOKIE.role)?.value);

  if (!jwt) {
    if (pathname === LOGIN_PATH) return NextResponse.next();

    const loginUrl = request.nextUrl.clone();
    loginUrl.pathname = LOGIN_PATH;
    loginUrl.searchParams.set('next', pathname);
    return NextResponse.redirect(loginUrl);
  }

  if (pathname === '/') {
    const redirectUrl = request.nextUrl.clone();
    if (!role) {
      redirectUrl.pathname = LOGIN_PATH;
      redirectUrl.searchParams.set('next', pathname);
      return NextResponse.redirect(redirectUrl);
    }
    redirectUrl.pathname = roleHomePath(role);
    return NextResponse.redirect(redirectUrl);
  }

  if (pathname === LOGIN_PATH) {
    if (!role) return NextResponse.next();
    const redirectUrl = request.nextUrl.clone();
    redirectUrl.pathname = roleHomePath(role);
    return NextResponse.redirect(redirectUrl);
  }

  if (!role) {
    const loginUrl = request.nextUrl.clone();
    loginUrl.pathname = LOGIN_PATH;
    loginUrl.searchParams.set('next', pathname);
    return NextResponse.redirect(loginUrl);
  }

  if (role === 'admin') {
    return NextResponse.next();
  }

  const allowedPrefixes = role === 'operator' ? OPERATOR_ALLOWED_PREFIXES : VIEWER_ALLOWED_PREFIXES;
  if (isAllowedPath(pathname, allowedPrefixes)) {
    return NextResponse.next();
  }

  const redirectUrl = request.nextUrl.clone();
  redirectUrl.pathname = roleHomePath(role);
  return NextResponse.redirect(redirectUrl);
}

export const config = {
  matcher: ['/((?!_next/static|_next/image|favicon.ico|.*\\..*).*)'],
};
