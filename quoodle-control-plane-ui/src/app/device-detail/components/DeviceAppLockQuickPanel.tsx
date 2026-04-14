'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { Loader2, RefreshCw, Search, ShieldAlert, ShieldCheck } from 'lucide-react';
import { toast } from 'sonner';
import { resolveCommandMethod } from '@/lib/commandMethodResolver';
import type { NormalizedCommandResult } from '@/lib/commandResults';

type MatchType = 'basename' | 'full_path';

interface AppLockRule {
  rule_id: string;
  match_type: MatchType;
  value: string;
  action: 'block';
  priority: number;
  expires_at: string | null;
}

interface AppLockBundle {
  enabled: boolean;
  mode: 'blocklist';
  fail_mode: 'open';
  policy_version: string;
  policy_hash: string;
  event_dedupe_sec: number;
  updated_at: string;
  rules: AppLockRule[];
}

interface AppLockResponse {
  status?: string;
  push_status?: string;
  message?: string;
  app_lock?: Partial<AppLockBundle>;
}

interface ProcessEntry {
  name?: unknown;
  path?: unknown;
}

interface DiscoveredApp {
  basename: string;
  displayName: string;
  processCount: number;
  paths: string[];
}

interface QuickAppPreset {
  label: string;
  basename: string;
}

interface DeviceAppLockQuickPanelProps {
  deviceId: string;
  hostname: string;
  recentResults: NormalizedCommandResult[];
  onScanApps?: () => Promise<void> | void;
  isScanningApps?: boolean;
}

const DEFAULT_BUNDLE: AppLockBundle = {
  enabled: false,
  mode: 'blocklist',
  fail_mode: 'open',
  policy_version: '',
  policy_hash: '',
  event_dedupe_sec: 30,
  updated_at: '',
  rules: [],
};

const QUICK_APP_PRESETS: QuickAppPreset[] = [
  { label: 'WhatsApp', basename: 'whatsapp.root.exe' },
  { label: 'Discord', basename: 'discord.exe' },
  { label: 'Telegram', basename: 'telegram.exe' },
  { label: 'Steam', basename: 'steam.exe' },
  { label: 'Epic Games', basename: 'epicgameslauncher.exe' },
  { label: 'Battle.net', basename: 'battle.net.exe' },
  { label: 'Chrome', basename: 'chrome.exe' },
  { label: 'Edge', basename: 'msedge.exe' },
  { label: 'Firefox', basename: 'firefox.exe' },
  { label: 'Opera', basename: 'opera.exe' },
];

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function pathBasename(value: string): string {
  const parts = value.split(/[\\/]/).filter(Boolean);
  return parts[parts.length - 1] ?? '';
}

