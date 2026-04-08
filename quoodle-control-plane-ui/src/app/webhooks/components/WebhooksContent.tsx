'use client';
import React, { useState } from 'react';
import { Webhook, Plus, RefreshCw, Trash2, Play, Pause, CheckCircle, XCircle, AlertTriangle, Shield, ChevronDown, ChevronUp, Copy, Eye, EyeOff, RotateCcw, Activity, Zap, Globe, Lock, X, Save } from 'lucide-react';
import { toast } from 'sonner';

type WebhookStatus = 'active' | 'paused' | 'failing';
type RetryPolicy = 'exponential' | 'linear' | 'none';

interface WebhookEndpoint {
  id: string;
  name: string;
  url: string;
  status: WebhookStatus;
  events: string[];
  secret: string;
  signingAlgo: 'hmac-sha256' | 'hmac-sha512';
  retryPolicy: RetryPolicy;
  maxRetries: number;
  lastDelivery: string | null;
  lastStatus: number | null;
  totalDeliveries: number;
  failureCount: number;
  createdAt: string;
}

interface DeliveryLog {
  id: string;
  webhookId: string;
  event: string;
  status: 'success' | 'failed' | 'retrying';
  statusCode: number | null;
  attempt: number;
  maxAttempts: number;
  timestamp: string;
  duration: string;
  payload: string;
  response: string | null;
}

const EVENT_TYPES = [
  'command.completed', 'command.failed', 'command.queued',
  'device.online', 'device.offline', 'device.quarantined',
  'alert.critical', 'alert.high', 'alert.medium',
  'result.system-info', 'result.screenshot', 'result.filesystem',
  'compliance.drift', 'compliance.violation',
  'audit.policy_change', 'audit.user_action',
];

const mockWebhooks: WebhookEndpoint[] = [
  {
    id: 'wh-001', name: 'Splunk SIEM', url: 'https://splunk.corp.internal/services/collector/event',
    status: 'active', events: ['command.completed', 'command.failed', 'alert.critical', 'alert.high', 'result.system-info'],
    secret: 'whsec_a1b2c3d4e5f6789012345678901234567890abcdef',
    signingAlgo: 'hmac-sha256', retryPolicy: 'exponential', maxRetries: 5,
    lastDelivery: '21:06:09', lastStatus: 200, totalDeliveries: 1842, failureCount: 3, createdAt: '2026-03-01',
  },
  {
    id: 'wh-002', name: 'PagerDuty Alerts', url: 'https://events.pagerduty.com/v2/enqueue',
    status: 'active', events: ['alert.critical', 'device.quarantined', 'compliance.violation'],
    secret: 'whsec_b2c3d4e5f6789012345678901234567890abcdef01',
    signingAlgo: 'hmac-sha256', retryPolicy: 'exponential', maxRetries: 3,
    lastDelivery: '20:58:44', lastStatus: 202, totalDeliveries: 247, failureCount: 0, createdAt: '2026-03-10',
  },
  {
    id: 'wh-003', name: 'Elastic SIEM', url: 'https://elastic.corp.internal:9200/quoodle-events/_doc',
    status: 'failing', events: ['command.completed', 'command.failed', 'result.system-info', 'result.screenshot', 'result.filesystem'],
    secret: 'whsec_c3d4e5f6789012345678901234567890abcdef0102',
    signingAlgo: 'hmac-sha512', retryPolicy: 'linear', maxRetries: 3,
    lastDelivery: '20:14:22', lastStatus: 503, totalDeliveries: 5621, failureCount: 47, createdAt: '2026-02-15',
  },
  {
    id: 'wh-004', name: 'Slack Ops Channel', url: 'https://hooks.slack.com/services/T00000000/B00000000/XXXXXXXX',
    status: 'paused', events: ['alert.critical', 'device.offline', 'compliance.drift'],
    secret: 'whsec_d4e5f6789012345678901234567890abcdef010203',
    signingAlgo: 'hmac-sha256', retryPolicy: 'none', maxRetries: 0,
    lastDelivery: '18:30:00', lastStatus: 200, totalDeliveries: 892, failureCount: 2, createdAt: '2026-03-20',
  },
];

