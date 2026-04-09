import React from 'react';
import { Suspense } from 'react';
import AppLayout from '@/components/AppLayout';
import DeviceManagementContent from './components/DeviceManagementContent';
import AuditTrailSection from '@/components/AuditTrailSection';

export default function DeviceManagementPage() {
  return (
    <AppLayout currentPath="/device-management">
      <div className="space-y-6">
        <Suspense fallback={<div className="text-sm text-muted-foreground px-1 py-2">Loading devices...</div>}>
          <DeviceManagementContent />
        </Suspense>
        <div className="px-0">
          <AuditTrailSection title="Device Management Audit Trail" maxRows={5} />
        </div>
      </div>
    </AppLayout>
  );
}
