import React, { Suspense } from 'react';
import AppLayout from '@/components/AppLayout';
import TelemetryContent from './components/TelemetryContent';
import AuditTrailSection from '@/components/AuditTrailSection';

export default function TelemetryMonitoringPage() {
  return (
    <AppLayout currentPath="/telemetry-monitoring">
      <div className="space-y-6">
        <Suspense fallback={<div className="text-xs text-muted-foreground">Loading telemetry...</div>}>
          <TelemetryContent />
        </Suspense>
        <AuditTrailSection title="Telemetry Audit Trail" maxRows={5} />
      </div>
    </AppLayout>
  );
}
