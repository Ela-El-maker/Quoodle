'use client';
import React, { createContext, useContext, useState, useEffect } from 'react';
import type { AuthUser } from '@/lib/auth';

export type UserRole = AuthUser['role'];

interface AuthContextValue {
  user: AuthUser | null;
  loading: boolean;
  setUser: (user: AuthUser | null) => void;
  refreshUser: () => Promise<AuthUser | null>;
  logout: () => Promise<void>;
  hasPermission: (permission: PermissionKey) => boolean;
}

export type PermissionKey =
  | 'view_devices' |'manage_devices' |'send_commands' |'send_sensitive_commands' |'view_alerts' |'acknowledge_alerts' |'view_compliance' |'manage_compliance' |'view_audit' |'manage_users' |'manage_settings' |'export_data' |'pair_devices';

const ROLE_PERMISSIONS: Record<UserRole, Record<PermissionKey, boolean>> = {
  admin: {
    view_devices: true, manage_devices: true, send_commands: true, send_sensitive_commands: true,
    view_alerts: true, acknowledge_alerts: true, view_compliance: true, manage_compliance: true,
    view_audit: true, manage_users: true, manage_settings: true, export_data: true, pair_devices: true,
  },
  operator: {
    view_devices: true, manage_devices: false, send_commands: true, send_sensitive_commands: false,
    view_alerts: true, acknowledge_alerts: true, view_compliance: true, manage_compliance: false,
    view_audit: true, manage_users: false, manage_settings: false, export_data: true, pair_devices: true,
  },
  viewer: {
    view_devices: true, manage_devices: false, send_commands: false, send_sensitive_commands: false,
    view_alerts: false, acknowledge_alerts: false, view_compliance: true, manage_compliance: false,
    view_audit: true, manage_users: false, manage_settings: false, export_data: false, pair_devices: true,
  },
};

const AuthContext = createContext<AuthContextValue>({
  user: null,
  loading: true,
  setUser: () => {},
  refreshUser: async () => null,
  logout: async () => {},
  hasPermission: () => false,
});

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [user, setUserState] = useState<AuthUser | null>(null);
  const [loading, setLoading] = useState(true);

  const refreshUser = async (): Promise<AuthUser | null> => {
    try {
      const response = await fetch('/api/auth/me', {
        method: 'GET',
        credentials: 'include',
        cache: 'no-store',
      });

      if (!response.ok) {
        setUserState(null);
        return null;
      }

      const payload = (await response.json()) as { authenticated?: boolean; user?: AuthUser };
      const nextUser = payload.authenticated ? payload.user ?? null : null;
      setUserState(nextUser);
      return nextUser;
    } catch {
      setUserState(null);
      return null;
    }
  };

  useEffect(() => {
    void (async () => {
      setLoading(true);
      await refreshUser();
      setLoading(false);
    })();
  }, []);

  const setUser = (u: AuthUser | null) => {
    setUserState(u);
  };

  const logout = async () => {
    try {
      await fetch('/api/auth/logout', {
        method: 'POST',
        credentials: 'include',
      });
    } finally {
      setUserState(null);
    }
  };

  const hasPermission = (permission: PermissionKey): boolean => {
    if (!user) return false;
    // Admin has unrestricted access to everything
    if (user.role === 'admin') return true;
    return ROLE_PERMISSIONS[user.role]?.[permission] ?? false;
  };

  return (
    <AuthContext.Provider value={{ user, loading, setUser, refreshUser, logout, hasPermission }}>
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth() {
  return useContext(AuthContext);
}

export { ROLE_PERMISSIONS };
