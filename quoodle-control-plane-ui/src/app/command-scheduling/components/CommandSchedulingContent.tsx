'use client';
import React, { useState } from 'react';
import { Calendar, Plus, Play, Pause, Trash2, Clock, RefreshCw, CheckCircle, XCircle, AlertTriangle, Terminal, Monitor, RotateCcw, X, Save, Hash, List } from 'lucide-react';
import { toast } from 'sonner';

type ScheduleStatus = 'active' | 'paused' | 'completed' | 'failed';
type RunStatus = 'success' | 'failed' | 'running' | 'skipped';

interface ScheduledJob {
  id: string;
  name: string;
  command: string;
  params: Record<string, string>;
  deviceIds: string[];
  cronExpression: string;
  cronDescription: string;
  status: ScheduleStatus;
  nextRun: string | null;
  lastRun: string | null;
  lastRunStatus: RunStatus | null;
  batchId: string;
  totalRuns: number;
  successRuns: number;
  failedRuns: number;
  createdAt: string;
  createdBy: string;
}

interface RunRecord {
  id: string;
  batchId: string;
  jobId: string;
  jobName: string;
  deviceId: string;
  hostname: string;
  status: RunStatus;
  startedAt: string;
  completedAt: string | null;
  duration: string | null;
  commandId: string | null;
  error: string | null;
}

const CRON_PRESETS = [
  { label: 'Every 5 minutes', value: '*/5 * * * *' },
  { label: 'Every 15 minutes', value: '*/15 * * * *' },
  { label: 'Every hour', value: '0 * * * *' },
  { label: 'Every 6 hours', value: '0 */6 * * *' },
  { label: 'Daily at midnight', value: '0 0 * * *' },
  { label: 'Daily at 9am', value: '0 9 * * *' },
  { label: 'Weekly (Mon 9am)', value: '0 9 * * 1' },
  { label: 'Monthly (1st, midnight)', value: '0 0 1 * *' },
];

const COMMAND_LIBRARY = [
  'system-info', 'screenshot-capture', 'filesystem', 'process-list',
  'network-info', 'event-logs', 'installed-apps', 'hardware-info',
  'performance-metrics', 'services-list', 'scheduled-tasks', 'users-list',
  'ping', 'lock_screen',
];

const mockJobs: ScheduledJob[] = [
  {
    id: 'job-001', name: 'Hourly System Health Check', command: 'system-info', params: {},
    deviceIds: ['WKSTN-055', 'WKSTN-001', 'WKSTN-002', 'WKSTN-042'],
    cronExpression: '0 * * * *', cronDescription: 'Every hour',
    status: 'active', nextRun: '22:00:00', lastRun: '21:00:01', lastRunStatus: 'success',
    batchId: 'BATCH-001', totalRuns: 168, successRuns: 165, failedRuns: 3, createdAt: '2026-03-01', createdBy: 'admin@quoodle.io',
  },
  {
    id: 'job-002', name: 'Daily Screenshot Audit', command: 'screenshot-capture', params: {},
    deviceIds: ['WKSTN-055', 'WKSTN-001', 'WKSTN-002', 'WKSTN-042', 'WKSTN-088', 'WKSTN-103'],
    cronExpression: '0 9 * * *', cronDescription: 'Daily at 9am',
    status: 'active', nextRun: '09:00:00 (tomorrow)', lastRun: '09:00:02', lastRunStatus: 'success',
    batchId: 'BATCH-002', totalRuns: 35, successRuns: 35, failedRuns: 0, createdAt: '2026-03-01', createdBy: 'admin@quoodle.io',
  },
  {
    id: 'job-003', name: 'Process List Monitor', command: 'process-list', params: {},
    deviceIds: ['SRV-PROD-01'],
    cronExpression: '*/15 * * * *', cronDescription: 'Every 15 minutes',
    status: 'active', nextRun: '21:15:00', lastRun: '21:00:05', lastRunStatus: 'success',
    batchId: 'BATCH-003', totalRuns: 672, successRuns: 670, failedRuns: 2, createdAt: '2026-02-15', createdBy: 'devops@quoodle.io',
  },
  {
    id: 'job-004', name: 'Weekly Compliance Scan', command: 'installed-apps', params: {},
    deviceIds: ['WKSTN-055', 'WKSTN-001', 'WKSTN-002', 'WKSTN-042', 'WKSTN-088', 'WKSTN-103', 'WKSTN-007', 'WKSTN-011'],
    cronExpression: '0 9 * * 1', cronDescription: 'Weekly on Monday at 9am',
    status: 'paused', nextRun: null, lastRun: '09:00:10', lastRunStatus: 'failed',
    batchId: 'BATCH-004', totalRuns: 8, successRuns: 6, failedRuns: 2, createdAt: '2026-02-01', createdBy: 'admin@quoodle.io',
  },
];

