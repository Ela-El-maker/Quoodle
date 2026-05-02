'use client';

import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  AlertTriangle,
  Bell,
  Edit2,
  Lock,
  Plus,
  RefreshCw,
  Save,
  Shield,
  ShieldCheck,
  ToggleLeft,
  ToggleRight,
  Trash2,
  Users,
  UserCheck,
  UserX,
} from 'lucide-react';
import { toast } from 'sonner';
import AppLockManagerSection from './AppLockManagerSection';

type SettingsTab =
  | 'alert-rules'
  | 'app-lock'
  | 'policy-editor'
  | 'compliance-thresholds'
  | 'roles-permissions'
  | 'team-members';

type Role = 'admin' | 'operator' | 'viewer';
type AccountStatus = 'active' | 'inactive' | 'pending';
type Severity = 'critical' | 'warning' | 'info';

interface AlertRule {
  id: string;
  name: string;
  condition: string;
  severity: Severity;
  channels: string[];
  enabled: boolean;
}

interface PolicyEntry {
  id: string;
  policy_key: string;
  policy_value: string | null;
  scope: string;
  value_type: string;
  description: string | null;
  is_mutable: boolean;
}

interface ComplianceThreshold {
  id: string;
  control: string;
  metric: string;
  threshold: number;
  unit: string | null;
  severity: 'critical' | 'warning';
  enabled: boolean;
}

interface TeamDevice {
  device_id: string;
  device_name: string;
  lifecycle_state: string;
  os_build: string | null;
}

interface TeamMember {
  id: string;
  display_name: string;
  email: string;
  role: Role;
  account_status: AccountStatus;
  device_access: string[];
}

type PermissionsMatrix = Record<Role, Record<string, boolean>>;

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
    const message =
      typeof payload.message === 'string'
        ? payload.message
        : typeof (payload.error as { message?: string } | undefined)?.message === 'string'
        ? ((payload.error as { message: string }).message)
        : 'request_failed';
    throw new Error(message);
  }
  return payload as unknown as T;
}

const TAB_ITEMS: Array<{ key: SettingsTab; label: string; icon: React.ElementType }> = [
  { key: 'alert-rules', label: 'Alert Rules', icon: Bell },
  { key: 'app-lock', label: 'App Lock', icon: Lock },
  { key: 'policy-editor', label: 'Policy Editor', icon: Shield },
  { key: 'compliance-thresholds', label: 'Compliance Thresholds', icon: ShieldCheck },
  { key: 'roles-permissions', label: 'Roles & Permissions', icon: Users },
  { key: 'team-members', label: 'Team Members', icon: Users },
];

const BASE_PERMISSION_KEYS = [
  'view_devices',
  'manage_devices',
  'send_commands',
  'send_sensitive_commands',
  'view_alerts',
  'acknowledge_alerts',
  'view_compliance',
  'manage_compliance',
  'view_audit',
  'manage_users',
  'manage_settings',
  'export_data',
  'pair_devices',
];

function prettyPermission(value: string): string {
  return value
    .split('_')
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(' ');
}

function severityClass(severity: Severity): string {
  if (severity === 'critical') return 'bg-red-500/20 text-red-400 border-red-500/30';
  if (severity === 'warning') return 'bg-amber-500/20 text-amber-400 border-amber-500/30';
  return 'bg-blue-500/20 text-blue-400 border-blue-500/30';
}

