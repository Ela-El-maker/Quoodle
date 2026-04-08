import React from 'react';
import type { Metadata, Viewport } from 'next';
import '../styles/tailwind.css';
import { Toaster } from 'sonner';
import { AuthProvider } from '@/contexts/AuthContext';

export const viewport: Viewport = {
  width: 'device-width',
  initialScale: 1,
};

export const metadata: Metadata = {
  title: 'Quoodle — Windows Fleet Control Plane',
  description: 'Push-first near-realtime control plane for managing Windows device fleets — monitor health, dispatch commands, and maintain compliance posture.',
  icons: {
    icon: [{ url: '/favicon.ico', type: 'image/x-icon' }],
  },
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en">
      <body>
        <AuthProvider>{children}</AuthProvider>
        <Toaster
          position="bottom-right"
          toastOptions={{
            style: {
              background: 'hsl(240 10% 8%)',
              border: '1px solid hsl(240 5% 16%)',
              color: 'hsl(0 0% 98%)',
              fontFamily: 'IBM Plex Sans, sans-serif',
              fontSize: '13px',
            },
          }}
        />
      </body>
    </html>
  );
}
