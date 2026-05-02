import { resolveCommandMethod } from '@/lib/commandMethodResolver';
import {
  resultPreview,
  toRawResultJson,
  type NormalizedCommandResult,
} from '@/lib/commandResults';

export type ResultWidgetType = 'stats' | 'kv' | 'table' | 'log' | 'diagnostics' | 'artifact' | 'filesystem';

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

export interface ResultArtifactDefinition {
  url: string | null;
  checksum: string | null;
  contentType?: string | null;
}

export interface ResultFilesystemEntry {
  name: string;
  path: string;
  type: 'directory' | 'file' | 'other';
  parentPath: string | null;
  size: number | null;
  extension: string | null;
  modifiedAt: string | null;
  createdAt: string | null;
  isHidden: boolean;
  isSystem: boolean;
  isSymlink: boolean;
  targetPath: string | null;
  downloadable: boolean;
  downloadMethod: string | null;
}

export interface ResultFilesystemDefinition {
  rootPath: string;
  entries: ResultFilesystemEntry[];
  recursive: boolean;
  maxDepth: number | null;
  partial: boolean;
  nextCursor: string | null;
  canDownload: boolean;
  downloadMethod: string | null;
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
  artifact?: ResultArtifactDefinition;
  filesystem?: ResultFilesystemDefinition;
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
  list_services: 'Service Inventory',
  list_connections: 'Connection Inventory',
  list_mounts: 'Mount Inventory',
  network_info: 'Network Inventory',
  get_active_window: 'Active Window',
  list_files: 'Filesystem Browser',
  download_file: 'File Download',
  upload_file: 'File Upload',
  create_directory: 'Create Directory',
  create_file: 'Create File',
  delete_file: 'Delete File',
  delete_directory: 'Delete Directory',
  screenshot: 'Screenshot Capture',
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

function normalizeServicesArray(data: unknown): Array<Record<string, unknown>> {
  if (Array.isArray(data)) {
    return data.filter((item): item is Record<string, unknown> => isObject(item));
  }
  if (isObject(data) && Array.isArray(data.services)) {
    return data.services.filter((item): item is Record<string, unknown> => isObject(item));
  }
  return [];
}

function normalizeConnectionsArray(data: unknown): Array<Record<string, unknown>> {
  if (Array.isArray(data)) {
    return data.filter((item): item is Record<string, unknown> => isObject(item));
  }
  if (isObject(data) && Array.isArray(data.connections)) {
    return data.connections.filter((item): item is Record<string, unknown> => isObject(item));
  }
  return [];
}

function normalizeMountsArray(data: unknown): Array<Record<string, unknown>> {
  if (Array.isArray(data)) {
    return data.filter((item): item is Record<string, unknown> => isObject(item));
  }
  if (isObject(data) && Array.isArray(data.mounts)) {
    return data.mounts.filter((item): item is Record<string, unknown> => isObject(item));
  }
  return [];
}

function normalizeNetworkAdaptersArray(data: unknown): Array<Record<string, unknown>> {
  if (Array.isArray(data)) {
    return data.filter((item): item is Record<string, unknown> => isObject(item));
  }
  if (isObject(data) && Array.isArray(data.adapters)) {
    return data.adapters.filter((item): item is Record<string, unknown> => isObject(item));
  }
  return [];
}

function normalizeTopTalkersArray(data: unknown): Array<Record<string, unknown>> {
  if (!isObject(data) || !Array.isArray(data.top_talkers_by_connection_count)) return [];
  return data.top_talkers_by_connection_count.filter((item): item is Record<string, unknown> => isObject(item));
}

function normalizeRoutesArray(data: unknown): Array<Record<string, unknown>> {
  if (!isObject(data) || !Array.isArray(data.default_routes)) return [];
  return data.default_routes.filter((item): item is Record<string, unknown> => isObject(item));
}

function normalizeWifiPayload(data: unknown): Record<string, unknown> {
  if (!isObject(data) || !isObject(data.wifi)) return {};
  return data.wifi;
}

function normalizeVpnSummaryPayload(data: unknown): Record<string, unknown> {
  if (!isObject(data) || !isObject(data.vpn_summary)) return {};
  return data.vpn_summary;
}

function normalizeStringArrayField(data: unknown, key: string): string[] {
  if (!isObject(data) || !Array.isArray(data[key])) return [];
  return (data[key] as unknown[])
    .filter((item): item is string => typeof item === 'string')
    .map((item) => item.trim())
    .filter((item) => item.length > 0);
}

type SavedWifiProfile = {
  ssid: string;
  password: string;
};

function normalizeSavedWifiProfilesField(data: unknown, key: string): SavedWifiProfile[] {
  if (!isObject(data) || !Array.isArray(data[key])) return [];
  const rows = data[key] as unknown[];
  const profiles: SavedWifiProfile[] = [];

  for (const row of rows) {
    if (typeof row === 'string') {
      const ssid = row.trim();
      if (ssid.length === 0) continue;
      profiles.push({ ssid, password: '(no saved password or open network)' });
      continue;
    }

    if (!isObject(row)) continue;
    const ssid = typeof row.ssid === 'string' ? row.ssid.trim() : '';
    if (ssid.length === 0) continue;
    const passwordRaw = typeof row.password === 'string' ? row.password.trim() : '';
    profiles.push({
      ssid,
      password: passwordRaw.length > 0 ? passwordRaw : '(no saved password or open network)',
    });
  }

  return profiles;
}

function formatSavedWifiProfilesLog(profiles: SavedWifiProfile[]): string {
  if (profiles.length === 0) {
    return 'Saved Wi-Fi networks and passwords:\n\n(no saved Wi-Fi profiles found)';
  }
  const lines: string[] = ['Saved Wi-Fi networks and passwords:', ''];
  for (const profile of profiles) {
    lines.push(`SSID: ${profile.ssid}`);
    lines.push(`Password: ${profile.password}`);
    lines.push('----------------------------------------');
  }
  return lines.join('\n');
}

function readSnapshotCounts(data: unknown): { count: number; totalSeen: number | null } {
  if (!isObject(data)) return { count: 0, totalSeen: null };
  const countRaw = data.count;
  const totalRaw = data.total_seen;
  const count = typeof countRaw === 'number' && Number.isFinite(countRaw) ? Math.max(0, Math.trunc(countRaw)) : 0;
  const totalSeen =
    typeof totalRaw === 'number' && Number.isFinite(totalRaw)
      ? Math.max(0, Math.trunc(totalRaw))
      : null;
  return { count, totalSeen };
}

function normalizeActiveWindowPayload(data: unknown): Record<string, unknown> {
  return isObject(data) ? data : {};
}

function normalizeFileEntriesArray(data: unknown): Array<Record<string, unknown>> {
  if (Array.isArray(data)) {
    return data.filter((item): item is Record<string, unknown> => isObject(item));
  }
  if (isObject(data) && Array.isArray(data.entries)) {
    return data.entries.filter((item): item is Record<string, unknown> => isObject(item));
  }
  return [];
}

function normalizePathSeparator(path: string): string {
  return path.replace(/[\\/]+/g, '/');
}

function toCanonicalPath(path: string): string {
  const trimmed = path.trim();
  if (trimmed === '') return '';
  const canonical = normalizePathSeparator(trimmed).replace(/\/+$/, '');
  return canonical === '' ? '/' : canonical;
}

function parentPathOf(path: string): string | null {
  const canonical = toCanonicalPath(path);
  if (!canonical || canonical === '/') return null;
  const parts = canonical.split('/').filter(Boolean);
  if (parts.length <= 1) return null;
  return parts.slice(0, -1).join('/');
}

function parseBoolean(value: unknown): boolean {
  if (value === true) return true;
  if (value === false || value == null) return false;
  if (typeof value === 'number') return value === 1;
  if (typeof value === 'string') {
    const normalized = value.trim().toLowerCase();
    return normalized === 'true' || normalized === '1' || normalized === 'yes';
  }
  return false;
}

function parseOptionalNumber(value: unknown): number | null {
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  if (typeof value === 'string' && value.trim() !== '') {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) return parsed;
  }
  return null;
}

