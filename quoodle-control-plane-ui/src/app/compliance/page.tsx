import React from 'react';
import AppLayout from '@/components/AppLayout';
import ComplianceContent from './components/ComplianceContent';

export default function CompliancePage() {
  return (
    <AppLayout currentPath="/compliance">
      <ComplianceContent />
    </AppLayout>
  );
}