const mockRuns: RunRecord[] = [
  { id: 'run-001', batchId: 'BATCH-001', jobId: 'job-001', jobName: 'Hourly System Health Check', deviceId: 'WKSTN-055', hostname: 'WKSTN-055', status: 'success', startedAt: '21:00:01', completedAt: '21:00:09', duration: '8s', commandId: 'CMD-7742', error: null },
  { id: 'run-002', batchId: 'BATCH-001', jobId: 'job-001', jobName: 'Hourly System Health Check', deviceId: 'WKSTN-001', hostname: 'WKSTN-001', status: 'success', startedAt: '21:00:01', completedAt: '21:00:08', duration: '7s', commandId: 'CMD-7743', error: null },
  { id: 'run-003', batchId: 'BATCH-001', jobId: 'job-001', jobName: 'Hourly System Health Check', deviceId: 'WKSTN-002', hostname: 'WKSTN-002', status: 'success', startedAt: '21:00:01', completedAt: '21:00:10', duration: '9s', commandId: 'CMD-7744', error: null },
  { id: 'run-004', batchId: 'BATCH-001', jobId: 'job-001', jobName: 'Hourly System Health Check', deviceId: 'WKSTN-042', hostname: 'WKSTN-042', status: 'failed', startedAt: '21:00:01', completedAt: '21:00:15', duration: '14s', commandId: 'CMD-7745', error: 'Agent timeout — no ACK within TTL' },
  { id: 'run-005', batchId: 'BATCH-003', jobId: 'job-003', jobName: 'Process List Monitor', deviceId: 'SRV-PROD-01', hostname: 'SRV-PROD-01', status: 'running', startedAt: '21:00:05', completedAt: null, duration: null, commandId: 'CMD-7746', error: null },
  { id: 'run-006', batchId: 'BATCH-004', jobId: 'job-004', jobName: 'Weekly Compliance Scan', deviceId: 'WKSTN-007', hostname: 'WKSTN-007', status: 'failed', startedAt: '09:00:10', completedAt: '09:00:25', duration: '15s', commandId: 'CMD-7700', error: 'Device offline — command expired' },
];

