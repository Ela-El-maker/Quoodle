'use client';
import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  Calendar,
  Plus,
  Play,
  Pause,
  Trash2,
  Clock,
  RefreshCw,
  CheckCircle,
  XCircle,
  AlertTriangle,
  Terminal,
  Monitor,
  RotateCcw,
  X,
  Save,
  Hash,
  Loader2,
} from 'lucide-react';
import { toast } from 'sonner';
import { resolveCommandMethod } from '@/lib/commandMethodResolver';

type ScheduleStatus = 'active' | 'paused' | 'completed' | 'failed';
type RunStatus = 'success' | 'failed' | 'running' | 'skipped';

interface ScheduledJob {
  id: string;
  name: string;
  command: string;
  params: Record<string, unknown>;
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
  enabled: boolean;
  timezone: string;
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

interface ApiScheduleRow {
  id: string;
  name?: string;
  method?: string;
  params?: Record<string, unknown>;
  resolved_device_ids?: string[];
  target_ids?: string[];
  cron_expression?: string;
  timezone?: string;
  enabled?: boolean;
  last_run_at?: string | null;
  next_run_at?: string | null;
  last_run_status?: string | null;
  total_runs?: number;
  success_runs?: number;
  failed_runs?: number;
  created_at?: string | null;
  created_by_email?: string | null;
}

interface ApiSchedulesResponse {
  schedules?: ApiScheduleRow[];
}

interface ApiRunRow {
  id: string;
  batch_id?: string | null;
  job_id?: string | null;
  job_name?: string | null;
  device_id?: string | null;
  hostname?: string | null;
  status?: string | null;
  started_at?: string | null;
  completed_at?: string | null;
  duration_seconds?: number | null;
  command_id?: string | null;
  error_message?: string | null;
}

interface ApiRunsResponse {
  runs?: ApiRunRow[];
}

interface DevicesApiResponse {
  devices?: Array<{
    device_id: string;
    device_name?: string | null;
  }>;
}

interface CapabilitiesApiResponse {
  canonical_methods?: string[];
  runtime_supported_methods?: string[];
}

interface CreatePayload {
  name: string;
  method: string;
  cronExpression: string;
  cronDescription: string;
  deviceIds: string[];
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

function formatDate(value: string | null | undefined): string {
  if (!value) return '-';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return '-';
  return date.toLocaleDateString();
}

function formatDateTime(value: string | null | undefined): string | null {
  if (!value) return null;
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return null;
  return date.toLocaleString();
}

function describeCron(expression: string): string {
  const preset = CRON_PRESETS.find((item) => item.value === expression);
  return preset?.label ?? expression;
}

function mapRunStatus(value: string | null | undefined): RunStatus {
  const normalized = String(value ?? '').trim().toLowerCase();
  if (normalized === 'success' || normalized === 'completed') return 'success';
  if (normalized === 'failed' || normalized === 'error' || normalized === 'expired' || normalized === 'rejected') return 'failed';
  return 'running';
}

function mapScheduleStatus(enabled: boolean): ScheduleStatus {
  return enabled ? 'active' : 'paused';
}

function toScheduledJob(row: ApiScheduleRow): ScheduledJob {
  const totalRuns = Number(row.total_runs ?? 0);
  const successRuns = Number(row.success_runs ?? 0);
  const failedRuns = Number(row.failed_runs ?? 0);
  const deviceIds = Array.isArray(row.resolved_device_ids) && row.resolved_device_ids.length > 0
    ? row.resolved_device_ids
    : Array.isArray(row.target_ids)
      ? row.target_ids
      : [];
  const id = String(row.id);
  const enabled = Boolean(row.enabled);
  const cronExpression = String(row.cron_expression ?? '');

  return {
    id,
    name: String(row.name ?? 'Unnamed schedule'),
    command: String(row.method ?? 'unknown'),
    params: row.params ?? {},
    deviceIds,
    cronExpression,
    cronDescription: describeCron(cronExpression),
    status: mapScheduleStatus(enabled),
    nextRun: formatDateTime(row.next_run_at),
    lastRun: formatDateTime(row.last_run_at),
    lastRunStatus: row.last_run_status ? mapRunStatus(row.last_run_status) : null,
    batchId: `SCH-${id.slice(-6).toUpperCase()}`,
    totalRuns,
    successRuns,
    failedRuns,
    createdAt: formatDate(row.created_at ?? null),
    createdBy: String(row.created_by_email ?? 'unknown'),
    enabled,
    timezone: String(row.timezone ?? 'UTC'),
  };
}

function toRunRecord(row: ApiRunRow): RunRecord {
  const startedAt = formatDateTime(row.started_at);
  const completedAt = formatDateTime(row.completed_at);
  const durationSeconds = Number(row.duration_seconds ?? 0);

  return {
    id: String(row.id),
    batchId: String(row.batch_id ?? row.id),
    jobId: String(row.job_id ?? ''),
    jobName: String(row.job_name ?? 'Unknown job'),
    deviceId: String(row.device_id ?? ''),
    hostname: String(row.hostname ?? row.device_id ?? 'unknown-device'),
    status: mapRunStatus(row.status),
    startedAt: startedAt ?? '-',
    completedAt,
    duration: durationSeconds > 0 ? `${durationSeconds}s` : null,
    commandId: row.command_id ? String(row.command_id) : null,
    error: row.error_message ? String(row.error_message) : null,
  };
}

export default function CommandSchedulingContent() {
  const [jobs, setJobs] = useState<ScheduledJob[]>([]);
  const [runs, setRuns] = useState<RunRecord[]>([]);
  const [selectedJobId, setSelectedJobId] = useState<string | null>(null);
  const [activeTab, setActiveTab] = useState<'jobs' | 'history'>('jobs');
  const [showCreateModal, setShowCreateModal] = useState(false);
  const [historyFilter, setHistoryFilter] = useState<string>('all');
  const [isLoading, setIsLoading] = useState(true);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [isSaving, setIsSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const [deviceOptions, setDeviceOptions] = useState<Array<{ id: string; label: string }>>([]);
  const [commandOptions, setCommandOptions] = useState<string[]>([]);

  const fetchAbortRef = useRef<AbortController | null>(null);
  const selectedJob = useMemo(() => jobs.find((job) => job.id === selectedJobId) ?? null, [jobs, selectedJobId]);

  const loadData = useCallback(async (mode: 'initial' | 'refresh' | 'silent' = 'initial') => {
    if (mode === 'initial') setIsLoading(true);
    if (mode === 'refresh') setIsRefreshing(true);

    fetchAbortRef.current?.abort();
    const controller = new AbortController();
    fetchAbortRef.current = controller;

    try {
      const [schedulesRes, runsRes, devicesRes, capabilitiesRes] = await Promise.all([
        fetch('/api/schedules', { credentials: 'include', cache: 'no-store', signal: controller.signal }),
        fetch('/api/schedules/runs?limit=400', { credentials: 'include', cache: 'no-store', signal: controller.signal }),
        fetch('/api/devices?per_page=200', { credentials: 'include', cache: 'no-store', signal: controller.signal }),
        fetch('/api/commands/capabilities', { credentials: 'include', cache: 'no-store', signal: controller.signal }),
      ]);

      if (!schedulesRes.ok) throw new Error(`schedules_http_${schedulesRes.status}`);
      if (!runsRes.ok) throw new Error(`schedule_runs_http_${runsRes.status}`);

      const schedulesPayload = (await schedulesRes.json()) as ApiSchedulesResponse;
      const runsPayload = (await runsRes.json()) as ApiRunsResponse;
      const devicesPayload = devicesRes.ok ? ((await devicesRes.json()) as DevicesApiResponse) : { devices: [] };
      const capabilitiesPayload = capabilitiesRes.ok
        ? ((await capabilitiesRes.json()) as CapabilitiesApiResponse)
        : { canonical_methods: [], runtime_supported_methods: [] };

      const nextJobs = (schedulesPayload.schedules ?? []).map(toScheduledJob);
      const nextRuns = (runsPayload.runs ?? []).map(toRunRecord);

      setJobs(nextJobs);
      setRuns(nextRuns);
      setSelectedJobId((current) => (current && nextJobs.some((job) => job.id === current) ? current : null));

      const devices = (devicesPayload.devices ?? [])
        .map((device) => ({
          id: String(device.device_id),
          label: device.device_name ? `${device.device_name} (${device.device_id})` : String(device.device_id),
        }))
        .sort((a, b) => a.label.localeCompare(b.label));
      setDeviceOptions(devices);

      const runtime = Array.isArray(capabilitiesPayload.runtime_supported_methods)
        ? capabilitiesPayload.runtime_supported_methods
        : [];
      const canonical = Array.isArray(capabilitiesPayload.canonical_methods)
        ? capabilitiesPayload.canonical_methods
        : [];
      const methods = Array.from(new Set([...runtime, ...canonical])).sort();
      setCommandOptions(methods);

      setError(null);
    } catch (loadError) {
      if ((loadError as Error).name === 'AbortError') return;
      console.error('scheduling-load-failed', loadError);
      setError('Failed to load schedule data');
      if (mode === 'initial') {
        setJobs([]);
        setRuns([]);
      }
    } finally {
      if (mode === 'initial') setIsLoading(false);
      if (mode === 'refresh') setIsRefreshing(false);
    }
  }, []);

  useEffect(() => {
    void loadData('initial');
  }, [loadData]);

  useEffect(() => {
    let interval: ReturnType<typeof setInterval> | null = null;

    const startPolling = () => {
      if (interval) clearInterval(interval);
      const pollMs = document.visibilityState === 'visible' ? 10000 : 30000;
      interval = setInterval(() => {
        void loadData('silent');
      }, pollMs);
    };

    startPolling();
    const onVisibility = () => startPolling();
    document.addEventListener('visibilitychange', onVisibility);

    return () => {
      if (interval) clearInterval(interval);
      document.removeEventListener('visibilitychange', onVisibility);
      fetchAbortRef.current?.abort();
    };
  }, [loadData]);

  const toggleJobStatus = async (id: string) => {
    const job = jobs.find((entry) => entry.id === id);
    if (!job) return;

    try {
      const response = await fetch(`/api/schedules/${encodeURIComponent(id)}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        credentials: 'include',
        body: JSON.stringify({ enabled: !job.enabled }),
      });

      if (!response.ok) throw new Error(`toggle_http_${response.status}`);
      toast.success('Schedule updated');
      void loadData('refresh');
    } catch (toggleError) {
      console.error('schedule-toggle-failed', toggleError);
      toast.error('Failed to update schedule');
    }
  };

  const deleteJob = async (id: string) => {
    try {
      const response = await fetch(`/api/schedules/${encodeURIComponent(id)}`, {
        method: 'DELETE',
        credentials: 'include',
      });

      if (!response.ok) throw new Error(`delete_http_${response.status}`);
      if (selectedJobId === id) setSelectedJobId(null);
      toast.success('Scheduled job removed');
      void loadData('refresh');
    } catch (deleteError) {
      console.error('schedule-delete-failed', deleteError);
      toast.error('Failed to delete schedule');
    }
  };

  const runNow = (job: ScheduledJob) => {
    toast.promise(
      fetch(`/api/schedules/${encodeURIComponent(job.id)}/run-now`, {
        method: 'POST',
        credentials: 'include',
        headers: { 'Content-Type': 'application/json' },
      }).then((response) => {
        if (!response.ok) throw new Error(`run_now_http_${response.status}`);
        return response;
      }),
      {
        loading: `Running ${job.name} now...`,
        success: `Run dispatched for ${job.deviceIds.length} devices`,
        error: 'Run now failed',
      },
    );

    void loadData('refresh');
  };

  const createSchedule = async (payload: CreatePayload) => {
    setIsSaving(true);

    try {
      const timezone = Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC';
      const response = await fetch('/api/schedules', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        credentials: 'include',
        body: JSON.stringify({
          name: payload.name,
          method: resolveCommandMethod(payload.method),
          params: {},
          target_type: 'device',
          target_ids: payload.deviceIds,
          cron_expression: payload.cronExpression,
          timezone,
          enabled: true,
        }),
      });

      if (!response.ok) {
        const errorPayload = (await response.json().catch(() => ({}))) as { reason?: string; message?: string };
        throw new Error(errorPayload.reason ?? errorPayload.message ?? `create_http_${response.status}`);
      }

      setShowCreateModal(false);
      toast.success('Schedule created');
      void loadData('refresh');
    } catch (createError) {
      console.error('schedule-create-failed', createError);
      toast.error((createError as Error).message || 'Failed to create schedule');
    } finally {
      setIsSaving(false);
    }
  };

  const statusColor = (status: ScheduleStatus) =>
    status === 'active'
      ? 'text-green-400 bg-green-500/10 border-green-500/20'
      : status === 'paused'
        ? 'text-amber-400 bg-amber-500/10 border-amber-500/20'
        : status === 'failed'
          ? 'text-red-400 bg-red-500/10 border-red-500/20'
          : 'text-muted-foreground bg-muted border-border';

  const runStatusColor = (status: RunStatus) =>
    status === 'success'
      ? 'text-green-400'
      : status === 'failed'
        ? 'text-red-400'
        : status === 'running'
          ? 'text-blue-400'
          : 'text-muted-foreground';

  const filteredRuns = historyFilter === 'all'
    ? runs
    : runs.filter((run) => run.batchId === historyFilter || run.jobId === historyFilter);

  return (
    <div className="space-y-4 fade-in">
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

      {error ? (
        <div className="bg-red-500/10 border border-red-500/30 rounded-md px-3 py-2 text-xs text-red-300">
          {error}
        </div>
      ) : null}

      <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
        {[
          { label: 'Active Schedules', value: jobs.filter((job) => job.status === 'active').length, icon: Play, color: 'text-green-400' },
          { label: 'Paused', value: jobs.filter((job) => job.status === 'paused').length, icon: Pause, color: 'text-amber-400' },
          { label: 'Total Runs', value: jobs.reduce((acc, job) => acc + job.totalRuns, 0).toLocaleString(), icon: Hash, color: 'text-primary' },
          {
            label: 'Success Rate',
            value: `${Math.round((jobs.reduce((acc, job) => acc + job.successRuns, 0) / Math.max(jobs.reduce((acc, job) => acc + job.totalRuns, 0), 1)) * 100)}%`,
            icon: CheckCircle,
            color: 'text-green-400',
          },
        ].map((stat) => (
          <div key={stat.label} className="bg-card border border-border rounded-lg p-4">
            <div className="flex items-center justify-between mb-1">
              <p className="text-xs text-muted-foreground">{stat.label}</p>
              <stat.icon size={14} className={stat.color} />
            </div>
            <p className="text-2xl font-bold tabular-nums">{stat.value}</p>
          </div>
        ))}
      </div>

      <div className="flex items-center gap-2">
        <div className="flex items-center gap-1 bg-muted/30 rounded-lg p-1 w-fit">
          {(['jobs', 'history'] as const).map((tab) => (
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

        <button
          onClick={() => {
            void loadData('refresh');
          }}
          className="flex items-center gap-1.5 px-3 py-1.5 text-xs text-muted-foreground border border-border rounded-md hover:bg-muted/60 transition-colors"
        >
          {isRefreshing ? <Loader2 size={12} className="animate-spin" /> : <RefreshCw size={12} />}
          Refresh
        </button>
      </div>

      {isLoading ? (
        <div className="bg-card border border-border rounded-lg h-64 flex items-center justify-center text-sm text-muted-foreground">
          <Loader2 size={16} className="animate-spin mr-2" /> Loading schedules...
        </div>
      ) : null}

      {!isLoading && activeTab === 'jobs' && (
        <div className="grid grid-cols-1 xl:grid-cols-3 gap-4">
          <div className="xl:col-span-1 space-y-2">
            {jobs.map((job) => (
              <div
                key={job.id}
                onClick={() => setSelectedJobId(selectedJobId === job.id ? null : job.id)}
                className={`bg-card border rounded-lg p-4 cursor-pointer transition-all hover:border-primary/40 ${
                  selectedJobId === job.id ? 'border-primary/60 bg-primary/5' : 'border-border'
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
                {job.nextRun ? (
                  <p className="text-[11px] text-primary mt-1.5 flex items-center gap-1">
                    <Clock size={10} /> Next: {job.nextRun}
                  </p>
                ) : null}
              </div>
            ))}

            {jobs.length === 0 ? (
              <div className="bg-card border border-border rounded-lg p-6 text-center text-sm text-muted-foreground">
                No schedules found.
              </div>
            ) : null}
          </div>

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
                    <button onClick={() => { void toggleJobStatus(selectedJob.id); }} className="flex items-center gap-1.5 px-2.5 py-1.5 text-xs bg-amber-500/10 border border-amber-500/20 text-amber-400 rounded-md hover:bg-amber-500/20 transition-colors">
                      {selectedJob.status === 'active' ? <><Pause size={11} /> Pause</> : <><Play size={11} /> Resume</>}
                    </button>
                    <button onClick={() => { void deleteJob(selectedJob.id); }} className="p-1.5 text-muted-foreground hover:text-red-400 transition-colors">
                      <Trash2 size={14} />
                    </button>
                  </div>
                </div>
                <div className="p-5 space-y-4">
                  <div className="bg-muted/30 rounded-lg p-4">
                    <p className="text-[10px] text-muted-foreground uppercase tracking-wide mb-2">Cron Expression</p>
                    <div className="flex items-center gap-3">
                      <code className="text-lg font-mono font-bold text-primary">{selectedJob.cronExpression}</code>
                      <span className="text-sm text-muted-foreground">- {selectedJob.cronDescription}</span>
                    </div>
                    <div className="grid grid-cols-5 gap-1 mt-3">
                      {['Minute', 'Hour', 'Day', 'Month', 'Weekday'].map((label, index) => {
                        const parts = selectedJob.cronExpression.split(' ');
                        return (
                          <div key={label} className="text-center">
                            <p className="text-[10px] text-muted-foreground">{label}</p>
                            <p className="text-sm font-mono font-semibold">{parts[index] ?? '*'}</p>
                          </div>
                        );
                      })}
                    </div>
                  </div>

                  <div className="grid grid-cols-3 gap-3">
                    {[
                      { label: 'Total Runs', value: selectedJob.totalRuns.toLocaleString() },
                      { label: 'Successful', value: selectedJob.successRuns.toLocaleString(), color: 'text-green-400' },
                      { label: 'Failed', value: selectedJob.failedRuns.toLocaleString(), color: selectedJob.failedRuns > 0 ? 'text-red-400' : undefined },
                    ].map((stat) => (
                      <div key={stat.label} className="bg-muted/30 rounded-lg p-3 text-center">
                        <p className="text-[10px] text-muted-foreground uppercase tracking-wide mb-1">{stat.label}</p>
                        <p className={`text-xl font-bold tabular-nums ${stat.color ?? ''}`}>{stat.value}</p>
                      </div>
                    ))}
                  </div>

                  <div>
                    <p className="text-[10px] text-muted-foreground uppercase tracking-wide mb-2">Target Devices ({selectedJob.deviceIds.length})</p>
                    <div className="flex flex-wrap gap-1.5">
                      {selectedJob.deviceIds.map((deviceId) => (
                        <span key={deviceId} className="text-[11px] px-2 py-0.5 bg-muted/40 text-muted-foreground rounded-full border border-border font-mono">{deviceId}</span>
                      ))}
                    </div>
                  </div>

                  <div>
                    <p className="text-[10px] text-muted-foreground uppercase tracking-wide mb-2">Recent Batch Runs</p>
                    <div className="space-y-1.5">
                      {runs.filter((run) => run.jobId === selectedJob.id).slice(0, 8).map((run) => (
                        <div key={run.id} className="flex items-center gap-3 bg-muted/20 rounded-lg px-3 py-2.5">
                          {run.status === 'success' ? <CheckCircle size={12} className="text-green-400 flex-shrink-0" />
                            : run.status === 'failed' ? <XCircle size={12} className="text-red-400 flex-shrink-0" />
                              : run.status === 'running' ? <RotateCcw size={12} className="text-blue-400 flex-shrink-0 animate-spin" />
                                : <AlertTriangle size={12} className="text-muted-foreground flex-shrink-0" />}
                          <span className={`text-[11px] font-medium w-14 ${runStatusColor(run.status)}`}>{run.status.toUpperCase()}</span>
                          <span className="text-[11px] font-mono text-muted-foreground flex-1">{run.hostname}</span>
                          <span className="text-[11px] text-muted-foreground tabular-nums">{run.startedAt}</span>
                          {run.duration ? <span className="text-[11px] text-muted-foreground">{run.duration}</span> : null}
                          {run.error ? <span className="text-[11px] text-red-400 truncate max-w-[120px]" title={run.error}>{run.error}</span> : null}
                        </div>
                      ))}

                      {runs.filter((run) => run.jobId === selectedJob.id).length === 0 ? (
                        <div className="text-xs text-muted-foreground py-3">No run history yet.</div>
                      ) : null}
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

      {!isLoading && activeTab === 'history' && (
        <div className="space-y-3">
          <div className="flex items-center gap-2">
            <select
              value={historyFilter}
              onChange={(event) => setHistoryFilter(event.target.value)}
              className="text-xs bg-muted/60 border border-border rounded-md px-2.5 py-1.5 text-foreground focus:outline-none focus:ring-1 focus:ring-primary/50"
            >
              <option value="all">All Batches</option>
              {jobs.map((job) => (
                <option key={job.batchId} value={job.id}>{job.batchId} - {job.name}</option>
              ))}
            </select>
            <button onClick={() => { void loadData('refresh'); }} className="flex items-center gap-1.5 px-3 py-1.5 text-xs text-muted-foreground border border-border rounded-md hover:bg-muted/60 transition-colors">
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
                    {['Batch ID', 'Job', 'Device', 'Status', 'Started', 'Duration', 'Command ID', 'Error'].map((column) => (
                      <th key={column} className="px-3 py-3 text-left font-semibold text-muted-foreground tracking-wide uppercase text-[10px] whitespace-nowrap">{column}</th>
                    ))}
                  </tr>
                </thead>
                <tbody className="divide-y divide-border">
                  {filteredRuns.map((run) => (
                    <tr key={run.id} className="hover:bg-muted/20 transition-colors">
                      <td className="px-3 py-3 font-mono text-[11px] text-primary">{run.batchId}</td>
                      <td className="px-3 py-3 text-[11px] max-w-[140px] truncate">{run.jobName}</td>
                      <td className="px-3 py-3 font-mono text-[11px]">{run.hostname}</td>
                      <td className="px-3 py-3">
                        <div className="flex items-center gap-1.5">
                          {run.status === 'success' ? <CheckCircle size={11} className="text-green-400" />
                            : run.status === 'failed' ? <XCircle size={11} className="text-red-400" />
                              : run.status === 'running' ? <RotateCcw size={11} className="text-blue-400 animate-spin" />
                                : <AlertTriangle size={11} className="text-muted-foreground" />}
                          <span className={`font-medium ${runStatusColor(run.status)}`}>{run.status.toUpperCase()}</span>
                        </div>
                      </td>
                      <td className="px-3 py-3 tabular-nums text-muted-foreground">{run.startedAt}</td>
                      <td className="px-3 py-3 text-muted-foreground">{run.duration ?? '-'}</td>
                      <td className="px-3 py-3 font-mono text-[11px] text-muted-foreground">{run.commandId ?? '-'}</td>
                      <td className="px-3 py-3 text-[11px] text-red-400 max-w-[160px] truncate" title={run.error ?? undefined}>{run.error ?? '-'}</td>
                    </tr>
                  ))}
                  {filteredRuns.length === 0 ? (
                    <tr>
                      <td colSpan={8} className="px-3 py-8 text-center text-muted-foreground text-xs">No execution history found.</td>
                    </tr>
                  ) : null}
                </tbody>
              </table>
            </div>
          </div>
        </div>
      )}

      {showCreateModal ? (
        <CreateScheduleModal
          onClose={() => setShowCreateModal(false)}
          onSave={createSchedule}
          deviceOptions={deviceOptions}
          commandOptions={commandOptions}
          isSubmitting={isSaving}
        />
      ) : null}
    </div>
  );
}

function CreateScheduleModal({
  onClose,
  onSave,
  deviceOptions,
  commandOptions,
  isSubmitting,
}: {
  onClose: () => void;
  onSave: (payload: CreatePayload) => Promise<void>;
  deviceOptions: Array<{ id: string; label: string }>;
  commandOptions: string[];
  isSubmitting: boolean;
}) {
  const [name, setName] = useState('');
  const [command, setCommand] = useState(commandOptions[0] ?? '');
  const [cronExpression, setCronExpression] = useState('0 * * * *');
  const [cronDescription, setCronDescription] = useState('Every hour');
  const [deviceIds, setDeviceIds] = useState<string[]>([]);

  useEffect(() => {
    if (!command && commandOptions.length > 0) {
      setCommand(commandOptions[0]);
    }
  }, [command, commandOptions]);

  const toggleDevice = (id: string) => {
    setDeviceIds((previous) => (previous.includes(id) ? previous.filter((entry) => entry !== id) : [...previous, id]));
  };

  const handleSave = () => {
    if (!name.trim() || !command || deviceIds.length === 0) {
      toast.error('Please fill in all required fields and select at least one device');
      return;
    }

    void onSave({
      name: name.trim(),
      method: command,
      cronExpression,
      cronDescription,
      deviceIds,
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
              <input value={name} onChange={(event) => setName(event.target.value)} placeholder="e.g. Hourly System Health Check" className="w-full px-3 py-2 text-sm bg-muted/60 border border-border rounded-md focus:outline-none focus:ring-1 focus:ring-primary/50" />
            </div>
            <div>
              <label className="text-xs text-muted-foreground mb-1 block">Command *</label>
              <select value={command} onChange={(event) => setCommand(event.target.value)} className="w-full px-3 py-2 text-sm bg-muted/60 border border-border rounded-md focus:outline-none focus:ring-1 focus:ring-primary/50">
                {commandOptions.map((method) => <option key={method} value={method}>{method}</option>)}
              </select>
            </div>
            <div>
              <label className="text-xs text-muted-foreground mb-1 block">Cron Expression</label>
              <input value={cronExpression} onChange={(event) => setCronExpression(event.target.value)} placeholder="0 * * * *" className="w-full px-3 py-2 text-sm bg-muted/60 border border-border rounded-md font-mono focus:outline-none focus:ring-1 focus:ring-primary/50" />
              <div className="flex flex-wrap gap-1.5 mt-2">
                {CRON_PRESETS.map((preset) => (
                  <button key={preset.value} onClick={() => { setCronExpression(preset.value); setCronDescription(preset.label); }} className={`text-[11px] px-2 py-0.5 rounded-full border transition-colors ${cronExpression === preset.value ? 'bg-primary/20 text-primary border-primary/40' : 'bg-muted/40 text-muted-foreground border-border hover:border-primary/30'}`}>
                    {preset.label}
                  </button>
                ))}
              </div>
            </div>
            <div>
              <label className="text-xs text-muted-foreground mb-2 block">Target Devices *</label>
              <div className="flex flex-wrap gap-1.5">
                {deviceOptions.map((device) => (
                  <button key={device.id} onClick={() => toggleDevice(device.id)} className={`text-[11px] px-2 py-0.5 rounded-full border font-mono transition-colors ${deviceIds.includes(device.id) ? 'bg-primary/20 text-primary border-primary/40' : 'bg-muted/40 text-muted-foreground border-border hover:border-primary/30'}`}>
                    {device.id}
                  </button>
                ))}
              </div>
              {deviceOptions.length === 0 ? <p className="text-[11px] text-muted-foreground mt-2">No visible devices found.</p> : null}
            </div>
          </div>
          <div className="flex items-center justify-end gap-2 px-5 py-4 border-t border-border">
            <button onClick={onClose} className="px-4 py-2 text-sm text-muted-foreground hover:text-foreground transition-colors">Cancel</button>
            <button disabled={isSubmitting} onClick={handleSave} className="flex items-center gap-1.5 px-4 py-2 text-sm bg-primary text-primary-foreground rounded-md hover:bg-primary/90 transition-colors disabled:opacity-60">
              {isSubmitting ? <Loader2 size={13} className="animate-spin" /> : <Save size={13} />} Create Schedule
            </button>
          </div>
        </div>
      </div>
    </>
  );
}
