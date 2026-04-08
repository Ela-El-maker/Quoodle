import React from 'react';
import AppLayout from '@/components/AppLayout';
import AlertsContent from './components/AlertsContent';

export default function AlertsPage() {
  return (
    <AppLayout currentPath="/alerts">
      <AlertsContent />
    </AppLayout>
  );
}