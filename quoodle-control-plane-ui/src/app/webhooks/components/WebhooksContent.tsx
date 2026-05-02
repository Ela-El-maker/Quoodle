'use client';

import React, { useCallback, useEffect, useMemo, useState } from 'react';
import {
  Activity,
  AlertTriangle,
  CheckCircle,
  ChevronDown,
  ChevronUp,
  Copy,
  Eye,
  EyeOff,
  Globe,
  Lock,
  Pause,
  Play,
  Plus,
  RefreshCw,
  RotateCcw,
  Save,
  Shield,
  Trash2,
  Webhook,
  X,
  Zap,
} from 'lucide-react';
import { toast } from 'sonner';

type WebhookStatus = 'active' | 'paused' | 'failing';
type RetryPolicy = 'exponential' | 'linear' | 'none';
type DeliveryStatus = 'pending' | 'retrying' | 'sent' | 'dead_letter';
type WebhooksTab = 'endpoints' | 'deliveries' | 'inbound' | 'docs';

interface WebhookEndpoint {
  id: string;
  name: string;
  url: string;
  status: WebhookStatus;
  events: string[];
  signing_algo: string;
  secret_masked: string;
  retry_policy: RetryPolicy;
  max_retries: number;
  timeout_ms: number;
  total_deliveries: number;
  success_count: number;
  failure_count: number;
  retrying_count: number;
  last_delivery: string | null;
  last_status: number | null;
  last_latency_ms: number | null;
  created_at: string | null;
  updated_at: string | null;
  can_manage: boolean;
  owner_email: string | null;
}

interface DeliveryLog {
  id: string;
  endpoint_id: string;
  endpoint_name: string | null;
  event_type: string;
  event_id: string;
  status: DeliveryStatus;
  attempt: number;
  max_attempts: number;
  next_attempt_at: string | null;
  http_status: number | null;
  latency_ms: number | null;
  response_body: string | null;
  last_error: string | null;
  sent_at: string | null;
  delivered_at: string | null;
  created_at: string | null;
  replayed_from_delivery_id: string | null;
  payload: Record<string, unknown> | null;
  can_replay: boolean;
}

interface EndpointsResponse {
  endpoints: WebhookEndpoint[];
  event_catalog: string[];
}

interface DeliveriesResponse {
  deliveries: DeliveryLog[];
}

interface InboundEvent {
  id: number;
  event_key: string;
  event_type: string;
  command_id: string | null;
  received_at: string | null;
  created_at: string | null;
}

interface InboundResponse {
  events: InboundEvent[];
  stats: {
    last_24h: number;
    total_shown: number;
  };
  event_breakdown: Array<{ event_type: string; total: number }>;
}

interface EndpointDraft {
  id?: string;
  name: string;
  url: string;
  events: string[];
  retry_policy: RetryPolicy;
  max_retries: number;
  timeout_ms: number;
}

interface SecretResponse {
  signing_secret_plaintext: string;
  signing_algo?: string;
}

async function requestJson<T>(url: string, init?: RequestInit): Promise<T> {
  const response = await fetch(url, {
    ...init,
    headers: {
      'Content-Type': 'application/json',
      ...(init?.headers ?? {}),
    },
    cache: 'no-store',
  });
  const payload = (await response.json().catch(() => ({}))) as Record<string, unknown>;
  if (!response.ok) {
    const message = typeof payload.message === 'string' ? payload.message : 'request_failed';
    throw new Error(message);
  }
  return payload as T;
}

function endpointStatusClass(status: WebhookStatus): string {
  if (status === 'active') return 'text-green-400 bg-green-500/10 border-green-500/20';
  if (status === 'failing') return 'text-red-400 bg-red-500/10 border-red-500/20';
  return 'text-amber-400 bg-amber-500/10 border-amber-500/20';
}

function deliveryStatusClass(status: DeliveryStatus): string {
  if (status === 'sent') return 'text-green-400';
  if (status === 'dead_letter') return 'text-red-400';
  return 'text-amber-400';
}

function safeIsoLocal(input: string | null): string {
  if (!input) return '—';
  const date = new Date(input);
  if (Number.isNaN(date.getTime())) return input;
  return date.toLocaleString();
}

function renderSecret(masked: string, plain: string | null): string {
  return plain ?? masked;
}