const mockDeliveries: DeliveryLog[] = [
  { id: 'del-001', webhookId: 'wh-001', event: 'command.completed', status: 'success', statusCode: 200, attempt: 1, maxAttempts: 5, timestamp: '21:06:09', duration: '142ms', payload: '{"event":"command.completed","command_id":"CMD-7742","device_id":"WKSTN-055","result":"ok"}', response: '{"status":"ok"}' },
  { id: 'del-002', webhookId: 'wh-001', event: 'alert.critical', status: 'success', statusCode: 200, attempt: 1, maxAttempts: 5, timestamp: '21:04:11', duration: '98ms', payload: '{"event":"alert.critical","device_id":"SRV-PROD-04","message":"Attestation hash mismatch"}', response: '{"status":"ok"}' },
  { id: 'del-003', webhookId: 'wh-003', event: 'result.system-info', status: 'failed', statusCode: 503, attempt: 3, maxAttempts: 3, timestamp: '20:14:22', duration: '5001ms', payload: '{"event":"result.system-info","device_id":"WKSTN-001","data":{...}}', response: 'Service Unavailable' },
  { id: 'del-004', webhookId: 'wh-003', event: 'command.completed', status: 'retrying', statusCode: null, attempt: 2, maxAttempts: 3, timestamp: '20:12:00', duration: '—', payload: '{"event":"command.completed","command_id":"CMD-7737"}', response: null },
  { id: 'del-005', webhookId: 'wh-002', event: 'alert.critical', status: 'success', statusCode: 202, attempt: 1, maxAttempts: 3, timestamp: '20:58:44', duration: '211ms', payload: '{"event":"alert.critical","device_id":"SRV-PROD-04"}', response: '{"dedup_key":"abc123"}' },
];

