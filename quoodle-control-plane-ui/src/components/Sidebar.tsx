'use client';
import React from 'react';
import Link from 'next/link';
import AppLogo from '@/components/ui/AppLogo';
import { LayoutDashboard, Monitor, Terminal, Bell, Activity, ShieldCheck, ScrollText, HeartPulse, ChevronLeft, ChevronRight, X, Settings, Eye, BarChart2, Webhook, Calendar, History, LogOut, Smartphone } from 'lucide-react';

interface SidebarProps {
  collapsed: boolean;
  onToggle: () => void;
  mobileOpen: boolean;
  onMobileClose: () => void;
  currentPath: string;
  userRole?: 'admin' | 'operator' | 'viewer';
  userName?: string;
  userEmail?: string;
  onLogout?: () => void | Promise<void>;
}

// ─── Nav groups by role ───────────────────────────────────────────────────────
const adminNavGroups = [
  {
    label: 'Operations',
    items: [
      { label: 'Dashboard',    icon: LayoutDashboard, path: '/dashboard',          badge: null },
      { label: 'Devices',      icon: Monitor,         path: '/device-management',  badge: '3' },
      { label: 'Mobile Devices', icon: Smartphone,    path: '/mobile-devices',     badge: null },
      { label: 'Commands',     icon: Terminal,        path: '/command-dispatch',   badge: '5' },
      { label: 'Results',      icon: BarChart2,       path: '/command-results',    badge: null },
      { label: 'History',      icon: History,         path: '/command-history',    badge: null },
      { label: 'Scheduling',   icon: Calendar,        path: '/command-scheduling', badge: null },
      { label: 'Alerts',       icon: Bell,            path: '/alerts',             badge: '2', badgeVariant: 'danger' as const },
      { label: 'Notifications',icon: Bell,            path: '/notifications',      badge: null },
    ],
  },
  {
    label: 'Monitoring',
    items: [
      { label: 'Telemetry',    icon: Activity,        path: '/telemetry-monitoring', badge: null },
      { label: 'Compliance',   icon: ShieldCheck,     path: '/compliance',           badge: null },
      { label: 'Audit Trail',  icon: ScrollText,      path: '/audit',                badge: null },
    ],
  },
  {
    label: 'Integrations',
    items: [
      { label: 'Webhooks',     icon: Webhook,         path: '/webhooks',             badge: null },
    ],
  },
  {
    label: 'System',
    items: [
      { label: 'System Health',icon: HeartPulse,      path: '/system-health',        badge: null },
      { label: 'Settings',     icon: Settings,        path: '/settings',             badge: null },
    ],
  },
];

const operatorNavGroups = [
  {
    label: 'My Console',
    items: [
      { label: 'Operator Console', icon: LayoutDashboard, path: '/operator-console',    badge: null },
      { label: 'My Devices',       icon: Monitor,         path: '/device-management',   badge: null },
      { label: 'Mobile Devices',   icon: Smartphone,      path: '/mobile-devices',      badge: null },
      { label: 'Commands',         icon: Terminal,        path: '/command-dispatch',     badge: null },
      { label: 'Results',          icon: BarChart2,       path: '/command-results',      badge: null },
      { label: 'History',          icon: History,         path: '/command-history',      badge: null },
      { label: 'Scheduling',       icon: Calendar,        path: '/command-scheduling',   badge: null },
      { label: 'Alerts',           icon: Bell,            path: '/alerts',               badge: '2', badgeVariant: 'danger' as const },
      { label: 'Notifications',    icon: Bell,            path: '/notifications',        badge: null },
    ],
  },
  {
    label: 'Monitoring',
    items: [
      { label: 'Telemetry',        icon: Activity,        path: '/telemetry-monitoring', badge: null },
      { label: 'Compliance',       icon: ShieldCheck,     path: '/compliance',           badge: null },
      { label: 'Audit Trail',      icon: ScrollText,      path: '/audit',                badge: null },
    ],
  },
  {
    label: 'Integrations',
    items: [
      { label: 'Webhooks',         icon: Webhook,         path: '/webhooks',             badge: null },
    ],
  },
];

