import React from 'react';
import AppLayout from '@/components/AppLayout';
import MobileDevicesContent from './components/MobileDevicesContent';

export default function MobileDevicesPage() {
  return (
    <AppLayout currentPath="/mobile-devices">
      <MobileDevicesContent />
    </AppLayout>
  );
}