export default function WebhooksContent() {
  const [activeTab, setActiveTab] = useState<WebhooksTab>('endpoints');
  const [endpoints, setEndpoints] = useState<WebhookEndpoint[]>([]);
  const [deliveries, setDeliveries] = useState<DeliveryLog[]>([]);
  const [inboundEvents, setInboundEvents] = useState<InboundEvent[]>([]);
  const [inboundEventBreakdown, setInboundEventBreakdown] = useState<Array<{ event_type: string; total: number }>>(
    [],
  );
  const [inboundLast24h, setInboundLast24h] = useState(0);
  const [eventCatalog, setEventCatalog] = useState<string[]>([]);
  const [loadingEndpoints, setLoadingEndpoints] = useState(false);
  const [loadingDeliveries, setLoadingDeliveries] = useState(false);
  const [loadingInbound, setLoadingInbound] = useState(false);
  const [selectedEndpointId, setSelectedEndpointId] = useState<string | null>(null);
  const [expandedDeliveryId, setExpandedDeliveryId] = useState<string | null>(null);
  const [revealedSecrets, setRevealedSecrets] = useState<Record<string, string>>({});
  const [createModalOpen, setCreateModalOpen] = useState(false);
  const [editModalOpen, setEditModalOpen] = useState(false);
  const [editingDraft, setEditingDraft] = useState<EndpointDraft | null>(null);
  const [deliveryFilterEndpointId, setDeliveryFilterEndpointId] = useState<string>('');
  const [deliveryFilterStatus, setDeliveryFilterStatus] = useState<string>('');
  const [deliveryFilterEventType, setDeliveryFilterEventType] = useState<string>('');
  const [inboundFilterEventType, setInboundFilterEventType] = useState<string>('');

  const selectedEndpoint = useMemo(
    () => endpoints.find((endpoint) => endpoint.id === selectedEndpointId) ?? null,
    [endpoints, selectedEndpointId],
  );

  const loadEndpoints = useCallback(async () => {
    setLoadingEndpoints(true);
    try {
      const payload = await requestJson<EndpointsResponse>('/api/webhooks/endpoints');
      setEndpoints(payload.endpoints ?? []);
      setEventCatalog(payload.event_catalog ?? []);
      if (!selectedEndpointId && payload.endpoints.length > 0) {
        setSelectedEndpointId(payload.endpoints[0].id);
      }
      if (selectedEndpointId && !payload.endpoints.some((item) => item.id === selectedEndpointId)) {
        setSelectedEndpointId(payload.endpoints[0]?.id ?? null);
      }
    } catch (error) {
      const message = error instanceof Error ? error.message : 'failed_to_load_endpoints';
      toast.error(message);
    } finally {
      setLoadingEndpoints(false);
    }
  }, [selectedEndpointId]);

  const loadDeliveries = useCallback(async () => {
    setLoadingDeliveries(true);
    try {
      const params = new URLSearchParams();
      if (deliveryFilterEndpointId) params.set('endpoint_id', deliveryFilterEndpointId);
      if (deliveryFilterStatus) params.set('status', deliveryFilterStatus);
      if (deliveryFilterEventType) params.set('event_type', deliveryFilterEventType);
      params.set('limit', '300');
      const query = params.toString();
      const payload = await requestJson<DeliveriesResponse>(
        query ? `/api/webhooks/deliveries?${query}` : '/api/webhooks/deliveries',
      );
      setDeliveries(payload.deliveries ?? []);
    } catch (error) {
      const message = error instanceof Error ? error.message : 'failed_to_load_deliveries';
      toast.error(message);
    } finally {
      setLoadingDeliveries(false);
    }
  }, [deliveryFilterEndpointId, deliveryFilterStatus, deliveryFilterEventType]);

  const loadInbound = useCallback(async () => {
    setLoadingInbound(true);
    try {
      const params = new URLSearchParams();
      if (inboundFilterEventType) params.set('event_type', inboundFilterEventType);
      params.set('limit', '300');
      const query = params.toString();
      const payload = await requestJson<InboundResponse>(
        query ? `/api/webhooks/inbound?${query}` : '/api/webhooks/inbound',
      );
      setInboundEvents(payload.events ?? []);
      setInboundEventBreakdown(payload.event_breakdown ?? []);
      setInboundLast24h(Number(payload.stats?.last_24h ?? 0));
    } catch (error) {
      const message = error instanceof Error ? error.message : 'failed_to_load_inbound_events';
      toast.error(message);
    } finally {
      setLoadingInbound(false);
    }
  }, [inboundFilterEventType]);

  useEffect(() => {
    void loadEndpoints();
  }, [loadEndpoints]);

  useEffect(() => {
    void loadDeliveries();
  }, [loadDeliveries]);

  useEffect(() => {
    void loadInbound();
  }, [loadInbound]);

  const refreshAll = async (): Promise<void> => {
    await Promise.all([loadEndpoints(), loadDeliveries(), loadInbound()]);
  };

  const handleCreateEndpoint = async (draft: EndpointDraft): Promise<void> => {
    const payload = await requestJson<{ endpoint: WebhookEndpoint; signing_secret_plaintext: string }>(
      '/api/webhooks/endpoints',
      {
        method: 'POST',
        body: JSON.stringify(draft),
      },
    );
    setRevealedSecrets((prev) => ({ ...prev, [payload.endpoint.id]: payload.signing_secret_plaintext }));
    setCreateModalOpen(false);
    toast.success('Webhook endpoint created');
    await refreshAll();
    setSelectedEndpointId(payload.endpoint.id);
  };

  const handleUpdateEndpoint = async (endpointId: string, draft: EndpointDraft): Promise<void> => {
    await requestJson<{ endpoint: WebhookEndpoint }>(`/api/webhooks/endpoints/${encodeURIComponent(endpointId)}`, {
      method: 'PATCH',
      body: JSON.stringify(draft),
    });
    setEditModalOpen(false);
    setEditingDraft(null);
    toast.success('Webhook endpoint updated');
    await refreshAll();
  };

  const handleDeleteEndpoint = async (endpointId: string): Promise<void> => {
    await requestJson<{ status: string }>(`/api/webhooks/endpoints/${encodeURIComponent(endpointId)}`, {
      method: 'DELETE',
      body: JSON.stringify({}),
    });
    toast.success('Webhook endpoint deleted');
    setRevealedSecrets((prev) => {
      const next = { ...prev };
      delete next[endpointId];
      return next;
    });
    await refreshAll();
  };

  const handleToggleEndpoint = async (endpoint: WebhookEndpoint): Promise<void> => {
    const action = endpoint.status === 'paused' ? 'resume' : 'pause';
    await requestJson<{ status: string }>(
      `/api/webhooks/endpoints/${encodeURIComponent(endpoint.id)}/${action}`,
      {
        method: 'POST',
        body: JSON.stringify({}),
      },
    );
    toast.success(`Endpoint ${action === 'pause' ? 'paused' : 'resumed'}`);
    await refreshAll();
  };

  const handleTestEndpoint = async (endpoint: WebhookEndpoint): Promise<void> => {
    const eventType = endpoint.events[0] ?? eventCatalog[0] ?? 'command.completed';
    await requestJson<{ status: string; delivery_id: string }>(
      `/api/webhooks/endpoints/${encodeURIComponent(endpoint.id)}/test`,
      {
        method: 'POST',
        body: JSON.stringify({
          event_type: eventType,
          data: { source: 'webhooks_ui', endpoint_name: endpoint.name },
        }),
      },
    );
    toast.success('Test delivery queued');
    await loadDeliveries();
  };

  const handleRevealSecret = async (endpoint: WebhookEndpoint): Promise<void> => {
    if (revealedSecrets[endpoint.id]) {
      setRevealedSecrets((prev) => {
        const next = { ...prev };
        delete next[endpoint.id];
        return next;
      });
      return;
    }

    const payload = await requestJson<SecretResponse>(
      `/api/webhooks/endpoints/${encodeURIComponent(endpoint.id)}/reveal-secret`,
    );
    setRevealedSecrets((prev) => ({ ...prev, [endpoint.id]: payload.signing_secret_plaintext }));
  };

  const handleRotateSecret = async (endpoint: WebhookEndpoint): Promise<void> => {
    const payload = await requestJson<SecretResponse>(
      `/api/webhooks/endpoints/${encodeURIComponent(endpoint.id)}/rotate-secret`,
      {
        method: 'POST',
        body: JSON.stringify({}),
      },
    );
    setRevealedSecrets((prev) => ({ ...prev, [endpoint.id]: payload.signing_secret_plaintext }));
    toast.success('Signing secret rotated');
    await loadEndpoints();
  };

  const handleReplayDelivery = async (delivery: DeliveryLog): Promise<void> => {
    await requestJson<{ status: string; delivery_id: string }>(
      `/api/webhooks/deliveries/${encodeURIComponent(delivery.id)}/replay`,
      {
        method: 'POST',
        body: JSON.stringify({}),
      },
    );
    toast.success('Replay queued');
    await loadDeliveries();
  };

  const health = useMemo(() => {
    const activeEndpoints = endpoints.filter((endpoint) => endpoint.status === 'active').length;
    const failingEndpoints = endpoints.filter((endpoint) => endpoint.status === 'failing').length;
    const sentDeliveries = deliveries.filter((delivery) => delivery.status === 'sent').length;
    const failedDeliveries = deliveries.filter((delivery) => delivery.status === 'dead_letter').length;
    const latencies = deliveries
      .filter((delivery) => delivery.latency_ms !== null && delivery.status === 'sent')
      .slice(0, 50)
      .map((delivery) => Number(delivery.latency_ms ?? 0));
    const avgLatencyMs =
      latencies.length > 0 ? Math.round(latencies.reduce((sum, value) => sum + value, 0) / latencies.length) : 0;
    return {
      activeEndpoints,
      failingEndpoints,
      sentDeliveries,
      failedDeliveries,
      avgLatencyMs,
    };
  }, [deliveries, endpoints]);

  const endpointDeliveries = useMemo(() => {
    if (!selectedEndpoint) return [];
    return deliveries.filter((delivery) => delivery.endpoint_id === selectedEndpoint.id);
  }, [deliveries, selectedEndpoint]);

  const isBusy = loadingEndpoints || loadingDeliveries || loadingInbound;

  return (
    <div className="space-y-4 fade-in">
      <div className="flex items-center justify-between gap-3">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">Outbound Integrations</h1>
          <p className="text-sm text-muted-foreground mt-0.5">
            Configure outbound webhook endpoints, delivery retries, signing, and replay.
          </p>
        </div>
        <div className="flex items-center gap-2">
          <button
            onClick={() => void refreshAll()}
            className="flex items-center gap-2 px-3 py-2 text-sm font-medium border border-border rounded-md hover:bg-muted/50 transition-all"
          >
            <RefreshCw size={14} className={isBusy ? 'animate-spin' : ''} />
            Refresh
          </button>
          <button
            onClick={() => setCreateModalOpen(true)}
            className="flex items-center gap-2 px-3 py-2 text-sm font-medium bg-primary text-primary-foreground rounded-md hover:bg-primary/90 transition-all"
          >
            <Plus size={15} />
            Add Endpoint
          </button>
        </div>
      </div>

      <div className="grid grid-cols-2 md:grid-cols-6 gap-3">
        <StatCard label="Total Endpoints" value={String(endpoints.length)} icon={Webhook} color="text-primary" />
        <StatCard label="Active" value={String(health.activeEndpoints)} icon={CheckCircle} color="text-green-400" />
        <StatCard label="Failing" value={String(health.failingEndpoints)} icon={AlertTriangle} color="text-red-400" />
        <StatCard label="Sent Deliveries" value={String(health.sentDeliveries)} icon={Activity} color="text-blue-400" />
        <StatCard label="Inbound (24h)" value={String(inboundLast24h)} icon={Shield} color="text-cyan-400" />
        <StatCard label="Avg Latency" value={`${health.avgLatencyMs}ms`} icon={Zap} color="text-amber-400" />
      </div>

      <div className="flex items-center gap-1 bg-muted/30 rounded-lg p-1 w-fit">
        {(['endpoints', 'deliveries', 'inbound', 'docs'] as const).map((tab) => (
          <button
            key={tab}
            onClick={() => setActiveTab(tab)}
            className={`px-3 py-1.5 rounded-md text-xs font-medium transition-all capitalize ${
              activeTab === tab ? 'bg-card text-foreground shadow-sm' : 'text-muted-foreground hover:text-foreground'
            }`}
          >
            {tab === 'docs'
              ? 'Signature Docs'
              : tab === 'inbound'
              ? 'Inbound'
              : tab.charAt(0).toUpperCase() + tab.slice(1)}
          </button>
        ))}
      </div>

      {activeTab === 'endpoints' && (
        <div className="grid grid-cols-1 xl:grid-cols-3 gap-4">
          <div className="xl:col-span-1 space-y-2">
            {loadingEndpoints && endpoints.length === 0 ? (
              <div className="text-xs text-muted-foreground p-4 border border-border rounded-lg">Loading endpoints…</div>
            ) : (
              endpoints.map((endpoint) => (
                <div
                  key={endpoint.id}
                  onClick={() => setSelectedEndpointId((current) => (current === endpoint.id ? null : endpoint.id))}
                  className={`bg-card border rounded-lg p-4 cursor-pointer transition-all hover:border-primary/40 ${
                    selectedEndpointId === endpoint.id ? 'border-primary/60 bg-primary/5' : 'border-border'
                  }`}
                >
                  <div className="flex items-start justify-between mb-2 gap-2">
                    <div className="flex items-center gap-2 min-w-0">
                      <Globe size={14} className="text-muted-foreground flex-shrink-0 mt-0.5" />
                      <div className="min-w-0">
                        <p className="text-sm font-semibold truncate">{endpoint.name}</p>
                        <p className="text-[11px] text-muted-foreground font-mono truncate">{endpoint.url}</p>
                      </div>
                    </div>
                    <span className={`text-[10px] font-semibold px-2 py-0.5 rounded-full border ${endpointStatusClass(endpoint.status)}`}>
                      {endpoint.status.toUpperCase()}
                    </span>
                  </div>
                  <div className="flex items-center gap-3 text-[11px] text-muted-foreground">
                    <span className="flex items-center gap-1">
                      <Zap size={10} />
                      {endpoint.events.length} events
                    </span>
                    <span className="flex items-center gap-1">
                      <RotateCcw size={10} />
                      {endpoint.retry_policy}
                    </span>
                    <span className="flex items-center gap-1">
                      <Activity size={10} />
                      {endpoint.total_deliveries}
                    </span>
                  </div>
                  {endpoint.failure_count > 0 && (
                    <div className="mt-2 flex items-center gap-1 text-[11px] text-red-400">
                      <AlertTriangle size={10} />
                      {endpoint.failure_count} dead-letter deliveries
                    </div>
                  )}
                </div>
              ))
            )}
          </div>

          <div className="xl:col-span-2">
            {selectedEndpoint ? (
              <div className="bg-card border border-border rounded-lg">
                <div className="flex items-center justify-between px-5 py-4 border-b border-border gap-3">
                  <div>
                    <h3 className="font-semibold">{selectedEndpoint.name}</h3>
                    <p className="text-xs text-muted-foreground font-mono break-all">{selectedEndpoint.url}</p>
                  </div>
                  <div className="flex items-center gap-2">
                    <button
                      onClick={() => void handleTestEndpoint(selectedEndpoint)}
                      disabled={!selectedEndpoint.can_manage}
                      className="flex items-center gap-1.5 px-2.5 py-1.5 text-xs bg-blue-500/10 border border-blue-500/20 text-blue-400 rounded-md hover:bg-blue-500/20 transition-colors disabled:opacity-50"
                    >
                      <Play size={11} />
                      Test
                    </button>
                    <button
                      onClick={() => void handleToggleEndpoint(selectedEndpoint)}
                      disabled={!selectedEndpoint.can_manage}
                      className="flex items-center gap-1.5 px-2.5 py-1.5 text-xs bg-amber-500/10 border border-amber-500/20 text-amber-400 rounded-md hover:bg-amber-500/20 transition-colors disabled:opacity-50"
                    >
                      {selectedEndpoint.status === 'paused' ? <Play size={11} /> : <Pause size={11} />}
                      {selectedEndpoint.status === 'paused' ? 'Resume' : 'Pause'}
                    </button>
                    <button
                      onClick={() => {
                        setEditingDraft({
                          id: selectedEndpoint.id,
                          name: selectedEndpoint.name,
                          url: selectedEndpoint.url,
                          events: selectedEndpoint.events,
                          retry_policy: selectedEndpoint.retry_policy,
                          max_retries: selectedEndpoint.max_retries,
                          timeout_ms: selectedEndpoint.timeout_ms,
                        });
                        setEditModalOpen(true);
                      }}
                      disabled={!selectedEndpoint.can_manage}
                      className="flex items-center gap-1.5 px-2.5 py-1.5 text-xs bg-muted/60 border border-border text-foreground rounded-md hover:bg-muted transition-colors disabled:opacity-50"
                    >
                      <Save size={11} />
                      Edit
                    </button>
                    <button
                      onClick={() => void handleDeleteEndpoint(selectedEndpoint.id)}
                      disabled={!selectedEndpoint.can_manage}
                      className="p-1.5 text-muted-foreground hover:text-red-400 transition-colors disabled:opacity-50"
                    >
                      <Trash2 size={14} />
                    </button>
                  </div>
                </div>

                <div className="p-5 space-y-4">
                  <div>
                    <p className="text-[10px] text-muted-foreground uppercase tracking-wide mb-2 flex items-center gap-1.5">
                      <Lock size={10} />
                      Signing Secret (HMAC-SHA256)
                    </p>
                    <div className="flex items-center gap-2 bg-muted/40 rounded-md px-3 py-2">
                      <code className="text-xs font-mono flex-1 truncate">
                        {renderSecret(selectedEndpoint.secret_masked, revealedSecrets[selectedEndpoint.id] ?? null)}
                      </code>
                      <button
                        onClick={() => void handleRevealSecret(selectedEndpoint)}
                        disabled={!selectedEndpoint.can_manage}
                        className="text-muted-foreground hover:text-foreground transition-colors disabled:opacity-50"
                      >
                        {revealedSecrets[selectedEndpoint.id] ? <EyeOff size={13} /> : <Eye size={13} />}
                      </button>
                      <button
                        onClick={() => {
                          const value = renderSecret(
                            selectedEndpoint.secret_masked,
                            revealedSecrets[selectedEndpoint.id] ?? null,
                          );
                          void navigator.clipboard.writeText(value);
                          toast.success('Secret copied');
                        }}
                        className="text-muted-foreground hover:text-foreground transition-colors"
                      >
                        <Copy size={13} />
                      </button>
                      <button
                        onClick={() => void handleRotateSecret(selectedEndpoint)}
                        disabled={!selectedEndpoint.can_manage}
                        className="text-muted-foreground hover:text-foreground transition-colors disabled:opacity-50"
                      >
                        <RotateCcw size={13} />
                      </button>
                    </div>
                  </div>

                  <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
                    <SmallStat label="Retry Policy" value={selectedEndpoint.retry_policy} />
                    <SmallStat label="Max Retries" value={String(selectedEndpoint.max_retries)} />
                    <SmallStat label="Timeout (ms)" value={String(selectedEndpoint.timeout_ms)} />
                    <SmallStat label="Last Status" value={selectedEndpoint.last_status ? String(selectedEndpoint.last_status) : '—'} />
                  </div>

                  <div>
                    <p className="text-[10px] text-muted-foreground uppercase tracking-wide mb-2">Subscribed Events</p>
                    <div className="flex flex-wrap gap-1.5">
                      {selectedEndpoint.events.map((eventType) => (
                        <span
                          key={eventType}
                          className="text-[11px] px-2 py-0.5 bg-primary/10 text-primary rounded-full border border-primary/20"
                        >
                          {eventType}
                        </span>
                      ))}
                    </div>
                  </div>

                  <div>
                    <p className="text-[10px] text-muted-foreground uppercase tracking-wide mb-2">Recent Deliveries</p>
                    <div className="space-y-1.5">
                      {endpointDeliveries.slice(0, 8).map((delivery) => (
                        <div key={delivery.id} className="bg-muted/20 rounded-lg overflow-hidden">
                          <div
                            className="flex items-center gap-3 px-3 py-2.5 cursor-pointer hover:bg-muted/40 transition-colors"
                            onClick={() =>
                              setExpandedDeliveryId((current) => (current === delivery.id ? null : delivery.id))
                            }
                          >
                            <span className={`text-[11px] font-medium w-24 ${deliveryStatusClass(delivery.status)}`}>
                              {delivery.status.toUpperCase()}
                            </span>
                            <span className="text-[11px] text-muted-foreground flex-1 truncate">{delivery.event_type}</span>
                            <span className="text-[11px] text-muted-foreground tabular-nums">{safeIsoLocal(delivery.created_at)}</span>
                            <span className="text-[11px] text-muted-foreground">
                              {delivery.attempt}/{delivery.max_attempts}
                            </span>
                            {expandedDeliveryId === delivery.id ? <ChevronUp size={11} /> : <ChevronDown size={11} />}
                          </div>
                          {expandedDeliveryId === delivery.id && (
                            <div className="px-3 pb-3 space-y-2 border-t border-border/50">
                              <div className="mt-2 text-[11px] text-muted-foreground">
                                HTTP {delivery.http_status ?? '—'} · Latency {delivery.latency_ms ?? '—'}ms
                              </div>
                              <pre className="text-[11px] font-mono bg-muted/40 rounded p-2 overflow-x-auto text-muted-foreground">
                                {JSON.stringify(delivery.payload ?? {}, null, 2)}
                              </pre>
                              {(delivery.response_body || delivery.last_error) && (
                                <pre className="text-[11px] font-mono bg-muted/40 rounded p-2 overflow-x-auto text-muted-foreground">
                                  {(delivery.response_body ?? delivery.last_error ?? '').slice(0, 1200)}
                                </pre>
                              )}
                            </div>
                          )}
                        </div>
                      ))}
                      {endpointDeliveries.length === 0 && (
                        <div className="text-xs text-muted-foreground border border-border rounded-lg p-3">
                          No deliveries for this endpoint yet.
                        </div>
                      )}
                    </div>
                  </div>
                </div>
              </div>
            ) : (
              <div className="bg-card border border-border rounded-lg flex items-center justify-center h-64">
                <div className="text-center">
                  <Webhook size={32} className="mx-auto text-muted-foreground/30 mb-3" />
                  <p className="text-sm font-medium text-muted-foreground">Select an endpoint to view details</p>
                  <p className="text-xs text-muted-foreground/60 mt-1">
                    Pick any endpoint on the left to inspect config and delivery history.
                  </p>
                </div>
              </div>
            )}
          </div>
        </div>
      )}

      {activeTab === 'deliveries' && (
        <div className="bg-card border border-border rounded-lg overflow-hidden">
          <div className="px-4 py-3 border-b border-border flex items-center justify-between gap-3 flex-wrap">
            <p className="text-sm font-semibold">Delivery History</p>
            <div className="flex items-center gap-2 flex-wrap">
              <select
                value={deliveryFilterEndpointId}
                onChange={(event) => setDeliveryFilterEndpointId(event.target.value)}
                className="px-2.5 py-1.5 text-xs bg-muted/60 border border-border rounded-md"
              >
                <option value="">All Endpoints</option>
                {endpoints.map((endpoint) => (
                  <option key={endpoint.id} value={endpoint.id}>
                    {endpoint.name}
                  </option>
                ))}
              </select>
              <select
                value={deliveryFilterStatus}
                onChange={(event) => setDeliveryFilterStatus(event.target.value)}
                className="px-2.5 py-1.5 text-xs bg-muted/60 border border-border rounded-md"
              >
                <option value="">All Status</option>
                <option value="pending">pending</option>
                <option value="retrying">retrying</option>
                <option value="sent">sent</option>
                <option value="dead_letter">dead_letter</option>
              </select>
              <select
                value={deliveryFilterEventType}
                onChange={(event) => setDeliveryFilterEventType(event.target.value)}
                className="px-2.5 py-1.5 text-xs bg-muted/60 border border-border rounded-md"
              >
                <option value="">All Event Types</option>
                {eventCatalog.map((eventType) => (
                  <option key={eventType} value={eventType}>
                    {eventType}
                  </option>
                ))}
              </select>
              <button
                onClick={() => void loadDeliveries()}
                className="flex items-center gap-1.5 text-xs text-muted-foreground hover:text-foreground transition-colors"
              >
                <RefreshCw size={12} className={loadingDeliveries ? 'animate-spin' : ''} />
                Refresh
              </button>
            </div>
          </div>
          <div className="divide-y divide-border">
            {deliveries.map((delivery) => (
              <div key={delivery.id} className="overflow-hidden">
                <div
                  className="flex items-center gap-3 px-4 py-3 cursor-pointer hover:bg-muted/20 transition-colors"
                  onClick={() =>
                    setExpandedDeliveryId((current) => (current === delivery.id ? null : delivery.id))
                  }
                >
                  <span className={`text-xs font-semibold w-24 ${deliveryStatusClass(delivery.status)}`}>
                    {delivery.status.toUpperCase()}
                  </span>
                  <span className="text-xs text-muted-foreground w-48 truncate">{delivery.endpoint_name ?? 'Unknown'}</span>
                  <span className="text-xs flex-1 truncate">{delivery.event_type}</span>
                  <span className="text-xs text-muted-foreground">{safeIsoLocal(delivery.created_at)}</span>
                  <span className="text-xs font-mono text-muted-foreground w-14 text-right">
                    {delivery.http_status ?? '—'}
                  </span>
                  <span className="text-xs text-muted-foreground w-20 text-right">{delivery.latency_ms ?? '—'}ms</span>
                  <span className="text-xs text-muted-foreground">
                    {delivery.attempt}/{delivery.max_attempts}
                  </span>
                  {delivery.status === 'dead_letter' && delivery.can_replay && (
                    <button
                      onClick={(event) => {
                        event.stopPropagation();
                        void handleReplayDelivery(delivery);
                      }}
                      className="flex items-center gap-1 px-2 py-1 text-[11px] bg-amber-500/10 border border-amber-500/20 text-amber-400 rounded-md hover:bg-amber-500/20 transition-colors"
                    >
                      <RotateCcw size={10} />
                      Replay
                    </button>
                  )}
                  {expandedDeliveryId === delivery.id ? <ChevronUp size={12} /> : <ChevronDown size={12} />}
                </div>
                {expandedDeliveryId === delivery.id && (
                  <div className="px-4 pb-4 space-y-2 bg-muted/10 border-t border-border/50">
                    <div className="text-[11px] text-muted-foreground mt-3">
                      Delivery ID: <code>{delivery.id}</code>
                    </div>
                    <pre className="text-[11px] font-mono bg-muted/40 rounded p-2 overflow-x-auto text-muted-foreground">
                      {JSON.stringify(delivery.payload ?? {}, null, 2)}
                    </pre>
                    {(delivery.response_body || delivery.last_error) && (
                      <pre className="text-[11px] font-mono bg-muted/40 rounded p-2 overflow-x-auto text-muted-foreground">
                        {(delivery.response_body ?? delivery.last_error ?? '').slice(0, 1600)}
                      </pre>
                    )}
                  </div>
                )}
              </div>
            ))}
            {!loadingDeliveries && deliveries.length === 0 && (
              <div className="p-4 text-xs text-muted-foreground">No deliveries matched the selected filters.</div>
            )}
          </div>
        </div>
      )}

      {activeTab === 'inbound' && (
        <div className="bg-card border border-border rounded-lg overflow-hidden">
          <div className="px-4 py-3 border-b border-border flex items-center justify-between gap-3 flex-wrap">
            <p className="text-sm font-semibold">Inbound Webhook Events (Internal)</p>
            <div className="flex items-center gap-2 flex-wrap">
              <select
                value={inboundFilterEventType}
                onChange={(event) => setInboundFilterEventType(event.target.value)}
                className="px-2.5 py-1.5 text-xs bg-muted/60 border border-border rounded-md"
              >
                <option value="">All Event Types</option>
                {inboundEventBreakdown.map((item) => (
                  <option key={item.event_type} value={item.event_type}>
                    {item.event_type}
                  </option>
                ))}
              </select>
              <button
                onClick={() => void loadInbound()}
                className="flex items-center gap-1.5 text-xs text-muted-foreground hover:text-foreground transition-colors"
              >
                <RefreshCw size={12} className={loadingInbound ? 'animate-spin' : ''} />
                Refresh
              </button>
            </div>
          </div>

          <div className="px-4 py-3 border-b border-border text-xs text-muted-foreground flex items-center gap-3 flex-wrap">
            <span>Last 24h: {inboundLast24h}</span>
            <span>Showing: {inboundEvents.length}</span>
            {inboundEventBreakdown.length > 0 && (
              <span className="truncate">
                Top:
                {' '}
                {inboundEventBreakdown
                  .slice(0, 4)
                  .map((item) => `${item.event_type} (${item.total})`)
                  .join(' · ')}
              </span>
            )}
          </div>

          <div className="divide-y divide-border">
            {inboundEvents.map((event) => (
              <div key={`${event.id}-${event.event_key}`} className="px-4 py-3 grid grid-cols-12 gap-3 text-xs">
                <div className="col-span-3 font-medium truncate">{event.event_type}</div>
                <div className="col-span-4 text-muted-foreground font-mono truncate">{event.event_key}</div>
                <div className="col-span-3 text-muted-foreground font-mono truncate">{event.command_id ?? '—'}</div>
                <div className="col-span-2 text-muted-foreground text-right">{safeIsoLocal(event.received_at)}</div>
              </div>
            ))}
            {!loadingInbound && inboundEvents.length === 0 && (
              <div className="p-4 text-xs text-muted-foreground">No inbound events found for the selected filter.</div>
            )}
          </div>
        </div>
      )}

      {activeTab === 'docs' && (
        <div className="bg-card border border-border rounded-lg p-6 space-y-6">
          <div>
            <h3 className="font-semibold mb-2 flex items-center gap-2">
              <Shield size={16} className="text-primary" />
              Signature Verification
            </h3>
            <p className="text-sm text-muted-foreground mb-3">
              Every outbound delivery is signed with HMAC-SHA256 using canonical input:
              <code className="bg-muted px-1 rounded text-xs ml-1">{'<timestamp>.<event_id>.<raw_body>'}</code>
            </p>
            <div className="bg-muted/40 rounded-lg p-4">
              <p className="text-[10px] text-muted-foreground uppercase tracking-wide mb-2">Request Headers</p>
              <pre className="text-xs font-mono text-muted-foreground overflow-x-auto">{`X-Quoodle-Signature: <hex hmac sha256>
X-Quoodle-Timestamp: <ISO-8601 timestamp>
X-Quoodle-Event-Id: <event_id>
X-Quoodle-Delivery-Id: <delivery_id>
Content-Type: application/json`}</pre>
            </div>
          </div>

          <div className="bg-muted/40 rounded-lg p-4">
            <p className="text-[10px] text-muted-foreground uppercase tracking-wide mb-2">
              HMAC-SHA256 Verification (Node.js)
            </p>
            <pre className="text-xs font-mono text-muted-foreground overflow-x-auto">{`import crypto from 'crypto';

function verifyWebhook({ secret, timestamp, eventId, rawBody, receivedSignature }) {
  const canonical = \`\${timestamp}.\${eventId}.\${rawBody}\`;
  const expected = crypto.createHmac('sha256', secret).update(canonical).digest('hex');
  return crypto.timingSafeEqual(Buffer.from(expected, 'utf8'), Buffer.from(receivedSignature, 'utf8'));
}`}</pre>
          </div>

          <div>
            <h3 className="font-semibold mb-2 flex items-center gap-2">
              <RotateCcw size={16} className="text-primary" />
              Retry Policies
            </h3>
            <div className="space-y-2">
              <PolicyRow
                name="exponential"
                description="Backoff grows per attempt with jitter until max_retries is reached."
              />
              <PolicyRow name="linear" description="Fixed delay between attempts until max_retries is reached." />
              <PolicyRow name="none" description="Single attempt only, no retries." />
            </div>
          </div>
        </div>
      )}

      {createModalOpen && (
        <EndpointModal
          title="Create Webhook Endpoint"
          eventCatalog={eventCatalog}
          onClose={() => setCreateModalOpen(false)}
          onSubmit={(draft) => void handleCreateEndpoint(draft)}
        />
      )}

      {editModalOpen && editingDraft && (
        <EndpointModal
          title="Edit Webhook Endpoint"
          initialValue={editingDraft}
          eventCatalog={eventCatalog}
          onClose={() => {
            setEditModalOpen(false);
            setEditingDraft(null);
          }}
          onSubmit={(draft) => void handleUpdateEndpoint(editingDraft.id ?? '', draft)}
        />
      )}
    </div>
  );
}

