'use client';
import React, { useState } from 'react';
import {
  Bell,
  Shield,
  ShieldCheck,
  Users,
  Plus,
  Trash2,
  Edit2,
  Save,
  X,
  ChevronDown,
  ChevronUp,
  ToggleLeft,
  ToggleRight,
  AlertTriangle,
  CheckCircle2,
  Lock,
  Eye,
  Terminal,
  Monitor,
  Share2,
  UserX,
  UserCheck,
  Search,
  MoreHorizontal,
} from 'lucide-react';
import { toast } from 'sonner';

// ─── Types ────────────────────────────────────────────────────────────────────

interface AlertRule {
  id: string;
  name: string;
  condition: string;
  severity: 'critical' | 'warning' | 'info';
  channel: string;
  enabled: boolean;
}

interface PolicyEntry {
  id: string;
  key: string;
  value: string;
  description: string;
  editable: boolean;
}

interface ComplianceThreshold {
  id: string;
  control: string;
  metric: string;
  threshold: number;
  unit: string;
  severity: 'critical' | 'warning';
}

interface RolePermission {
  role: 'admin' | 'operator' | 'viewer';
  permissions: Record<string, boolean>;
}

interface TeamMember {
  id: string;
  name: string;
  email: string;
  role: 'admin' | 'operator' | 'viewer';
  status: 'active' | 'inactive' | 'pending';
  lastActive: string;
  deviceAccess: string[]; // device IDs
}

interface DeviceEntry {
  id: string;
  hostname: string;
  os: string;
  status: 'online' | 'offline' | 'degraded';
}

// ─── Mock Data ────────────────────────────────────────────────────────────────

const initialAlertRules: AlertRule[] = [
  { id: 'AR-001', name: 'Attestation Failure', condition: 'device.attestation_status == "failed"', severity: 'critical', channel: 'email + webhook', enabled: true },
  { id: 'AR-002', name: 'Policy Hash Drift', condition: 'device.policy_hash != fleet.policy_hash', severity: 'warning', channel: 'email', enabled: true },
  { id: 'AR-003', name: 'High Risk Score', condition: 'device.risk_score > 0.7', severity: 'critical', channel: 'email + webhook', enabled: true },
  { id: 'AR-004', name: 'Device Offline > 5min', condition: 'device.last_seen > 300s', severity: 'warning', channel: 'email', enabled: false },
  { id: 'AR-005', name: 'Command Failure Rate', condition: 'commands.failure_rate > 0.3 (1h window)', severity: 'warning', channel: 'webhook', enabled: true },
  { id: 'AR-006', name: 'Kernel Guard Missing', condition: 'device.kernel_guard == false', severity: 'critical', channel: 'email + webhook', enabled: true },
];

const initialPolicies: PolicyEntry[] = [
  { id: 'POL-001', key: 'policy.version', value: 'policy-2026-04', description: 'Current active fleet policy version', editable: false },
  { id: 'POL-002', key: 'command.ttl_seconds', value: '300', description: 'Default command TTL before expiry', editable: true },
  { id: 'POL-003', key: 'command.require_2fa', value: 'true', description: 'Require 2FA for all sensitive commands', editable: true },
  { id: 'POL-004', key: 'agent.heartbeat_interval', value: '30', description: 'Agent heartbeat interval in seconds', editable: true },
  { id: 'POL-005', key: 'quarantine.auto_on_attestation_fail', value: 'true', description: 'Auto-quarantine device on attestation failure', editable: true },
  { id: 'POL-006', key: 'session.max_idle_minutes', value: '60', description: 'Max idle session duration before forced logout', editable: true },
  { id: 'POL-007', key: 'dispatch.signature_algo', value: 'Ed25519', description: 'Signing algorithm for command dispatch', editable: false },
];

const initialThresholds: ComplianceThreshold[] = [
  { id: 'CT-001', control: 'Risk Score', metric: 'device.risk_score', threshold: 70, unit: '/100', severity: 'critical' },
  { id: 'CT-002', control: 'Policy Drift', metric: 'fleet.drift_count', threshold: 5, unit: 'devices', severity: 'warning' },
  { id: 'CT-003', control: 'Offline Devices', metric: 'fleet.offline_pct', threshold: 20, unit: '%', severity: 'warning' },
  { id: 'CT-004', control: 'Compliance Score', metric: 'fleet.compliance_score', threshold: 75, unit: '%', severity: 'critical' },
  { id: 'CT-005', control: 'Heartbeat Lag', metric: 'device.heartbeat_lag', threshold: 60, unit: 'seconds', severity: 'warning' },
  { id: 'CT-006', control: 'Command Failure Rate', metric: 'commands.failure_rate', threshold: 30, unit: '%', severity: 'critical' },
];