export default function SettingsContent() {
  const [activeTab, setActiveTab] = useState<SettingsTab>('alert-rules');
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const inFlightRef = useRef(false);

  const [alertRules, setAlertRules] = useState<AlertRule[]>([]);
  const [policyEntries, setPolicyEntries] = useState<PolicyEntry[]>([]);
  const [thresholds, setThresholds] = useState<ComplianceThreshold[]>([]);
  const [permissions, setPermissions] = useState<PermissionsMatrix>({
    admin: {},
    operator: {},
    viewer: {},
  });
  const [members, setMembers] = useState<TeamMember[]>([]);
  const [devices, setDevices] = useState<TeamDevice[]>([]);

  const [newRule, setNewRule] = useState({
    name: '',
    condition: '',
    severity: 'warning' as Severity,
    channelsCsv: 'email',
  });
  const [newThreshold, setNewThreshold] = useState({
    control: '',
    metric: '',
    threshold: '',
    unit: '',
    severity: 'warning' as 'critical' | 'warning',
  });
  const [newMember, setNewMember] = useState({
    display_name: '',
    email: '',
    role: 'viewer' as Role,
    account_status: 'pending' as AccountStatus,
  });

  const [expandedMemberId, setExpandedMemberId] = useState<string | null>(null);
  const [memberDrafts, setMemberDrafts] = useState<Record<string, TeamMember>>({});
  const [roleDrafts, setRoleDrafts] = useState<PermissionsMatrix>({
    admin: {},
    operator: {},
    viewer: {},
  });

  const loadAll = useCallback(async (showLoader: boolean) => {
    if (inFlightRef.current) {
      return;
    }
    inFlightRef.current = true;
    if (showLoader) setLoading(true);
    setRefreshing(true);
    try {
      const [
        rulesRes,
        policyRes,
        thresholdsRes,
        matrixRes,
        membersRes,
      ] = await Promise.all([
        requestJson<{ rules: AlertRule[] }>('/api/settings/alert-rules'),
        requestJson<{ entries: PolicyEntry[] }>('/api/settings/policy-entries'),
        requestJson<{ thresholds: ComplianceThreshold[] }>('/api/settings/compliance-thresholds'),
        requestJson<{ matrix: PermissionsMatrix }>('/api/settings/roles/permissions'),
        requestJson<{ members: TeamMember[]; devices: TeamDevice[] }>('/api/settings/team-members'),
      ]);

      const matrix = matrixRes.matrix ?? { admin: {}, operator: {}, viewer: {} };
      setAlertRules(rulesRes.rules ?? []);
      setPolicyEntries(policyRes.entries ?? []);
      setThresholds(thresholdsRes.thresholds ?? []);
      setPermissions(matrix);
      setRoleDrafts(matrix);
      setMembers(membersRes.members ?? []);
      setDevices(membersRes.devices ?? []);
      setMemberDrafts(
        (membersRes.members ?? []).reduce<Record<string, TeamMember>>((acc, member) => {
          acc[member.id] = { ...member };
          return acc;
        }, {}),
      );
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'failed_to_load_settings');
    } finally {
      inFlightRef.current = false;
      setLoading(false);
      setRefreshing(false);
    }
  }, []);

  useEffect(() => {
    void loadAll(true);
  }, [loadAll]);

  useEffect(() => {
    let timer: ReturnType<typeof setInterval> | null = null;

    const schedulePoll = () => {
      if (timer) {
        clearInterval(timer);
      }
      const intervalMs = document.hidden ? 30000 : 5000;
      timer = setInterval(() => {
        void loadAll(false);
      }, intervalMs);
    };

    const handleVisibility = () => {
      schedulePoll();
      void loadAll(false);
    };

    schedulePoll();
    document.addEventListener('visibilitychange', handleVisibility);
    return () => {
      if (timer) {
        clearInterval(timer);
      }
      document.removeEventListener('visibilitychange', handleVisibility);
    };
  }, [loadAll]);

  const permissionKeys = useMemo(() => {
    const dynamic = new Set<string>(BASE_PERMISSION_KEYS);
    (Object.values(permissions) as Array<Record<string, boolean>>).forEach((matrix) => {
      Object.keys(matrix ?? {}).forEach((key) => dynamic.add(key));
    });
    return Array.from(dynamic.values()).sort();
  }, [permissions]);

  const handleCreateAlertRule = async (): Promise<void> => {
    const channels = newRule.channelsCsv
      .split(',')
      .map((item) => item.trim())
      .filter(Boolean);
    if (!newRule.name.trim() || !newRule.condition.trim()) {
      toast.error('Name and condition are required');
      return;
    }

    try {
      const payload = await requestJson<{ rule: AlertRule }>('/api/settings/alert-rules', {
        method: 'POST',
        body: JSON.stringify({
          name: newRule.name.trim(),
          condition: newRule.condition.trim(),
          severity: newRule.severity,
          channels,
          enabled: true,
        }),
      });
      setAlertRules((prev) => [payload.rule, ...prev]);
      setNewRule({ name: '', condition: '', severity: 'warning', channelsCsv: 'email' });
      toast.success('Alert rule created');
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'failed_to_create_rule');
    }
  };

  const handleUpdateAlertRule = async (rule: AlertRule, patch: Partial<AlertRule>): Promise<void> => {
    try {
      const payload = await requestJson<{ rule: AlertRule }>(`/api/settings/alert-rules/${rule.id}`, {
        method: 'PATCH',
        body: JSON.stringify(patch),
      });
      setAlertRules((prev) => prev.map((item) => (item.id === rule.id ? payload.rule : item)));
      toast.success('Alert rule updated');
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'failed_to_update_rule');
    }
  };

  const handleDeleteAlertRule = async (id: string): Promise<void> => {
    try {
      await requestJson<{ status: string }>(`/api/settings/alert-rules/${id}`, { method: 'DELETE' });
      setAlertRules((prev) => prev.filter((item) => item.id !== id));
      toast.success('Alert rule deleted');
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'failed_to_delete_rule');
    }
  };

  const handleUpdatePolicy = async (entry: PolicyEntry, value: string): Promise<void> => {
    try {
      const payload = await requestJson<{ entry: PolicyEntry }>(`/api/settings/policy-entries/${entry.id}`, {
        method: 'PATCH',
        body: JSON.stringify({ policy_value: value }),
      });
      setPolicyEntries((prev) => prev.map((item) => (item.id === entry.id ? payload.entry : item)));
      toast.success('Policy updated');
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'failed_to_update_policy');
    }
  };

  const handleCreateThreshold = async (): Promise<void> => {
    if (!newThreshold.control.trim() || !newThreshold.metric.trim() || newThreshold.threshold === '') {
      toast.error('Control, metric and threshold are required');
      return;
    }
    try {
      const payload = await requestJson<{ threshold: ComplianceThreshold }>('/api/settings/compliance-thresholds', {
        method: 'POST',
        body: JSON.stringify({
          control: newThreshold.control.trim(),
          metric: newThreshold.metric.trim(),
          threshold: Number(newThreshold.threshold),
          unit: newThreshold.unit.trim() || null,
          severity: newThreshold.severity,
          enabled: true,
        }),
      });
      setThresholds((prev) => [...prev, payload.threshold]);
      setNewThreshold({ control: '', metric: '', threshold: '', unit: '', severity: 'warning' });
      toast.success('Compliance threshold created');
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'failed_to_create_threshold');
    }
  };

  const handleUpdateThreshold = async (
    threshold: ComplianceThreshold,
    patch: Partial<ComplianceThreshold>,
  ): Promise<void> => {
    try {
      const payload = await requestJson<{ threshold: ComplianceThreshold }>(
        `/api/settings/compliance-thresholds/${threshold.id}`,
        {
          method: 'PATCH',
          body: JSON.stringify(patch),
        },
      );
      setThresholds((prev) => prev.map((item) => (item.id === threshold.id ? payload.threshold : item)));
      toast.success('Compliance threshold updated');
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'failed_to_update_threshold');
    }
  };

  const handleDeleteThreshold = async (id: string): Promise<void> => {
    try {
      await requestJson<{ status: string }>(`/api/settings/compliance-thresholds/${id}`, { method: 'DELETE' });
      setThresholds((prev) => prev.filter((item) => item.id !== id));
      toast.success('Compliance threshold deleted');
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'failed_to_delete_threshold');
    }
  };

  const handleTogglePermission = (role: Role, key: string): void => {
    setRoleDrafts((prev) => ({
      ...prev,
      [role]: {
        ...prev[role],
        [key]: !(prev[role]?.[key] ?? false),
      },
    }));
  };

  const handleSaveRolePermissions = async (role: Role): Promise<void> => {
    try {
      const payload = await requestJson<{ role: string; permissions: Record<string, boolean> }>(
        `/api/settings/roles/${role}/permissions`,
        {
          method: 'PATCH',
          body: JSON.stringify({ permissions: roleDrafts[role] }),
        },
      );
      setPermissions((prev) => ({ ...prev, [role]: payload.permissions }));
      setRoleDrafts((prev) => ({ ...prev, [role]: payload.permissions }));
      toast.success(`${role} permissions updated`);
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'failed_to_update_permissions');
    }
  };

  const handleCreateMember = async (): Promise<void> => {
    if (!newMember.display_name.trim() || !newMember.email.trim()) {
      toast.error('Display name and email are required');
      return;
    }
    try {
      const payload = await requestJson<{ member: TeamMember }>('/api/settings/team-members', {
        method: 'POST',
        body: JSON.stringify({
          ...newMember,
          display_name: newMember.display_name.trim(),
          email: newMember.email.trim(),
          device_access: [],
        }),
      });
      setMembers((prev) => [payload.member, ...prev]);
      setMemberDrafts((prev) => ({ ...prev, [payload.member.id]: { ...payload.member } }));
      setNewMember({ display_name: '', email: '', role: 'viewer', account_status: 'pending' });
      toast.success('Team member created');
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'failed_to_create_member');
    }
  };

  const updateMemberDraft = (memberId: string, patch: Partial<TeamMember>): void => {
    setMemberDrafts((prev) => ({
      ...prev,
      [memberId]: {
        ...prev[memberId],
        ...patch,
      },
    }));
  };

  const toggleMemberDevice = (memberId: string, deviceId: string): void => {
    const draft = memberDrafts[memberId];
    if (!draft) return;
    const exists = draft.device_access.includes(deviceId);
    const next = exists
      ? draft.device_access.filter((id) => id !== deviceId)
      : [...draft.device_access, deviceId];
    updateMemberDraft(memberId, { device_access: next });
  };

  const handleSaveMember = async (memberId: string): Promise<void> => {
    const draft = memberDrafts[memberId];
    if (!draft) return;
    try {
      const payload = await requestJson<{ member: TeamMember }>(`/api/settings/team-members/${memberId}`, {
        method: 'PATCH',
        body: JSON.stringify({
          display_name: draft.display_name,
          role: draft.role,
          account_status: draft.account_status,
          device_access: draft.device_access,
        }),
      });
      setMembers((prev) => prev.map((item) => (item.id === memberId ? payload.member : item)));
      setMemberDrafts((prev) => ({ ...prev, [memberId]: { ...payload.member } }));
      toast.success('Team member updated');
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'failed_to_update_member');
    }
  };

  const handleActivateMember = async (memberId: string): Promise<void> => {
    try {
      const payload = await requestJson<{ member: TeamMember }>(`/api/settings/team-members/${memberId}/activate`, {
        method: 'POST',
        body: '{}',
      });
      setMembers((prev) => prev.map((item) => (item.id === memberId ? payload.member : item)));
      setMemberDrafts((prev) => ({ ...prev, [memberId]: { ...payload.member } }));
      toast.success('Member activated');
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'failed_to_activate_member');
    }
  };

  const handleDeactivateMember = async (memberId: string): Promise<void> => {
    try {
      const payload = await requestJson<{ member: TeamMember }>(`/api/settings/team-members/${memberId}/deactivate`, {
        method: 'POST',
        body: '{}',
      });
      setMembers((prev) => prev.map((item) => (item.id === memberId ? payload.member : item)));
      setMemberDrafts((prev) => ({ ...prev, [memberId]: { ...payload.member } }));
      toast.success('Member deactivated');
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'failed_to_deactivate_member');
    }
  };

  const statusColor = (status: AccountStatus): string => {
    if (status === 'active') return 'text-green-400';
    if (status === 'inactive') return 'text-muted-foreground';
    return 'text-amber-400';
  };

  return (
    <div className="space-y-6 fade-in">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">Settings</h1>
          <p className="text-sm text-muted-foreground mt-0.5">
            Admin-controlled system configuration with live backend enforcement
          </p>
        </div>
        <div className="flex items-center gap-2">
          <button
            onClick={() => void loadAll(false)}
            className="flex items-center gap-1.5 px-3 py-1.5 text-xs text-muted-foreground border border-border rounded-md hover:bg-muted/60 transition-colors"
          >
            <RefreshCw size={13} className={refreshing ? 'animate-spin' : ''} />
            Refresh
          </button>
          <div className="flex items-center gap-2 text-xs text-amber-400 bg-amber-500/10 border border-amber-500/20 rounded-md px-3 py-1.5">
            <AlertTriangle size={12} />
            Admin Only
          </div>
        </div>
      </div>

      <div className="flex items-center gap-1 bg-muted/30 rounded-lg p-1 flex-wrap">
        {TAB_ITEMS.map((tab) => (
          <button
            key={tab.key}
            onClick={() => setActiveTab(tab.key)}
            className={`flex items-center gap-1.5 px-3 py-1.5 rounded-md text-xs font-medium transition-all ${
              activeTab === tab.key
                ? 'bg-card text-foreground shadow-sm'
                : 'text-muted-foreground hover:text-foreground'
            }`}
          >
            <tab.icon size={13} />
            {tab.label}
          </button>
        ))}
      </div>

      {loading ? (
        <div className="bg-card border border-border rounded-lg p-8 text-sm text-muted-foreground text-center">
          Loading settings...
        </div>
      ) : (
        <>
          {activeTab === 'alert-rules' && (
            <div className="space-y-4">
              <div className="bg-card border border-border rounded-lg p-4 space-y-3">
                <h3 className="text-sm font-semibold">Create Alert Rule</h3>
                <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                  <input
                    value={newRule.name}
                    onChange={(event) => setNewRule((prev) => ({ ...prev, name: event.target.value }))}
                    placeholder="Rule name"
                    className="px-3 py-2 text-xs bg-muted/40 border border-border rounded-md"
                  />
                  <select
                    value={newRule.severity}
                    onChange={(event) =>
                      setNewRule((prev) => ({ ...prev, severity: event.target.value as Severity }))
                    }
                    className="px-3 py-2 text-xs bg-muted/40 border border-border rounded-md"
                  >
                    <option value="critical">critical</option>
                    <option value="warning">warning</option>
                    <option value="info">info</option>
                  </select>
                  <input
                    value={newRule.condition}
                    onChange={(event) => setNewRule((prev) => ({ ...prev, condition: event.target.value }))}
                    placeholder='condition, e.g. device.attestation_status == "failed"'
                    className="md:col-span-2 px-3 py-2 text-xs bg-muted/40 border border-border rounded-md font-mono"
                  />
                  <input
                    value={newRule.channelsCsv}
                    onChange={(event) => setNewRule((prev) => ({ ...prev, channelsCsv: event.target.value }))}
                    placeholder="channels (comma separated), e.g. email,webhook"
                    className="md:col-span-2 px-3 py-2 text-xs bg-muted/40 border border-border rounded-md"
                  />
                </div>
                <button
                  onClick={() => void handleCreateAlertRule()}
                  className="flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium bg-primary/10 border border-primary/30 text-primary rounded-md hover:bg-primary/20 transition-colors"
                >
                  <Plus size={12} />
                  Add Rule
                </button>
              </div>

              <div className="space-y-2">
                {alertRules.map((rule) => (
                  <AlertRuleRow
                    key={rule.id}
                    rule={rule}
                    onSave={(patch) => void handleUpdateAlertRule(rule, patch)}
                    onDelete={() => void handleDeleteAlertRule(rule.id)}
                  />
                ))}
                {alertRules.length === 0 && (
                  <div className="bg-card border border-border rounded-lg p-6 text-xs text-muted-foreground text-center">
                    No alert rules configured.
                  </div>
                )}
              </div>
            </div>
          )}

          {activeTab === 'app-lock' && <AppLockManagerSection />}

          {activeTab === 'policy-editor' && (
            <div className="bg-card border border-border rounded-lg overflow-hidden">
              <table className="w-full text-xs">
                <thead>
                  <tr className="border-b border-border bg-muted/20">
                    <th className="px-4 py-2.5 text-left text-[10px] uppercase tracking-wide text-muted-foreground">
                      Policy Key
                    </th>
                    <th className="px-4 py-2.5 text-left text-[10px] uppercase tracking-wide text-muted-foreground">
                      Value
                    </th>
                    <th className="px-4 py-2.5 text-left text-[10px] uppercase tracking-wide text-muted-foreground hidden md:table-cell">
                      Description
                    </th>
                    <th className="px-4 py-2.5 text-left text-[10px] uppercase tracking-wide text-muted-foreground hidden lg:table-cell">
                      Scope
                    </th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-border">
                  {policyEntries.map((entry) => (
                    <PolicyEntryRow
                      key={entry.id}
                      entry={entry}
                      onSave={(value) => void handleUpdatePolicy(entry, value)}
                    />
                  ))}
                  {policyEntries.length === 0 && (
                    <tr>
                      <td colSpan={4} className="px-4 py-6 text-center text-muted-foreground">
                        No policy entries available.
                      </td>
                    </tr>
                  )}
                </tbody>
              </table>
            </div>
          )}

          {activeTab === 'compliance-thresholds' && (
            <div className="space-y-4">
              <div className="bg-card border border-border rounded-lg p-4 space-y-3">
                <h3 className="text-sm font-semibold">Create Compliance Threshold</h3>
                <div className="grid grid-cols-1 md:grid-cols-5 gap-3">
                  <input
                    value={newThreshold.control}
                    onChange={(event) =>
                      setNewThreshold((prev) => ({ ...prev, control: event.target.value }))
                    }
                    placeholder="Control"
                    className="px-3 py-2 text-xs bg-muted/40 border border-border rounded-md"
                  />
                  <input
                    value={newThreshold.metric}
                    onChange={(event) =>
                      setNewThreshold((prev) => ({ ...prev, metric: event.target.value }))
                    }
                    placeholder="Metric"
                    className="px-3 py-2 text-xs bg-muted/40 border border-border rounded-md"
                  />
                  <input
                    type="number"
                    value={newThreshold.threshold}
                    onChange={(event) =>
                      setNewThreshold((prev) => ({ ...prev, threshold: event.target.value }))
                    }
                    placeholder="Threshold"
                    className="px-3 py-2 text-xs bg-muted/40 border border-border rounded-md"
                  />
                  <input
                    value={newThreshold.unit}
                    onChange={(event) =>
                      setNewThreshold((prev) => ({ ...prev, unit: event.target.value }))
                    }
                    placeholder="Unit"
                    className="px-3 py-2 text-xs bg-muted/40 border border-border rounded-md"
                  />
                  <select
                    value={newThreshold.severity}
                    onChange={(event) =>
                      setNewThreshold((prev) => ({
                        ...prev,
                        severity: event.target.value as 'critical' | 'warning',
                      }))
                    }
                    className="px-3 py-2 text-xs bg-muted/40 border border-border rounded-md"
                  >
                    <option value="critical">critical</option>
                    <option value="warning">warning</option>
                  </select>
                </div>
                <button
                  onClick={() => void handleCreateThreshold()}
                  className="flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium bg-primary/10 border border-primary/30 text-primary rounded-md hover:bg-primary/20 transition-colors"
                >
                  <Plus size={12} />
                  Add Threshold
                </button>
              </div>

              <div className="space-y-2">
                {thresholds.map((threshold) => (
                  <ComplianceThresholdRow
                    key={threshold.id}
                    threshold={threshold}
                    onSave={(patch) => void handleUpdateThreshold(threshold, patch)}
                    onDelete={() => void handleDeleteThreshold(threshold.id)}
                  />
                ))}
                {thresholds.length === 0 && (
                  <div className="bg-card border border-border rounded-lg p-6 text-xs text-muted-foreground text-center">
                    No compliance thresholds configured.
                  </div>
                )}
              </div>
            </div>
          )}

          {activeTab === 'roles-permissions' && (
            <div className="space-y-3">
              {(['admin', 'operator', 'viewer'] as Role[]).map((role) => (
                <div key={role} className="bg-card border border-border rounded-lg p-4">
                  <div className="flex items-center justify-between mb-3">
                    <h3 className="text-sm font-semibold capitalize">{role}</h3>
                    <button
                      onClick={() => void handleSaveRolePermissions(role)}
                      className="flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium bg-primary/10 border border-primary/30 text-primary rounded-md hover:bg-primary/20 transition-colors"
                    >
                      <Save size={12} />
                      Save
                    </button>
                  </div>
                  <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-2">
                    {permissionKeys.map((permission) => {
                      const checked = Boolean(roleDrafts[role]?.[permission]);
                      return (
                        <label
                          key={`${role}-${permission}`}
                          className={`flex items-center gap-2 px-2.5 py-2 rounded border cursor-pointer ${
                            checked ? 'border-primary/40 bg-primary/5' : 'border-border bg-muted/20'
                          }`}
                        >
                          <input
                            type="checkbox"
                            checked={checked}
                            onChange={() => handleTogglePermission(role, permission)}
                            className="w-3 h-3 accent-primary"
                          />
                          <span className="text-xs">{prettyPermission(permission)}</span>
                        </label>
                      );
                    })}
                  </div>
                </div>
              ))}
            </div>
          )}

          {activeTab === 'team-members' && (
            <div className="space-y-4">
              <div className="bg-card border border-border rounded-lg p-4 space-y-3">
                <h3 className="text-sm font-semibold">Add Team Member</h3>
                <div className="grid grid-cols-1 md:grid-cols-4 gap-3">
                  <input
                    value={newMember.display_name}
                    onChange={(event) =>
                      setNewMember((prev) => ({ ...prev, display_name: event.target.value }))
                    }
                    placeholder="Display name"
                    className="px-3 py-2 text-xs bg-muted/40 border border-border rounded-md"
                  />
                  <input
                    value={newMember.email}
                    onChange={(event) => setNewMember((prev) => ({ ...prev, email: event.target.value }))}
                    placeholder="Email"
                    className="px-3 py-2 text-xs bg-muted/40 border border-border rounded-md"
                  />
                  <select
                    value={newMember.role}
                    onChange={(event) =>
                      setNewMember((prev) => ({ ...prev, role: event.target.value as Role }))
                    }
                    className="px-3 py-2 text-xs bg-muted/40 border border-border rounded-md"
                  >
                    <option value="admin">admin</option>
                    <option value="operator">operator</option>
                    <option value="viewer">viewer</option>
                  </select>
                  <select
                    value={newMember.account_status}
                    onChange={(event) =>
                      setNewMember((prev) => ({
                        ...prev,
                        account_status: event.target.value as AccountStatus,
                      }))
                    }
                    className="px-3 py-2 text-xs bg-muted/40 border border-border rounded-md"
                  >
                    <option value="active">active</option>
                    <option value="pending">pending</option>
                    <option value="inactive">inactive</option>
                  </select>
                </div>
                <button
                  onClick={() => void handleCreateMember()}
                  className="flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium bg-primary/10 border border-primary/30 text-primary rounded-md hover:bg-primary/20 transition-colors"
                >
                  <Plus size={12} />
                  Create Member
                </button>
              </div>

              <div className="space-y-2">
                {members.map((member) => {
                  const draft = memberDrafts[member.id] ?? member;
                  const expanded = expandedMemberId === member.id;
                  return (
                    <div key={member.id} className="bg-card border border-border rounded-lg">
                      <div className="px-4 py-3 flex items-center justify-between gap-3">
                        <div>
                          <p className="text-sm font-medium">{member.display_name}</p>
                          <p className="text-xs text-muted-foreground">{member.email}</p>
                        </div>
                        <div className="flex items-center gap-2">
                          <span className={`text-xs font-semibold capitalize ${statusColor(member.account_status)}`}>
                            {member.account_status}
                          </span>
                          <button
                            onClick={() =>
                              setExpandedMemberId((current) => (current === member.id ? null : member.id))
                            }
                            className="flex items-center gap-1 px-2 py-1 text-xs border border-border rounded hover:bg-muted/50"
                          >
                            <Edit2 size={11} />
                            Manage
                          </button>
                        </div>
                      </div>

                      {expanded && (
                        <div className="px-4 pb-4 space-y-3 border-t border-border/60 pt-3">
                          <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
                            <input
                              value={draft.display_name}
                              onChange={(event) =>
                                updateMemberDraft(member.id, { display_name: event.target.value })
                              }
                              className="px-3 py-2 text-xs bg-muted/40 border border-border rounded-md"
                            />
                            <select
                              value={draft.role}
                              onChange={(event) =>
                                updateMemberDraft(member.id, { role: event.target.value as Role })
                              }
                              className="px-3 py-2 text-xs bg-muted/40 border border-border rounded-md"
                            >
                              <option value="admin">admin</option>
                              <option value="operator">operator</option>
                              <option value="viewer">viewer</option>
                            </select>
                            <select
                              value={draft.account_status}
                              onChange={(event) =>
                                updateMemberDraft(member.id, { account_status: event.target.value as AccountStatus })
                              }
                              className="px-3 py-2 text-xs bg-muted/40 border border-border rounded-md"
                            >
                              <option value="active">active</option>
                              <option value="pending">pending</option>
                              <option value="inactive">inactive</option>
                            </select>
                          </div>

                          <div className="bg-muted/20 border border-border rounded-lg p-3">
                            <p className="text-xs font-semibold mb-2">Device Access</p>
                            <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-2 max-h-56 overflow-auto">
                              {devices.map((device) => {
                                const granted = draft.device_access.includes(device.device_id);
                                return (
                                  <label
                                    key={`${member.id}-${device.device_id}`}
                                    className={`flex items-center justify-between px-2.5 py-2 rounded border cursor-pointer ${
                                      granted
                                        ? 'border-primary/40 bg-primary/5'
                                        : 'border-border bg-card'
                                    }`}
                                  >
                                    <div className="min-w-0">
                                      <p className="text-xs font-medium truncate">{device.device_name}</p>
                                      <p className="text-[10px] text-muted-foreground truncate">
                                        {device.device_id}
                                      </p>
                                    </div>
                                    <input
                                      type="checkbox"
                                      checked={granted}
                                      onChange={() => toggleMemberDevice(member.id, device.device_id)}
                                      className="w-3 h-3 accent-primary"
                                    />
                                  </label>
                                );
                              })}
                            </div>
                          </div>

                          <div className="flex items-center gap-2">
                            <button
                              onClick={() => void handleSaveMember(member.id)}
                              className="flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium bg-primary/10 border border-primary/30 text-primary rounded-md hover:bg-primary/20 transition-colors"
                            >
                              <Save size={12} />
                              Save Member
                            </button>
                            {member.account_status !== 'active' ? (
                              <button
                                onClick={() => void handleActivateMember(member.id)}
                                className="flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium border border-green-500/30 text-green-400 rounded-md hover:bg-green-500/10 transition-colors"
                              >
                                <UserCheck size={12} />
                                Activate
                              </button>
                            ) : (
                              <button
                                onClick={() => void handleDeactivateMember(member.id)}
                                className="flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium border border-red-500/30 text-red-400 rounded-md hover:bg-red-500/10 transition-colors"
                              >
                                <UserX size={12} />
                                Deactivate
                              </button>
                            )}
                          </div>
                        </div>
                      )}
                    </div>
                  );
                })}
                {members.length === 0 && (
                  <div className="bg-card border border-border rounded-lg p-6 text-xs text-muted-foreground text-center">
                    No team members found.
                  </div>
                )}
              </div>
            </div>
          )}
        </>
      )}
    </div>
  );
}