const viewerNavGroups = [
  {
    label: 'My Console',
    items: [
      { label: 'Viewer Console',   icon: Eye,             path: '/viewer-console',       badge: null },
      { label: 'Devices',          icon: Monitor,         path: '/device-management',    badge: null },
      { label: 'Mobile Devices',   icon: Smartphone,      path: '/mobile-devices',       badge: null },
      { label: 'Notifications',    icon: Bell,            path: '/notifications',        badge: null },
    ],
  },
  {
    label: 'Reports',
    items: [
      { label: 'Compliance',       icon: ShieldCheck,     path: '/compliance',           badge: null },
      { label: 'Audit Trail',      icon: ScrollText,      path: '/audit',                badge: null },
    ],
  },
];

const roleNavGroups = {
  admin: adminNavGroups,
  operator: operatorNavGroups,
  viewer: viewerNavGroups,
};

const roleLabels = { admin: 'Admin', operator: 'Operator', viewer: 'Viewer' };

export default function Sidebar({
  collapsed,
  onToggle,
  mobileOpen,
  onMobileClose,
  currentPath,
  userRole = 'operator',
  userName,
  userEmail,
  onLogout,
}: SidebarProps) {
  const isActive = (path: string) => currentPath === path || currentPath.startsWith(path + '/');

  return (
    <>
      {/* Desktop sidebar */}
      <aside
        className={`hidden lg:flex flex-col bg-card border-r border-border transition-all duration-300 ease-in-out flex-shrink-0 ${
          collapsed ? 'w-16' : 'w-60'
        }`}
      >
        <SidebarContent
          collapsed={collapsed}
          onToggle={onToggle}
          isActive={isActive}
          showToggle
          userRole={userRole}
          userName={userName}
          userEmail={userEmail}
          onLogout={onLogout}
        />
      </aside>

      {/* Mobile sidebar */}
      <aside
        className={`fixed inset-y-0 left-0 z-50 flex flex-col w-60 bg-card border-r border-border lg:hidden transition-transform duration-300 ease-in-out ${
          mobileOpen ? 'translate-x-0' : '-translate-x-full'
        }`}
      >
        <div className="flex items-center justify-between px-4 h-14 border-b border-border">
          <div className="flex items-center gap-2">
            <AppLogo size={28} />
            <span className="font-semibold text-sm tracking-tight">Quoodle</span>
          </div>
          <button onClick={onMobileClose} className="p-1.5 rounded-md text-muted-foreground hover:text-foreground hover:bg-muted transition-colors" aria-label="Close menu">
            <X size={16} />
          </button>
        </div>
        <SidebarContent
          collapsed={false}
          onToggle={onToggle}
          isActive={isActive}
          showToggle={false}
          userRole={userRole}
          userName={userName}
          userEmail={userEmail}
          onLogout={onLogout}
        />
      </aside>
    </>
  );
}