const PERMISSION_KEYS = [
  { key: 'view_devices', label: 'View Devices' },
  { key: 'manage_devices', label: 'Manage Devices' },
  { key: 'send_commands', label: 'Send Commands' },
  { key: 'send_sensitive_commands', label: 'Sensitive Commands' },
  { key: 'view_alerts', label: 'View Alerts' },
  { key: 'acknowledge_alerts', label: 'Acknowledge Alerts' },
  { key: 'view_compliance', label: 'View Compliance' },
  { key: 'manage_compliance', label: 'Manage Compliance' },
  { key: 'view_audit', label: 'View Audit Trail' },
  { key: 'manage_users', label: 'Manage Users' },
  { key: 'manage_settings', label: 'Manage Settings' },
  { key: 'export_data', label: 'Export Data' },
];

const initialRoles: RolePermission[] = [
  {
    role: 'admin',
    permissions: {
      view_devices: true, manage_devices: true, send_commands: true, send_sensitive_commands: true,
      view_alerts: true, acknowledge_alerts: true, view_compliance: true, manage_compliance: true,
      view_audit: true, manage_users: true, manage_settings: true, export_data: true,
    },
  },
  {
    role: 'operator',
    permissions: {
      view_devices: true, manage_devices: false, send_commands: true, send_sensitive_commands: false,
      view_alerts: true, acknowledge_alerts: true, view_compliance: true, manage_compliance: false,
      view_audit: true, manage_users: false, manage_settings: false, export_data: true,
    },
  },
  {
    role: 'viewer',
    permissions: {
      view_devices: true, manage_devices: false, send_commands: false, send_sensitive_commands: false,
      view_alerts: true, acknowledge_alerts: false, view_compliance: true, manage_compliance: false,
      view_audit: true, manage_users: false, manage_settings: false, export_data: false,
    },
  },
];

const initialTeamMembers: TeamMember[] = [
  { id: 'USR-001', name: 'Admin User', email: 'admin@quoodle.io', role: 'admin', status: 'active', lastActive: '2 min ago', deviceAccess: ['PC001', 'PC002', 'WKSTN-042', 'WKSTN-007', 'WKSTN-019', 'SRV-PROD-04'] },
  { id: 'USR-002', name: 'Ops Team', email: 'ops.team@quoodle.io', role: 'operator', status: 'active', lastActive: '5 min ago', deviceAccess: ['PC001', 'PC002', 'WKSTN-042', 'WKSTN-007'] },
  { id: 'USR-003', name: 'Nina Osei', email: 'nina.osei@quoodle.io', role: 'operator', status: 'active', lastActive: '12 min ago', deviceAccess: ['WKSTN-019', 'SRV-PROD-04'] },
  { id: 'USR-004', name: 'DevOps', email: 'devops@quoodle.io', role: 'operator', status: 'active', lastActive: '1 hour ago', deviceAccess: ['PC001', 'WKSTN-042'] },
  { id: 'USR-005', name: 'Viewer User', email: 'viewer@quoodle.io', role: 'viewer', status: 'active', lastActive: '3 hours ago', deviceAccess: ['PC001', 'PC002'] },
  { id: 'USR-006', name: 'Sarah Chen', email: 'sarah.chen@quoodle.io', role: 'viewer', status: 'inactive', lastActive: '2 days ago', deviceAccess: [] },
  { id: 'USR-007', name: 'James Okafor', email: 'james.okafor@quoodle.io', role: 'operator', status: 'pending', lastActive: 'Never', deviceAccess: [] },
];

const allDevices: DeviceEntry[] = [
  { id: 'PC001', hostname: 'WKSTN-001', os: 'Windows 11', status: 'online' },
  { id: 'PC002', hostname: 'WKSTN-002', os: 'Windows 11', status: 'online' },
  { id: 'WKSTN-042', hostname: 'WKSTN-042', os: 'Windows 10', status: 'online' },
  { id: 'WKSTN-007', hostname: 'WKSTN-007', os: 'Windows 11', status: 'degraded' },
  { id: 'WKSTN-019', hostname: 'WKSTN-019', os: 'Windows 10', status: 'offline' },
  { id: 'SRV-PROD-04', hostname: 'SRV-PROD-04', os: 'Windows Server 2022', status: 'online' },
];

// ─── Sub-components ───────────────────────────────────────────────────────────

const severityBadge = (s: 'critical' | 'warning' | 'info') => {
  const map = {
    critical: 'bg-red-500/20 text-red-400 border-red-500/30',
    warning: 'bg-amber-500/20 text-amber-400 border-amber-500/30',
    info: 'bg-blue-500/20 text-blue-400 border-blue-500/30',
  };
  return (
    <span className={`text-[10px] font-semibold px-2 py-0.5 rounded-full border ${map[s]}`}>
      {s.toUpperCase()}
    </span>
  );
};

// ─── Alert Rules Section ──────────────────────────────────────────────────────

