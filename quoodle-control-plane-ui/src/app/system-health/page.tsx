import React from 'react';
import AppLayout from '@/components/AppLayout';
import SystemHealthContent from './components/SystemHealthContent';

export default function SystemHealthPage() {
  return (
    <AppLayout currentPath="/system-health">
      <SystemHealthContent />
    </AppLayout>
  );
}
