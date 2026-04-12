import { NextRequest, NextResponse } from 'next/server';
import { proxyAuthedBinaryGet } from '../../devices/_shared';

interface Params {
  params: Promise<{ artifactId: string }>;
}

export async function GET(request: NextRequest, context: Params): Promise<NextResponse> {
  const { artifactId } = await context.params;
  return proxyAuthedBinaryGet(request, `/artifact/${encodeURIComponent(artifactId)}`);
}