export default function CommandSchedulingContent() {
  const [jobs, setJobs] = useState<ScheduledJob[]>(mockJobs);
  const [selectedJob, setSelectedJob] = useState<ScheduledJob | null>(null);
  const [activeTab, setActiveTab] = useState<'jobs' | 'history'>('jobs');
  const [showCreateModal, setShowCreateModal] = useState(false);
  const [historyFilter, setHistoryFilter] = useState<string>('all');

  const toggleJobStatus = (id: string) => {
    setJobs(prev => prev.map(j => j.id === id ? { ...j, status: j.status === 'active' ? 'paused' : 'active' } : j));
    toast.success('Schedule updated');
  };

  const deleteJob = (id: string) => {
    setJobs(prev => prev.filter(j => j.id !== id));
    if (selectedJob?.id === id) setSelectedJob(null);
    toast.success('Scheduled job removed');
  };

  const runNow = (job: ScheduledJob) => {
    toast.promise(
      new Promise(resolve => setTimeout(resolve, 1500)),
      { loading: `Running ${job.name} now…`, success: `Batch ${job.batchId} dispatched to ${job.deviceIds.length} devices`, error: 'Dispatch failed' }
    );
  };

  const statusColor = (s: ScheduleStatus) =>
    s === 'active' ? 'text-green-400 bg-green-500/10 border-green-500/20' :
    s === 'paused' ? 'text-amber-400 bg-amber-500/10 border-amber-500/20' :
    s === 'failed'? 'text-red-400 bg-red-500/10 border-red-500/20' : 'text-muted-foreground bg-muted border-border';

  const runStatusColor = (s: RunStatus) =>
    s === 'success' ? 'text-green-400' : s === 'failed' ? 'text-red-400' : s === 'running' ? 'text-blue-400' : 'text-muted-foreground';

  const filteredRuns = historyFilter === 'all' ? mockRuns : mockRuns.filter(r => r.batchId === historyFilter || r.jobId === historyFilter);

  return (
    <div className="space-y-4 fade-in">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">Command Scheduling</h1>
          <p className="text-sm text-muted-foreground mt-0.5">Queue commands for future execution with cron expressions and recurring runs</p>
        </div>
        <button
          onClick={() => setShowCreateModal(true)}
          className="flex items-center gap-2 px-3 py-2 text-sm font-medium bg-primary text-primary-foreground rounded-md hover:bg-primary/90 transition-all"
        >
          <Plus size={15} /> New Schedule
        </button>
      </div>

      {/* Stats */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
        {[
          { label: 'Active Schedules', value: jobs.filter(j => j.status === 'active').length, icon: Play, color: 'text-green-400' },
          { label: 'Paused', value: jobs.filter(j => j.status === 'paused').length, icon: Pause, color: 'text-amber-400' },
          { label: 'Total Runs', value: jobs.reduce((a, j) => a + j.totalRuns, 0).toLocaleString(), icon: Hash, color: 'text-primary' },
          { label: 'Success Rate', value: `${Math.round(jobs.reduce((a, j) => a + j.successRuns, 0) / Math.max(jobs.reduce((a, j) => a + j.totalRuns, 0), 1) * 100)}%`, icon: CheckCircle, color: 'text-green-400' },
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
        {(['jobs', 'history'] as const).map(tab => (
          <button
            key={tab}
            onClick={() => setActiveTab(tab)}
            className={`px-3 py-1.5 rounded-md text-xs font-medium transition-all capitalize ${
              activeTab === tab ? 'bg-card text-foreground shadow-sm' : 'text-muted-foreground hover:text-foreground'
            }`}
          >
            {tab === 'history' ? 'Execution History' : 'Scheduled Jobs'}
          </button>
        ))}
      </div>

      {activeTab === 'jobs' && (
        <div className="grid grid-cols-1 xl:grid-cols-3 gap-4">
          {/* Job list */}
          <div className="xl:col-span-1 space-y-2">
            {jobs.map(job => (
              <div
                key={job.id}
                onClick={() => setSelectedJob(selectedJob?.id === job.id ? null : job)}
                className={`bg-card border rounded-lg p-4 cursor-pointer transition-all hover:border-primary/40 ${
                  selectedJob?.id === job.id ? 'border-primary/60 bg-primary/5' : 'border-border'
                }`}
              >
                <div className="flex items-start justify-between mb-2">
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-semibold truncate">{job.name}</p>
                    <p className="text-[11px] text-muted-foreground font-mono">{job.cronExpression}</p>
                    <p className="text-[11px] text-muted-foreground">{job.cronDescription}</p>
                  </div>
                  <span className={`text-[10px] font-semibold px-2 py-0.5 rounded-full border ml-2 flex-shrink-0 ${statusColor(job.status)}`}>
                    {job.status.toUpperCase()}
                  </span>
                </div>
                <div className="flex items-center gap-3 text-[11px] text-muted-foreground">
                  <span className="flex items-center gap-1"><Terminal size={10} /> {job.command}</span>
                  <span className="flex items-center gap-1"><Monitor size={10} /> {job.deviceIds.length} devices</span>
                </div>
                {job.nextRun && (
                  <p className="text-[11px] text-primary mt-1.5 flex items-center gap-1">
                    <Clock size={10} /> Next: {job.nextRun}
                  </p>
                )}
              </div>
            ))}
          </div>

          {/* Job detail */}
          <div className="xl:col-span-2">
            {selectedJob ? (
              <div className="bg-card border border-border rounded-lg">
                <div className="flex items-center justify-between px-5 py-4 border-b border-border">
                  <div>
                    <h3 className="font-semibold">{selectedJob.name}</h3>
                    <p className="text-xs text-muted-foreground font-mono">{selectedJob.batchId}</p>
                  </div>
                  <div className="flex items-center gap-2">
                    <button onClick={() => runNow(selectedJob)} className="flex items-center gap-1.5 px-2.5 py-1.5 text-xs bg-green-500/10 border border-green-500/20 text-green-400 rounded-md hover:bg-green-500/20 transition-colors">
                      <Play size={11} /> Run Now
                    </button>
                    <button onClick={() => toggleJobStatus(selectedJob.id)} className="flex items-center gap-1.5 px-2.5 py-1.5 text-xs bg-amber-500/10 border border-amber-500/20 text-amber-400 rounded-md hover:bg-amber-500/20 transition-colors">
                      {selectedJob.status === 'active' ? <><Pause size={11} /> Pause</> : <><Play size={11} /> Resume</>}
                    </button>
                    <button onClick={() => deleteJob(selectedJob.id)} className="p-1.5 text-muted-foreground hover:text-red-400 transition-colors">
                      <Trash2 size={14} />
                    </button>
                  </div>
                </div>
                <div className="p-5 space-y-4">
                  {/* Cron */}
                  <div className="bg-muted/30 rounded-lg p-4">
                    <p className="text-[10px] text-muted-foreground uppercase tracking-wide mb-2">Cron Expression</p>
                    <div className="flex items-center gap-3">
                      <code className="text-lg font-mono font-bold text-primary">{selectedJob.cronExpression}</code>
                      <span className="text-sm text-muted-foreground">— {selectedJob.cronDescription}</span>
                    </div>
                    <div className="grid grid-cols-5 gap-1 mt-3">
                      {['Minute', 'Hour', 'Day', 'Month', 'Weekday'].map((label, i) => {
                        const parts = selectedJob.cronExpression.split(' ');
                        return (
                          <div key={label} className="text-center">
                            <p className="text-[10px] text-muted-foreground">{label}</p>
                            <p className="text-sm font-mono font-semibold">{parts[i] ?? '*'}</p>
                          </div>
                        );
                      })}
                    </div>
                  </div>

                  {/* Stats */}
                  <div className="grid grid-cols-3 gap-3">
                    {[
                      { label: 'Total Runs', value: selectedJob.totalRuns.toLocaleString() },
                      { label: 'Successful', value: selectedJob.successRuns.toLocaleString(), color: 'text-green-400' },
                      { label: 'Failed', value: selectedJob.failedRuns.toLocaleString(), color: selectedJob.failedRuns > 0 ? 'text-red-400' : undefined },
                    ].map(s => (
                      <div key={s.label} className="bg-muted/30 rounded-lg p-3 text-center">
                        <p className="text-[10px] text-muted-foreground uppercase tracking-wide mb-1">{s.label}</p>
                        <p className={`text-xl font-bold tabular-nums ${s.color ?? ''}`}>{s.value}</p>
                      </div>
                    ))}
                  </div>

                  {/* Devices */}
                  <div>
                    <p className="text-[10px] text-muted-foreground uppercase tracking-wide mb-2">Target Devices ({selectedJob.deviceIds.length})</p>
                    <div className="flex flex-wrap gap-1.5">
                      {selectedJob.deviceIds.map(d => (
                        <span key={d} className="text-[11px] px-2 py-0.5 bg-muted/40 text-muted-foreground rounded-full border border-border font-mono">{d}</span>
                      ))}
                    </div>
                  </div>

                  {/* Recent runs for this job */}
                  <div>
                    <p className="text-[10px] text-muted-foreground uppercase tracking-wide mb-2">Recent Batch Runs</p>
                    <div className="space-y-1.5">
                      {mockRuns.filter(r => r.jobId === selectedJob.id).map(run => (
                        <div key={run.id} className="flex items-center gap-3 bg-muted/20 rounded-lg px-3 py-2.5">
                          {run.status === 'success' ? <CheckCircle size={12} className="text-green-400 flex-shrink-0" /> :
                           run.status === 'failed' ? <XCircle size={12} className="text-red-400 flex-shrink-0" /> :
                           run.status === 'running' ? <RotateCcw size={12} className="text-blue-400 flex-shrink-0 animate-spin" /> :
                           <AlertTriangle size={12} className="text-muted-foreground flex-shrink-0" />}
                          <span className={`text-[11px] font-medium w-14 ${runStatusColor(run.status)}`}>{run.status.toUpperCase()}</span>
                          <span className="text-[11px] font-mono text-muted-foreground flex-1">{run.hostname}</span>
                          <span className="text-[11px] text-muted-foreground tabular-nums">{run.startedAt}</span>
                          {run.duration && <span className="text-[11px] text-muted-foreground">{run.duration}</span>}
                          {run.error && <span className="text-[11px] text-red-400 truncate max-w-[120px]" title={run.error}>{run.error}</span>}
                        </div>
                      ))}
                    </div>
                  </div>
                </div>
              </div>
            ) : (
              <div className="bg-card border border-border rounded-lg flex items-center justify-center h-64">
                <div className="text-center">
                  <Calendar size={32} className="mx-auto text-muted-foreground/30 mb-3" />
                  <p className="text-sm font-medium text-muted-foreground">Select a scheduled job to view details</p>
                </div>
              </div>
            )}
          </div>
        </div>
      )}

      {activeTab === 'history' && (
        <div className="space-y-3">
          {/* Batch filter */}
          <div className="flex items-center gap-2">
            <select
              value={historyFilter}
              onChange={e => setHistoryFilter(e.target.value)}
              className="text-xs bg-muted/60 border border-border rounded-md px-2.5 py-1.5 text-foreground focus:outline-none focus:ring-1 focus:ring-primary/50"
            >
              <option value="all">All Batches</option>
              {jobs.map(j => (
                <option key={j.batchId} value={j.batchId}>{j.batchId} — {j.name}</option>
              ))}
            </select>
            <button onClick={() => toast.info('History refreshed')} className="flex items-center gap-1.5 px-3 py-1.5 text-xs text-muted-foreground border border-border rounded-md hover:bg-muted/60 transition-colors">
              <RefreshCw size={12} /> Refresh
            </button>
          </div>

          <div className="bg-card border border-border rounded-lg overflow-hidden">
            <div className="px-4 py-3 border-b border-border">
              <p className="text-sm font-semibold">Execution History</p>
            </div>
            <div className="overflow-x-auto">
              <table className="w-full text-xs">
                <thead>
                  <tr className="border-b border-border bg-muted/20">
                    {['Batch ID', 'Job', 'Device', 'Status', 'Started', 'Duration', 'Command ID', 'Error'].map(col => (
                      <th key={col} className="px-3 py-3 text-left font-semibold text-muted-foreground tracking-wide uppercase text-[10px] whitespace-nowrap">{col}</th>
                    ))}
                  </tr>
                </thead>
                <tbody className="divide-y divide-border">
                  {filteredRuns.map(run => (
                    <tr key={run.id} className="hover:bg-muted/20 transition-colors">
                      <td className="px-3 py-3 font-mono text-[11px] text-primary">{run.batchId}</td>
                      <td className="px-3 py-3 text-[11px] max-w-[140px] truncate">{run.jobName}</td>
                      <td className="px-3 py-3 font-mono text-[11px]">{run.hostname}</td>
                      <td className="px-3 py-3">
                        <div className="flex items-center gap-1.5">
                          {run.status === 'success' ? <CheckCircle size={11} className="text-green-400" /> :
                           run.status === 'failed' ? <XCircle size={11} className="text-red-400" /> :
                           run.status === 'running' ? <RotateCcw size={11} className="text-blue-400 animate-spin" /> :
                           <AlertTriangle size={11} className="text-muted-foreground" />}
                          <span className={`font-medium ${runStatusColor(run.status)}`}>{run.status.toUpperCase()}</span>
                        </div>
                      </td>
                      <td className="px-3 py-3 tabular-nums text-muted-foreground">{run.startedAt}</td>
                      <td className="px-3 py-3 text-muted-foreground">{run.duration ?? '—'}</td>
                      <td className="px-3 py-3 font-mono text-[11px] text-muted-foreground">{run.commandId ?? '—'}</td>
                      <td className="px-3 py-3 text-[11px] text-red-400 max-w-[160px] truncate" title={run.error ?? undefined}>{run.error ?? '—'}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        </div>
      )}

      {/* Create Modal */}
      {showCreateModal && (
        <CreateScheduleModal
          onClose={() => setShowCreateModal(false)}
          onSave={(job) => {
            setJobs(prev => [...prev, job]);
            setShowCreateModal(false);
            toast.success('Schedule created');
          }}
        />
      )}
    </div>
  );
}

function CreateScheduleModal({ onClose, onSave }: { onClose: () => void; onSave: (job: ScheduledJob) => void }) {
  const [name, setName] = useState('');
  const [command, setCommand] = useState('system-info');
  const [cronExpression, setCronExpression] = useState('0 * * * *');
  const [cronDescription, setCronDescription] = useState('Every hour');
  const [deviceIds, setDeviceIds] = useState<string[]>([]);
  const deviceOptions = ['WKSTN-055', 'WKSTN-001', 'WKSTN-002', 'WKSTN-042', 'WKSTN-088', 'WKSTN-103', 'SRV-PROD-01'];

  const toggleDevice = (d: string) => setDeviceIds(prev => prev.includes(d) ? prev.filter(x => x !== d) : [...prev, d]);

  const handleSave = () => {
    if (!name || deviceIds.length === 0) {
      toast.error('Please fill in all required fields and select at least one device');
      return;
    }
    const batchId = 'BATCH-' + String(Math.floor(Math.random() * 900) + 100);
    onSave({
      id: 'job-' + Date.now(), name, command, params: {},
      deviceIds, cronExpression, cronDescription,
      status: 'active', nextRun: 'Calculating…', lastRun: null, lastRunStatus: null,
      batchId, totalRuns: 0, successRuns: 0, failedRuns: 0,
      createdAt: new Date().toISOString().split('T')[0], createdBy: 'admin@quoodle.io',
    });
  };

  return (
    <>
      <div className="fixed inset-0 bg-black/50 z-40" onClick={onClose} />
      <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
        <div className="bg-zinc-950 border border-border rounded-xl w-full max-w-lg max-h-[90vh] overflow-y-auto">
          <div className="flex items-center justify-between px-5 py-4 border-b border-border">
            <h3 className="font-semibold">New Scheduled Job</h3>
            <button onClick={onClose} className="p-1.5 text-muted-foreground hover:text-foreground transition-colors"><X size={15} /></button>
          </div>
          <div className="p-5 space-y-4">
            <div>
              <label className="text-xs text-muted-foreground mb-1 block">Job Name *</label>
              <input value={name} onChange={e => setName(e.target.value)} placeholder="e.g. Hourly System Health Check" className="w-full px-3 py-2 text-sm bg-muted/60 border border-border rounded-md focus:outline-none focus:ring-1 focus:ring-primary/50" />
            </div>
            <div>
              <label className="text-xs text-muted-foreground mb-1 block">Command</label>
              <select value={command} onChange={e => setCommand(e.target.value)} className="w-full px-3 py-2 text-sm bg-muted/60 border border-border rounded-md focus:outline-none focus:ring-1 focus:ring-primary/50">
                {COMMAND_LIBRARY.map(c => <option key={c} value={c}>{c}</option>)}
              </select>
            </div>
            <div>
              <label className="text-xs text-muted-foreground mb-1 block">Cron Expression</label>
              <input value={cronExpression} onChange={e => setCronExpression(e.target.value)} placeholder="0 * * * *" className="w-full px-3 py-2 text-sm bg-muted/60 border border-border rounded-md font-mono focus:outline-none focus:ring-1 focus:ring-primary/50" />
              <div className="flex flex-wrap gap-1.5 mt-2">
                {CRON_PRESETS.map(p => (
                  <button key={p.value} onClick={() => { setCronExpression(p.value); setCronDescription(p.label); }} className={`text-[11px] px-2 py-0.5 rounded-full border transition-colors ${cronExpression === p.value ? 'bg-primary/20 text-primary border-primary/40' : 'bg-muted/40 text-muted-foreground border-border hover:border-primary/30'}`}>
                    {p.label}
                  </button>
                ))}
              </div>
            </div>
            <div>
              <label className="text-xs text-muted-foreground mb-2 block">Target Devices *</label>
              <div className="flex flex-wrap gap-1.5">
                {deviceOptions.map(d => (
                  <button key={d} onClick={() => toggleDevice(d)} className={`text-[11px] px-2 py-0.5 rounded-full border font-mono transition-colors ${deviceIds.includes(d) ? 'bg-primary/20 text-primary border-primary/40' : 'bg-muted/40 text-muted-foreground border-border hover:border-primary/30'}`}>
                    {d}
                  </button>
                ))}
              </div>
            </div>
          </div>
          <div className="flex items-center justify-end gap-2 px-5 py-4 border-t border-border">
            <button onClick={onClose} className="px-4 py-2 text-sm text-muted-foreground hover:text-foreground transition-colors">Cancel</button>
            <button onClick={handleSave} className="flex items-center gap-1.5 px-4 py-2 text-sm bg-primary text-primary-foreground rounded-md hover:bg-primary/90 transition-colors">
              <Save size={13} /> Create Schedule
            </button>
          </div>
        </div>
      </div>
    </>
  );
}
