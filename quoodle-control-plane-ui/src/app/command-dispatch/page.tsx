import React from 'react';
import AppLayout from '@/components/AppLayout';
import CommandDispatchContent from './components/CommandDispatchContent';
import AuditTrailSection from '@/components/AuditTrailSection';

export default function CommandDispatchPage() {
  return (
    <AppLayout currentPath="/command-dispatch">
      <div className="space-y-6">
        <CommandDispatchContent />
        <AuditTrailSection title="Command Dispatch Audit Trail" maxRows={5} />
      </div>
    </AppLayout>
  );
}