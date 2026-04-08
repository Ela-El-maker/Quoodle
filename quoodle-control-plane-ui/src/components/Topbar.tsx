'use client';
import React, { useState } from 'react';
import { Menu, Search, Bell, Wifi, WifiOff, RefreshCw } from 'lucide-react';
import Link from 'next/link';

interface TopbarProps {
  onMobileMenuToggle: () => void;
}

export default function Topbar({ onMobileMenuToggle }: TopbarProps) {
  const [liveConnected] = useState(true);

  return (
    <header className="h-14 border-b border-border bg-zinc-950/80 backdrop-blur-sm flex items-center px-4 gap-3 flex-shrink-0 z-30">
      {/* Mobile menu toggle */}
      <button
        onClick={onMobileMenuToggle}
        className="lg:hidden p-1.5 rounded-md text-muted-foreground hover:text-foreground hover:bg-muted transition-colors"
        aria-label="Open menu"
      >
        <Menu size={18} />
      </button>

      {/* Search */}
      <div className="flex-1 max-w-sm hidden md:flex items-center gap-2 bg-muted/60 border border-border rounded-md px-3 py-1.5 text-sm text-muted-foreground">
        <Search size={13} />
        <span className="text-xs">Search devices, commands… (⌘K)</span>
      </div>

      <div className="flex-1" />

      {/* Live status indicator */}
      <div className={`hidden sm:flex items-center gap-1.5 text-xs px-2.5 py-1 rounded-full border ${
        liveConnected
          ? 'bg-green-500/10 border-green-500/20 text-green-400' :'bg-amber-500/10 border-amber-500/20 text-amber-400'
      }`}>
        {liveConnected ? (
          <>
            <span className="w-1.5 h-1.5 rounded-full bg-green-400 pulse-dot" />
            <Wifi size={11} />
            <span className="font-medium">Live</span>
          </>
        ) : (
          <>
            <WifiOff size={11} />
            <span className="font-medium">Polling fallback</span>
          </>
        )}
      </div>

      {/* Last updated */}
      <span className="hidden lg:block text-[11px] text-muted-foreground tabular-nums">
        Updated 21:06:13 UTC
      </span>

      {/* Refresh */}
      <button className="p-1.5 rounded-md text-muted-foreground hover:text-foreground hover:bg-muted transition-colors" aria-label="Refresh">
        <RefreshCw size={14} />
      </button>

      {/* Alerts */}
      <Link
        href="/alerts"
        className="relative p-1.5 rounded-md text-muted-foreground hover:text-foreground hover:bg-muted transition-colors"
        aria-label="Alerts"
      >
        <Bell size={16} />
        <span className="absolute top-0.5 right-0.5 w-2 h-2 rounded-full bg-red-500" />
      </Link>
    </header>
  );
}