function AlertRuleRow({
  rule,
  onSave,
  onDelete,
}: {
  rule: AlertRule;
  onSave: (patch: Partial<AlertRule>) => void;
  onDelete: () => void;
}) {
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState(rule);

  useEffect(() => {
    setDraft(rule);
  }, [rule]);

  const save = (): void => {
    onSave({
      name: draft.name,
      condition: draft.condition,
      severity: draft.severity,
      channels: draft.channels,
      enabled: draft.enabled,
    });
    setEditing(false);
  };

  return (
    <div className={`bg-card border rounded-lg p-4 ${rule.enabled ? 'border-border' : 'border-border/40 opacity-70'}`}>
      {editing ? (
        <div className="space-y-3">
          <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
            <input
              value={draft.name}
              onChange={(event) => setDraft((prev) => ({ ...prev, name: event.target.value }))}
              className="px-3 py-2 text-xs bg-muted/40 border border-border rounded-md"
            />
            <select
              value={draft.severity}
              onChange={(event) => setDraft((prev) => ({ ...prev, severity: event.target.value as Severity }))}
              className="px-3 py-2 text-xs bg-muted/40 border border-border rounded-md"
            >
              <option value="critical">critical</option>
              <option value="warning">warning</option>
              <option value="info">info</option>
            </select>
          </div>
          <input
            value={draft.condition}
            onChange={(event) => setDraft((prev) => ({ ...prev, condition: event.target.value }))}
            className="px-3 py-2 text-xs bg-muted/40 border border-border rounded-md font-mono w-full"
          />
          <input
            value={draft.channels.join(',')}
            onChange={(event) =>
              setDraft((prev) => ({
                ...prev,
                channels: event.target.value
                  .split(',')
                  .map((item) => item.trim())
                  .filter(Boolean),
              }))
            }
            className="px-3 py-2 text-xs bg-muted/40 border border-border rounded-md w-full"
          />
          <div className="flex items-center gap-2">
            <button
              onClick={save}
              className="flex items-center gap-1 px-2.5 py-1 text-xs bg-green-500/10 border border-green-500/20 text-green-400 rounded-md hover:bg-green-500/20 transition-colors"
            >
              <Save size={11} />
              Save
            </button>
            <button
              onClick={() => setEditing(false)}
              className="px-2.5 py-1 text-xs border border-border rounded-md text-muted-foreground hover:bg-muted/60"
            >
              Cancel
            </button>
          </div>
        </div>
      ) : (
        <div className="flex items-center gap-3">
          <div className="flex-1 min-w-0">
            <div className="flex items-center gap-2 flex-wrap">
              <span className="text-sm font-medium">{rule.name}</span>
              <span className={`text-[10px] font-semibold px-2 py-0.5 rounded-full border ${severityClass(rule.severity)}`}>
                {rule.severity.toUpperCase()}
              </span>
              <span className="text-[10px] text-muted-foreground bg-muted/40 px-1.5 py-0.5 rounded">
                {(rule.channels ?? []).join(', ') || 'none'}
              </span>
            </div>
            <p className="font-mono text-[11px] text-muted-foreground mt-0.5 truncate">{rule.condition}</p>
          </div>
          <div className="flex items-center gap-1.5">
            <button
              onClick={() => setEditing(true)}
              className="p-1.5 rounded text-muted-foreground hover:text-foreground hover:bg-muted transition-colors"
            >
              <Edit2 size={12} />
            </button>
            <button
              onClick={onDelete}
              className="p-1.5 rounded text-muted-foreground hover:text-red-400 hover:bg-red-500/10 transition-colors"
            >
              <Trash2 size={12} />
            </button>
            <button
              onClick={() => onSave({ enabled: !rule.enabled })}
              className="p-1 rounded transition-colors"
            >
              {rule.enabled ? (
                <ToggleRight size={22} className="text-primary" />
              ) : (
                <ToggleLeft size={22} className="text-muted-foreground" />
              )}
            </button>
          </div>
        </div>
      )}
    </div>
  );
}

