'use client';
import AppLayout from '@/components/AppLayout';
import ViewerDashboard from './components/ViewerDashboard';

export default function ViewerConsolePage() {
  return (
    <AppLayout currentPath="/viewer-console">
      <ViewerDashboard />
    </AppLayout>
  );
}