function StatCard({
  label,
  value,
  icon: Icon,
  color,
}: {
  label: string;
  value: string;
  icon: React.ComponentType<{ size?: number; className?: string }>;
  color: string;
}) {
  return (
    <div className="bg-card border border-border rounded-lg p-4">
      <div className="flex items-center justify-between mb-1">
        <p className="text-xs text-muted-foreground">{label}</p>
        <Icon size={14} className={color} />
      </div>
      <p className="text-2xl font-bold tabular-nums">{value}</p>
    </div>
  );
}

function SmallStat({ label, value }: { label: string; value: string }) {
  return (
    <div className="bg-muted/30 rounded-lg p-3">
      <p className="text-[10px] text-muted-foreground uppercase tracking-wide mb-1">{label}</p>
      <p className="text-sm font-semibold">{value}</p>
    </div>
  );
}

function PolicyRow({ name, description }: { name: string; description: string }) {
  return (
    <div className="flex items-start gap-3 bg-muted/30 rounded-lg p-3">
      <div className="flex-1">
        <p className="text-sm font-medium font-mono">{name}</p>
        <p className="text-xs text-muted-foreground mt-0.5">{description}</p>
      </div>
    </div>
  );
}

function EndpointModal({
  title,
  initialValue,
  eventCatalog,
  onClose,
  onSubmit,
}: {
  title: string;
  initialValue?: EndpointDraft;
  eventCatalog: string[];
  onClose: () => void;
  onSubmit: (draft: EndpointDraft) => void;
}) {
  const [name, setName] = useState(initialValue?.name ?? '');
  const [url, setUrl] = useState(initialValue?.url ?? '');
  const [events, setEvents] = useState<string[]>(initialValue?.events ?? []);
  const [retryPolicy, setRetryPolicy] = useState<RetryPolicy>(initialValue?.retry_policy ?? 'exponential');
  const [maxRetries, setMaxRetries] = useState<number>(initialValue?.max_retries ?? 3);
  const [timeoutMs, setTimeoutMs] = useState<number>(initialValue?.timeout_ms ?? 5000);

  const toggleEvent = (eventType: string): void => {
    setEvents((current) =>
      current.includes(eventType) ? current.filter((item) => item !== eventType) : [...current, eventType],
    );
  };

  const save = (): void => {
    if (!name.trim() || !url.trim()) {
      toast.error('Name and URL are required');
      return;
    }
    if (events.length === 0) {
      toast.error('Select at least one event type');
      return;
    }
    onSubmit({
      name: name.trim(),
      url: url.trim(),
      events,
      retry_policy: retryPolicy,
      max_retries: Math.max(0, Math.min(maxRetries, 10)),
      timeout_ms: Math.max(500, Math.min(timeoutMs, 30000)),
    });
  };

  return (
    <>
      <div className="fixed inset-0 bg-black/50 z-40" onClick={onClose} />
      <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
        <div className="bg-card border border-border rounded-xl w-full max-w-xl max-h-[90vh] overflow-y-auto">
          <div className="flex items-center justify-between px-5 py-4 border-b border-border">
            <h3 className="font-semibold">{title}</h3>
            <button
              onClick={onClose}
              className="p-1.5 text-muted-foreground hover:text-foreground transition-colors"
            >
              <X size={15} />
            </button>
          </div>

          <div className="p-5 space-y-4">
            <div>
              <label className="text-xs text-muted-foreground mb-1 block">Endpoint Name *</label>
              <input
                value={name}
                onChange={(event) => setName(event.target.value)}
                placeholder="e.g. SOC Bridge"
                className="w-full px-3 py-2 text-sm bg-muted/60 border border-border rounded-md focus:outline-none focus:ring-1 focus:ring-primary/50"
              />
            </div>

            <div>
              <label className="text-xs text-muted-foreground mb-1 block">Endpoint URL *</label>
              <input
                value={url}
                onChange={(event) => setUrl(event.target.value)}
                placeholder="https://example.com/quoodle/webhook"
                className="w-full px-3 py-2 text-sm bg-muted/60 border border-border rounded-md focus:outline-none focus:ring-1 focus:ring-primary/50"
              />
            </div>

            <div className="grid grid-cols-3 gap-3">
              <div>
                <label className="text-xs text-muted-foreground mb-1 block">Retry Policy</label>
                <select
                  value={retryPolicy}
                  onChange={(event) => setRetryPolicy(event.target.value as RetryPolicy)}
                  className="w-full px-3 py-2 text-sm bg-muted/60 border border-border rounded-md focus:outline-none focus:ring-1 focus:ring-primary/50"
                >
                  <option value="exponential">exponential</option>
                  <option value="linear">linear</option>
                  <option value="none">none</option>
                </select>
              </div>
              <div>
                <label className="text-xs text-muted-foreground mb-1 block">Max Retries</label>
                <input
                  type="number"
                  min={0}
                  max={10}
                  value={maxRetries}
                  onChange={(event) => setMaxRetries(Number(event.target.value))}
                  className="w-full px-3 py-2 text-sm bg-muted/60 border border-border rounded-md focus:outline-none focus:ring-1 focus:ring-primary/50"
                />
              </div>
              <div>
                <label className="text-xs text-muted-foreground mb-1 block">Timeout (ms)</label>
                <input
                  type="number"
                  min={500}
                  max={30000}
                  value={timeoutMs}
                  onChange={(event) => setTimeoutMs(Number(event.target.value))}
                  className="w-full px-3 py-2 text-sm bg-muted/60 border border-border rounded-md focus:outline-none focus:ring-1 focus:ring-primary/50"
                />
              </div>
            </div>

            <div>
              <label className="text-xs text-muted-foreground mb-2 block">Event Subscriptions *</label>
              <div className="flex flex-wrap gap-1.5 max-h-40 overflow-y-auto">
                {eventCatalog.map((eventType) => (
                  <button
                    key={eventType}
                    onClick={() => toggleEvent(eventType)}
                    className={`text-[11px] px-2 py-0.5 rounded-full border transition-colors ${
                      events.includes(eventType)
                        ? 'bg-primary/20 text-primary border-primary/40'
                        : 'bg-muted/40 text-muted-foreground border-border hover:border-primary/30'
                    }`}
                  >
                    {eventType}
                  </button>
                ))}
              </div>
            </div>
          </div>

          <div className="flex items-center justify-end gap-2 px-5 py-4 border-t border-border">
            <button onClick={onClose} className="px-4 py-2 text-sm text-muted-foreground hover:text-foreground">
              Cancel
            </button>
            <button
              onClick={save}
              className="flex items-center gap-1.5 px-4 py-2 text-sm bg-primary text-primary-foreground rounded-md hover:bg-primary/90"
            >
              <Save size={13} />
              Save Endpoint
            </button>
          </div>
        </div>
      </div>
    </>
  );
}

