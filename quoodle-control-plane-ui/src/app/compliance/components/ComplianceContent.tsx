'use client';
import React, { useState } from 'react';
import { ShieldCheck, AlertTriangle, CheckCircle2, XCircle, RefreshCw, Download } from 'lucide-react';
import StatusBadge from '@/components/ui/StatusBadge';
import AuditTrailSection from '@/components/AuditTrailSection';
import ExportModal from '@/components/ExportModal';

interface ComplianceCheck {
  id: string;
  category: string;
  control: string;
  description: string;
  status: 'compliant' | 'non_compliant' | 'drift' | 'pending';
  affectedDevices: number;
  lastChecked: string;
  severity: 'critical' | 'warning' | 'info';
}

const complianceChecks: ComplianceCheck[] = [
  { id: 'CC-001', category: 'Attestation', control: 'TPM-ATTEST-01', description: 'All devices must pass TPM attestation on boot', status: 'non_compliant', affectedDevices: 2, lastChecked: '21:06:00', severity: 'critical' },
  { id: 'CC-002', category: 'Policy Sync', control: 'POL-SYNC-01', description: 'Device policy hash must match fleet policy-2026-04', status: 'drift', affectedDevices: 6, lastChecked: '21:05:55', severity: 'warning' },
  { id: 'CC-003', category: 'Kernel Guard', control: 'KG-DRIVER-01', description: 'Kernel Guard driver must be active on all managed devices', status: 'non_compliant', affectedDevices: 3, lastChecked: '21:05:50', severity: 'critical' },
  { id: 'CC-004', category: 'Agent Version', control: 'AGENT-VER-01', description: 'All agents must run version 0.0.1 or higher', status: 'compliant', affectedDevices: 0, lastChecked: '21:05:45', severity: 'info' },
  { id: 'CC-005', category: 'Encryption', control: 'ENC-DISK-01', description: 'Full disk encryption must be enabled on all endpoints', status: 'compliant', affectedDevices: 0, lastChecked: '21:05:40', severity: 'info' },
  { id: 'CC-006', category: 'Command Auth', control: 'CMD-AUTH-01', description: 'All commands must be Ed25519 signed and 2FA verified', status: 'compliant', affectedDevices: 0, lastChecked: '21:05:35', severity: 'info' },
  { id: 'CC-007', category: 'Heartbeat', control: 'HB-INTERVAL-01', description: 'Device heartbeat interval must not exceed 60 seconds', status: 'drift', affectedDevices: 4, lastChecked: '21:05:30', severity: 'warning' },
  { id: 'CC-008', category: 'Quarantine', control: 'QUAR-POLICY-01', description: 'Quarantined devices must block all non-remediation commands', status: 'compliant', affectedDevices: 0, lastChecked: '21:05:25', severity: 'info' },
];

const categories = ['All', 'Attestation', 'Policy Sync', 'Kernel Guard', 'Agent Version', 'Encryption', 'Command Auth', 'Heartbeat', 'Quarantine'];

const statusIcon = {
  compliant:     <CheckCircle2 size={14} className="text-green-400" />,
  non_compliant: <XCircle size={14} className="text-red-400" />,
  drift:         <AlertTriangle size={14} className="text-amber-400" />,
  pending:       <RefreshCw size={14} className="text-zinc-400" />,
};

const severityBg = {
  critical: 'border-l-red-500',
  warning:  'border-l-amber-500',
  info:     'border-l-zinc-600',
};

