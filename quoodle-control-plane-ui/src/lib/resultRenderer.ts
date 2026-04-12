import { resolveCommandMethod } from '@/lib/commandMethodResolver';
import {
  resultPreview,
  toRawResultJson,
  type NormalizedCommandResult,
} from '@/lib/commandResults';

export type ResultWidgetType = 'stats' | 'kv' | 'table' | 'log' | 'diagnostics';

export interface ResultShellMeta {
  commandId: string;
  method: string;
  state: string;
  status: string | null;
  deviceName: string;
  actorEmail: string;
  queuedAt: string | null;
  completedAt: string | null;
  transport: string | null;
  requestId: string | null;
  kernelExecId: string | null;
  kernelTimestamp: string | null;
}

export interface ResultDiagnosticsItem {
  severity: 'info' | 'warning' | 'error';
  field?: string;
  reason: string;
  message: string;
}

export interface ResultHeroStat {
  label: string;
  value: string;
  tone?: 'default' | 'success' | 'warning' | 'danger' | 'info';
}

export interface ResultKeyValueItem {
  key: string;
  label: string;
  value: string;
  isEmpty?: boolean;
}

export interface ResultTableDefinition {
  columns: string[];
  rows: Array<Record<string, string>>;
}

export interface ResultSectionDefinition {
  id: string;
  title: string;
  widget: ResultWidgetType;
  description?: string;
  stats?: ResultHeroStat[];
  keyValues?: ResultKeyValueItem[];
  table?: ResultTableDefinition;
  logText?: string;
  diagnostics?: ResultDiagnosticsItem[];
  collapsedByDefault?: boolean;
  emptySummary?: string | null;
}

export interface ResultViewModel {
  title: string;
  subtitle: string;
  commandMethod: string;
  shell: ResultShellMeta;
  hero: ResultHeroStat[];
  sections: ResultSectionDefinition[];
  diagnostics: ResultDiagnosticsItem[];
  rawJson: string;
  fallbackUsed: boolean;
}

export interface ResultRenderDefinition {
  method: string;
  title: string;
  build: (row: NormalizedCommandResult) => ResultViewModel;
}

const KNOWN_COLLECT_SECTIONS = [
  'identity',
  'os',
  'hardware',
  'runtime',
  'storage',
  'network',
  'security',
] as const;

const methodTitleMap: Record<string, string> = {
  collect_system_info: 'System Snapshot',
  ping: 'Ping Result',
  list_processes: 'Process Inventory',
};

const isObject = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value);

const isPrimitive = (value: unknown): value is string | number | boolean | null =>
  value == null || typeof value === 'string' || typeof value === 'number' || typeof value === 'boolean';

function toLabel(raw: string): string {
  return raw
    .replace(/_/g, ' ')
    .replace(/([a-z])([A-Z])/g, '$1 $2')
    .replace(/\s+/g, ' ')
    .trim()
    .replace(/^./, (m) => m.toUpperCase());
}

function toDisplayValue(value: unknown): string {
  if (value == null) return 'Not collected';
  if (typeof value === 'boolean') return value ? 'Yes' : 'No';
  if (typeof value === 'number') return Number.isFinite(value) ? String(value) : 'Not collected';
  if (typeof value === 'string') return value.trim() === '' ? 'Not collected' : value;
  if (Array.isArray(value)) return `${value.length} item(s)`;
  if (isObject(value)) return `${Object.keys(value).length} field(s)`;
  return String(value);
}

function objectEntries(
  source: Record<string, unknown>,
  options?: { hideNull?: boolean },
): { keyValues: ResultKeyValueItem[]; hiddenCount: number; total: number } {
  const hideNull = options?.hideNull ?? false;
  let hiddenCount = 0;
  const keyValues: ResultKeyValueItem[] = [];
  const keys = Object.keys(source);
  for (const key of keys) {
    const value = source[key];
    const empty = value == null || value === '';
    if (hideNull && empty) {
      hiddenCount += 1;
      continue;
    }
    keyValues.push({
      key,
      label: toLabel(key),
      value: toDisplayValue(value),
      isEmpty: empty,
    });
  }
  return { keyValues, hiddenCount, total: keys.length };
}

function extractStructuredData(row: NormalizedCommandResult): unknown {
  return row.result?.data ?? null;
}

function buildShell(row: NormalizedCommandResult, method: string): ResultShellMeta {
  const meta = isObject(row.result?.meta) ? row.result?.meta : null;
  return {
    commandId: row.commandId,
    method,
    state: row.state,
    status: typeof row.resultStatus === 'string' ? row.resultStatus : null,
    deviceName: row.deviceName,
    actorEmail: row.actorEmail,
    queuedAt: row.queuedAt,
    completedAt: row.completedAt,
    transport: typeof meta?.transport === 'string' ? meta.transport : null,
    requestId: typeof meta?.request_id === 'string' ? meta.request_id : null,
    kernelExecId: typeof meta?.kernel_exec_id === 'string' ? meta.kernel_exec_id : null,
    kernelTimestamp: typeof meta?.kernel_timestamp === 'string' ? meta.kernel_timestamp : null,
  };
}