function AlertRulesSection() {
  const [rules, setRules] = useState<AlertRule[]>(initialAlertRules);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [editName, setEditName] = useState('');
  const [editCondition, setEditCondition] = useState('');

  const toggleRule = (id: string) => {
    setRules((prev) => prev.map((r) => r.id === id ? { ...r, enabled: !r.enabled } : r));
    const rule = rules.find((r) => r.id === id);
    if (rule) toast.success(`Rule "${rule.name}" ${rule.enabled ? 'disabled' : 'enabled'}`);
  };

  const startEdit = (rule: AlertRule) => {
    setEditingId(rule.id);
    setEditName(rule.name);
    setEditCondition(rule.condition);
  };

  const saveEdit = (id: string) => {
    setRules((prev) => prev.map((r) => r.id === id ? { ...r, name: editName, condition: editCondition } : r));
    setEditingId(null);
    toast.success('Alert rule updated');
  };

  const deleteRule = (id: string) => {
    setRules((prev) => prev.filter((r) => r.id !== id));
    toast.success('Alert rule deleted');
  };

  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between">
        <div>
          <h3 className="text-sm font-semibold">Alert Rules</h3>
          <p className="text-xs text-muted-foreground mt-0.5">Configure conditions that trigger operational alerts</p>
        </div>
        <button
          onClick={() => toast.info('Add rule form coming soon')}
          className="flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium bg-primary/10 border border-primary/30 text-primary rounded-md hover:bg-primary/20 transition-colors"
        >
          <Plus size={12} />
          Add Rule
        </button>
      </div>

      <div className="space-y-2">
        {rules.map((rule) => (
          <div
            key={rule.id}
            className={`bg-card border rounded-lg px-4 py-3 transition-all ${rule.enabled ? 'border-border' : 'border-border/40 opacity-60'}`}
          >
            {editingId === rule.id ? (
              <div className="space-y-2">
                <input
                  value={editName}
                  onChange={(e) => setEditName(e.target.value)}
                  className="w-full px-2.5 py-1.5 text-xs bg-muted/60 border border-border rounded-md text-foreground focus:outline-none focus:ring-1 focus:ring-primary/50"
                  placeholder="Rule name"
                />
                <input
                  value={editCondition}
                  onChange={(e) => setEditCondition(e.target.value)}
                  className="w-full px-2.5 py-1.5 text-xs bg-muted/60 border border-border rounded-md font-mono text-foreground focus:outline-none focus:ring-1 focus:ring-primary/50"
                  placeholder="Condition expression"
                />
                <div className="flex items-center gap-2">
                  <button onClick={() => saveEdit(rule.id)} className="flex items-center gap-1 px-2.5 py-1 text-xs bg-green-500/10 border border-green-500/20 text-green-400 rounded-md hover:bg-green-500/20 transition-colors">
                    <Save size={11} /> Save
                  </button>
                  <button onClick={() => setEditingId(null)} className="flex items-center gap-1 px-2.5 py-1 text-xs text-muted-foreground border border-border rounded-md hover:bg-muted/60 transition-colors">
                    <X size={11} /> Cancel
                  </button>
                </div>
              </div>
            ) : (
              <div className="flex items-center gap-3">
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2 flex-wrap">
                    <span className="text-sm font-medium">{rule.name}</span>
                    {severityBadge(rule.severity)}
                    <span className="text-[10px] text-muted-foreground bg-muted/40 px-1.5 py-0.5 rounded">{rule.channel}</span>
                  </div>
                  <p className="font-mono text-[11px] text-muted-foreground mt-0.5 truncate">{rule.condition}</p>
                </div>
                <div className="flex items-center gap-1.5 flex-shrink-0">
                  <button onClick={() => startEdit(rule)} className="p-1.5 rounded text-muted-foreground hover:text-foreground hover:bg-muted transition-colors">
                    <Edit2 size={12} />
                  </button>
                  <button onClick={() => deleteRule(rule.id)} className="p-1.5 rounded text-muted-foreground hover:text-red-400 hover:bg-red-500/10 transition-colors">
                    <Trash2 size={12} />
                  </button>
                  <button onClick={() => toggleRule(rule.id)} className="p-1 rounded transition-colors">
                    {rule.enabled
                      ? <ToggleRight size={22} className="text-primary" />
                      : <ToggleLeft size={22} className="text-muted-foreground" />}
                  </button>
                </div>
              </div>
            )}
          </div>
        ))}
      </div>
    </div>
  );
}

// ─── Policy Editor Section ────────────────────────────────────────────────────

