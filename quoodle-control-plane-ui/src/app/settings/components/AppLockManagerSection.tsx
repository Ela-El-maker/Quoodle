'use client';

import { useMemo, useState } from 'react';
import { Plus, RefreshCw, ShieldAlert, Trash2 } from 'lucide-react';
import { toast } from 'sonner';

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
  status: string;
  push_status?: string;
  app_lock: AppLockBundle;
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

function normalizeBasename(value: string): string {
  const trimmed = value.trim().toLowerCase();
  if (!trimmed) return '';
  return trimmed.endsWith('.exe') ? trimmed : `${trimmed}.exe`;
}

function normalizeRuleValue(matchType: MatchType, value: string): string {
  if (matchType === 'basename') return normalizeBasename(value);
  return value.trim();
}

function makeRuleId(matchType: MatchType, value: string): string {
  const clean = normalizeRuleValue(matchType, value).replace(/[^a-z0-9.-]+/gi, '-').toLowerCase();
  const suffix = Date.now().toString(36).slice(-6);
  return `rule-${clean}-${suffix}`;
}

export default function AppLockManagerSection() {
  const [bundle, setBundle] = useState<AppLockBundle>(DEFAULT_BUNDLE);
  const [loading, setLoading] = useState(false);
  const [saving, setSaving] = useState(false);
  const [newMatchType, setNewMatchType] = useState<MatchType>('basename');
  const [newValue, setNewValue] = useState('');
  const [newPriority, setNewPriority] = useState(100);
  const [checkValue, setCheckValue] = useState('');

  const blockedCheck = useMemo(() => {
    const input = checkValue.trim();
    if (!input) return null;
    const basenameTarget = normalizeBasename(input);
    const fullPathTarget = input.toLowerCase();
    const matchedRule = bundle.rules.find((rule) => {
      if (rule.match_type === 'basename') {
        return normalizeBasename(rule.value) === basenameTarget;
      }
      return (rule.value ?? '').toLowerCase() === fullPathTarget;
    });

    return {
      blocked: bundle.enabled && Boolean(matchedRule),
      matchedRule,
    };
  }, [bundle.enabled, bundle.rules, checkValue]);

  async function loadPolicy() {
    setLoading(true);
    try {
      const res = await fetch('/api/policy/app-lock', { method: 'GET', cache: 'no-store' });
      const json = (await res.json()) as Partial<AppLockResponse>;
      if (!res.ok || !json.app_lock) {
        throw new Error((json as { message?: string })?.message ?? 'Failed to load app-lock policy');
      }
      setBundle({ ...DEFAULT_BUNDLE, ...json.app_lock, rules: json.app_lock.rules ?? [] });
      toast.success('App lock policy loaded');
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'Failed to load app-lock policy');
    } finally {
      setLoading(false);
    }
  }

  async function savePolicy(nextBundle: AppLockBundle) {
    setSaving(true);
    try {
      const res = await fetch('/api/policy/app-lock', {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
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
        }),
      });
      const json = (await res.json()) as Partial<AppLockResponse> & { message?: string };
      if (!res.ok || !json.app_lock) {
        throw new Error(json.message ?? 'Failed to save app-lock policy');
      }
      setBundle({ ...DEFAULT_BUNDLE, ...json.app_lock, rules: json.app_lock.rules ?? [] });
      toast.success(`App lock policy saved (${json.push_status ?? 'accepted'})`);
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'Failed to save app-lock policy');
    } finally {
      setSaving(false);
    }
  }

  async function clearPolicy() {
    if (!window.confirm('Clear all app-lock rules and disable enforcement?')) return;
    setSaving(true);
    try {
      const res = await fetch('/api/policy/app-lock', { method: 'DELETE' });
      const json = (await res.json()) as Partial<AppLockResponse> & { message?: string };
      if (!res.ok || !json.app_lock) {
        throw new Error(json.message ?? 'Failed to clear app-lock policy');
      }
      setBundle({ ...DEFAULT_BUNDLE, ...json.app_lock, rules: json.app_lock.rules ?? [] });
      toast.success('App lock policy cleared');
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'Failed to clear app-lock policy');
    } finally {
      setSaving(false);
    }
  }

  function addRule() {
    const normalized = normalizeRuleValue(newMatchType, newValue);
    if (!normalized) {
      toast.error('Enter an app basename or full path');
      return;
    }
    const alreadyExists = bundle.rules.some(
      (rule) => rule.match_type === newMatchType && normalizeRuleValue(rule.match_type, rule.value) === normalized,
    );
    if (alreadyExists) {
      toast.warning('Rule already exists');
      return;
    }

    const nextRule: AppLockRule = {
      rule_id: makeRuleId(newMatchType, normalized),
      match_type: newMatchType,
      value: normalized,
      action: 'block',
      priority: Math.max(1, Math.min(999999, Number(newPriority) || 100)),
      expires_at: null,
    };
    setBundle((prev) => ({ ...prev, rules: [...prev.rules, nextRule] }));
    setNewValue('');
    setNewPriority(100);
  }

  function removeRule(ruleId: string) {
    setBundle((prev) => ({ ...prev, rules: prev.rules.filter((rule) => rule.rule_id !== ruleId) }));
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between gap-2 flex-wrap">
        <div>
          <h3 className="text-sm font-semibold">App Lock Manager</h3>
          <p className="text-xs text-muted-foreground mt-0.5">Block multiple apps by basename or full path and push policy instantly</p>
        </div>
        <div className="flex items-center gap-2">
          <button
            onClick={loadPolicy}
            disabled={loading}
            className="flex items-center gap-1.5 px-3 py-1.5 text-xs border border-border rounded-md text-muted-foreground hover:text-foreground hover:bg-muted/60 transition-colors disabled:opacity-60"
          >
            <RefreshCw size={12} />
            {loading ? 'Loading...' : 'Reload'}
          </button>
          <button
            onClick={clearPolicy}
            disabled={saving}
            className="flex items-center gap-1.5 px-3 py-1.5 text-xs border border-red-500/30 text-red-400 rounded-md hover:bg-red-500/10 transition-colors disabled:opacity-60"
          >
            <Trash2 size={12} />
            Clear Policy
          </button>
          <button
            onClick={() => savePolicy(bundle)}
            disabled={saving}
            className="flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium bg-primary/10 border border-primary/30 text-primary rounded-md hover:bg-primary/20 transition-colors disabled:opacity-60"
          >
            <ShieldAlert size={12} />
            {saving ? 'Saving...' : 'Save Policy'}
          </button>
        </div>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-4 gap-3">
        <label className="bg-card border border-border rounded-lg px-3 py-2.5 text-xs">
          <span className="text-[10px] text-muted-foreground uppercase tracking-wide">Enforcement</span>
          <select
            value={bundle.enabled ? 'on' : 'off'}
            onChange={(e) => setBundle((prev) => ({ ...prev, enabled: e.target.value === 'on' }))}
            className="w-full mt-1 bg-transparent text-foreground focus:outline-none"
          >
            <option value="on">Enabled</option>
            <option value="off">Disabled</option>
          </select>
        </label>
        <label className="bg-card border border-border rounded-lg px-3 py-2.5 text-xs">
          <span className="text-[10px] text-muted-foreground uppercase tracking-wide">Mode</span>
          <div className="mt-1 text-foreground">blocklist</div>
        </label>
        <label className="bg-card border border-border rounded-lg px-3 py-2.5 text-xs">
          <span className="text-[10px] text-muted-foreground uppercase tracking-wide">Fail Mode</span>
          <div className="mt-1 text-foreground">open</div>
        </label>
        <label className="bg-card border border-border rounded-lg px-3 py-2.5 text-xs">
          <span className="text-[10px] text-muted-foreground uppercase tracking-wide">Event Dedupe Sec</span>
          <input
            type="number"
            min={1}
            max={3600}
            value={bundle.event_dedupe_sec}
            onChange={(e) => setBundle((prev) => ({ ...prev, event_dedupe_sec: Math.max(1, Math.min(3600, Number(e.target.value) || 30)) }))}
            className="w-full mt-1 bg-transparent text-foreground focus:outline-none"
          />
        </label>
      </div>

      <div className="bg-card border border-border rounded-lg p-3 space-y-2">
        <div className="text-xs font-medium">Add Block Rule</div>
        <div className="grid grid-cols-1 md:grid-cols-5 gap-2">
          <select
            value={newMatchType}
            onChange={(e) => setNewMatchType(e.target.value as MatchType)}
            className="px-2.5 py-2 text-xs bg-muted/40 border border-border rounded-md"
          >
            <option value="basename">basename</option>
            <option value="full_path">full_path</option>
          </select>
          <input
            value={newValue}
            onChange={(e) => setNewValue(e.target.value)}
            placeholder={newMatchType === 'basename' ? 'whatsapp.root.exe' : 'C:\\Path\\To\\App.exe'}
            className="md:col-span-3 px-2.5 py-2 text-xs bg-muted/40 border border-border rounded-md"
          />
          <input
            type="number"
            min={1}
            max={999999}
            value={newPriority}
            onChange={(e) => setNewPriority(Number(e.target.value) || 100)}
            className="px-2.5 py-2 text-xs bg-muted/40 border border-border rounded-md"
            title="priority"
          />
        </div>
        <button
          onClick={addRule}
          className="flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium bg-primary/10 border border-primary/30 text-primary rounded-md hover:bg-primary/20 transition-colors"
        >
          <Plus size={12} />
          Add Rule
        </button>
      </div>

      <div className="bg-card border border-border rounded-lg overflow-hidden">
        <div className="px-3 py-2.5 border-b border-border flex items-center justify-between text-xs">
          <span className="font-medium">Current Rules</span>
          <span className="text-muted-foreground">{bundle.rules.length} rule(s)</span>
        </div>
        {bundle.rules.length === 0 ? (
          <div className="px-3 py-6 text-xs text-muted-foreground">No app-lock rules configured.</div>
        ) : (
          <table className="w-full text-xs">
            <thead>
              <tr className="bg-muted/20 border-b border-border">
                <th className="px-3 py-2 text-left">Rule ID</th>
                <th className="px-3 py-2 text-left">Match</th>
                <th className="px-3 py-2 text-left">Value</th>
                <th className="px-3 py-2 text-left">Priority</th>
                <th className="px-3 py-2 w-12" />
              </tr>
            </thead>
            <tbody>
              {bundle.rules.map((rule) => (
                <tr key={rule.rule_id} className="border-b border-border/60 last:border-0">
                  <td className="px-3 py-2 font-mono text-[11px]">{rule.rule_id}</td>
                  <td className="px-3 py-2">{rule.match_type}</td>
                  <td className="px-3 py-2 font-mono text-[11px]">{rule.value}</td>
                  <td className="px-3 py-2">{rule.priority}</td>
                  <td className="px-3 py-2">
                    <button
                      onClick={() => removeRule(rule.rule_id)}
                      className="p-1.5 rounded text-muted-foreground hover:text-red-400 hover:bg-red-500/10 transition-colors"
                      title="Remove rule"
                    >
                      <Trash2 size={12} />
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      <div className="bg-card border border-border rounded-lg p-3 space-y-2">
        <div className="text-xs font-medium">Check If App Is Blocked</div>
        <div className="flex items-center gap-2">
          <input
            value={checkValue}
            onChange={(e) => setCheckValue(e.target.value)}
            placeholder="whatsapp.root.exe or full path"
            className="flex-1 px-2.5 py-2 text-xs bg-muted/40 border border-border rounded-md"
          />
        </div>
        {blockedCheck && (
          <div
            className={`text-xs px-2.5 py-2 rounded border ${
              blockedCheck.blocked
                ? 'bg-red-500/10 border-red-500/30 text-red-300'
                : 'bg-green-500/10 border-green-500/30 text-green-300'
            }`}
          >
            {blockedCheck.blocked ? 'Blocked by policy' : 'Not blocked'}
            {blockedCheck.matchedRule ? ` (rule: ${blockedCheck.matchedRule.rule_id})` : ''}
          </div>
        )}
      </div>
    </div>
  );
}
