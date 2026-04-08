import React from 'react';
import AppLayout from '@/components/AppLayout';
import AuditContent from './components/AuditContent';

export default function AuditPage() {
  return (
    <AppLayout currentPath="/audit">
      <AuditContent />
    </AppLayout>
  );
}