function PolicyEntryRow({
  entry,
  onSave,
}: {
  entry: PolicyEntry;
  onSave: (value: string) => void;
}) {
  const [editing, setEditing] = useState(false);
  const [value, setValue] = useState(entry.policy_value ?? '');

  return (
    <tr className="hover:bg-muted/10 transition-colors">
      <td className="px-4 py-2.5">
        <span className="font-mono text-[11px] text-primary">{entry.policy_key}</span>
      </td>
      <td className="px-4 py-2.5">
        {editing ? (
          <div className="flex items-center gap-1.5">
            <input
              value={value}
              onChange={(event) => setValue(event.target.value)}
              className="px-2 py-1 text-xs bg-muted/60 border border-primary/40 rounded font-mono"
            />
            <button
              onClick={() => {
                onSave(value);
                setEditing(false);
              }}
              className="p-1 text-green-400 hover:text-green-300"
            >
              <Save size={12} />
            </button>
          </div>
        ) : (
          <span className="font-mono text-[11px]">{entry.policy_value ?? ''}</span>
        )}
      </td>
      <td className="px-4 py-2.5 text-muted-foreground hidden md:table-cell">{entry.description ?? '—'}</td>
      <td className="px-4 py-2.5 hidden lg:table-cell">
        <div className="flex items-center justify-between gap-2">
          <span className="text-[11px] text-muted-foreground">{entry.scope}</span>
          {entry.is_mutable ? (
            <button
              onClick={() => {
                if (!editing) {
                  setValue(entry.policy_value ?? '');
                }
                setEditing((prev) => !prev);
              }}
              className="p-1.5 rounded text-muted-foreground hover:text-foreground hover:bg-muted"
            >
              <Edit2 size={12} />
            </button>
          ) : (
            <Lock size={11} className="text-muted-foreground/40" />
          )}
        </div>
      </td>
    </tr>
  );
}

