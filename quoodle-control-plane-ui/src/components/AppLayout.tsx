'use client';
import React, { useState } from 'react';
import Sidebar from './Sidebar';
import Topbar from './Topbar';
import { useAuth } from '@/contexts/AuthContext';

interface AppLayoutProps {
  children: React.ReactNode;
  currentPath?: string;
  userRole?: 'admin' | 'operator' | 'viewer';
}

export default function AppLayout({ children, currentPath = '', userRole = 'viewer' }: AppLayoutProps) {
  const [sidebarCollapsed, setSidebarCollapsed] = useState(false);
  const [mobileSidebarOpen, setMobileSidebarOpen] = useState(false);
  const { user } = useAuth();

  const effectiveRole = user?.role ?? userRole;
  const effectiveEmail =
    user?.email ??
    (effectiveRole === 'admin'
      ? 'admin@quoodle.io'
      : effectiveRole === 'operator'
        ? 'ops.team@quoodle.io'
        : 'viewer@quoodle.io');
  const effectiveName =
    user?.name ??
    (effectiveRole === 'admin' ? 'Admin' : effectiveRole === 'operator' ? 'Operator' : 'Viewer');

  return (
    <div className="flex h-screen bg-background overflow-hidden">
      {/* Mobile overlay */}
      {mobileSidebarOpen && (
        <div
          className="fixed inset-0 bg-black/60 z-40 lg:hidden"
          onClick={() => setMobileSidebarOpen(false)}
        />
      )}

      {/* Sidebar */}
      <Sidebar
        collapsed={sidebarCollapsed}
        onToggle={() => setSidebarCollapsed(!sidebarCollapsed)}
        mobileOpen={mobileSidebarOpen}
        onMobileClose={() => setMobileSidebarOpen(false)}
        currentPath={currentPath}
        userRole={effectiveRole}
        userName={effectiveName}
        userEmail={effectiveEmail}
      />

      {/* Main content */}
      <div className="flex flex-col flex-1 min-w-0 overflow-hidden">
        <Topbar onMobileMenuToggle={() => setMobileSidebarOpen(true)} />
        <main className="flex-1 overflow-y-auto scrollbar-thin">
          <div className="max-w-screen-2xl mx-auto px-4 lg:px-6 xl:px-8 2xl:px-10 py-6">
            {children}
          </div>
        </main>
      </div>
    </div>
  );
}