function SidebarContent({
  collapsed,
  onToggle,
  isActive,
  showToggle,
  userRole,
  userName,
  userEmail,
  onLogout,
}: {
  collapsed: boolean;
  onToggle: () => void;
  isActive: (path: string) => boolean;
  showToggle: boolean;
  userRole: 'admin' | 'operator' | 'viewer';
  userName?: string;
  userEmail?: string;
  onLogout?: () => void | Promise<void>;
}) {
  const navGroups = roleNavGroups[userRole] ?? adminNavGroups;

  return (
    <>
      {/* Logo */}
      <div className={`flex items-center h-14 border-b border-border flex-shrink-0 ${collapsed ? 'justify-center px-2' : 'px-4 gap-2'}`}>
        <AppLogo size={28} />
        {!collapsed && <span className="font-semibold text-sm tracking-tight">Quoodle</span>}
        {showToggle && (
          <button
            onClick={onToggle}
            className={`ml-auto p-1 rounded-md text-muted-foreground hover:text-foreground hover:bg-muted transition-colors ${collapsed ? 'ml-0' : ''}`}
            aria-label={collapsed ? 'Expand sidebar' : 'Collapse sidebar'}
          >
            {collapsed ? <ChevronRight size={14} /> : <ChevronLeft size={14} />}
          </button>
        )}
      </div>

      {/* Role badge */}
      {!collapsed && (
        <div className="px-3 pt-3 pb-1">
          <div className={`flex items-center gap-1.5 px-2 py-1 rounded-md text-[10px] font-semibold uppercase tracking-wider w-fit ${
            userRole === 'admin' ? 'bg-primary/10 text-primary' :
            userRole === 'operator' ? 'bg-amber-500/10 text-amber-400' : 'bg-blue-500/10 text-blue-400'
          }`}>
            {userRole === 'viewer' ? <Eye size={10} /> : userRole === 'operator' ? <Terminal size={10} /> : <Settings size={10} />}
            {roleLabels[userRole]}
          </div>
        </div>
      )}

      {/* Nav groups */}
      <nav className="flex-1 overflow-y-auto scrollbar-thin py-3 px-2">
        {navGroups.map((group) => (
          <div key={`group-${group.label}`} className="mb-4">
            {!collapsed && (
              <p className="text-[10px] font-semibold tracking-widest uppercase text-muted-foreground px-2 mb-1">
                {group.label}
              </p>
            )}
            {group.items.map((item) => {
              const active = isActive(item.path);
              return (
                <Link
                  key={`nav-${item.path}`}
                  href={item.path}
                  className={`group relative flex items-center gap-3 px-2 py-2 rounded-md mb-0.5 transition-all duration-150 ${
                    active ? 'bg-primary/10 text-primary' : 'text-muted-foreground hover:text-foreground hover:bg-muted/60'
                  }`}
                  title={collapsed ? item.label : undefined}
                >
                  <item.icon size={16} className="flex-shrink-0" />
                  {!collapsed && (
                    <>
                      <span className="text-sm font-medium flex-1">{item.label}</span>
                      {item.badge && (
                        <span className={`text-[10px] font-semibold px-1.5 py-0.5 rounded-full tabular-nums ${
                          item.badgeVariant === 'danger' ? 'bg-red-500/20 text-red-400' : 'bg-muted text-muted-foreground'
                        }`}>
                          {item.badge}
                        </span>
                      )}
                    </>
                  )}
                  {collapsed && item.badge && (
                    <span className={`absolute top-1 right-1 w-1.5 h-1.5 rounded-full ${
                      item.badgeVariant === 'danger' ? 'bg-red-500' : 'bg-primary'
                    }`} />
                  )}
                </Link>
              );
            })}
          </div>
        ))}
      </nav>

      {/* Footer */}
      <div className="border-t border-border p-2 flex-shrink-0">
        <Link
          href="/profile"
          className={`flex items-center gap-3 px-2 py-2 rounded-md text-muted-foreground hover:text-foreground hover:bg-muted/60 transition-colors ${collapsed ? 'justify-center' : ''}`}
          title={collapsed ? 'Profile' : undefined}
        >
          <div className={`w-6 h-6 rounded-full flex items-center justify-center text-[10px] font-bold flex-shrink-0 ${
            userRole === 'admin' ? 'bg-primary/20 text-primary' :
            userRole === 'operator' ? 'bg-amber-500/20 text-amber-400' : 'bg-blue-500/20 text-blue-400'
          }`}>
            {userRole === 'admin' ? 'A' : userRole === 'operator' ? 'O' : 'V'}
          </div>
          {!collapsed && (
            <div className="flex-1 min-w-0">
              <p className="text-xs font-medium truncate">{userName ?? roleLabels[userRole]}</p>
              <p className="text-[10px] text-muted-foreground truncate">
                {userEmail ?? (userRole === 'admin' ? 'admin@quoodle.io' : userRole === 'operator' ? 'ops.team@quoodle.io' : 'viewer@quoodle.io')}
              </p>
            </div>
          )}
        </Link>
        <button
          type="button"
          onClick={() => {
            if (onLogout) void onLogout();
          }}
          className={`mt-1 w-full flex items-center gap-3 px-2 py-2 rounded-md text-muted-foreground hover:text-foreground hover:bg-muted/60 transition-colors ${collapsed ? 'justify-center' : ''}`}
          title={collapsed ? 'Log out' : undefined}
        >
          <LogOut size={14} className="flex-shrink-0" />
          {!collapsed && <span className="text-xs font-medium">Log out</span>}
        </button>
      </div>
    </>
  );
}