function buildBaseModel(row: NormalizedCommandResult, method: string, title: string): ResultViewModel {
  return {
    title,
    subtitle: resultPreview(row),
    commandMethod: method,
    shell: buildShell(row, method),
    hero: [],
    sections: [],
    diagnostics: [],
    rawJson: toRawResultJson(row),
    fallbackUsed: false,
  };
}

function buildDiagnosticsFromRow(row: NormalizedCommandResult): ResultDiagnosticsItem[] {
  const diagnostics: ResultDiagnosticsItem[] = [];
  if (row.state === 'failed' || row.state === 'rejected' || row.state === 'expired') {
    diagnostics.push({
      severity: 'error',
      reason: row.reason || row.errorMessage || 'command_failed',
      message: row.errorMessage || row.reason || `Command ended in ${row.state}`,
    });
  }
  if (row.errorCode != null) {
    diagnostics.push({
      severity: 'warning',
      reason: 'error_code',
      message: `Error code ${row.errorCode}`,
    });
  }
  return diagnostics;
}

function buildCollectSystemInfo(row: NormalizedCommandResult): ResultViewModel {
  const model = buildBaseModel(row, 'collect_system_info', methodTitleMap.collect_system_info);
  const data = extractStructuredData(row);
  const payload = isObject(data) ? data : {};

  const identity = isObject(payload.identity) ? payload.identity : {};
  const os = isObject(payload.os) ? payload.os : {};
  const hardware = isObject(payload.hardware) ? payload.hardware : {};
  const runtime = isObject(payload.runtime) ? payload.runtime : {};

  const includedFields = Array.isArray(payload.included_fields)
    ? payload.included_fields.filter((v): v is string => typeof v === 'string')
    : [];
  const maskedFields = Array.isArray(payload.masked_fields)
    ? payload.masked_fields.filter((v): v is string => typeof v === 'string')
    : [];

  model.hero = [
    { label: 'OS', value: toDisplayValue(os.product_name ?? 'Unknown'), tone: 'info' },
    { label: 'Version', value: toDisplayValue(os.version ?? os.build ?? 'Unknown') },
    { label: 'CPU', value: toDisplayValue(hardware.cpu_model ?? 'Unknown') },
    { label: 'RAM', value: toDisplayValue(hardware.ram_total_mb ?? 'Unknown') },
    { label: 'Uptime', value: toDisplayValue(runtime.uptime_sec ?? 'Unknown') },
    { label: 'Kernel Mode', value: toDisplayValue(payload.kernel_mode ?? false), tone: 'success' },
  ];

  const identityBlock = objectEntries(identity, { hideNull: true });
  const osBlock = objectEntries(os, { hideNull: true });
  const hardwareBlock = objectEntries(hardware, { hideNull: true });
  const runtimeBlock = objectEntries(runtime, { hideNull: true });

  const notIncluded = KNOWN_COLLECT_SECTIONS.filter((section) => !includedFields.includes(section));
  const failures = Array.isArray(payload.collection_failures) ? payload.collection_failures : [];
  const sectionFailures: ResultDiagnosticsItem[] = failures
    .filter((item) => isObject(item))
    .map((item) => ({
      severity: 'warning',
      field: typeof item.field === 'string' ? item.field : undefined,
      reason: typeof item.reason === 'string' ? item.reason : 'collection_failure',
      message:
        typeof item.field === 'string'
          ? `${item.field}: ${typeof item.reason === 'string' ? item.reason : 'collection_failure'}`
          : typeof item.reason === 'string'
            ? item.reason
            : 'Collection failure',
    }));

  for (const section of notIncluded) {
    sectionFailures.push({
      severity: 'info',
      field: section,
      reason: 'not_requested',
      message: `${toLabel(section)} was not requested in this snapshot`,
    });
  }
  if (maskedFields.length > 0) {
    sectionFailures.push({
      severity: 'warning',
      reason: 'masked_fields',
      message: `${maskedFields.length} field(s) were masked by policy`,
    });
  }

  model.diagnostics = [...buildDiagnosticsFromRow(row), ...sectionFailures];

  model.sections = [
    {
      id: 'overview',
      title: 'Overview',
      widget: 'stats',
      stats: model.hero,
      description: `Included sections: ${includedFields.length > 0 ? includedFields.join(', ') : 'none'}`,
    },
    {
      id: 'identity',
      title: 'Identity',
      widget: 'kv',
      keyValues: identityBlock.keyValues,
      emptySummary: identityBlock.keyValues.length === 0 ? 'No identity fields collected' : null,
    },
    {
      id: 'os',
      title: 'OS',
      widget: 'kv',
      keyValues: osBlock.keyValues,
      emptySummary: osBlock.keyValues.length === 0 ? 'No OS fields collected' : null,
    },
    {
      id: 'hardware',
      title: 'Hardware',
      widget: 'kv',
      keyValues: hardwareBlock.keyValues,
      emptySummary:
        hardwareBlock.hiddenCount > 0
          ? `${hardwareBlock.hiddenCount} field(s) not collected in this snapshot`
          : null,
    },
    {
      id: 'runtime',
      title: 'Runtime',
      widget: 'kv',
      keyValues: runtimeBlock.keyValues,
      emptySummary: runtimeBlock.keyValues.length === 0 ? 'No runtime fields collected' : null,
    },
    {
      id: 'diagnostics',
      title: 'Diagnostics',
      widget: 'diagnostics',
      diagnostics: model.diagnostics,
      emptySummary: model.diagnostics.length === 0 ? 'No diagnostics reported' : null,
    },
  ];

  return model;
}