export default function WebhooksContent() {
  const [webhooks, setWebhooks] = useState<WebhookEndpoint[]>(mockWebhooks);
  const [selectedWebhook, setSelectedWebhook] = useState<WebhookEndpoint | null>(null);
  const [showCreateModal, setShowCreateModal] = useState(false);
  const [activeTab, setActiveTab] = useState<'endpoints' | 'deliveries' | 'docs'>('endpoints');
  const [expandedDelivery, setExpandedDelivery] = useState<string | null>(null);
  const [revealedSecrets, setRevealedSecrets] = useState<Set<string>>(new Set());

  const toggleSecret = (id: string) => {
    setRevealedSecrets(prev => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id); else next.add(id);
      return next;
    });
  };

  const toggleStatus = (id: string) => {
    setWebhooks(prev => prev.map(w => w.id === id ? { ...w, status: w.status === 'active' ? 'paused' : 'active' } : w));
    toast.success('Webhook status updated');
  };

  const deleteWebhook = (id: string) => {
    setWebhooks(prev => prev.filter(w => w.id !== id));
    if (selectedWebhook?.id === id) setSelectedWebhook(null);
    toast.success('Webhook endpoint deleted');
  };

  const testWebhook = (wh: WebhookEndpoint) => {
    toast.promise(
      new Promise(resolve => setTimeout(resolve, 1200)),
      { loading: `Sending test event to ${wh.name}…`, success: 'Test delivery sent — check delivery logs', error: 'Test delivery failed' }
    );
  };

  const statusColor = (s: WebhookStatus) =>
    s === 'active' ? 'text-green-400 bg-green-500/10 border-green-500/20' :
    s === 'failing'? 'text-red-400 bg-red-500/10 border-red-500/20' : 'text-amber-400 bg-amber-500/10 border-amber-500/20';

  const deliveryStatusColor = (s: string) =>
    s === 'success' ? 'text-green-400' : s === 'failed' ? 'text-red-400' : 'text-amber-400';

  const deliveries = selectedWebhook
    ? mockDeliveries.filter(d => d.webhookId === selectedWebhook.id)
    : mockDeliveries;

  return (
    <div className="space-y-4 fade-in">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">Webhook Endpoints</h1>
          <p className="text-sm text-muted-foreground mt-0.5">Push command results to SIEM and monitoring systems with retry + signature validation</p>
        </div>
        <button
          onClick={() => setShowCreateModal(true)}
          className="flex items-center gap-2 px-3 py-2 text-sm font-medium bg-primary text-primary-foreground rounded-md hover:bg-primary/90 transition-all"
        >
          <Plus size={15} /> Add Endpoint
        </button>
      </div>

      {/* Stats row */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
        {[
          { label: 'Total Endpoints', value: webhooks.length, icon: Webhook, color: 'text-primary' },
          { label: 'Active', value: webhooks.filter(w => w.status === 'active').length, icon: CheckCircle, color: 'text-green-400' },
          { label: 'Failing', value: webhooks.filter(w => w.status === 'failing').length, icon: AlertTriangle, color: 'text-red-400' },
          { label: 'Total Deliveries', value: webhooks.reduce((a, w) => a + w.totalDeliveries, 0).toLocaleString(), icon: Activity, color: 'text-blue-400' },
        ].map(stat => (
          <div key={stat.label} className="bg-card border border-border rounded-lg p-4">
            <div className="flex items-center justify-between mb-1">
              <p className="text-xs text-muted-foreground">{stat.label}</p>
              <stat.icon size={14} className={stat.color} />
            </div>
            <p className="text-2xl font-bold tabular-nums">{stat.value}</p>
          </div>
        ))}
      </div>

      {/* Tabs */}
      <div className="flex items-center gap-1 bg-muted/30 rounded-lg p-1 w-fit">
        {(['endpoints', 'deliveries', 'docs'] as const).map(tab => (
          <button
            key={tab}
            onClick={() => setActiveTab(tab)}
            className={`px-3 py-1.5 rounded-md text-xs font-medium transition-all capitalize ${
              activeTab === tab ? 'bg-card text-foreground shadow-sm' : 'text-muted-foreground hover:text-foreground'
            }`}
          >
            {tab === 'docs' ? 'Signature Docs' : tab.charAt(0).toUpperCase() + tab.slice(1)}
          </button>
        ))}
      </div>

      {activeTab === 'endpoints' && (
        <div className="grid grid-cols-1 xl:grid-cols-3 gap-4">
          {/* Endpoint list */}
          <div className="xl:col-span-1 space-y-2">
            {webhooks.map(wh => (
              <div
                key={wh.id}
                onClick={() => setSelectedWebhook(selectedWebhook?.id === wh.id ? null : wh)}
                className={`bg-card border rounded-lg p-4 cursor-pointer transition-all hover:border-primary/40 ${
                  selectedWebhook?.id === wh.id ? 'border-primary/60 bg-primary/5' : 'border-border'
                }`}
              >
                <div className="flex items-start justify-between mb-2">
                  <div className="flex items-center gap-2">
                    <Globe size={14} className="text-muted-foreground flex-shrink-0 mt-0.5" />
                    <div>
                      <p className="text-sm font-semibold">{wh.name}</p>
                      <p className="text-[11px] text-muted-foreground font-mono truncate max-w-[180px]">{wh.url}</p>
                    </div>
                  </div>
                  <span className={`text-[10px] font-semibold px-2 py-0.5 rounded-full border ${statusColor(wh.status)}`}>
                    {wh.status.toUpperCase()}
                  </span>
                </div>
                <div className="flex items-center gap-3 text-[11px] text-muted-foreground">
                  <span className="flex items-center gap-1"><Zap size={10} /> {wh.events.length} events</span>
                  <span className="flex items-center gap-1"><RotateCcw size={10} /> {wh.retryPolicy}</span>
                  <span className="flex items-center gap-1"><Activity size={10} /> {wh.totalDeliveries.toLocaleString()}</span>
                </div>
                {wh.failureCount > 0 && (
                  <div className="mt-2 flex items-center gap-1 text-[11px] text-red-400">
                    <AlertTriangle size={10} /> {wh.failureCount} recent failures
                  </div>
                )}
              </div>
            ))}
          </div>

          {/* Endpoint detail */}
          <div className="xl:col-span-2">
            {selectedWebhook ? (
              <div className="bg-card border border-border rounded-lg">
                <div className="flex items-center justify-between px-5 py-4 border-b border-border">
                  <div>
                    <h3 className="font-semibold">{selectedWebhook.name}</h3>
                    <p className="text-xs text-muted-foreground font-mono">{selectedWebhook.url}</p>
                  </div>
                  <div className="flex items-center gap-2">
                    <button onClick={() => testWebhook(selectedWebhook)} className="flex items-center gap-1.5 px-2.5 py-1.5 text-xs bg-blue-500/10 border border-blue-500/20 text-blue-400 rounded-md hover:bg-blue-500/20 transition-colors">
                      <Play size={11} /> Test
                    </button>
                    <button onClick={() => toggleStatus(selectedWebhook.id)} className="flex items-center gap-1.5 px-2.5 py-1.5 text-xs bg-amber-500/10 border border-amber-500/20 text-amber-400 rounded-md hover:bg-amber-500/20 transition-colors">
                      {selectedWebhook.status === 'active' ? <><Pause size={11} /> Pause</> : <><Play size={11} /> Resume</>}
                    </button>
                    <button onClick={() => deleteWebhook(selectedWebhook.id)} className="p-1.5 text-muted-foreground hover:text-red-400 transition-colors">
                      <Trash2 size={14} />
                    </button>
                  </div>
                </div>

                <div className="p-5 space-y-4">
                  {/* Signing secret */}
                  <div>
                    <p className="text-[10px] text-muted-foreground uppercase tracking-wide mb-2 flex items-center gap-1.5"><Lock size={10} /> Signing Secret ({selectedWebhook.signingAlgo})</p>
                    <div className="flex items-center gap-2 bg-muted/40 rounded-md px-3 py-2">
                      <code className="text-xs font-mono flex-1 truncate">
                        {revealedSecrets.has(selectedWebhook.id) ? selectedWebhook.secret : '•'.repeat(40)}
                      </code>
                      <button onClick={() => toggleSecret(selectedWebhook.id)} className="text-muted-foreground hover:text-foreground transition-colors">
                        {revealedSecrets.has(selectedWebhook.id) ? <EyeOff size={13} /> : <Eye size={13} />}
                      </button>
                      <button onClick={() => { navigator.clipboard.writeText(selectedWebhook.secret); toast.success('Secret copied'); }} className="text-muted-foreground hover:text-foreground transition-colors">
                        <Copy size={13} />
                      </button>
                    </div>
                  </div>

                  {/* Retry config */}
                  <div className="grid grid-cols-3 gap-3">
                    {[
                      { label: 'Retry Policy', value: selectedWebhook.retryPolicy },
                      { label: 'Max Retries', value: selectedWebhook.maxRetries.toString() },
                      { label: 'Last HTTP Status', value: selectedWebhook.lastStatus?.toString() ?? '—' },
                    ].map(item => (
                      <div key={item.label} className="bg-muted/30 rounded-lg p-3">
                        <p className="text-[10px] text-muted-foreground uppercase tracking-wide mb-1">{item.label}</p>
                        <p className="text-sm font-semibold">{item.value}</p>
                      </div>
                    ))}
                  </div>

                  {/* Events */}
                  <div>
                    <p className="text-[10px] text-muted-foreground uppercase tracking-wide mb-2">Subscribed Events</p>
                    <div className="flex flex-wrap gap-1.5">
                      {selectedWebhook.events.map(ev => (
                        <span key={ev} className="text-[11px] px-2 py-0.5 bg-primary/10 text-primary rounded-full border border-primary/20">{ev}</span>
                      ))}
                    </div>
                  </div>

                  {/* Recent deliveries */}
                  <div>
                    <p className="text-[10px] text-muted-foreground uppercase tracking-wide mb-2">Recent Deliveries</p>
                    <div className="space-y-1.5">
                      {deliveries.slice(0, 5).map(del => (
                        <div key={del.id} className="bg-muted/20 rounded-lg overflow-hidden">
                          <div
                            className="flex items-center gap-3 px-3 py-2.5 cursor-pointer hover:bg-muted/40 transition-colors"
                            onClick={() => setExpandedDelivery(expandedDelivery === del.id ? null : del.id)}
                          >
                            {del.status === 'success' ? <CheckCircle size={12} className="text-green-400 flex-shrink-0" /> :
                             del.status === 'failed' ? <XCircle size={12} className="text-red-400 flex-shrink-0" /> :
                             <RotateCcw size={12} className="text-amber-400 flex-shrink-0 animate-spin" />}
                            <span className={`text-[11px] font-medium ${deliveryStatusColor(del.status)}`}>{del.status.toUpperCase()}</span>
                            <span className="text-[11px] text-muted-foreground flex-1">{del.event}</span>
                            <span className="text-[11px] text-muted-foreground tabular-nums">{del.timestamp}</span>
                            <span className="text-[11px] text-muted-foreground">{del.duration}</span>
                            {del.statusCode && <span className="text-[11px] font-mono text-muted-foreground">{del.statusCode}</span>}
                            <span className="text-[11px] text-muted-foreground">Attempt {del.attempt}/{del.maxAttempts}</span>
                            {expandedDelivery === del.id ? <ChevronUp size={11} /> : <ChevronDown size={11} />}
                          </div>
                          {expandedDelivery === del.id && (
                            <div className="px-3 pb-3 space-y-2 border-t border-border/50">
                              <div>
                                <p className="text-[10px] text-muted-foreground uppercase tracking-wide mt-2 mb-1">Payload</p>
                                <pre className="text-[11px] font-mono bg-muted/40 rounded p-2 overflow-x-auto text-muted-foreground">{del.payload}</pre>
                              </div>
                              {del.response && (
                                <div>
                                  <p className="text-[10px] text-muted-foreground uppercase tracking-wide mb-1">Response</p>
                                  <pre className="text-[11px] font-mono bg-muted/40 rounded p-2 overflow-x-auto text-muted-foreground">{del.response}</pre>
                                </div>
                              )}
                            </div>
                          )}
                        </div>
                      ))}
                    </div>
                  </div>
                </div>
              </div>
            ) : (
              <div className="bg-card border border-border rounded-lg flex items-center justify-center h-64">
                <div className="text-center">
                  <Webhook size={32} className="mx-auto text-muted-foreground/30 mb-3" />
                  <p className="text-sm font-medium text-muted-foreground">Select an endpoint to view details</p>
                  <p className="text-xs text-muted-foreground/60 mt-1">Click any endpoint on the left to inspect configuration and delivery logs</p>
                </div>
              </div>
            )}
          </div>
        </div>
      )}

      {activeTab === 'deliveries' && (
        <div className="bg-card border border-border rounded-lg overflow-hidden">
          <div className="px-4 py-3 border-b border-border flex items-center justify-between">
            <p className="text-sm font-semibold">All Delivery Logs</p>
            <button onClick={() => toast.info('Logs refreshed')} className="flex items-center gap-1.5 text-xs text-muted-foreground hover:text-foreground transition-colors">
              <RefreshCw size={12} /> Refresh
            </button>
          </div>
          <div className="divide-y divide-border">
            {mockDeliveries.map(del => (
              <div key={del.id} className="overflow-hidden">
                <div
                  className="flex items-center gap-3 px-4 py-3 cursor-pointer hover:bg-muted/20 transition-colors"
                  onClick={() => setExpandedDelivery(expandedDelivery === del.id ? null : del.id)}
                >
                  {del.status === 'success' ? <CheckCircle size={13} className="text-green-400 flex-shrink-0" /> :
                   del.status === 'failed' ? <XCircle size={13} className="text-red-400 flex-shrink-0" /> :
                   <RotateCcw size={13} className="text-amber-400 flex-shrink-0 animate-spin" />}
                  <span className={`text-xs font-semibold w-16 ${deliveryStatusColor(del.status)}`}>{del.status.toUpperCase()}</span>
                  <span className="text-xs text-muted-foreground w-32 truncate">{mockWebhooks.find(w => w.id === del.webhookId)?.name}</span>
                  <span className="text-xs flex-1">{del.event}</span>
                  <span className="text-xs text-muted-foreground tabular-nums">{del.timestamp}</span>
                  <span className="text-xs text-muted-foreground">{del.duration}</span>
                  <span className="text-xs font-mono text-muted-foreground w-10 text-right">{del.statusCode ?? '—'}</span>
                  <span className="text-xs text-muted-foreground">Attempt {del.attempt}/{del.maxAttempts}</span>
                  {expandedDelivery === del.id ? <ChevronUp size={12} /> : <ChevronDown size={12} />}
                </div>
                {expandedDelivery === del.id && (
                  <div className="px-4 pb-4 space-y-2 bg-muted/10 border-t border-border/50">
                    <div>
                      <p className="text-[10px] text-muted-foreground uppercase tracking-wide mt-3 mb-1">Payload</p>
                      <pre className="text-[11px] font-mono bg-muted/40 rounded p-2 overflow-x-auto text-muted-foreground">{del.payload}</pre>
                    </div>
                    {del.response && (
                      <div>
                        <p className="text-[10px] text-muted-foreground uppercase tracking-wide mb-1">Response</p>
                        <pre className="text-[11px] font-mono bg-muted/40 rounded p-2 overflow-x-auto text-muted-foreground">{del.response}</pre>
                      </div>
                    )}
                  </div>
                )}
              </div>
            ))}
          </div>
        </div>
      )}

      {activeTab === 'docs' && (
        <div className="bg-card border border-border rounded-lg p-6 space-y-6">
          <div>
            <h3 className="font-semibold mb-2 flex items-center gap-2"><Shield size={16} className="text-primary" /> Signature Validation</h3>
            <p className="text-sm text-muted-foreground mb-3">Every webhook delivery includes an <code className="bg-muted px-1 rounded text-xs">X-Quoodle-Signature</code> header. Validate it to ensure the payload originated from Quoodle.</p>
            <div className="bg-muted/40 rounded-lg p-4">
              <p className="text-[10px] text-muted-foreground uppercase tracking-wide mb-2">HMAC-SHA256 Validation (Python)</p>
              <pre className="text-xs font-mono text-muted-foreground overflow-x-auto">{`import hmac, hashlib

def verify_signature(payload_body: bytes, secret: str, signature_header: str) -> bool:
    expected = hmac.new(
        secret.encode('utf-8'),
        payload_body,
        hashlib.sha256
    ).hexdigest()
    received = signature_header.replace('sha256=', '')
    return hmac.compare_digest(expected, received)`}</pre>
            </div>
          </div>

          <div>
            <h3 className="font-semibold mb-2 flex items-center gap-2"><RotateCcw size={16} className="text-primary" /> Retry Policies</h3>
            <div className="space-y-2">
              {[
                { name: 'Exponential Backoff', desc: 'Retries at 1s, 2s, 4s, 8s, 16s intervals. Best for transient failures.', badge: 'Recommended' },
                { name: 'Linear', desc: 'Retries at fixed 30s intervals. Predictable for rate-limited endpoints.', badge: null },
                { name: 'None', desc: 'No retries. Fire-and-forget. Use for non-critical notifications.', badge: null },
              ].map(p => (
                <div key={p.name} className="flex items-start gap-3 bg-muted/30 rounded-lg p-3">
                  <div className="flex-1">
                    <div className="flex items-center gap-2">
                      <p className="text-sm font-medium">{p.name}</p>
                      {p.badge && <span className="text-[10px] px-1.5 py-0.5 bg-green-500/10 text-green-400 rounded-full border border-green-500/20">{p.badge}</span>}
                    </div>
                    <p className="text-xs text-muted-foreground mt-0.5">{p.desc}</p>
                  </div>
                </div>
              ))}
            </div>
          </div>

          <div>
            <h3 className="font-semibold mb-2 flex items-center gap-2"><Zap size={16} className="text-primary" /> Event Payload Schema</h3>
            <div className="bg-muted/40 rounded-lg p-4">
              <pre className="text-xs font-mono text-muted-foreground overflow-x-auto">{`{
  "event": "command.completed",
  "timestamp": "2026-04-05T21:06:09Z",
  "delivery_id": "del-001",
  "data": {
    "command_id": "CMD-7742",
    "device_id": "WKSTN-055",
    "method": "system-info",
    "actor": "chloe.dubois@quoodle.io",
    "result": { ... },
    "trace_id": "TRACE-7742"
  }
}`}</pre>
            </div>
          </div>
        </div>
      )}

      {/* Create Modal */}
      {showCreateModal && (
        <CreateWebhookModal onClose={() => setShowCreateModal(false)} onSave={(wh) => {
          setWebhooks(prev => [...prev, wh]);
          setShowCreateModal(false);
          toast.success('Webhook endpoint created');
        }} />
      )}
    </div>
  );
}

