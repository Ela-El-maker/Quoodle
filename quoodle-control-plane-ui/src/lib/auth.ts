export type UserRole = 'admin' | 'operator' | 'viewer';

export interface AuthUser {
  id: string;
  email: string;
  name: string;
  role: UserRole;
  twoFactorEnabled?: boolean;
}

export const AUTH_COOKIE = {
  jwt: 'quoodle_jwt',
  refreshToken: 'quoodle_refresh_token',
  sessionId: 'quoodle_session_id',
  role: 'quoodle_user_role',
} as const;

export function normalizeRole(value: string | null | undefined): UserRole | null {
  if (value === 'admin' || value === 'operator' || value === 'viewer') {
    return value;
  }

  return null;
}

export function roleHomePath(role: UserRole): string {
  if (role === 'admin') return '/dashboard';
  if (role === 'operator') return '/operator-console';
  return '/viewer-console';
}

export const OPERATOR_ALLOWED_PREFIXES: readonly string[] = [
  '/operator-console',
  '/device-management',
  '/device-detail',
  '/command-dispatch',
  '/command-results',
  '/command-history',
  '/command-scheduling',
  '/alerts',
  '/notifications',
  '/telemetry-monitoring',
  '/compliance',
  '/audit',
  '/profile',
];

export const VIEWER_ALLOWED_PREFIXES: readonly string[] = [
  '/viewer-console',
  '/device-management',
  '/device-detail',
  '/alerts',
  '/notifications',
  '/compliance',
  '/audit',
  '/profile',
];