function findNumericMetric(source: Record<string, unknown>, candidates: string[]): string | null {
  for (const key of candidates) {
    const value = source[key];
    if (typeof value === 'number' && Number.isFinite(value)) return String(value);
    if (typeof value === 'string' && value.trim() !== '' && !Number.isNaN(Number(value))) return value;
  }
  return null;
}

function buildPing(row: NormalizedCommandResult): ResultViewModel {
  const model = buildBaseModel(row, 'ping', methodTitleMap.ping);
  const data = extractStructuredData(row);
  const payload = isObject(data) ? data : {};
  const latency = findNumericMetric(payload, [
    'latency_ms',
    'round_trip_ms',
    'rtt_ms',
    'duration_ms',
  ]);

  model.hero = [
    { label: 'State', value: toLabel(row.state), tone: row.state === 'completed' ? 'success' : 'warning' },
    { label: 'Status', value: toDisplayValue(row.resultStatus ?? payload.status ?? 'Unknown') },
    { label: 'Latency', value: latency ? `${latency} ms` : 'Unknown', tone: 'info' },
  ];

  const details = objectEntries(payload, { hideNull: true });
  model.diagnostics = buildDiagnosticsFromRow(row);
  model.sections = [
    {
      id: 'overview',
      title: 'Overview',
      widget: 'stats',
      stats: model.hero,
    },
    {
      id: 'details',
      title: 'Details',
      widget: 'kv',
      keyValues: details.keyValues,
      emptySummary: details.keyValues.length === 0 ? 'No ping details returned' : null,
    },
    {
      id: 'diagnostics',
      title: 'Diagnostics',
      widget: 'diagnostics',
      diagnostics: model.diagnostics,
      emptySummary: model.diagnostics.length === 0 ? 'No diagnostics reported' : null,
    },
  ];
  return model;
}

function normalizeProcessArray(data: unknown): Array<Record<string, unknown>> {
  if (Array.isArray(data)) {
    return data.filter((item): item is Record<string, unknown> => isObject(item));
  }
  if (isObject(data) && Array.isArray(data.processes)) {
    return data.processes.filter((item): item is Record<string, unknown> => isObject(item));
  }
  return [];
}

function buildProcessTable(rows: Array<Record<string, unknown>>): ResultTableDefinition {
  const preferred = ['pid', 'name', 'cpu', 'memory', 'memory_mb', 'user', 'path', 'start_time'];
  const discovered = new Set<string>();
  for (const row of rows) {
    for (const key of Object.keys(row)) {
      discovered.add(key);
    }
  }
  const ordered = preferred.filter((k) => discovered.has(k));
  for (const key of discovered) {
    if (!ordered.includes(key)) ordered.push(key);
  }
  const columns = ordered.slice(0, 8);
  const mappedRows = rows.slice(0, 250).map((row, index) => {
    const mapped: Record<string, string> = { __id: String(index + 1) };
    for (const column of columns) {
      mapped[column] = toDisplayValue(row[column]);
    }
    return mapped;
  });
  return { columns, rows: mappedRows };
}

