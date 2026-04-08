import AppLayout from '@/components/AppLayout';
import SettingsContent from './components/SettingsContent';

export default function SettingsPage() {
  return (
    <AppLayout currentPath="/settings">
      <SettingsContent />
    </AppLayout>
  );
}
