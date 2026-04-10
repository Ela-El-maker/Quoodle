export function telemetryNumber(value: unknown): number | null {
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  if (typeof value === 'string') {
    const parsed = Number(value.replace('%', '').trim());
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

export function telemetryPercent(value: unknown, fallback = 'Unknown'): string {
  const parsed = telemetryNumber(value);
  if (parsed == null) return fallback;
  return `${Math.max(0, Math.min(100, parsed)).toFixed(0)}%`;
}

export function telemetryRisk(value: unknown): number | null {
  const parsed = telemetryNumber(value);
  if (parsed == null) return null;
  if (parsed <= 1) {
    return Math.max(0, Math.min(100, parsed * 100));
  }
  return Math.max(0, Math.min(100, parsed));
}

export function telemetryText(value: unknown, fallback = 'Unknown'): string {
  if (typeof value === 'string') {
    const trimmed = value.trim();
    return trimmed ? trimmed : fallback;
  }
  if (typeof value === 'number' && Number.isFinite(value)) {
    return String(value);
  }
  return fallback;
}

export function telemetryBooleanStatus(
  value: unknown,
  trueText: string,
  falseText: string,
  fallback = 'Unknown',
): string {
  if (typeof value === 'boolean') {
    return value ? trueText : falseText;
  }
  return fallback;
}

export function telemetryMaskedFields(value: unknown, fallback = 'No data available'): string {
  if (!Array.isArray(value)) return fallback;
  if (value.length === 0) return 'None';
  const normalized = value.map((item) => telemetryText(item, '')).filter(Boolean);
  return normalized.length > 0 ? normalized.join(', ') : 'None';
}

export type KernelTelemetryCategory = 'exec' | 'integrity' | 'attestation' | 'update' | 'runtime';

export type ParsedKernelTelemetryEvent = {
  eventId: number;
  eventType: number;
  eventTimestampUnix: number;
  category: KernelTelemetryCategory;
  subtype: string;
  severity: string;
  decision: string;
  reasonCode: string;
  durationMs: number;
  queueDepth: number;
  dropCount: number;
  opcode: string;
  status: string;
  errorCode: number;
  policyRef: string;
  maskedFields: string[];
  payload: Record<string, unknown>;
  payloadJson: string;
};

function normalizeKernelCategory(value: unknown): KernelTelemetryCategory {
  const category = telemetryText(value, 'exec').toLowerCase();
  if (category === 'integrity' || category === 'attestation' || category === 'update' || category === 'runtime') {
    return category;
  }
  return 'exec';
}

export function parseKernelTelemetryEvent(value: unknown): ParsedKernelTelemetryEvent | null {
  if (!value || typeof value !== 'object') return null;
  const kernelEvent = value as Record<string, unknown>;
  const payloadJson = telemetryText(kernelEvent.payload_json, '{}');

  let payload: Record<string, unknown> = {};
  if (typeof kernelEvent.payload === 'object' && kernelEvent.payload !== null) {
    payload = kernelEvent.payload as Record<string, unknown>;
  } else {
    try {
      const parsed = JSON.parse(payloadJson) as unknown;
      if (parsed && typeof parsed === 'object') {
        payload = parsed as Record<string, unknown>;
      }
    } catch {
      payload = {};
    }
  }

  const status = telemetryText(payload.status, 'unknown').toLowerCase();
  const errorCode = telemetryNumber(payload.error_code) ?? 0;

  const normalizedPayload: Record<string, unknown> = { ...payload };
  normalizedPayload.category = normalizeKernelCategory(payload.category);
  normalizedPayload.subtype = telemetryText(payload.subtype, 'opcode').toLowerCase();
  normalizedPayload.severity = telemetryText(
    payload.severity,
    status !== 'ok' || errorCode > 0 ? 'high' : 'info',
  ).toLowerCase();
  normalizedPayload.decision = telemetryText(
    payload.decision,
    status === 'ok' || status === 'completed' ? 'allow' : 'deny',
  ).toLowerCase();
  normalizedPayload.reason_code = telemetryText(payload.reason_code, status || 'unknown').toLowerCase();
  normalizedPayload.duration_ms = telemetryNumber(payload.duration_ms) ?? 0;
  normalizedPayload.queue_depth = telemetryNumber(payload.queue_depth) ?? 0;
  normalizedPayload.drop_count = telemetryNumber(payload.drop_count ?? payload.dropped_events) ?? 0;
  normalizedPayload.policy_ref = telemetryText(payload.policy_ref, '');
  normalizedPayload.masked_fields = Array.isArray(payload.masked_fields)
    ? payload.masked_fields.map((item) => telemetryText(item, '')).filter(Boolean)
    : [];

  return {
    eventId: telemetryNumber(kernelEvent.event_id) ?? 0,
    eventType: telemetryNumber(kernelEvent.event_type) ?? 0,
    eventTimestampUnix: telemetryNumber(kernelEvent.event_timestamp_unix) ?? 0,
    category: normalizedPayload.category as KernelTelemetryCategory,
    subtype: String(normalizedPayload.subtype),
    severity: String(normalizedPayload.severity),
    decision: String(normalizedPayload.decision),
    reasonCode: String(normalizedPayload.reason_code),
    durationMs: Number(normalizedPayload.duration_ms),
    queueDepth: Number(normalizedPayload.queue_depth),
    dropCount: Number(normalizedPayload.drop_count),
    opcode: telemetryText(payload.opcode, 'Unknown'),
    status,
    errorCode,
    policyRef: String(normalizedPayload.policy_ref),
    maskedFields: normalizedPayload.masked_fields as string[],
    payload: normalizedPayload,
    payloadJson,
  };
}