function buildListProcesses(row: NormalizedCommandResult): ResultViewModel {
  const model = buildBaseModel(row, 'list_processes', methodTitleMap.list_processes);
  const data = extractStructuredData(row);
  const processes = normalizeProcessArray(data);
  const table = buildProcessTable(processes);

  model.hero = [
    { label: 'Status', value: toDisplayValue(row.resultStatus ?? row.state), tone: 'info' },
    { label: 'Processes', value: String(processes.length), tone: 'success' },
  ];
  model.diagnostics = buildDiagnosticsFromRow(row);
  model.sections = [
    {
      id: 'overview',
      title: 'Overview',
      widget: 'stats',
      stats: model.hero,
      description: processes.length > 250 ? 'Showing first 250 rows' : undefined,
    },
    {
      id: 'processes',
      title: 'Processes',
      widget: 'table',
      table,
      emptySummary: processes.length === 0 ? 'No process rows were returned' : null,
    },
    {
      id: 'diagnostics',
      title: 'Diagnostics',
      widget: 'diagnostics',
      diagnostics: model.diagnostics,
      emptySummary: model.diagnostics.length === 0 ? 'No diagnostics reported' : null,
    },
  ];
  return model;
}

function buildGeneric(row: NormalizedCommandResult, method: string): ResultViewModel {
  const model = buildBaseModel(row, method, methodTitleMap[method] ?? toLabel(method));
  const data = extractStructuredData(row);
  model.hero = [
    { label: 'State', value: toLabel(row.state), tone: row.state === 'completed' ? 'success' : 'warning' },
    { label: 'Status', value: toDisplayValue(row.resultStatus ?? row.result?.status ?? 'Unknown') },
  ];

  if (isObject(data)) {
    const sections: ResultSectionDefinition[] = [];
    for (const [key, value] of Object.entries(data)) {
      if (isObject(value)) {
        const block = objectEntries(value, { hideNull: true });
        sections.push({
          id: key,
          title: toLabel(key),
          widget: 'kv',
          keyValues: block.keyValues,
          collapsedByDefault: block.total > 0 && block.hiddenCount / block.total >= 0.6,
          emptySummary:
            block.keyValues.length === 0
              ? 'No populated fields in this section'
              : block.hiddenCount > 0
                ? `${block.hiddenCount} field(s) hidden because they were not collected`
                : null,
        });
        continue;
      }
      if (Array.isArray(value) && value.every((item) => isObject(item))) {
        sections.push({
          id: key,
          title: toLabel(key),
          widget: 'table',
          table: buildProcessTable(value as Array<Record<string, unknown>>),
          collapsedByDefault: value.length === 0,
          emptySummary: value.length === 0 ? 'No rows returned' : null,
        });
        continue;
      }
      if (isPrimitive(value)) {
        sections.push({
          id: key,
          title: toLabel(key),
          widget: 'kv',
          keyValues: [{ key, label: toLabel(key), value: toDisplayValue(value), isEmpty: value == null }],
          collapsedByDefault: value == null,
        });
      }
    }
    model.sections = sections.length > 0 ? sections : [{
      id: 'summary',
      title: 'Summary',
      widget: 'log',
      logText: model.subtitle,
    }];
  } else if (typeof row.result?.output_text === 'string' && row.result.output_text.trim() !== '') {
    model.sections = [{
      id: 'output',
      title: 'Output',
      widget: 'log',
      logText: row.result.output_text,
    }];
  } else {
    model.sections = [{
      id: 'summary',
      title: 'Summary',
      widget: 'log',
      logText: model.subtitle,
    }];
  }

  model.diagnostics = buildDiagnosticsFromRow(row);
  model.sections.push({
    id: 'diagnostics',
    title: 'Diagnostics',
    widget: 'diagnostics',
    diagnostics: model.diagnostics,
    collapsedByDefault: model.diagnostics.length === 0,
    emptySummary: model.diagnostics.length === 0 ? 'No diagnostics reported' : null,
  });
  return model;
}

const renderDefinitions: Record<string, ResultRenderDefinition> = {
  collect_system_info: {
    method: 'collect_system_info',
    title: methodTitleMap.collect_system_info,
    build: buildCollectSystemInfo,
  },
  ping: {
    method: 'ping',
    title: methodTitleMap.ping,
    build: buildPing,
  },
  list_processes: {
    method: 'list_processes',
    title: methodTitleMap.list_processes,
    build: buildListProcesses,
  },
};

function safeFallback(row: NormalizedCommandResult, method: string, error: unknown): ResultViewModel {
  const model = buildGeneric(row, method);
  model.fallbackUsed = true;
  const message = error instanceof Error ? error.message : 'Renderer failed';
  model.diagnostics.unshift({
    severity: 'warning',
    reason: 'renderer_fallback',
    message,
  });
  return model;
}

export function renderResult(method: string, row: NormalizedCommandResult): ResultViewModel {
  const canonicalMethod = resolveCommandMethod(method || row.method);
  const renderer = renderDefinitions[canonicalMethod];
  try {
    if (renderer) {
      return renderer.build(row);
    }
    return buildGeneric(row, canonicalMethod);
  } catch (error) {
    return safeFallback(row, canonicalMethod, error);
  }
}

export function isResultsRendererV2Enabled(): boolean {
  return process.env.NEXT_PUBLIC_RESULTS_RENDERER_V2 !== '0';
}

