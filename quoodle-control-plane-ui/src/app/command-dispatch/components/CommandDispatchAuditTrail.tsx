'use client';

import React, { useCallback, useEffect, useRef, useState } from 'react';
import AuditTrailSection, { type AuditEntry } from '@/components/AuditTrailSection';
import { mapCommandListRow, type CommandListRowApi } from '@/lib/commandResults';
import { formatLocalDateTime } from '@/lib/dateTime';

interface CommandsApiResponse {
  commands?: CommandListRowApi[];
}

function parseSortTime(value: string): number {
  const parsed = Date.parse(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function toAuditEntry(rowApi: CommandListRowApi): AuditEntry {
  const row = mapCommandListRow(rowApi);
  const state = row.state;
  const outcome: AuditEntry['outcome'] = state === 'completed'
    ? 'success'
    : ['failed', 'expired', 'rejected'].includes(state)
      ? 'failure'
      : 'pending';

  return {
    id: `AUD-CMD-${row.commandId}`,
    timestamp: formatLocalDateTime(row.completedAt ?? row.queuedAt, '-'),
    actor: row.actorEmail,
    actorRole: row.actorEmail === 'system' ? 'System' : 'Operator',
    eventType: 'command_execution',
    action: `COMMAND_${state.toUpperCase()}`,
    target: row.deviceId,
    detail: `${row.method} (${row.commandId})${row.errorMessage ? ` - ${row.errorMessage}` : ''}`,
    outcome,
  };
}

export default function CommandDispatchAuditTrail() {
  const [entries, setEntries] = useState<AuditEntry[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const abortRef = useRef<AbortController | null>(null);

  const load = useCallback(async (mode: 'initial' | 'refresh' = 'initial') => {
    if (mode === 'initial') setLoading(true);

    abortRef.current?.abort();
    const controller = new AbortController();
    abortRef.current = controller;

    try {
      const response = await fetch('/api/commands?limit=120', {
        credentials: 'include',
        cache: 'no-store',
        signal: controller.signal,
      });
      if (!response.ok) throw new Error(`http_${response.status}`);
      const payload = (await response.json()) as CommandsApiResponse;
      const mapped = (payload.commands ?? [])
        .map(toAuditEntry)
        .sort((a, b) => parseSortTime(b.timestamp) - parseSortTime(a.timestamp))
        .slice(0, 120);
      setEntries(mapped);
      setError(null);
    } catch (loadError) {
      if ((loadError as Error).name === 'AbortError') return;
      console.error('command-dispatch-audit-load-failed', loadError);
      setError('Failed to load data');
      if (mode === 'initial') setEntries([]);
    } finally {
      if (mode === 'initial') setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load('initial');
  }, [load]);

  useEffect(() => {
    let interval: ReturnType<typeof setInterval> | null = null;
    const startPolling = () => {
      if (interval) clearInterval(interval);
      const pollMs = document.visibilityState === 'visible' ? 15000 : 30000;
      interval = setInterval(() => {
        void load('refresh');
      }, pollMs);
    };

    startPolling();
    const handleVisibility = () => startPolling();
    document.addEventListener('visibilitychange', handleVisibility);

    return () => {
      if (interval) clearInterval(interval);
      document.removeEventListener('visibilitychange', handleVisibility);
      abortRef.current?.abort();
    };
  }, [load]);

  return (
    <AuditTrailSection
      title="Command Dispatch Audit Trail"
      maxRows={5}
      entries={entries}
      loading={loading}
      error={error}
    />
  );
}