function CreateWebhookModal({ onClose, onSave }: { onClose: () => void; onSave: (wh: WebhookEndpoint) => void }) {
  const [name, setName] = useState('');
  const [url, setUrl] = useState('');
  const [selectedEvents, setSelectedEvents] = useState<string[]>([]);
  const [retryPolicy, setRetryPolicy] = useState<RetryPolicy>('exponential');
  const [maxRetries, setMaxRetries] = useState(3);
  const [signingAlgo, setSigningAlgo] = useState<'hmac-sha256' | 'hmac-sha512'>('hmac-sha256');

  const toggleEvent = (ev: string) => {
    setSelectedEvents(prev => prev.includes(ev) ? prev.filter(e => e !== ev) : [...prev, ev]);
  };

  const handleSave = () => {
    if (!name || !url || selectedEvents.length === 0) {
      toast.error('Please fill in all required fields and select at least one event');
      return;
    }
    const secret = 'whsec_' + Array.from({ length: 40 }, () => Math.random().toString(36)[2]).join('');
    onSave({
      id: 'wh-' + Date.now(),
      name, url, status: 'active', events: selectedEvents,
      secret, signingAlgo, retryPolicy, maxRetries,
      lastDelivery: null, lastStatus: null,
      totalDeliveries: 0, failureCount: 0, createdAt: new Date().toISOString().split('T')[0],
    });
  };

  return (
    <>
      <div className="fixed inset-0 bg-black/50 z-40" onClick={onClose} />
      <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
        <div className="bg-zinc-950 border border-border rounded-xl w-full max-w-lg max-h-[90vh] overflow-y-auto">
          <div className="flex items-center justify-between px-5 py-4 border-b border-border">
            <h3 className="font-semibold">Add Webhook Endpoint</h3>
            <button onClick={onClose} className="p-1.5 text-muted-foreground hover:text-foreground transition-colors"><X size={15} /></button>
          </div>
          <div className="p-5 space-y-4">
            <div>
              <label className="text-xs text-muted-foreground mb-1 block">Endpoint Name *</label>
              <input value={name} onChange={e => setName(e.target.value)} placeholder="e.g. Splunk SIEM" className="w-full px-3 py-2 text-sm bg-muted/60 border border-border rounded-md focus:outline-none focus:ring-1 focus:ring-primary/50" />
            </div>
            <div>
              <label className="text-xs text-muted-foreground mb-1 block">Endpoint URL *</label>
              <input value={url} onChange={e => setUrl(e.target.value)} placeholder="https://your-siem.example.com/webhook" className="w-full px-3 py-2 text-sm bg-muted/60 border border-border rounded-md focus:outline-none focus:ring-1 focus:ring-primary/50" />
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className="text-xs text-muted-foreground mb-1 block">Signing Algorithm</label>
                <select value={signingAlgo} onChange={e => setSigningAlgo(e.target.value as 'hmac-sha256' | 'hmac-sha512')} className="w-full px-3 py-2 text-sm bg-muted/60 border border-border rounded-md focus:outline-none focus:ring-1 focus:ring-primary/50">
                  <option value="hmac-sha256">HMAC-SHA256</option>
                  <option value="hmac-sha512">HMAC-SHA512</option>
                </select>
              </div>
              <div>
                <label className="text-xs text-muted-foreground mb-1 block">Retry Policy</label>
                <select value={retryPolicy} onChange={e => setRetryPolicy(e.target.value as RetryPolicy)} className="w-full px-3 py-2 text-sm bg-muted/60 border border-border rounded-md focus:outline-none focus:ring-1 focus:ring-primary/50">
                  <option value="exponential">Exponential Backoff</option>
                  <option value="linear">Linear</option>
                  <option value="none">None</option>
                </select>
              </div>
            </div>
            {retryPolicy !== 'none' && (
              <div>
                <label className="text-xs text-muted-foreground mb-1 block">Max Retries</label>
                <input type="number" min={1} max={10} value={maxRetries} onChange={e => setMaxRetries(Number(e.target.value))} className="w-full px-3 py-2 text-sm bg-muted/60 border border-border rounded-md focus:outline-none focus:ring-1 focus:ring-primary/50" />
              </div>
            )}
            <div>
              <label className="text-xs text-muted-foreground mb-2 block">Events to Subscribe *</label>
              <div className="flex flex-wrap gap-1.5 max-h-40 overflow-y-auto">
                {EVENT_TYPES.map(ev => (
                  <button
                    key={ev}
                    onClick={() => toggleEvent(ev)}
                    className={`text-[11px] px-2 py-0.5 rounded-full border transition-colors ${
                      selectedEvents.includes(ev)
                        ? 'bg-primary/20 text-primary border-primary/40' :'bg-muted/40 text-muted-foreground border-border hover:border-primary/30'
                    }`}
                  >
                    {ev}
                  </button>
                ))}
              </div>
            </div>
          </div>
          <div className="flex items-center justify-end gap-2 px-5 py-4 border-t border-border">
            <button onClick={onClose} className="px-4 py-2 text-sm text-muted-foreground hover:text-foreground transition-colors">Cancel</button>
            <button onClick={handleSave} className="flex items-center gap-1.5 px-4 py-2 text-sm bg-primary text-primary-foreground rounded-md hover:bg-primary/90 transition-colors">
              <Save size={13} /> Create Endpoint
            </button>
          </div>
        </div>
      </div>
    </>
  );
}
