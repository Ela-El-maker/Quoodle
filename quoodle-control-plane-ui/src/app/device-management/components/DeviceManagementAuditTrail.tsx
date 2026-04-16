'use client';

import React, { useCallback, useEffect, useRef, useState } from 'react';
import AuditTrailSection, { type AuditEntry } from '@/components/AuditTrailSection';
import { useAuth } from '@/contexts/AuthContext';
import {
  composeAuditEntries,
  type DeviceAlertsResponse,
  type DeviceCommandRowApi,
  type DeviceCommandsResponse,
} from '../lib/deviceManagementData';

export default function DeviceManagementAuditTrail() {
  const { user } = useAuth();
  const canViewAlerts = user?.role ? user.role !== 'viewer' : false;
  const [entries, setEntries] = useState<AuditEntry[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const refreshAbortRef = useRef<AbortController | null>(null);

  const loadAudit = useCallback(async (initial = false) => {
    refreshAbortRef.current?.abort();
    const controller = new AbortController();
    refreshAbortRef.current = controller;

    if (initial) setLoading(true);

    try {
      const alertsRequest = canViewAlerts
        ? fetch('/api/alerts?limit=120', { credentials: 'include', cache: 'no-store', signal: controller.signal })
        : Promise.resolve(new Response(JSON.stringify({ alerts: [] }), { status: 200 }));
      const [commandsRes, alertsRes] = await Promise.all([
        fetch('/api/commands?limit=120', { credentials: 'include', cache: 'no-store', signal: controller.signal }),
        alertsRequest,
      ]);

      if (!commandsRes.ok && !alertsRes.ok) {
        throw new Error('fetch_failed');
      }

      const commandsPayload = commandsRes.ok
        ? ((await commandsRes.json()) as DeviceCommandsResponse)
        : { commands: [] as DeviceCommandRowApi[] };
      const alertsPayload = canViewAlerts && alertsRes.ok
        ? ((await alertsRes.json()) as DeviceAlertsResponse)
        : { alerts: [] };

      const mapped = composeAuditEntries(commandsPayload.commands ?? [], alertsPayload.alerts ?? []);
      setEntries(mapped);
      setError(null);
    } catch (loadError) {
      if ((loadError as Error).name === 'AbortError') return;
      console.error('device-management-audit-load-failed', loadError);
      setError('Failed to load data');
      if (initial) setEntries([]);
    } finally {
      if (initial) setLoading(false);
    }
  }, [canViewAlerts]);

  useEffect(() => {
    void loadAudit(true);
    const interval = window.setInterval(() => {
      void loadAudit(false);
    }, 30000);

    return () => {
      window.clearInterval(interval);
      refreshAbortRef.current?.abort();
    };
  }, [loadAudit]);

  return <AuditTrailSection title="Device Management Audit Trail" maxRows={5} entries={entries} loading={loading} error={error} />;
}