export default function ComplianceContent() {
  const [categoryFilter, setCategoryFilter] = useState('All');
  const [statusFilter, setStatusFilter] = useState<string>('all');
  const [showExport, setShowExport] = useState(false);

  const filtered = complianceChecks.filter((c) => {
    const matchCat = categoryFilter === 'All' || c.category === categoryFilter;
    const matchStatus = statusFilter === 'all' || c.status === statusFilter;
    return matchCat && matchStatus;
  });

  const summary = {
    compliant:     complianceChecks.filter((c) => c.status === 'compliant').length,
    non_compliant: complianceChecks.filter((c) => c.status === 'non_compliant').length,
    drift:         complianceChecks.filter((c) => c.status === 'drift').length,
    total:         complianceChecks.length,
  };
  const score = Math.round((summary.compliant / summary.total) * 100);

  return (
    <div className="space-y-6 fade-in">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">Compliance</h1>
          <p className="text-sm text-muted-foreground mt-0.5">Policy controls and regulatory posture across the fleet</p>
        </div>
        <div className="flex items-center gap-2">
          <button
            onClick={() => setShowExport(true)}
            className="flex items-center gap-1.5 px-3 py-1.5 text-xs text-muted-foreground border border-border rounded-md hover:bg-muted/60 transition-colors"
          >
            <Download size={13} />
            Export
          </button>
          <div className="flex items-center gap-2 text-xs text-muted-foreground bg-muted/40 border border-border rounded-md px-3 py-1.5">
            <span className="w-1.5 h-1.5 rounded-full bg-green-400 pulse-dot" />
            Last scan 21:06:00 UTC
          </div>
        </div>
      </div>

      {/* Score cards */}
      <div className="grid grid-cols-2 sm:grid-cols-4 gap-4">
        <div className="bg-card border border-border rounded-lg p-4 text-center">
          <p className={`text-3xl font-bold tabular-nums ${score >= 80 ? 'text-green-400' : score >= 60 ? 'text-amber-400' : 'text-red-400'}`}>{score}%</p>
          <p className="text-xs text-muted-foreground mt-1 uppercase tracking-wide font-medium">Compliance Score</p>
        </div>
        <div
          className="bg-green-500/5 border border-green-500/20 rounded-lg p-4 text-center cursor-pointer hover:border-green-500/40 transition-colors"
          onClick={() => setStatusFilter(statusFilter === 'compliant' ? 'all' : 'compliant')}
        >
          <p className="text-3xl font-bold tabular-nums text-green-400">{summary.compliant}</p>
          <p className="text-xs text-green-400/70 mt-1 uppercase tracking-wide font-medium">Compliant</p>
        </div>
        <div
          className="bg-amber-500/5 border border-amber-500/20 rounded-lg p-4 text-center cursor-pointer hover:border-amber-500/40 transition-colors"
          onClick={() => setStatusFilter(statusFilter === 'drift' ? 'all' : 'drift')}
        >
          <p className="text-3xl font-bold tabular-nums text-amber-400">{summary.drift}</p>
          <p className="text-xs text-amber-400/70 mt-1 uppercase tracking-wide font-medium">Drift</p>
        </div>
        <div
          className="bg-red-500/5 border border-red-500/20 rounded-lg p-4 text-center cursor-pointer hover:border-red-500/40 transition-colors"
          onClick={() => setStatusFilter(statusFilter === 'non_compliant' ? 'all' : 'non_compliant')}
        >
          <p className="text-3xl font-bold tabular-nums text-red-400">{summary.non_compliant}</p>
          <p className="text-xs text-red-400/70 mt-1 uppercase tracking-wide font-medium">Non-Compliant</p>
        </div>
      </div>

      {/* Category filter */}
      <div className="flex flex-wrap gap-1.5">
        {categories.map((cat) => (
          <button
            key={cat}
            onClick={() => setCategoryFilter(cat)}
            className={`px-3 py-1 rounded-full text-xs font-medium transition-all ${
              categoryFilter === cat
                ? 'bg-primary/20 text-primary border border-primary/30' :'bg-muted/40 text-muted-foreground border border-border hover:text-foreground'
            }`}
          >
            {cat}
          </button>
        ))}
      </div>

      {/* Controls list */}
      <div className="space-y-2">
        {filtered.map((check) => (
          <div
            key={check.id}
            className={`bg-card border border-border border-l-2 ${severityBg[check.severity]} rounded-lg px-4 py-3 flex items-center gap-4 hover:bg-muted/10 transition-colors`}
          >
            <div className="flex-shrink-0">{statusIcon[check.status]}</div>
            <div className="flex-1 min-w-0">
              <div className="flex items-center gap-2 flex-wrap">
                <span className="font-mono text-[11px] text-muted-foreground">{check.control}</span>
                <span className="text-[10px] px-1.5 py-0.5 rounded bg-muted text-muted-foreground">{check.category}</span>
              </div>
              <p className="text-sm font-medium mt-0.5">{check.description}</p>
            </div>
            <div className="flex items-center gap-4 flex-shrink-0">
              {check.affectedDevices > 0 && (
                <div className="text-right">
                  <p className="text-xs font-semibold text-red-400">{check.affectedDevices}</p>
                  <p className="text-[10px] text-muted-foreground">affected</p>
                </div>
              )}
              <StatusBadge variant={check.status} />
              <span className="font-mono text-[10px] text-muted-foreground">{check.lastChecked}</span>
            </div>
          </div>
        ))}
        {filtered.length === 0 && (
          <div className="bg-card border border-border rounded-lg px-4 py-12 text-center">
            <ShieldCheck size={32} className="mx-auto text-muted-foreground/30 mb-3" />
            <p className="text-sm text-muted-foreground">No controls match the selected filters</p>
          </div>
        )}
      </div>

      {/* Audit trail */}
      <AuditTrailSection title="Compliance Audit Trail" maxRows={5} />

      {showExport && (
        <ExportModal
          title="Compliance"
          fields={[
            { key: 'id', label: 'Check ID' },
            { key: 'category', label: 'Category' },
            { key: 'control', label: 'Control ID' },
            { key: 'description', label: 'Description' },
            { key: 'status', label: 'Status' },
            { key: 'affected_devices', label: 'Affected Devices' },
            { key: 'last_checked', label: 'Last Checked' },
            { key: 'severity', label: 'Severity' },
          ]}
          onClose={() => setShowExport(false)}
        />
      )}
    </div>
  );
}
