'use client';
import AppLayout from '@/components/AppLayout';
import { Suspense } from 'react';
import DeviceDetailPageContent from './components/DeviceDetailPageContent';

export default function DeviceDetailPage() {
  return (
    <AppLayout currentPath="/device-detail">
      <Suspense fallback={<div className="p-8 text-center text-muted-foreground text-sm">Loading device…</div>}>
        <DeviceDetailPageContent />
      </Suspense>
    </AppLayout>
  );
}
