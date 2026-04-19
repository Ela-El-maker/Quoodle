import { NextRequest, NextResponse } from 'next/server';
import { proxyAuthedGet } from '../../../devices/_shared';

export async function GET(request: NextRequest): Promise<NextResponse> {
  return proxyAuthedGet(request, '/settings/roles/permissions');
}

