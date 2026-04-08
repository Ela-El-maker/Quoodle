'use client';
import AppLayout from '@/components/AppLayout';
import OperatorDashboard from './components/OperatorDashboard';

export default function OperatorConsolePage() {
  return (
    <AppLayout currentPath="/operator-console">
      <OperatorDashboard />
    </AppLayout>
  );
}