function normalizePath(value: string): string {
  return value.trim().replace(/\//g, '\\').toLowerCase();
}

function normalizeBasename(value: string, allowImplicitExe: boolean): string {
  const trimmed = value.trim();
  if (!trimmed) return '';
  const candidate = pathBasename(trimmed).toLowerCase();
  if (!candidate) return '';
  if (candidate.endsWith('.exe')) return candidate;
  if (allowImplicitExe && !candidate.includes('.')) {
    return `${candidate}.exe`;
  }
  return '';
}

function normalizeRuleValue(matchType: MatchType, value: string): string {
  if (matchType === 'basename') {
    return normalizeBasename(value, true);
  }
  return normalizePath(value);
}

function coerceBundle(raw?: Partial<AppLockBundle>): AppLockBundle {
  if (!raw) return DEFAULT_BUNDLE;
  const rawRules: unknown[] = Array.isArray(raw.rules) ? raw.rules : [];
  const rules: AppLockRule[] = rawRules
    .filter((rule): rule is Record<string, unknown> => isRecord(rule))
    .map((rule) => ({
      rule_id: String(rule.rule_id ?? ''),
      match_type: (rule.match_type === 'full_path' ? 'full_path' : 'basename') as MatchType,
      value: String(rule.value ?? ''),
      action: 'block' as const,
      priority: Number.isFinite(Number(rule.priority)) ? Number(rule.priority) : 1000,
      expires_at: rule.expires_at ? String(rule.expires_at) : null,
    }))
    .filter((rule) => rule.rule_id !== '' && rule.value.trim() !== '');

  return {
    enabled: Boolean(raw.enabled),
    mode: 'blocklist',
    fail_mode: 'open',
    policy_version: String(raw.policy_version ?? ''),
    policy_hash: String(raw.policy_hash ?? ''),
    event_dedupe_sec: Number.isFinite(Number(raw.event_dedupe_sec)) ? Number(raw.event_dedupe_sec) : 30,
    updated_at: String(raw.updated_at ?? ''),
    rules,
  };
}

function uniqueSorted(values: string[]): string[] {
  return Array.from(new Set(values)).sort((a, b) => a.localeCompare(b));
}

function sanitizeRuleId(raw: string): string {
  const normalized = raw.replace(/[^a-z0-9._-]+/gi, '-').toLowerCase();
  return normalized.slice(0, 64);
}

function sortRules(rules: AppLockRule[]): AppLockRule[] {
  return [...rules].sort((a, b) => a.priority - b.priority || a.rule_id.localeCompare(b.rule_id));
}

function ruleMatches(rule: AppLockRule, matchType: MatchType, normalizedValue: string): boolean {
  return (
    rule.match_type === matchType &&
    normalizeRuleValue(matchType, rule.value) === normalizeRuleValue(matchType, normalizedValue)
  );
}

function extractDiscoveredApps(results: NormalizedCommandResult[]): DiscoveredApp[] {
  const byBasename = new Map<
    string,
    {
      displayName: string;
      processCount: number;
      paths: Set<string>;
    }
  >();

  for (const row of results) {
    if (resolveCommandMethod(row.method) !== 'list_processes') continue;
    if (!row.result || !isRecord(row.result)) continue;
    const data = row.result.data;
    if (!isRecord(data)) continue;

    const processesCandidate = data.processes;
    if (!Array.isArray(processesCandidate)) continue;

    for (const processItem of processesCandidate) {
      if (!isRecord(processItem)) continue;
      const entry = processItem as ProcessEntry;
      const rawName = typeof entry.name === 'string' ? entry.name : '';
      const rawPath = typeof entry.path === 'string' ? entry.path : '';

      const basenameFromName = normalizeBasename(rawName, false);
      const basenameFromPathValue = normalizeBasename(rawPath, false);
      const basename = basenameFromName || basenameFromPathValue;
      if (!basename) continue;

      const current = byBasename.get(basename) ?? {
        displayName: basename,
        processCount: 0,
        paths: new Set<string>(),
      };

      current.processCount += 1;
      if (rawPath.trim() !== '') {
        current.paths.add(normalizePath(rawPath));
      }
      if (rawName.trim().toLowerCase().endsWith('.exe')) {
        current.displayName = rawName.trim();
      }

      byBasename.set(basename, current);
    }
  }

  return Array.from(byBasename.entries())
    .map(([basename, value]) => ({
      basename,
      displayName: value.displayName,
      processCount: value.processCount,
      paths: uniqueSorted(Array.from(value.paths)),
    }))
    .sort((a, b) => a.displayName.localeCompare(b.displayName));
}

function appIsBlocked(bundle: AppLockBundle, app: DiscoveredApp): boolean {
  if (!bundle.enabled) return false;
  const pathSet = new Set(app.paths);
  return bundle.rules.some((rule) => {
    if (rule.match_type === 'basename') {
      return normalizeRuleValue('basename', rule.value) === app.basename;
    }
    if (!pathSet.size) return false;
    return pathSet.has(normalizeRuleValue('full_path', rule.value));
  });
}

function ruleIsBlocked(bundle: AppLockBundle, matchType: MatchType, value: string): boolean {
  if (!bundle.enabled) return false;
  const normalized = normalizeRuleValue(matchType, value);
  if (!normalized) return false;
  return bundle.rules.some((rule) => ruleMatches(rule, matchType, normalized));
}

export default function DeviceAppLockQuickPanel({
  deviceId,
  hostname,
  recentResults,
  onScanApps,
  isScanningApps = false,
}: DeviceAppLockQuickPanelProps) {
  const [bundle, setBundle] = useState<AppLockBundle>(DEFAULT_BUNDLE);
  const [loadingPolicy, setLoadingPolicy] = useState(false);
  const [savingKey, setSavingKey] = useState<string | null>(null);
  const [search, setSearch] = useState('');
  const [customMatchType, setCustomMatchType] = useState<MatchType>('basename');
  const [customApp, setCustomApp] = useState('');
  const scopedPolicyUrl = useMemo(
    () => `/api/policy/app-lock?device_id=${encodeURIComponent(deviceId)}`,
    [deviceId],
  );

  const discoveredApps = useMemo(() => extractDiscoveredApps(recentResults), [recentResults]);
  const filteredApps = useMemo(() => {
    const needle = search.trim().toLowerCase();
    if (!needle) return discoveredApps;
    return discoveredApps.filter(
      (app) =>
        app.displayName.toLowerCase().includes(needle) ||
        app.basename.includes(needle) ||
        app.paths.some((path) => path.includes(needle)),
    );
  }, [discoveredApps, search]);

  const customNormalizedValue = useMemo(
    () => normalizeRuleValue(customMatchType, customApp),
    [customApp, customMatchType],
  );
  const customBlocked = useMemo(
    () => (customNormalizedValue ? ruleIsBlocked(bundle, customMatchType, customNormalizedValue) : false),
    [bundle, customMatchType, customNormalizedValue],
  );
  const activeRules = useMemo(() => sortRules(bundle.rules), [bundle.rules]);

  const loadPolicy = useCallback(async () => {
    setLoadingPolicy(true);
      try {
      const response = await fetch(scopedPolicyUrl, { method: 'GET', cache: 'no-store' });
      const json = (await response.json()) as AppLockResponse;
      if (!response.ok || !json.app_lock) {
        throw new Error(json.message ?? 'Failed to load app-lock policy');
      }
      setBundle(coerceBundle(json.app_lock));
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'Failed to load app-lock policy');
    } finally {
      setLoadingPolicy(false);
    }
  }, [scopedPolicyUrl]);

  useEffect(() => {
    void loadPolicy();
  }, [loadPolicy]);

  const persistPolicy = useCallback(
    async (nextBundle: AppLockBundle, key: string, successMessage: string) => {
      setSavingKey(key);
      try {
        const payload = {
          enabled: nextBundle.enabled,
          mode: 'blocklist',
          fail_mode: 'open',
          event_dedupe_sec: nextBundle.event_dedupe_sec,
          rules: nextBundle.rules.map((rule) => ({
            rule_id: rule.rule_id,
            match_type: rule.match_type,
            value: normalizeRuleValue(rule.match_type, rule.value),
            action: 'block',
            priority: rule.priority,
            expires_at: rule.expires_at ?? null,
          })),
        };

        const response = await fetch(scopedPolicyUrl, {
          method: 'PUT',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(payload),
        });

        const json = (await response.json()) as AppLockResponse;
        if (!response.ok || !json.app_lock) {
          throw new Error(json.message ?? 'Failed to save app-lock policy');
        }

        setBundle(coerceBundle(json.app_lock));
        toast.success(successMessage);
      } catch (error) {
        toast.error(error instanceof Error ? error.message : 'Failed to save app-lock policy');
      } finally {
        setSavingKey(null);
      }
    },
    [scopedPolicyUrl],
  );

  const toggleDiscoveredApp = useCallback(
    async (app: DiscoveredApp) => {
      const blocked = appIsBlocked(bundle, app);
      const normalizedAppPaths = new Set(app.paths.map((path) => normalizeRuleValue('full_path', path)));

      let nextRules = bundle.rules.filter((rule) => {
        if (blocked) {
          if (rule.match_type === 'basename') {
            return normalizeRuleValue('basename', rule.value) !== app.basename;
          }
          if (!normalizedAppPaths.size) return true;
          return !normalizedAppPaths.has(normalizeRuleValue('full_path', rule.value));
        }
        return true;
      });

      if (!blocked) {
        const exists = nextRules.some(
          (rule) =>
            rule.match_type === 'basename' &&
            normalizeRuleValue('basename', rule.value) === app.basename,
        );
        if (!exists) {
          const ruleIdBase = sanitizeRuleId(`dev-${deviceId}-${app.basename}-${Date.now().toString(36)}`);
          nextRules = [
            ...nextRules,
            {
              rule_id: ruleIdBase || `rule-${Date.now().toString(36)}`,
              match_type: 'basename',
              value: app.basename,
              action: 'block',
              priority: 100,
              expires_at: null,
            },
          ];
        }
      }

      const finalRules = sortRules(nextRules);
      const nextBundle: AppLockBundle = {
        ...bundle,
        enabled: finalRules.length > 0 ? true : false,
        rules: finalRules,
      };

      await persistPolicy(
        nextBundle,
        app.basename,
        blocked ? `${app.displayName} unblocked` : `${app.displayName} blocked`,
      );
    },
    [bundle, deviceId, persistPolicy],
  );

  const toggleCustomRule = useCallback(async () => {
    if (!customNormalizedValue) {
      if (customMatchType === 'basename') {
        toast.error('Enter an executable name, for example whatsapp.root.exe');
      } else {
        toast.error('Enter a full executable path, for example C:\\Program Files\\App\\app.exe');
      }
      return;
    }

    const blocked = ruleIsBlocked(bundle, customMatchType, customNormalizedValue);
    let nextRules = bundle.rules.filter((rule) => !ruleMatches(rule, customMatchType, customNormalizedValue));

    if (!blocked) {
      const ruleId = sanitizeRuleId(`dev-${deviceId}-${customNormalizedValue}-${Date.now().toString(36)}`);
      nextRules = [
        ...nextRules,
        {
          rule_id: ruleId || `rule-${Date.now().toString(36)}`,
          match_type: customMatchType,
          value: customNormalizedValue,
          action: 'block',
          priority: 100,
          expires_at: null,
        },
      ];
    }

    const finalRules = sortRules(nextRules);
    const nextBundle: AppLockBundle = {
      ...bundle,
      enabled: finalRules.length > 0 ? true : false,
      rules: finalRules,
    };

    await persistPolicy(
      nextBundle,
      `custom-${customMatchType}-${customNormalizedValue}`,
      blocked ? `${customNormalizedValue} unblocked` : `${customNormalizedValue} blocked`,
    );
  }, [bundle, customMatchType, customNormalizedValue, deviceId, persistPolicy]);

  const removeRule = useCallback(
    async (rule: AppLockRule) => {
      const nextRules = sortRules(bundle.rules.filter((item) => item.rule_id !== rule.rule_id));
      const nextBundle: AppLockBundle = {
        ...bundle,
        enabled: nextRules.length > 0 ? true : false,
        rules: nextRules,
      };
      await persistPolicy(nextBundle, `remove-${rule.rule_id}`, `${rule.value} unblocked`);
    },
    [bundle, persistPolicy],
  );

  const togglePreset = useCallback(
    async (preset: QuickAppPreset) => {
      const value = normalizeRuleValue('basename', preset.basename);
      const blocked = ruleIsBlocked(bundle, 'basename', value);
      let nextRules = bundle.rules.filter((rule) => !ruleMatches(rule, 'basename', value));
      if (!blocked) {
        const ruleId = sanitizeRuleId(`dev-${deviceId}-${value}-${Date.now().toString(36)}`);
        nextRules = [
          ...nextRules,
          {
            rule_id: ruleId || `rule-${Date.now().toString(36)}`,
            match_type: 'basename',
            value,
            action: 'block',
            priority: 100,
            expires_at: null,
          },
        ];
      }
      const finalRules = sortRules(nextRules);
      const nextBundle: AppLockBundle = {
        ...bundle,
        enabled: finalRules.length > 0 ? true : false,
        rules: finalRules,
      };
      await persistPolicy(
        nextBundle,
        `preset-${value}`,
        blocked ? `${preset.label} unblocked` : `${preset.label} blocked`,
      );
    },
    [bundle, deviceId, persistPolicy],
  );

  return (
    <div className="bg-card border border-border rounded-lg p-4 space-y-3">
      <div className="flex items-center justify-between gap-2">
        <div>
          <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wide">Device App Lock</p>
          <p className="text-[11px] text-muted-foreground mt-1">
            Quick block/unblock for {hostname} using discovered processes plus pre-block rules.
          </p>
          <p className="text-[10px] text-blue-300 mt-1">Scope: this panel writes policy for this device only.</p>
        </div>
        <button
          onClick={() => void loadPolicy()}
          disabled={loadingPolicy}
          className="flex items-center gap-1.5 px-2.5 py-1.5 text-[11px] border border-border rounded-md text-muted-foreground hover:text-foreground hover:bg-muted/60 transition-colors disabled:opacity-60"
        >
          <RefreshCw size={12} className={loadingPolicy ? 'animate-spin' : ''} />
          Refresh
        </button>
      </div>

      <div className="flex items-center gap-2 flex-wrap">
        <button
          onClick={() => {
            if (onScanApps) {
              void onScanApps();
            }
          }}
          disabled={!onScanApps || isScanningApps}
          className="flex items-center gap-1.5 px-2.5 py-1.5 text-[11px] border border-border rounded-md text-muted-foreground hover:text-foreground hover:bg-muted/60 transition-colors disabled:opacity-60"
        >
          <RefreshCw size={12} className={isScanningApps ? 'animate-spin' : ''} />
          {isScanningApps ? 'Scanning...' : 'Scan Apps Now'}
        </button>
        <span className="text-[11px] text-muted-foreground">
          Uses `list_processes` to refresh discovered app toggles.
        </span>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-3 gap-2">
        <div className="bg-muted/30 rounded-lg p-2.5">
          <p className="text-[10px] text-muted-foreground uppercase tracking-wide">Policy</p>
          <p className={`text-xs font-semibold ${bundle.enabled ? 'text-red-300' : 'text-green-300'}`}>
            {bundle.enabled ? 'Enabled' : 'Disabled'}
          </p>
        </div>
        <div className="bg-muted/30 rounded-lg p-2.5">
          <p className="text-[10px] text-muted-foreground uppercase tracking-wide">Rules</p>
          <p className="text-xs font-semibold">{bundle.rules.length}</p>
        </div>
        <div className="bg-muted/30 rounded-lg p-2.5">
          <p className="text-[10px] text-muted-foreground uppercase tracking-wide">Detected Apps</p>
          <p className="text-xs font-semibold">{discoveredApps.length}</p>
        </div>
      </div>

      <div className="bg-muted/20 border border-border rounded-lg p-2.5 space-y-2">
        <div className="flex items-center justify-between gap-2">
          <p className="text-[11px] font-medium">Quick App Toggle (works even if app is not running)</p>
          <div className="inline-flex items-center gap-1 rounded-md border border-border p-1">
            <button
              onClick={() => setCustomMatchType('basename')}
              className={`px-2 py-1 text-[10px] rounded ${
                customMatchType === 'basename'
                  ? 'bg-blue-500/20 text-blue-300'
                  : 'text-muted-foreground hover:text-foreground'
              }`}
            >
              Name
            </button>
            <button
              onClick={() => setCustomMatchType('full_path')}
              className={`px-2 py-1 text-[10px] rounded ${
                customMatchType === 'full_path'
                  ? 'bg-blue-500/20 text-blue-300'
                  : 'text-muted-foreground hover:text-foreground'
              }`}
            >
              Full Path
            </button>
          </div>
        </div>
        <div className="flex items-center gap-2">
          <input
            value={customApp}
            onChange={(event) => setCustomApp(event.target.value)}
            placeholder={
              customMatchType === 'basename'
                ? 'whatsapp.root.exe'
                : 'C:\\Program Files\\WindowsApps\\...\\whatsapp.root.exe'
            }
            className="flex-1 px-2.5 py-2 text-xs bg-background border border-border rounded-md"
          />
          <button
            onClick={() => void toggleCustomRule()}
            disabled={savingKey === `custom-${customMatchType}-${customNormalizedValue}` || !customNormalizedValue}
            className={`px-3 py-2 text-xs font-medium rounded-md border transition-colors disabled:opacity-60 ${
              customBlocked
                ? 'border-green-500/30 bg-green-500/10 text-green-300 hover:bg-green-500/20'
                : 'border-red-500/30 bg-red-500/10 text-red-300 hover:bg-red-500/20'
            }`}
          >
            {savingKey === `custom-${customMatchType}-${customNormalizedValue}`
              ? 'Saving...'
              : customBlocked
                ? 'Unblock'
                : 'Block'}
          </button>
        </div>
        <p className="text-[10px] text-muted-foreground">
          Use <span className="font-mono">Name</span> for future launches, even when the app is currently offline.
        </p>
      </div>

      <div className="bg-muted/20 border border-border rounded-lg p-2.5 space-y-2">
        <p className="text-[11px] font-medium">Popular App Quick Picks</p>
        <div className="flex flex-wrap gap-1.5">
          {QUICK_APP_PRESETS.map((preset) => {
            const blocked = ruleIsBlocked(bundle, 'basename', preset.basename);
            const presetKey = normalizeRuleValue('basename', preset.basename);
            const presetSaving = savingKey === `preset-${presetKey}`;
            return (
              <button
                key={preset.basename}
                onClick={() => void togglePreset(preset)}
                disabled={presetSaving}
                className={`px-2.5 py-1.5 rounded-md text-[11px] border transition-colors disabled:opacity-60 ${
                  blocked
                    ? 'border-red-500/30 bg-red-500/10 text-red-300 hover:bg-red-500/20'
                    : 'border-border bg-muted/40 text-muted-foreground hover:text-foreground hover:bg-muted/70'
                }`}
                title={preset.basename}
              >
                {presetSaving ? 'Saving...' : blocked ? `Blocked: ${preset.label}` : preset.label}
              </button>
            );
          })}
        </div>
      </div>

      <div className="space-y-2">
        <div className="relative">
          <Search size={12} className="absolute left-2.5 top-1/2 -translate-y-1/2 text-muted-foreground" />
          <input
            value={search}
            onChange={(event) => setSearch(event.target.value)}
            placeholder="Search discovered apps..."
            className="w-full pl-8 pr-3 py-2 text-xs bg-muted/40 border border-border rounded-md"
          />
        </div>
        {filteredApps.length === 0 ? (
          <div className="border border-border rounded-lg px-3 py-4 text-xs text-muted-foreground">
            {discoveredApps.length === 0
              ? 'No process inventory found yet. Run `Process List` for this device, then refresh.'
              : 'No apps matched your search.'}
          </div>
        ) : (
          <div className="max-h-72 overflow-y-auto rounded-lg border border-border divide-y divide-border">
            {filteredApps.map((app) => {
              const blocked = appIsBlocked(bundle, app);
              const rowSaving = savingKey === app.basename;
              const samplePath = app.paths[0] ?? '-';
              return (
                <div key={app.basename} className="px-3 py-2.5 flex items-center gap-3">
                  <div className="min-w-0 flex-1">
                    <p className="text-xs font-semibold truncate">{app.displayName}</p>
                    <p className="text-[11px] text-muted-foreground truncate">{samplePath}</p>
                    <p className="text-[10px] text-muted-foreground mt-1">{app.processCount} process instance(s)</p>
                  </div>
                  <button
                    onClick={() => void toggleDiscoveredApp(app)}
                    disabled={rowSaving}
                    className={`min-w-[90px] px-2.5 py-1.5 text-[11px] font-medium rounded-md border transition-colors disabled:opacity-60 flex items-center justify-center gap-1.5 ${
                      blocked
                        ? 'border-red-500/30 bg-red-500/10 text-red-300 hover:bg-red-500/20'
                        : 'border-green-500/30 bg-green-500/10 text-green-300 hover:bg-green-500/20'
                    }`}
                  >
                    {rowSaving ? (
                      <>
                        <Loader2 size={12} className="animate-spin" />
                        Saving
                      </>
                    ) : blocked ? (
                      <>
                        <ShieldAlert size={12} />
                        Blocked
                      </>
                    ) : (
                      <>
                        <ShieldCheck size={12} />
                        Allowed
                      </>
                    )}
                  </button>
                </div>
              );
            })}
          </div>
        )}
      </div>

      <div className="space-y-2">
        <p className="text-[11px] font-medium">Active Block Rules</p>
        {activeRules.length === 0 ? (
          <div className="border border-border rounded-lg px-3 py-3 text-xs text-muted-foreground">
            No block rules yet.
          </div>
        ) : (
          <div className="max-h-52 overflow-y-auto rounded-lg border border-border divide-y divide-border">
            {activeRules.map((rule) => {
              const rowSaving = savingKey === `remove-${rule.rule_id}`;
              return (
                <div key={rule.rule_id} className="px-3 py-2 flex items-center gap-3">
                  <div className="min-w-0 flex-1">
                    <p className="text-xs font-medium truncate">{rule.value}</p>
                    <p className="text-[10px] text-muted-foreground">
                      {rule.match_type === 'basename' ? 'Name rule' : 'Full-path rule'} | priority {rule.priority}
                    </p>
                  </div>
                  <button
                    onClick={() => void removeRule(rule)}
                    disabled={rowSaving}
                    className="px-2.5 py-1.5 text-[11px] font-medium rounded-md border border-green-500/30 bg-green-500/10 text-green-300 hover:bg-green-500/20 transition-colors disabled:opacity-60"
                  >
                    {rowSaving ? 'Saving...' : 'Unblock'}
                  </button>
                </div>
              );
            })}
          </div>
        )}
      </div>
    </div>
  );
}
