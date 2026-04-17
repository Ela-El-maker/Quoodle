import React from 'react';
import AppLayout from '@/components/AppLayout';
import CommandDispatchContent from './components/CommandDispatchContent';
import CommandDispatchAuditTrail from './components/CommandDispatchAuditTrail';

export default function CommandDispatchPage() {
  return (
    <AppLayout currentPath="/command-dispatch">
      <div className="space-y-6">
        <CommandDispatchContent />
        <CommandDispatchAuditTrail />
      </div>
    </AppLayout>
  );
}
