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