function parseOptionalString(value: unknown): string | null {
  if (typeof value !== 'string') return null;
  const trimmed = value.trim();
  return trimmed === '' ? null : trimmed;
}

function normalizeFilesystemEntries(rows: Array<Record<string, unknown>>): ResultFilesystemEntry[] {
  const mapped = rows.map((row) => {
    const rawPath = parseOptionalString(row.path) ?? '';
    const canonicalPath = toCanonicalPath(rawPath);
    const fallbackName =
      canonicalPath === ''
        ? 'unknown'
        : canonicalPath.split('/').filter(Boolean).slice(-1)[0] ?? canonicalPath;
    const rawName = parseOptionalString(row.name) ?? fallbackName;
    const rawType = (parseOptionalString(row.type) ?? parseOptionalString(row.entry_type) ?? 'other').toLowerCase();
    const isDirectoryHint =
      parseBoolean(row.is_directory) ||
      parseBoolean(row.is_dir) ||
      parseBoolean(row.directory) ||
      parseBoolean(row.is_folder);
    const isFileHint =
      parseBoolean(row.is_file) ||
      parseBoolean(row.file);
    const attrHints = Array.isArray(row.attributes)
      ? row.attributes.map((value) => String(value).toLowerCase())
      : [];
    const hasDirectoryAttribute = attrHints.some((value) => value.includes('directory'));
    const hasFileAttribute = attrHints.some((value) => value.includes('archive') || value.includes('file'));
    const type: ResultFilesystemEntry['type'] =
      rawType === 'directory' || rawType === 'dir' || rawType === 'folder' || isDirectoryHint || hasDirectoryAttribute
        ? 'directory'
        : rawType === 'file' || rawType === 'regular' || rawType === 'regular_file' || isFileHint || hasFileAttribute
          ? 'file'
          : 'other';
    const extension = parseOptionalString(row.extension);
    const normalizedExtension = extension ? extension.replace(/^\./, '').toLowerCase() : null;

    return {
      name: rawName,
      path: canonicalPath,
      type,
      parentPath: parentPathOf(canonicalPath),
      size: parseOptionalNumber(row.size),
      extension: normalizedExtension,
      modifiedAt: parseOptionalString(row.modified_at),
      createdAt: parseOptionalString(row.created_at),
      isHidden: parseBoolean(row.is_hidden),
      isSystem: parseBoolean(row.is_system),
      isSymlink: parseBoolean(row.is_symlink),
      targetPath: parseOptionalString(row.target_path),
      downloadable: parseBoolean(row.downloadable),
      downloadMethod: parseOptionalString(row.download_method),
    };
  });

  return mapped
    .filter((entry) => entry.path !== '')
    .sort((a, b) => {
      if (a.type !== b.type) {
        if (a.type === 'directory') return -1;
        if (b.type === 'directory') return 1;
      }
      return a.path.localeCompare(b.path, undefined, { sensitivity: 'base' });
    });
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

function buildListServices(row: NormalizedCommandResult): ResultViewModel {
  const model = buildBaseModel(row, 'list_services', methodTitleMap.list_services);
  const data = extractStructuredData(row);
  const services = normalizeServicesArray(data);
  const table = buildProcessTable(services);

  model.hero = [
    { label: 'Status', value: toDisplayValue(row.resultStatus ?? row.state), tone: 'info' },
    { label: 'Services', value: String(services.length), tone: 'success' },
  ];
  model.diagnostics = buildDiagnosticsFromRow(row);
  model.sections = [
    {
      id: 'overview',
      title: 'Overview',
      widget: 'stats',
      stats: model.hero,
      description: services.length > 250 ? 'Showing first 250 rows' : undefined,
    },
    {
      id: 'services',
      title: 'Services',
      widget: 'table',
      table,
      emptySummary: services.length === 0 ? 'No service rows were returned' : null,
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

function buildListConnections(row: NormalizedCommandResult): ResultViewModel {
  const model = buildBaseModel(row, 'list_connections', methodTitleMap.list_connections);
  const data = extractStructuredData(row);
  const connections = normalizeConnectionsArray(data);
  const topTalkers = normalizeTopTalkersArray(data);
  const table = buildProcessTable(connections);
  const topTalkersTable = buildProcessTable(topTalkers);
  const counts = readSnapshotCounts(data);
  const truncated = counts.totalSeen != null && counts.totalSeen > counts.count;

  model.hero = [
    { label: 'Status', value: toDisplayValue(row.resultStatus ?? row.state), tone: 'info' },
    { label: 'Connections', value: String(counts.count || connections.length), tone: 'success' },
    {
      label: 'Total Seen',
      value: counts.totalSeen == null ? 'Not collected' : String(counts.totalSeen),
      tone: truncated ? 'warning' : 'default',
    },
  ];
  model.diagnostics = buildDiagnosticsFromRow(row);
  if (truncated) {
    model.diagnostics.push({
      severity: 'warning',
      reason: 'truncated_to_limit',
      message: `Showing ${counts.count} connection rows from ${counts.totalSeen} observed.`,
    });
  }
  model.sections = [
    {
      id: 'overview',
      title: 'Overview',
      widget: 'stats',
      stats: model.hero,
      description: truncated
        ? `Bounded snapshot: showing ${counts.count} of ${counts.totalSeen} rows.`
        : undefined,
    },
    {
      id: 'talkers',
      title: 'Top Talkers',
      widget: 'table',
      table: topTalkersTable,
      emptySummary: topTalkers.length === 0 ? 'No top-talker summary was returned' : null,
    },
    {
      id: 'connections',
      title: 'Connections',
      widget: 'table',
      table,
      emptySummary: connections.length === 0 ? 'No connection rows were returned' : null,
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

function buildListMounts(row: NormalizedCommandResult): ResultViewModel {
  const model = buildBaseModel(row, 'list_mounts', methodTitleMap.list_mounts);
  const data = extractStructuredData(row);
  const mounts = normalizeMountsArray(data);
  const table = buildProcessTable(mounts);

  model.hero = [
    { label: 'Status', value: toDisplayValue(row.resultStatus ?? row.state), tone: 'info' },
    { label: 'Mounts', value: String(mounts.length), tone: 'success' },
  ];
  model.diagnostics = buildDiagnosticsFromRow(row);
  model.sections = [
    {
      id: 'overview',
      title: 'Overview',
      widget: 'stats',
      stats: model.hero,
      description: mounts.length > 250 ? 'Showing first 250 rows' : undefined,
    },
    {
      id: 'mounts',
      title: 'Mounts',
      widget: 'table',
      table,
      emptySummary: mounts.length === 0 ? 'No mount rows were returned' : null,
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

function buildNetworkInfo(row: NormalizedCommandResult): ResultViewModel {
  const model = buildBaseModel(row, 'network_info', methodTitleMap.network_info);
  const data = extractStructuredData(row);
  const adapters = normalizeNetworkAdaptersArray(data);
  const routes = normalizeRoutesArray(data);
  const wifi = normalizeWifiPayload(data);
  const vpnSummary = normalizeVpnSummaryPayload(data);
  const savedProfiles = normalizeSavedWifiProfilesField(data, 'saved_wifi_profiles');
  const wifiRiskSignals = normalizeStringArrayField(data, 'wifi_risk_signals');
  const adapterTable = buildProcessTable(adapters);
  const routesTable = buildProcessTable(routes);
  const wifiView = {
    ...wifi,
    saved_wifi_profile_count: savedProfiles.length,
    saved_wifi_profiles_preview: savedProfiles.slice(0, 12).map((profile) => profile.ssid).join(', '),
    wifi_risk_signal_count: wifiRiskSignals.length,
    wifi_risk_signals: wifiRiskSignals.join(', '),
    wifi_passwords_collected: isObject(data) ? data.wifi_passwords_collected : false,
    saved_wifi_password_count: isObject(data) ? data.saved_wifi_password_count : 0,
  };
  const wifiBlock = objectEntries(wifiView, { hideNull: true });
  const vpnBlock = objectEntries(vpnSummary, { hideNull: true });
  const counts = readSnapshotCounts(data);
  const truncated = counts.totalSeen != null && counts.totalSeen > counts.count;

  model.hero = [
    { label: 'Status', value: toDisplayValue(row.resultStatus ?? row.state), tone: 'info' },
    { label: 'Adapters', value: String(counts.count || adapters.length), tone: 'success' },
    {
      label: 'Wi-Fi',
      value: wifi.connected === true ? toDisplayValue(wifi.ssid ?? 'Connected') : 'Not connected',
      tone: wifi.connected === true ? 'success' : 'default',
    },
    {
      label: 'VPN Candidate',
      value: vpnSummary.detected === true ? 'Detected' : 'Not detected',
      tone: vpnSummary.detected === true ? 'warning' : 'success',
    },
  ];
  model.diagnostics = buildDiagnosticsFromRow(row);
  if (truncated) {
    model.diagnostics.push({
      severity: 'warning',
      reason: 'truncated_to_limit',
      message: `Showing ${counts.count} adapters from ${counts.totalSeen} observed.`,
    });
  }
  model.sections = [
    {
      id: 'overview',
      title: 'Overview',
      widget: 'stats',
      stats: model.hero,
      description: truncated
        ? `Bounded snapshot: showing ${counts.count} of ${counts.totalSeen} adapters.`
        : undefined,
    },
    {
      id: 'interfaces',
      title: 'Interfaces',
      widget: 'table',
      table: adapterTable,
      emptySummary: adapters.length === 0 ? 'No adapter rows were returned' : null,
    },
    {
      id: 'wifi',
      title: 'Wi-Fi',
      widget: 'kv',
      keyValues: wifiBlock.keyValues,
      description: wifiRiskSignals.length > 0
        ? `Risk signals: ${wifiRiskSignals.join(', ')}`
        : undefined,
      emptySummary: wifiBlock.keyValues.length === 0 ? 'No Wi-Fi details were returned' : null,
    },
    {
      id: 'saved-wifi',
      title: 'Saved Wi-Fi Networks',
      widget: 'log',
      logText: formatSavedWifiProfilesLog(savedProfiles),
    },
    {
      id: 'vpn-routes',
      title: 'VPN & Routes',
      widget: 'table',
      table: routesTable,
      description: vpnBlock.keyValues.length > 0
        ? vpnBlock.keyValues.map((item) => `${item.label}: ${item.value}`).join(' | ')
        : undefined,
      emptySummary: routes.length === 0 ? 'No default route rows were returned' : null,
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

function buildActiveWindow(row: NormalizedCommandResult): ResultViewModel {
  const model = buildBaseModel(row, 'get_active_window', methodTitleMap.get_active_window);
  const data = extractStructuredData(row);
  const payload = normalizeActiveWindowPayload(data);

  const helperWindow = (() => {
    const screenshot = isObject(payload.screenshot) ? payload.screenshot : {};
    const screenshotCaptureEnvelope = isObject(screenshot.capture) ? screenshot.capture : {};
    const screenshotCapture = isObject(screenshotCaptureEnvelope.capture) ? screenshotCaptureEnvelope.capture : {};
    const activeWindow = isObject(screenshotCapture.active_window) ? screenshotCapture.active_window : null;
    return activeWindow;
  })();

  const payloadEffective = (() => {
    if (payload.available === true) return payload;
    if (!helperWindow || helperWindow.available !== true) return payload;
    return {
      ...payload,
      ...helperWindow,
      status: 'ok',
      available: true,
      source: 'screenshot_helper',
    };
  })();

  const available = payloadEffective.available === true;
  const artifactUrl =
    (typeof row.artifactUrl === 'string' && row.artifactUrl.trim() !== '' ? row.artifactUrl : null) ??
    (typeof row.result?.artifact_url === 'string' && row.result.artifact_url.trim() !== '' ? row.result.artifact_url : null);
  const artifactChecksum =
    (typeof row.artifactChecksum === 'string' && row.artifactChecksum.trim() !== '' ? row.artifactChecksum : null) ??
    (typeof row.result?.artifact_checksum === 'string' && row.result.artifact_checksum.trim() !== ''
      ? row.result.artifact_checksum
      : null);
  const screenshotFormatRaw = (() => {
    const screenshot = isObject(payload.screenshot) ? payload.screenshot : {};
    const screenshotCaptureEnvelope = isObject(screenshot.capture) ? screenshot.capture : {};
    return typeof screenshotCaptureEnvelope.format === 'string' ? screenshotCaptureEnvelope.format : 'png';
  })();
  const screenshotFormat = screenshotFormatRaw.toLowerCase();
  const captureContentType = screenshotFormat === 'jpeg' || screenshotFormat === 'jpg' ? 'image/jpeg' : 'image/png';

  const payloadBlock = objectEntries(payloadEffective, { hideNull: true });
  model.hero = [
    {
      label: 'State',
      value: toLabel(row.state),
      tone: row.state === 'completed' ? 'success' : row.state === 'failed' ? 'danger' : 'info',
    },
    {
      label: 'Window',
      value: toDisplayValue(payloadEffective.title ?? payloadEffective.status ?? 'Unknown'),
      tone: available ? 'success' : 'warning',
    },
    {
      label: 'Process',
      value: toDisplayValue(payloadEffective.process_name ?? payloadEffective.pid ?? 'Unknown'),
      tone: 'info',
    },
    {
      label: 'Screenshot',
      value: artifactUrl ? 'Captured' : 'Unavailable',
      tone: artifactUrl ? 'success' : 'warning',
    },
  ];

  model.diagnostics = buildDiagnosticsFromRow(row);
  if (!available) {
    model.diagnostics.push({
      severity: 'warning',
      reason: 'window_unavailable',
      message: 'No interactive foreground window was available at collection time.',
    });
  }
  if (!artifactUrl) {
    model.diagnostics.push({
      severity: 'warning',
      reason: 'artifact_missing',
      message: 'Screenshot artifact URL was not returned for active window capture.',
    });
  }

  model.sections = [
    {
      id: 'overview',
      title: 'Overview',
      widget: 'stats',
      stats: model.hero,
    },
    {
      id: 'window',
      title: 'Window Details',
      widget: 'kv',
      keyValues: payloadBlock.keyValues,
      collapsedByDefault: !available,
      emptySummary: payloadBlock.keyValues.length === 0 ? 'No window details were returned' : null,
    },
    {
      id: 'artifact',
      title: 'Screenshot Artifact',
      widget: 'artifact',
      artifact: {
        url: artifactUrl,
        checksum: artifactChecksum,
        contentType: captureContentType,
      },
      emptySummary: artifactUrl ? null : 'Artifact not available for this command result.',
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

function buildListFiles(row: NormalizedCommandResult): ResultViewModel {
  const model = buildBaseModel(row, 'list_files', methodTitleMap.list_files);
  const data = extractStructuredData(row);
  const payload = isObject(data) ? data : {};
  const entriesRaw = normalizeFileEntriesArray(payload);
  const entries = normalizeFilesystemEntries(entriesRaw);
  const partial = payload.partial === true;
  const rootPath = toCanonicalPath(parseOptionalString(payload.path) ?? '');
  const recursive = payload.recursive === true;
  const maxDepth = parseOptionalNumber(payload.max_depth);
  const nextCursor = parseOptionalString(payload.next_cursor);
  const downloadConfig = isObject(payload.download) ? payload.download : {};
  const canDownload = downloadConfig.supported === true;
  const downloadMethod = parseOptionalString(downloadConfig.method);

  const directories = entries.filter((entry) => entry.type === 'directory').length;
  const files = entries.filter((entry) => entry.type === 'file').length;
  const hiddenCount = entries.filter((entry) => entry.isHidden).length;
  const systemCount = entries.filter((entry) => entry.isSystem).length;
  const downloadableCount = entries.filter((entry) => entry.downloadable).length;

  model.hero = [
    {
      label: 'State',
      value: toLabel(row.state),
      tone: row.state === 'completed' ? 'success' : row.state === 'failed' ? 'danger' : 'info',
    },
    { label: 'Path', value: toDisplayValue(rootPath || payload.path || 'Unknown'), tone: 'info' },
    { label: 'Folders', value: String(directories), tone: 'success' },
    { label: 'Files', value: String(files), tone: 'info' },
    { label: 'Downloadable', value: String(downloadableCount), tone: canDownload ? 'success' : 'warning' },
    { label: 'Partial', value: partial ? 'Yes' : 'No', tone: partial ? 'warning' : 'default' },
  ];

  const metadata = objectEntries(
    {
      path: rootPath || payload.path,
      recursive,
      max_depth: maxDepth,
      count: payload.count,
      total_seen: payload.total_seen,
      hidden_items: hiddenCount,
      system_items: systemCount,
      partial,
      next_cursor: nextCursor,
      download_supported: canDownload,
      download_method: downloadMethod,
    },
    { hideNull: true },
  );

  model.diagnostics = buildDiagnosticsFromRow(row);
  if (partial) {
    model.diagnostics.push({
      severity: 'warning',
      reason: 'partial_result',
      message: 'Result was truncated by the current limit. Narrow path or increase limit.',
    });
  }

  model.sections = [
    {
      id: 'overview',
      title: 'Overview',
      widget: 'stats',
      stats: model.hero,
      description: partial
        ? 'Partial snapshot. Refine path or lower depth/limit for full navigation.'
        : 'Filesystem snapshot ready. Use Explorer tab to browse like a file explorer.',
    },
    {
      id: 'explorer',
      title: 'Explorer',
      widget: 'filesystem',
      filesystem: {
        rootPath: rootPath || '/',
        entries,
        recursive,
        maxDepth,
        partial,
        nextCursor,
        canDownload,
        downloadMethod,
      },
      emptySummary: entries.length === 0 ? 'No entries were returned for this path' : null,
    },
    {
      id: 'metadata',
      title: 'Browse Metadata',
      widget: 'kv',
      keyValues: metadata.keyValues,
      emptySummary: metadata.keyValues.length === 0 ? 'No metadata returned' : null,
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

function buildDownloadFile(row: NormalizedCommandResult): ResultViewModel {
  const model = buildBaseModel(row, 'download_file', methodTitleMap.download_file);
  const data = extractStructuredData(row);
  const payload = isObject(data) ? data : {};
  const artifactUrl =
    (typeof row.artifactUrl === 'string' && row.artifactUrl.trim() !== '' ? row.artifactUrl : null) ??
    (typeof row.result?.artifact_url === 'string' && row.result.artifact_url.trim() !== '' ? row.result.artifact_url : null);
  const artifactChecksum =
    (typeof row.artifactChecksum === 'string' && row.artifactChecksum.trim() !== '' ? row.artifactChecksum : null) ??
    (typeof row.result?.artifact_checksum === 'string' && row.result.artifact_checksum.trim() !== ''
      ? row.result.artifact_checksum
      : null);
  const contentType =
    typeof payload.content_type === 'string' && payload.content_type.trim() !== ''
      ? payload.content_type
      : 'application/octet-stream';

  model.hero = [
    {
      label: 'State',
      value: toLabel(row.state),
      tone: row.state === 'completed' ? 'success' : row.state === 'failed' ? 'danger' : 'info',
    },
    { label: 'Name', value: toDisplayValue(payload.name ?? payload.path ?? 'Unknown'), tone: 'info' },
    { label: 'Size', value: toDisplayValue(payload.size_bytes ?? 'Unknown') },
    { label: 'Artifact', value: artifactUrl ? 'Uploaded' : 'Unavailable', tone: artifactUrl ? 'success' : 'warning' },
  ];

  const details = objectEntries(payload, { hideNull: true });
  model.diagnostics = buildDiagnosticsFromRow(row);
  if (!artifactUrl) {
    model.diagnostics.push({
      severity: 'warning',
      reason: 'artifact_missing',
      message: 'Download artifact URL was not returned.',
    });
  }

  model.sections = [
    {
      id: 'overview',
      title: 'Overview',
      widget: 'stats',
      stats: model.hero,
    },
    {
      id: 'artifact',
      title: 'Artifact',
      widget: 'artifact',
      artifact: {
        url: artifactUrl,
        checksum: artifactChecksum,
        contentType,
      },
      emptySummary: artifactUrl ? null : 'Artifact not available for this command result.',
    },
    {
      id: 'details',
      title: 'File Details',
      widget: 'kv',
      keyValues: details.keyValues,
      emptySummary: details.keyValues.length === 0 ? 'No file details returned' : null,
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

function buildScreenshot(row: NormalizedCommandResult): ResultViewModel {
  const model = buildBaseModel(row, 'screenshot', methodTitleMap.screenshot);
  const data = extractStructuredData(row);
  const payload = isObject(data) ? data : {};
  const capture = isObject(payload.capture) ? payload.capture : {};
  const authorization = isObject(payload.authorization) ? payload.authorization : {};
  const artifactUrl =
    (typeof row.artifactUrl === 'string' && row.artifactUrl.trim() !== '' ? row.artifactUrl : null) ??
    (typeof row.result?.artifact_url === 'string' && row.result.artifact_url.trim() !== '' ? row.result.artifact_url : null);
  const artifactChecksum =
    (typeof row.artifactChecksum === 'string' && row.artifactChecksum.trim() !== '' ? row.artifactChecksum : null) ??
    (typeof row.result?.artifact_checksum === 'string' && row.result.artifact_checksum.trim() !== ''
      ? row.result.artifact_checksum
      : null);

  const width = typeof capture.width === 'number' ? String(capture.width) : null;
  const height = typeof capture.height === 'number' ? String(capture.height) : null;
  const dimensions = width && height ? `${width} x ${height}` : 'Unknown';
  const captureFormatRaw =
    typeof capture.format === 'string'
      ? capture.format
      : typeof payload.format === 'string'
        ? payload.format
        : 'png';
  const captureFormat = captureFormatRaw.toLowerCase();
  const captureContentType =
    captureFormat === 'jpeg' || captureFormat === 'jpg' ? 'image/jpeg' : 'image/png';
  const captureWithoutPath = { ...capture };
  delete captureWithoutPath.output_path;

  model.hero = [
    {
      label: 'State',
      value: toLabel(row.state),
      tone: row.state === 'completed' ? 'success' : row.state === 'failed' ? 'danger' : 'info',
    },
    {
      label: 'Format',
      value: toDisplayValue(payload.format ?? capture.format ?? 'png'),
      tone: 'info',
    },
    {
      label: 'Resolution',
      value: toDisplayValue(payload.resolution ?? capture.resolution ?? dimensions),
    },
    {
      label: 'Artifact',
      value: artifactUrl ? 'Uploaded' : 'Unavailable',
      tone: artifactUrl ? 'success' : 'warning',
    },
  ];

  const captureBlock = objectEntries(captureWithoutPath, { hideNull: true });
  const authBlock = objectEntries(authorization, { hideNull: true });
  model.diagnostics = buildDiagnosticsFromRow(row);
  if (!artifactUrl) {
    model.diagnostics.push({
      severity: 'warning',
      reason: 'artifact_missing',
      message: 'Screenshot artifact URL was not returned.',
    });
  }

  model.sections = [
    {
      id: 'overview',
      title: 'Overview',
      widget: 'stats',
      stats: model.hero,
    },
    {
      id: 'artifact',
      title: 'Artifact',
      widget: 'artifact',
      artifact: {
        url: artifactUrl,
        checksum: artifactChecksum,
        contentType: captureContentType,
      },
      emptySummary: artifactUrl ? null : 'Artifact not available for this command result.',
    },
    {
      id: 'capture',
      title: 'Capture Metadata',
      widget: 'kv',
      keyValues: captureBlock.keyValues,
      emptySummary: captureBlock.keyValues.length === 0 ? 'No capture metadata returned' : null,
    },
    {
      id: 'authorization',
      title: 'Kernel Authorization',
      widget: 'kv',
      keyValues: authBlock.keyValues,
      emptySummary: authBlock.keyValues.length === 0 ? 'No authorization metadata returned' : null,
      collapsedByDefault: authBlock.keyValues.length === 0,
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
  list_services: {
    method: 'list_services',
    title: methodTitleMap.list_services,
    build: buildListServices,
  },
  list_connections: {
    method: 'list_connections',
    title: methodTitleMap.list_connections,
    build: buildListConnections,
  },
  list_mounts: {
    method: 'list_mounts',
    title: methodTitleMap.list_mounts,
    build: buildListMounts,
  },
  network_info: {
    method: 'network_info',
    title: methodTitleMap.network_info,
    build: buildNetworkInfo,
  },
  get_active_window: {
    method: 'get_active_window',
    title: methodTitleMap.get_active_window,
    build: buildActiveWindow,
  },
  list_files: {
    method: 'list_files',
    title: methodTitleMap.list_files,
    build: buildListFiles,
  },
  download_file: {
    method: 'download_file',
    title: methodTitleMap.download_file,
    build: buildDownloadFile,
  },
  screenshot: {
    method: 'screenshot',
    title: methodTitleMap.screenshot,
    build: buildScreenshot,
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
