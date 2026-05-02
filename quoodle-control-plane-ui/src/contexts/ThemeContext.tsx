'use client';

import React, { createContext, useCallback, useContext, useEffect, useMemo, useState } from 'react';

export type ThemePreference = 'light' | 'dark' | 'system';
export type ResolvedTheme = 'light' | 'dark';

interface ThemeContextValue {
  theme: ThemePreference;
  resolvedTheme: ResolvedTheme;
  setTheme: (theme: ThemePreference) => void;
  cycleTheme: () => void;
}

const THEME_STORAGE_KEY = 'quoodle_theme_preference';

const ThemeContext = createContext<ThemeContextValue>({
  theme: 'system',
  resolvedTheme: 'dark',
  setTheme: () => {},
  cycleTheme: () => {},
});

function resolveSystemTheme(): ResolvedTheme {
  if (typeof window === 'undefined') return 'dark';
  return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
}

function applyThemeToDocument(resolvedTheme: ResolvedTheme): void {
  if (typeof document === 'undefined') return;
  const root = document.documentElement;
  root.dataset.theme = resolvedTheme;
  root.style.colorScheme = resolvedTheme;
}

export function ThemeProvider({ children }: { children: React.ReactNode }) {
  const readStoredTheme = (): ThemePreference => {
    if (typeof window === 'undefined') return 'system';
    const stored = window.localStorage.getItem(THEME_STORAGE_KEY);
    return stored === 'light' || stored === 'dark' || stored === 'system' ? stored : 'system';
  };

  const [theme, setThemeState] = useState<ThemePreference>(() => readStoredTheme());
  const [systemTheme, setSystemTheme] = useState<ResolvedTheme>(() => resolveSystemTheme());

  const resolvedTheme: ResolvedTheme = theme === 'system' ? systemTheme : theme;

  useEffect(() => {
    if (theme !== 'system') return;
    const media = window.matchMedia('(prefers-color-scheme: dark)');
    const handleChange = (event: MediaQueryListEvent) => {
      setSystemTheme(event.matches ? 'dark' : 'light');
    };

    media.addEventListener('change', handleChange);
    return () => media.removeEventListener('change', handleChange);
  }, [theme]);

  useEffect(() => {
    applyThemeToDocument(resolvedTheme);
  }, [resolvedTheme]);

  const setTheme = useCallback((nextTheme: ThemePreference) => {
    setThemeState(nextTheme);
    if (nextTheme === 'system') {
      setSystemTheme(resolveSystemTheme());
    }
    window.localStorage.setItem(THEME_STORAGE_KEY, nextTheme);
  }, []);

  const cycleTheme = useCallback(() => {
    const next: ThemePreference = theme === 'system' ? 'light' : theme === 'light' ? 'dark' : 'system';
    setTheme(next);
  }, [setTheme, theme]);

  const value = useMemo<ThemeContextValue>(
    () => ({ theme, resolvedTheme, setTheme, cycleTheme }),
    [cycleTheme, resolvedTheme, setTheme, theme],
  );

  return <ThemeContext.Provider value={value}>{children}</ThemeContext.Provider>;
}

export function useTheme() {
  return useContext(ThemeContext);
}
