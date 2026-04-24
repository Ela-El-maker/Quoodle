'use client';

import React, { useEffect, useMemo, useRef, useState } from 'react';
import { Bot, Sparkles } from 'lucide-react';
import CopilotComposer from './copilot/CopilotComposer';
import CopilotContextBar from './copilot/CopilotContextBar';
import CopilotStateNotice from './copilot/CopilotStateNotice';
import CopilotTranscript from './copilot/CopilotTranscript';
import { askCopilot, fetchConversation } from './copilot/api';
import type { CopilotConversation, CopilotErrorState, CopilotTranscriptItem } from './copilot/types';

interface DeviceHealthCopilotPanelProps {
  deviceId: string;
  hostname: string;
}

const QUICK_PROMPTS = [
  'Why is this device unhealthy?',
  'What changed in the last hour?',
  'Which signals reduce confidence?',
];

function storageKey(deviceId: string): string {
  return `quoodle:copilot:device:${deviceId}:conversation`;
}

function initialConversation(deviceId: string, deviceName: string): CopilotConversation {
  return {
    conversationId: '',
    state: 'active',
    transcript: [],
    surface: 'web.device_detail',
    context: {
      deviceId,
      deviceName,
      scopeLabel: 'Current device only',
    },
  };
}

export default function DeviceHealthCopilotPanel({ deviceId, hostname }: DeviceHealthCopilotPanelProps) {
  const [conversation, setConversation] = useState<CopilotConversation>(() => initialConversation(deviceId, hostname));
  const [composerValue, setComposerValue] = useState('');
  const [loadingConversation, setLoadingConversation] = useState(true);
  const [sending, setSending] = useState(false);
  const [errorState, setErrorState] = useState<CopilotErrorState | null>(null);
  const transcriptEndRef = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    let cancelled = false;
    const controller = new AbortController();
    setLoadingConversation(true);
    setErrorState(null);
    setConversation(initialConversation(deviceId, hostname));

    const savedConversationId = typeof window !== 'undefined' ? window.localStorage.getItem(storageKey(deviceId)) : null;
    if (!savedConversationId) {
      setLoadingConversation(false);
      return () => {
        cancelled = true;
        controller.abort();
      };
    }

    void fetchConversation(savedConversationId, { deviceId, deviceName: hostname }, controller.signal)
      .then((loaded) => {
        if (cancelled) return;
        setConversation(loaded);
      })
      .catch((error: CopilotErrorState) => {
        if (cancelled) return;
        setErrorState(error);
      })
      .finally(() => {
        if (!cancelled) setLoadingConversation(false);
      });

    return () => {
      cancelled = true;
      controller.abort();
    };
  }, [deviceId, hostname]);

  useEffect(() => {
    transcriptEndRef.current?.scrollIntoView({ behavior: 'smooth', block: 'end' });
  }, [conversation.transcript, loadingConversation, sending]);

  const contextChips = useMemo(
    () => [
      { key: 'device', label: 'Device', value: hostname },
      { key: 'device-id', label: 'Device ID', value: deviceId },
      { key: 'scope', label: 'Scope', value: 'Current device only', tone: 'warning' as const },
      { key: 'surface', label: 'Surface', value: 'Device detail', tone: 'muted' as const },
      {
        key: 'conversation',
        label: 'Conversation',
        value: conversation.conversationId ? conversation.conversationId.slice(0, 12) : 'new',
        tone: 'muted' as const,
      },
    ],
    [conversation.conversationId, deviceId, hostname],
  );

  const submitAsk = async (prompt: string): Promise<void> => {
    const query = prompt.trim();
    if (!query || sending) return;

    setErrorState(null);
    setSending(true);

    const userItem: CopilotTranscriptItem = {
      id: `user-${Date.now()}`,
      type: 'user_message',
      timestamp: new Date().toISOString(),
      text: query,
    };
    const loadingItem: CopilotTranscriptItem = {
      id: `loading-${Date.now()}`,
      type: 'system_status',
      timestamp: new Date().toISOString(),
      status: 'loading',
      text: 'Reviewing device health and recent command failures...',
    };

    setConversation((current) => ({
      ...current,
      transcript: [...current.transcript, userItem, loadingItem],
    }));

    try {
      const askResult = await askCopilot(
        {
          conversation_id: conversation.conversationId || undefined,
          query,
          selected_refs: { device_id: deviceId },
          ui_surface: 'web.device_detail',
        },
      );

      if (typeof window !== 'undefined') {
        window.localStorage.setItem(storageKey(deviceId), askResult.conversationId);
      }

      const canonical = await fetchConversation(askResult.conversationId, { deviceId, deviceName: hostname });
      setConversation(canonical);
      setComposerValue('');
    } catch (error) {
      const state = error as CopilotErrorState;
      setErrorState(state);
      setConversation((current) => ({
        ...current,
        transcript: current.transcript
          .filter((item) => item.id !== loadingItem.id)
          .concat({
            id: `unavailable-${Date.now()}`,
            type: 'unavailable_notice',
            timestamp: new Date().toISOString(),
            message: state.message,
            correlationId: state.correlationId,
          }),
      }));
    } finally {
      setSending(false);
    }
  };

  const transcript = conversation.transcript.filter((item) => item.type !== 'system_status' || item.status !== 'loading' || sending);
  const emptyState = !loadingConversation && transcript.length === 0;

  return (
    <section className="bg-card border border-border rounded-lg p-4 flex flex-col gap-3 min-h-[520px]" aria-label="Device Health Copilot panel">
      <header className="flex items-center justify-between gap-3">
        <div className="flex items-center gap-2">
          <Bot size={14} className="text-primary" />
          <div>
            <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wide">Device Health Copilot</p>
            <p className="text-[11px] text-muted-foreground">Read-only operational intelligence</p>
          </div>
        </div>
      </header>

      <CopilotContextBar chips={contextChips} />

      {errorState?.code === 'scope_failure' && (
        <CopilotStateNotice kind="scope" title={errorState.title} message={errorState.message} correlationId={errorState.correlationId} />
      )}
      {errorState && errorState.code !== 'scope_failure' && (
        <CopilotStateNotice kind="unavailable" title={errorState.title} message={errorState.message} correlationId={errorState.correlationId} />
      )}

      <div className="flex-1 min-h-0 overflow-y-auto border border-border/60 rounded-md bg-muted/10 px-3 py-3">
        {loadingConversation && (
          <CopilotStateNotice kind="loading" title="Loading conversation..." message="Restoring persisted copilot history from Laravel." />
        )}

        {emptyState && (
          <div className="space-y-3">
            <p className="text-sm text-foreground/90">Ask about this device health. Copilot explains evidence, confidence, and freshness.</p>
            <div className="rounded border border-dashed border-border px-3 py-2 text-xs text-muted-foreground">
              Scope is pinned to this device. AI is advisory only and cannot execute commands.
            </div>
            <div className="space-y-2">
              <p className="text-[11px] text-muted-foreground uppercase tracking-wide">Try one of these</p>
              <div className="flex flex-wrap gap-2">
                {QUICK_PROMPTS.map((prompt) => (
                  <button
                    key={prompt}
                    type="button"
                    onClick={() => {
                      setComposerValue(prompt);
                      void submitAsk(prompt);
                    }}
                    className="inline-flex items-center gap-1 rounded-md border border-border px-2.5 py-1 text-[11px] hover:bg-muted/50"
                  >
                    <Sparkles size={11} className="text-primary" />
                    {prompt}
                  </button>
                ))}
              </div>
            </div>
          </div>
        )}

        {!emptyState && <CopilotTranscript items={transcript} />}
        <div ref={transcriptEndRef} />
      </div>

      <CopilotComposer
        value={composerValue}
        disabled={sending || loadingConversation || errorState?.code === 'scope_failure'}
        onChange={setComposerValue}
        onSubmit={() => void submitAsk(composerValue)}
      />
    </section>
  );
}