function ComplianceThresholdRow({
  threshold,
  onSave,
  onDelete,
}: {
  threshold: ComplianceThreshold;
  onSave: (patch: Partial<ComplianceThreshold>) => void;
  onDelete: () => void;
}) {
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState(threshold);

  useEffect(() => {
    setDraft(threshold);
  }, [threshold]);

  return (
    <div className="bg-card border border-border rounded-lg p-4">
      {editing ? (
        <div className="space-y-3">
          <div className="grid grid-cols-1 md:grid-cols-5 gap-3">
            <input
              value={draft.control}
              onChange={(event) => setDraft((prev) => ({ ...prev, control: event.target.value }))}
              className="px-3 py-2 text-xs bg-muted/40 border border-border rounded-md"
            />
            <input
              value={draft.metric}
              onChange={(event) => setDraft((prev) => ({ ...prev, metric: event.target.value }))}
              className="px-3 py-2 text-xs bg-muted/40 border border-border rounded-md"
            />
            <input
              type="number"
              value={draft.threshold}
              onChange={(event) =>
                setDraft((prev) => ({ ...prev, threshold: Number(event.target.value || 0) }))
              }
              className="px-3 py-2 text-xs bg-muted/40 border border-border rounded-md"
            />
            <input
              value={draft.unit ?? ''}
              onChange={(event) => setDraft((prev) => ({ ...prev, unit: event.target.value }))}
              className="px-3 py-2 text-xs bg-muted/40 border border-border rounded-md"
            />
            <select
              value={draft.severity}
              onChange={(event) =>
                setDraft((prev) => ({ ...prev, severity: event.target.value as 'critical' | 'warning' }))
              }
              className="px-3 py-2 text-xs bg-muted/40 border border-border rounded-md"
            >
              <option value="critical">critical</option>
              <option value="warning">warning</option>
            </select>
          </div>
          <div className="flex items-center gap-2">
            <button
              onClick={() => {
                onSave({
                  control: draft.control,
                  metric: draft.metric,
                  threshold: draft.threshold,
                  unit: draft.unit,
                  severity: draft.severity,
                  enabled: draft.enabled,
                });
                setEditing(false);
              }}
              className="flex items-center gap-1 px-2.5 py-1 text-xs bg-green-500/10 border border-green-500/20 text-green-400 rounded-md hover:bg-green-500/20 transition-colors"
            >
              <Save size={11} />
              Save
            </button>
            <button
              onClick={() => setEditing(false)}
              className="px-2.5 py-1 text-xs border border-border rounded-md text-muted-foreground hover:bg-muted/60"
            >
              Cancel
            </button>
          </div>
        </div>
      ) : (
        <div className="flex items-center justify-between gap-3">
          <div className="min-w-0">
            <div className="flex items-center gap-2 flex-wrap">
              <span className="text-sm font-medium">{threshold.control}</span>
              <span className={`text-[10px] font-semibold px-2 py-0.5 rounded-full border ${severityClass(threshold.severity)}`}>
                {threshold.severity.toUpperCase()}
              </span>
              {threshold.enabled ? (
                <span className="text-[10px] text-green-400 bg-green-500/10 border border-green-500/20 px-1.5 py-0.5 rounded">
                  ENABLED
                </span>
              ) : (
                <span className="text-[10px] text-muted-foreground bg-muted/50 border border-border px-1.5 py-0.5 rounded">
                  DISABLED
                </span>
              )}
            </div>
            <p className="font-mono text-[11px] text-muted-foreground mt-0.5">
              {threshold.metric} {'>='} {threshold.threshold}
              {threshold.unit ? ` ${threshold.unit}` : ''}
            </p>
          </div>
          <div className="flex items-center gap-1.5">
            <button
              onClick={() => setEditing(true)}
              className="p-1.5 rounded text-muted-foreground hover:text-foreground hover:bg-muted transition-colors"
            >
              <Edit2 size={12} />
            </button>
            <button
              onClick={() => onSave({ enabled: !threshold.enabled })}
              className="p-1 rounded"
            >
              {threshold.enabled ? (
                <ToggleRight size={22} className="text-primary" />
              ) : (
                <ToggleLeft size={22} className="text-muted-foreground" />
              )}
            </button>
            <button
              onClick={onDelete}
              className="p-1.5 rounded text-muted-foreground hover:text-red-400 hover:bg-red-500/10 transition-colors"
            >
              <Trash2 size={12} />
            </button>
          </div>
        </div>
      )}
    </div>
  );
}