function PolicyEditorSection() {
  const [policies, setPolicies] = useState<PolicyEntry[]>(initialPolicies);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [editValue, setEditValue] = useState('');

  const startEdit = (p: PolicyEntry) => {
    setEditingId(p.id);
    setEditValue(p.value);
  };

  const saveEdit = (id: string) => {
    setPolicies((prev) => prev.map((p) => p.id === id ? { ...p, value: editValue } : p));
    setEditingId(null);
    toast.success('Policy updated — changes will propagate on next sync');
  };

  return (
    <div className="space-y-3">
      <div>
        <h3 className="text-sm font-semibold">Policy Editor</h3>
        <p className="text-xs text-muted-foreground mt-0.5">Manage fleet-wide policy keys and enforcement values</p>
      </div>

      <div className="bg-card border border-border rounded-lg overflow-hidden">
        <table className="w-full text-xs">
          <thead>
            <tr className="border-b border-border bg-muted/20">
              <th className="px-4 py-2.5 text-left text-[10px] font-semibold text-muted-foreground uppercase tracking-wide">Policy Key</th>
              <th className="px-4 py-2.5 text-left text-[10px] font-semibold text-muted-foreground uppercase tracking-wide">Value</th>
              <th className="px-4 py-2.5 text-left text-[10px] font-semibold text-muted-foreground uppercase tracking-wide hidden md:table-cell">Description</th>
              <th className="px-4 py-2.5 w-16" />
            </tr>
          </thead>
          <tbody className="divide-y divide-border">
            {policies.map((p) => (
              <tr key={p.id} className="hover:bg-muted/10 transition-colors">
                <td className="px-4 py-2.5">
                  <span className="font-mono text-[11px] text-primary">{p.key}</span>
                </td>
                <td className="px-4 py-2.5">
                  {editingId === p.id ? (
                    <div className="flex items-center gap-1.5">
                      <input
                        value={editValue}
                        onChange={(e) => setEditValue(e.target.value)}
                        className="w-28 px-2 py-1 text-xs bg-muted/60 border border-primary/40 rounded font-mono text-foreground focus:outline-none"
                        autoFocus
                      />
                      <button onClick={() => saveEdit(p.id)} className="p-1 text-green-400 hover:text-green-300 transition-colors"><Save size={12} /></button>
                      <button onClick={() => setEditingId(null)} className="p-1 text-muted-foreground hover:text-foreground transition-colors"><X size={12} /></button>
                    </div>
                  ) : (
                    <span className="font-mono text-[11px]">{p.value}</span>
                  )}
                </td>
                <td className="px-4 py-2.5 text-muted-foreground hidden md:table-cell">{p.description}</td>
                <td className="px-4 py-2.5">
                  {p.editable && editingId !== p.id && (
                    <button onClick={() => startEdit(p)} className="p-1.5 rounded text-muted-foreground hover:text-foreground hover:bg-muted transition-colors">
                      <Edit2 size={12} />
                    </button>
                  )}
                  {!p.editable && (
                    <Lock size={11} className="text-muted-foreground/40 mx-auto" />
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}

// ─── Compliance Thresholds Section ───────────────────────────────────────────

function ComplianceThresholdsSection() {
  const [thresholds, setThresholds] = useState<ComplianceThreshold[]>(initialThresholds);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [editValue, setEditValue] = useState('');

  const startEdit = (t: ComplianceThreshold) => {
    setEditingId(t.id);
    setEditValue(String(t.threshold));
  };

  const saveEdit = (id: string) => {
    const num = parseFloat(editValue);
    if (isNaN(num)) { toast.error('Invalid threshold value'); return; }
    setThresholds((prev) => prev.map((t) => t.id === id ? { ...t, threshold: num } : t));
    setEditingId(null);
    toast.success('Compliance threshold updated');
  };

  return (
    <div className="space-y-3">
      <div>
        <h3 className="text-sm font-semibold">Compliance Thresholds</h3>
        <p className="text-xs text-muted-foreground mt-0.5">Define metric boundaries that trigger compliance violations</p>
      </div>

      <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
        {thresholds.map((t) => (
          <div key={t.id} className="bg-card border border-border rounded-lg px-4 py-3">
            <div className="flex items-start justify-between gap-2">
              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-2">
                  <span className="text-sm font-medium">{t.control}</span>
                  {severityBadge(t.severity)}
                </div>
                <p className="font-mono text-[10px] text-muted-foreground mt-0.5">{t.metric}</p>
              </div>
              <button onClick={() => startEdit(t)} className="p-1.5 rounded text-muted-foreground hover:text-foreground hover:bg-muted transition-colors flex-shrink-0">
                <Edit2 size={12} />
              </button>
            </div>
            <div className="mt-2">
              {editingId === t.id ? (
                <div className="flex items-center gap-1.5">
                  <input
                    value={editValue}
                    onChange={(e) => setEditValue(e.target.value)}
                    type="number"
                    className="w-20 px-2 py-1 text-xs bg-muted/60 border border-primary/40 rounded font-mono text-foreground focus:outline-none"
                    autoFocus
                  />
                  <span className="text-xs text-muted-foreground">{t.unit}</span>
                  <button onClick={() => saveEdit(t.id)} className="p-1 text-green-400 hover:text-green-300 transition-colors"><Save size={12} /></button>
                  <button onClick={() => setEditingId(null)} className="p-1 text-muted-foreground hover:text-foreground transition-colors"><X size={12} /></button>
                </div>
              ) : (
                <div className="flex items-center gap-1.5">
                  <span className={`text-xl font-bold tabular-nums ${t.severity === 'critical' ? 'text-red-400' : 'text-amber-400'}`}>
                    {t.threshold}
                  </span>
                  <span className="text-xs text-muted-foreground">{t.unit}</span>
                </div>
              )}
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

// ─── Role & Permission Management Section ────────────────────────────────────

function RolePermissionsSection() {
  const [roles, setRoles] = useState<RolePermission[]>(initialRoles);
  const [expandedRole, setExpandedRole] = useState<string | null>('admin');

  const togglePermission = (role: string, key: string) => {
    if (role === 'admin') { toast.error('Admin permissions cannot be modified'); return; }
    setRoles((prev) =>
      prev.map((r) =>
        r.role === role
          ? { ...r, permissions: { ...r.permissions, [key]: !r.permissions[key] } }
          : r
      )
    );
  };

  const saveRole = (role: string) => {
    toast.success(`${role.charAt(0).toUpperCase() + role.slice(1)} permissions saved`);
  };

  const roleColors: Record<string, string> = {
    admin: 'text-red-400 bg-red-500/10 border-red-500/20',
    operator: 'text-blue-400 bg-blue-500/10 border-blue-500/20',
    viewer: 'text-zinc-400 bg-zinc-500/10 border-zinc-500/20',
  };

  const roleIcons: Record<string, React.ElementType> = {
    admin: Lock,
    operator: Terminal,
    viewer: Eye,
  };

  return (
    <div className="space-y-3">
      <div>
        <h3 className="text-sm font-semibold">Role & Permission Management</h3>
        <p className="text-xs text-muted-foreground mt-0.5">Configure access control for each user role</p>
      </div>

      <div className="space-y-2">
        {roles.map((r) => {
          const RoleIcon = roleIcons[r.role];
          const isExpanded = expandedRole === r.role;
          const isAdmin = r.role === 'admin';
          return (
            <div key={r.role} className="bg-card border border-border rounded-lg overflow-hidden">
              <button
                onClick={() => setExpandedRole(isExpanded ? null : r.role)}
                className="w-full flex items-center gap-3 px-4 py-3 hover:bg-muted/10 transition-colors"
              >
                <div className={`w-7 h-7 rounded-lg flex items-center justify-center border ${roleColors[r.role]}`}>
                  <RoleIcon size={13} />
                </div>
                <div className="flex-1 text-left">
                  <span className="text-sm font-semibold capitalize">{r.role}</span>
                  <span className="text-xs text-muted-foreground ml-2">
                    {Object.values(r.permissions).filter(Boolean).length}/{PERMISSION_KEYS.length} permissions
                  </span>
                </div>
                {isAdmin && (
                  <span className="text-[10px] text-muted-foreground bg-muted/40 px-2 py-0.5 rounded-full">System Role</span>
                )}
                {isExpanded ? <ChevronUp size={14} className="text-muted-foreground" /> : <ChevronDown size={14} className="text-muted-foreground" />}
              </button>

              {isExpanded && (
                <div className="border-t border-border px-4 py-3">
                  <div className="grid grid-cols-2 sm:grid-cols-3 gap-2">
                    {PERMISSION_KEYS.map((perm) => {
                      const granted = r.permissions[perm.key];
                      return (
                        <label
                          key={perm.key}
                          className={`flex items-center gap-2 px-2.5 py-1.5 rounded-md border cursor-pointer transition-all ${
                            isAdmin ? 'opacity-60 cursor-not-allowed' : 'hover:bg-muted/30'
                          } ${granted ? 'bg-primary/5 border-primary/20' : 'bg-muted/20 border-border'}`}
                        >
                          <input
                            type="checkbox"
                            checked={granted}
                            disabled={isAdmin}
                            onChange={() => togglePermission(r.role, perm.key)}
                            className="w-3 h-3 accent-primary"
                          />
                          <span className="text-xs truncate">{perm.label}</span>
                          {granted
                            ? <CheckCircle2 size={11} className="text-green-400 ml-auto flex-shrink-0" />
                            : <X size={11} className="text-muted-foreground/40 ml-auto flex-shrink-0" />}
                        </label>
                      );
                    })}
                  </div>
                  {!isAdmin && (
                    <div className="mt-3 flex justify-end">
                      <button
                        onClick={() => saveRole(r.role)}
                        className="flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium bg-primary/10 border border-primary/30 text-primary rounded-md hover:bg-primary/20 transition-colors"
                      >
                        <Save size={12} />
                        Save Changes
                      </button>
                    </div>
                  )}
                </div>
              )}
            </div>
          );
        })}
      </div>
    </div>
  );
}

// ─── Team Members Section ─────────────────────────────────────────────────────

function TeamMembersSection() {
  const [members, setMembers] = useState<TeamMember[]>(initialTeamMembers);
  const [search, setSearch] = useState('');
  const [selectedMember, setSelectedMember] = useState<TeamMember | null>(null);
  const [showDeviceMatrix, setShowDeviceMatrix] = useState(false);

  const filtered = members.filter(
    (m) =>
      m.name.toLowerCase().includes(search.toLowerCase()) ||
      m.email.toLowerCase().includes(search.toLowerCase()) ||
      m.role.includes(search.toLowerCase())
  );

  const roleStyle: Record<string, string> = {
    admin: 'bg-red-500/10 text-red-400 border-red-500/20',
    operator: 'bg-blue-500/10 text-blue-400 border-blue-500/20',
    viewer: 'bg-zinc-500/10 text-zinc-400 border-zinc-500/20',
  };

  const statusStyle: Record<string, string> = {
    active: 'text-green-400',
    inactive: 'text-muted-foreground',
    pending: 'text-amber-400',
  };

  const statusDot: Record<string, string> = {
    active: 'bg-green-400',
    inactive: 'bg-zinc-500',
    pending: 'bg-amber-400 animate-pulse',
  };

  const toggleDeviceAccess = (memberId: string, deviceId: string) => {
    setMembers((prev) =>
      prev.map((m) => {
        if (m.id !== memberId) return m;
        const has = m.deviceAccess.includes(deviceId);
        const updated = has
          ? m.deviceAccess.filter((d) => d !== deviceId)
          : [...m.deviceAccess, deviceId];
        toast.success(has ? `Access revoked: ${deviceId}` : `Access granted: ${deviceId}`);
        return { ...m, deviceAccess: updated };
      })
    );
    // Update selectedMember if it's the one being modified
    if (selectedMember?.id === memberId) {
      setSelectedMember((prev) => {
        if (!prev) return prev;
        const has = prev.deviceAccess.includes(deviceId);
        return {
          ...prev,
          deviceAccess: has
            ? prev.deviceAccess.filter((d) => d !== deviceId)
            : [...prev.deviceAccess, deviceId],
        };
      });
    }
  };

  const revokeAllAccess = (memberId: string) => {
    setMembers((prev) =>
      prev.map((m) => (m.id === memberId ? { ...m, deviceAccess: [] } : m))
    );
    if (selectedMember?.id === memberId) {
      setSelectedMember((prev) => prev ? { ...prev, deviceAccess: [] } : prev);
    }
    toast.success('All device access revoked');
  };

  const grantAllAccess = (memberId: string) => {
    const allIds = allDevices.map((d) => d.id);
    setMembers((prev) =>
      prev.map((m) => (m.id === memberId ? { ...m, deviceAccess: allIds } : m))
    );
    if (selectedMember?.id === memberId) {
      setSelectedMember((prev) => prev ? { ...prev, deviceAccess: allIds } : prev);
    }
    toast.success('Full device access granted');
  };

  const deactivateMember = (memberId: string) => {
    setMembers((prev) =>
      prev.map((m) => (m.id === memberId ? { ...m, status: 'inactive' } : m))
    );
    toast.success('Member deactivated');
  };

  return (
    <div className="space-y-4">
      {/* Header */}
      <div className="flex items-center justify-between flex-wrap gap-2">
        <div>
          <h3 className="text-sm font-semibold">Team Members</h3>
          <p className="text-xs text-muted-foreground mt-0.5">Manage users, device access, and share/revoke controls</p>
        </div>
        <div className="flex items-center gap-2">
          <button
            onClick={() => setShowDeviceMatrix(!showDeviceMatrix)}
            className={`flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium border rounded-md transition-colors ${
              showDeviceMatrix
                ? 'bg-primary/10 border-primary/30 text-primary' :'border-border text-muted-foreground hover:text-foreground hover:bg-muted/60'
            }`}
          >
            <Monitor size={12} />
            {showDeviceMatrix ? 'Hide Matrix' : 'Device Matrix'}
          </button>
          <button
            onClick={() => toast.info('Invite member form coming soon')}
            className="flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium bg-primary/10 border border-primary/30 text-primary rounded-md hover:bg-primary/20 transition-colors"
          >
            <Plus size={12} />
            Invite Member
          </button>
        </div>
      </div>

      {/* Search */}
      <div className="relative">
        <Search size={13} className="absolute left-3 top-1/2 -translate-y-1/2 text-muted-foreground" />
        <input
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          placeholder="Search by name, email, or role…"
          className="w-full pl-8 pr-3 py-2 text-xs bg-muted/40 border border-border rounded-lg text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-1 focus:ring-primary/50"
        />
      </div>

      {/* Device Access Matrix */}
      {showDeviceMatrix && (
        <div className="bg-card border border-border rounded-lg overflow-hidden">
          <div className="px-4 py-3 border-b border-border flex items-center gap-2">
            <Monitor size={13} className="text-muted-foreground" />
            <h4 className="text-xs font-semibold">Device Access Matrix</h4>
            <span className="text-[10px] text-muted-foreground">— admin has unrestricted access to all devices</span>
          </div>
          <div className="overflow-x-auto scrollbar-thin">
            <table className="w-full text-xs">
              <thead>
                <tr className="border-b border-border bg-muted/20">
                  <th className="px-3 py-2.5 text-left text-[10px] font-semibold text-muted-foreground uppercase tracking-wide sticky left-0 bg-muted/20 min-w-[160px]">Member</th>
                  {allDevices.map((d) => (
                    <th key={d.id} className="px-3 py-2.5 text-center text-[10px] font-semibold text-muted-foreground uppercase tracking-wide whitespace-nowrap">
                      <div>{d.hostname}</div>
                      <div className={`text-[9px] font-normal ${d.status === 'online' ? 'text-green-400' : d.status === 'degraded' ? 'text-amber-400' : 'text-red-400'}`}>
                        {d.status}
                      </div>
                    </th>
                  ))}
                  <th className="px-3 py-2.5 text-center text-[10px] font-semibold text-muted-foreground uppercase tracking-wide whitespace-nowrap">Actions</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-border">
                {filtered.map((member) => (
                  <tr key={member.id} className="hover:bg-muted/10 transition-colors">
                    <td className="px-3 py-2.5 sticky left-0 bg-card">
                      <div>
                        <p className="font-medium text-foreground text-xs">{member.name}</p>
                        <span className={`text-[10px] px-1.5 py-0.5 rounded-full border font-medium ${roleStyle[member.role]}`}>
                          {member.role}
                        </span>
                      </div>
                    </td>
                    {allDevices.map((device) => {
                      const hasAccess = member.role === 'admin' || member.deviceAccess.includes(device.id);
                      const isAdmin = member.role === 'admin';
                      return (
                        <td key={device.id} className="px-3 py-2.5 text-center">
                          <button
                            onClick={() => !isAdmin && toggleDeviceAccess(member.id, device.id)}
                            disabled={isAdmin}
                            title={isAdmin ? 'Admin has unrestricted access' : hasAccess ? 'Click to revoke' : 'Click to grant'}
                            className={`w-6 h-6 rounded flex items-center justify-center mx-auto transition-all ${
                              isAdmin
                                ? 'cursor-default'
                                : hasAccess
                                ? 'hover:bg-red-500/10 cursor-pointer' :'hover:bg-green-500/10 cursor-pointer'
                            }`}
                          >
                            {hasAccess ? (
                              <CheckCircle2 size={14} className={isAdmin ? 'text-primary/60' : 'text-green-400'} />
                            ) : (
                              <X size={14} className="text-muted-foreground/30" />
                            )}
                          </button>
                        </td>
                      );
                    })}
                    <td className="px-3 py-2.5 text-center">
                      {member.role !== 'admin' && (
                        <div className="flex items-center justify-center gap-1">
                          <button
                            onClick={() => grantAllAccess(member.id)}
                            title="Grant all device access"
                            className="p-1 rounded text-green-400 hover:bg-green-500/10 transition-colors"
                          >
                            <UserCheck size={12} />
                          </button>
                          <button
                            onClick={() => revokeAllAccess(member.id)}
                            title="Revoke all device access"
                            className="p-1 rounded text-red-400 hover:bg-red-500/10 transition-colors"
                          >
                            <UserX size={12} />
                          </button>
                        </div>
                      )}
                      {member.role === 'admin' && (
                        <Lock size={11} className="text-muted-foreground/40 mx-auto" />
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* Member List */}
      <div className="space-y-2">
        {filtered.map((member) => (
          <div
            key={member.id}
            className="bg-card border border-border rounded-lg px-4 py-3 hover:border-border/80 transition-all"
          >
            <div className="flex items-center gap-3">
              {/* Avatar */}
              <div className={`w-8 h-8 rounded-full flex items-center justify-center text-xs font-bold flex-shrink-0 ${
                member.role === 'admin' ? 'bg-red-500/20 text-red-400' :
                member.role === 'operator'? 'bg-blue-500/20 text-blue-400' : 'bg-zinc-500/20 text-zinc-400'
              }`}>
                {member.name.charAt(0).toUpperCase()}
              </div>

              {/* Info */}
              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-2 flex-wrap">
                  <span className="text-sm font-medium">{member.name}</span>
                  <span className={`text-[10px] px-1.5 py-0.5 rounded-full border font-medium ${roleStyle[member.role]}`}>
                    {member.role}
                  </span>
                  <div className="flex items-center gap-1">
                    <span className={`w-1.5 h-1.5 rounded-full ${statusDot[member.status]}`} />
                    <span className={`text-[10px] ${statusStyle[member.status]}`}>{member.status}</span>
                  </div>
                </div>
                <div className="flex items-center gap-3 mt-0.5">
                  <p className="text-[11px] text-muted-foreground truncate">{member.email}</p>
                  <span className="text-[10px] text-muted-foreground">Last active: {member.lastActive}</span>
                  {member.role !== 'admin' && (
                    <span className="text-[10px] text-muted-foreground">
                      {member.deviceAccess.length}/{allDevices.length} devices
                    </span>
                  )}
                  {member.role === 'admin' && (
                    <span className="text-[10px] text-primary">All devices (unrestricted)</span>
                  )}
                </div>
              </div>

              {/* Actions */}
              <div className="flex items-center gap-1 flex-shrink-0">
                {member.role !== 'admin' && (
                  <>
                    <button
                      onClick={() => { setSelectedMember(member); setShowDeviceMatrix(true); }}
                      title="Manage device access"
                      className="flex items-center gap-1 px-2 py-1 text-[11px] border border-border rounded text-muted-foreground hover:text-foreground hover:bg-muted/60 transition-colors"
                    >
                      <Share2 size={11} />
                      Access
                    </button>
                    {member.status === 'active' && (
                      <button
                        onClick={() => deactivateMember(member.id)}
                        title="Deactivate member"
                        className="p-1.5 rounded text-muted-foreground hover:text-red-400 hover:bg-red-500/10 transition-colors"
                      >
                        <UserX size={13} />
                      </button>
                    )}
                  </>
                )}
                {member.role === 'admin' && (
                  <div className="flex items-center gap-1 px-2 py-1 text-[11px] border border-primary/20 rounded text-primary bg-primary/5">
                    <Lock size={10} />
                    System Admin
                  </div>
                )}
                <button className="p-1.5 rounded text-muted-foreground hover:text-foreground hover:bg-muted transition-colors">
                  <MoreHorizontal size={13} />
                </button>
              </div>
            </div>
          </div>
        ))}
        {filtered.length === 0 && (
          <div className="text-center py-8 text-xs text-muted-foreground">
            No members match your search
          </div>
        )}
      </div>

      {/* Summary stats */}
      <div className="grid grid-cols-3 gap-3">
        {(['admin', 'operator', 'viewer'] as const).map((role) => {
          const count = members.filter((m) => m.role === role).length;
          const active = members.filter((m) => m.role === role && m.status === 'active').length;
          return (
            <div key={role} className={`bg-card border rounded-lg px-3 py-2.5 ${roleStyle[role].replace('text-', 'border-').split(' ')[0]}/20 border-border`}>
              <p className={`text-xs font-semibold capitalize ${roleStyle[role].split(' ')[1]}`}>{role}s</p>
              <p className="text-lg font-bold tabular-nums mt-0.5">{count}</p>
              <p className="text-[10px] text-muted-foreground">{active} active</p>
            </div>
          );
        })}
      </div>
    </div>
  );
}

// ─── Main Settings Content ────────────────────────────────────────────────────

const TABS = [
  { key: 'alert-rules', label: 'Alert Rules', icon: Bell },
  { key: 'policy-editor', label: 'Policy Editor', icon: Shield },
  { key: 'compliance-thresholds', label: 'Compliance Thresholds', icon: ShieldCheck },
  { key: 'roles-permissions', label: 'Roles & Permissions', icon: Users },
  { key: 'team-members', label: 'Team Members', icon: Users },
];

export default function SettingsContent() {
  const [activeTab, setActiveTab] = useState('alert-rules');

  return (
    <div className="space-y-6 fade-in">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">Settings</h1>
          <p className="text-sm text-muted-foreground mt-0.5">Admin configuration — alert rules, policies, compliance, and access control</p>
        </div>
        <div className="flex items-center gap-2 text-xs text-muted-foreground bg-amber-500/10 border border-amber-500/20 rounded-md px-3 py-1.5">
          <AlertTriangle size={12} className="text-amber-400" />
          <span className="text-amber-400 font-medium">Admin Only</span>
        </div>
      </div>

      {/* Tab navigation */}
      <div className="flex items-center gap-1 bg-muted/30 rounded-lg p-1 flex-wrap">
        {TABS.map((tab) => (
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

      {/* Tab content */}
      <div className="fade-in">
        {activeTab === 'alert-rules' && <AlertRulesSection />}
        {activeTab === 'policy-editor' && <PolicyEditorSection />}
        {activeTab === 'compliance-thresholds' && <ComplianceThresholdsSection />}
        {activeTab === 'roles-permissions' && <RolePermissionsSection />}
        {activeTab === 'team-members' && <TeamMembersSection />}
      </div>
    </div>
  );
}
