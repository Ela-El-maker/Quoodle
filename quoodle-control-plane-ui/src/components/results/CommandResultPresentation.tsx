'use client';

import React, { useMemo, useState } from 'react';
import { AlertTriangle, Bug, ChevronRight, Copy, PanelRightClose, PanelRightOpen, Search } from 'lucide-react';
import { toast } from 'sonner';
import StatusBadge from '@/components/ui/StatusBadge';
import { formatLocalDateTime } from '@/lib/dateTime';
import { type NormalizedCommandResult, toRawResultJson } from '@/lib/commandResults';
import {
  isResultsRendererV2Enabled,
  renderResult,
  type ResultDiagnosticsItem,
  type ResultSectionDefinition,
  type ResultTableDefinition,
} from '@/lib/resultRenderer';

interface CommandResultPresentationProps {
  row: NormalizedCommandResult;
  compact?: boolean;
}

function formatTime(value: string | null | undefined): string {
  return formatLocalDateTime(value, '-');
}

function toneClass(tone?: 'default' | 'success' | 'warning' | 'danger' | 'info'): string {
  if (tone === 'success') return 'text-green-300';
  if (tone === 'warning') return 'text-amber-300';
  if (tone === 'danger') return 'text-red-300';
  if (tone === 'info') return 'text-blue-300';
  return 'text-foreground';
}

function severityClass(severity: ResultDiagnosticsItem['severity']): string {
  if (severity === 'error') return 'border-red-500/30 bg-red-500/10 text-red-200';
  if (severity === 'warning') return 'border-amber-500/30 bg-amber-500/10 text-amber-200';
  return 'border-blue-500/30 bg-blue-500/10 text-blue-200';
}

function renderTable(
  table: ResultTableDefinition | undefined,
  state: {
    search: string;
    sortBy: string | null;
    sortDirection: 'asc' | 'desc';
    setSearch: (value: string) => void;
    setSortBy: (value: string) => void;
  },
) {
  if (!table || table.columns.length === 0) {
    return <p className="text-xs text-muted-foreground">No table rows to display.</p>;
  }
  const lowered = state.search.trim().toLowerCase();
  const filtered = table.rows.filter((row) => {
    if (!lowered) return true;
    return table.columns.some((column) => String(row[column] ?? '').toLowerCase().includes(lowered));
  });
  const sorted = [...filtered].sort((a, b) => {
    if (!state.sortBy) return 0;
    const av = String(a[state.sortBy] ?? '');
    const bv = String(b[state.sortBy] ?? '');
    const cmp = av.localeCompare(bv, undefined, { numeric: true, sensitivity: 'base' });
    return state.sortDirection === 'asc' ? cmp : -cmp;
  });

  return (
    <div className="space-y-2">
      <div className="relative max-w-xs">
        <Search size={12} className="absolute left-2 top-1/2 -translate-y-1/2 text-muted-foreground" />
        <input
          value={state.search}
          onChange={(event) => state.setSearch(event.target.value)}
          placeholder="Search rows..."
          className="w-full rounded-md border border-border bg-muted/40 pl-7 pr-2 py-1.5 text-xs text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-1 focus:ring-primary/40"
        />
      </div>
      <div className="overflow-auto rounded-lg border border-border">
        <table className="min-w-full text-xs">
          <thead className="bg-muted/40 text-muted-foreground">
            <tr>
              {table.columns.map((column) => (
                <th key={column} className="text-left px-3 py-2 font-medium">
                  <button
                    type="button"
                    onClick={() => state.setSortBy(column)}
                    className="inline-flex items-center gap-1 hover:text-foreground transition-colors"
                  >
                    {column.replace(/_/g, ' ')}
                    {state.sortBy === column ? (state.sortDirection === 'asc' ? '↑' : '↓') : ''}
                  </button>
                </th>
              ))}
            </tr>
          </thead>
          <tbody className="divide-y divide-border">
            {sorted.length === 0 ? (
              <tr>
                <td className="px-3 py-3 text-muted-foreground" colSpan={table.columns.length}>No rows match your search.</td>
              </tr>
            ) : (
              sorted.map((row) => (
                <tr key={row.__id || JSON.stringify(row)} className="hover:bg-muted/20">
                  {table.columns.map((column) => (
                    <td key={column} className="px-3 py-2 whitespace-nowrap text-foreground">
                      {String(row[column] ?? '-')}
                    </td>
                  ))}
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}

export default function CommandResultPresentation({ row, compact = false }: CommandResultPresentationProps) {
  const vm = useMemo(() => renderResult(row.method, row), [row]);
  const [activeTab, setActiveTab] = useState<string>(vm.sections[0]?.id ?? 'debug');
  const [debugDrawerOpen, setDebugDrawerOpen] = useState(false);
  const [tableSearch, setTableSearch] = useState('');
  const [tableSortBy, setTableSortBy] = useState<string | null>(null);
  const [tableSortDirection, setTableSortDirection] = useState<'asc' | 'desc'>('asc');

  if (!isResultsRendererV2Enabled()) {
    return (
      <div className="bg-muted/20 border border-border rounded-lg p-3">
        <p className="text-[10px] uppercase tracking-wide text-muted-foreground mb-2">Output</p>
        <pre className="text-xs font-mono bg-zinc-950 rounded-md p-3 overflow-x-auto text-green-400">
          {toRawResultJson(row)}
        </pre>
      </div>
    );
  }

  const tabs = [...vm.sections, { id: 'debug', title: 'Debug', widget: 'log' as const }];
  const currentTab = tabs.some((tab) => tab.id === activeTab) ? activeTab : (tabs[0]?.id ?? 'debug');
  const activeSection = vm.sections.find((section) => section.id === currentTab);

  const changeSort = (value: string) => {
    if (tableSortBy === value) {
      setTableSortDirection((prev) => (prev === 'asc' ? 'desc' : 'asc'));
      return;
    }
    setTableSortBy(value);
    setTableSortDirection('asc');
  };

  const renderSection = (section: ResultSectionDefinition) => {
    if (section.widget === 'stats') {
      const stats = section.stats ?? [];
      return (
        <div className="space-y-3">
          {section.description ? <p className="text-xs text-muted-foreground">{section.description}</p> : null}
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-2">
            {stats.map((metric) => (
              <div key={metric.label} className="rounded-lg border border-border bg-muted/30 px-3 py-2">
                <p className="text-[10px] uppercase tracking-wide text-muted-foreground">{metric.label}</p>
                <p className={`mt-1 text-sm font-semibold ${toneClass(metric.tone)}`}>{metric.value}</p>
              </div>
            ))}
          </div>
        </div>
      );
    }
    if (section.widget === 'kv') {
      const keyValues = section.keyValues ?? [];
      return (
        <div className="space-y-3">
          {section.description ? <p className="text-xs text-muted-foreground">{section.description}</p> : null}
          {keyValues.length === 0 ? (
            <p className="text-xs text-muted-foreground">{section.emptySummary ?? 'No data available.'}</p>
          ) : (
            <div className="grid grid-cols-1 md:grid-cols-2 gap-2">
              {keyValues.map((entry) => (
                <div key={`${section.id}-${entry.key}`} className="rounded-md border border-border bg-muted/30 px-3 py-2">
                  <p className="text-[10px] uppercase tracking-wide text-muted-foreground">{entry.label}</p>
                  <p className={`text-xs mt-1 ${entry.isEmpty ? 'text-muted-foreground' : 'text-foreground'}`}>{entry.value}</p>
                </div>
              ))}
            </div>
          )}
          {section.emptySummary && keyValues.length > 0 ? (
            <p className="text-[11px] text-muted-foreground">{section.emptySummary}</p>
          ) : null}
        </div>
      );
    }
    if (section.widget === 'table') {
      return renderTable(section.table, {
        search: tableSearch,
        sortBy: tableSortBy,
        sortDirection: tableSortDirection,
        setSearch: setTableSearch,
        setSortBy: changeSort,
      });
    }
    if (section.widget === 'diagnostics') {
      const diagnostics = section.diagnostics ?? [];
      return (
        <div className="space-y-2">
          {diagnostics.length === 0 ? (
            <p className="text-xs text-muted-foreground">{section.emptySummary ?? 'No diagnostics reported.'}</p>
          ) : (
            diagnostics.map((item, index) => (
              <div key={`${section.id}-${index}`} className={`rounded-md border px-3 py-2 text-xs ${severityClass(item.severity)}`}>
                <p className="font-medium">{item.field ? `${item.field} · ${item.reason}` : item.reason}</p>
                <p className="mt-1 opacity-90">{item.message}</p>
              </div>
            ))
          )}
        </div>
      );
    }
    return (
      <pre className="text-xs font-mono bg-zinc-950 rounded-md p-3 overflow-x-auto text-green-400">
        {section.logText || vm.subtitle}
      </pre>
    );
  };

  return (
    <div className="space-y-3">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div className="min-w-0">
          <p className="text-sm font-semibold truncate">{vm.title}</p>
          <p className="text-xs text-muted-foreground truncate">{vm.subtitle}</p>
        </div>
        <div className="flex items-center gap-2">
          <StatusBadge variant={row.state} />
          <button
            onClick={async () => {
              await navigator.clipboard.writeText(vm.rawJson);
              toast.success('Raw output copied');
            }}
            className="inline-flex items-center gap-1 rounded-md border border-border bg-muted/40 px-2 py-1 text-[11px] text-muted-foreground hover:text-foreground transition-colors"
            title="Copy raw output"
          >
            <Copy size={12} />
            Copy
          </button>
          <button
            onClick={() => setDebugDrawerOpen(true)}
            className="inline-flex items-center gap-1 rounded-md border border-border bg-muted/40 px-2 py-1 text-[11px] text-muted-foreground hover:text-foreground transition-colors"
            title="Open debug drawer"
          >
            <PanelRightOpen size={12} />
            Debug
          </button>
        </div>
      </div>

      {!compact && vm.hero.length > 0 ? (
        <div className="grid grid-cols-2 lg:grid-cols-3 gap-2">
          {vm.hero.map((metric) => (
            <div key={`hero-${metric.label}`} className="rounded-md border border-border bg-muted/30 px-3 py-2">
              <p className="text-[10px] uppercase tracking-wide text-muted-foreground">{metric.label}</p>
              <p className={`text-xs mt-1 font-medium ${toneClass(metric.tone)}`}>{metric.value}</p>
            </div>
          ))}
        </div>
      ) : null}

      <div className="flex flex-wrap items-center gap-2 text-[11px] text-muted-foreground">
        <span className="px-2 py-1 rounded border border-border bg-muted/30">Device: {vm.shell.deviceName}</span>
        <span className="px-2 py-1 rounded border border-border bg-muted/30">Queued: {formatTime(vm.shell.queuedAt)}</span>
        <span className="px-2 py-1 rounded border border-border bg-muted/30">Completed: {formatTime(vm.shell.completedAt)}</span>
        {vm.shell.transport ? <span className="px-2 py-1 rounded border border-border bg-muted/30">Transport: {vm.shell.transport}</span> : null}
        {vm.shell.requestId ? <span className="px-2 py-1 rounded border border-border bg-muted/30">Request: {vm.shell.requestId}</span> : null}
      </div>

      {vm.fallbackUsed ? (
        <div className="rounded-md border border-amber-500/30 bg-amber-500/10 px-3 py-2 text-xs text-amber-200 flex items-center gap-1.5">
          <AlertTriangle size={13} />
          Renderer fallback mode is active for this command output.
        </div>
      ) : null}

      <div className="overflow-x-auto">
        <div className="inline-flex items-center gap-1 rounded-md border border-border bg-muted/30 p-1 min-w-full md:min-w-0">
          {tabs.map((tab) => (
            <button
              key={tab.id}
              onClick={() => setActiveTab(tab.id)}
                className={`rounded px-2.5 py-1 text-xs transition-colors ${
                currentTab === tab.id
                  ? 'bg-primary/20 text-primary border border-primary/20'
                  : 'text-muted-foreground hover:text-foreground'
              }`}
            >
              {tab.title}
            </button>
          ))}
        </div>
      </div>

      <div className="rounded-lg border border-border bg-muted/20 p-3 fade-in">
        {currentTab === 'debug' ? (
          <div className="space-y-2">
            <div className="flex items-center justify-between">
              <p className="text-[10px] uppercase tracking-wide text-muted-foreground">Raw Result JSON</p>
              <button
                onClick={() => setDebugDrawerOpen(true)}
                className="inline-flex items-center gap-1 text-xs text-muted-foreground hover:text-foreground transition-colors"
              >
                <PanelRightOpen size={12} />
                Open Drawer
              </button>
            </div>
            <pre className="text-xs font-mono bg-zinc-950 rounded-md p-3 overflow-x-auto text-green-400 max-h-80">
              {vm.rawJson}
            </pre>
          </div>
        ) : activeSection ? (
          renderSection(activeSection)
        ) : (
          <p className="text-xs text-muted-foreground">No section available.</p>
        )}
      </div>

      {debugDrawerOpen ? (
        <>
          <button
            type="button"
            onClick={() => setDebugDrawerOpen(false)}
            className="fixed inset-0 z-40 bg-black/50"
            aria-label="Close debug drawer backdrop"
          />
          <aside className="fixed inset-y-0 right-0 z-50 w-full max-w-2xl border-l border-border bg-card slide-in-right shadow-xl flex flex-col">
            <div className="flex items-center justify-between px-4 py-3 border-b border-border">
              <div className="flex items-center gap-2">
                <Bug size={14} className="text-muted-foreground" />
                <p className="text-sm font-semibold">Raw Result Debug</p>
              </div>
              <div className="flex items-center gap-2">
                <button
                  onClick={async () => {
                    await navigator.clipboard.writeText(vm.rawJson);
                    toast.success('Raw output copied');
                  }}
                  className="inline-flex items-center gap-1 rounded-md border border-border bg-muted/40 px-2 py-1 text-xs text-muted-foreground hover:text-foreground transition-colors"
                >
                  <Copy size={12} />
                  Copy
                </button>
                <button
                  onClick={() => setDebugDrawerOpen(false)}
                  className="inline-flex items-center gap-1 rounded-md border border-border bg-muted/40 px-2 py-1 text-xs text-muted-foreground hover:text-foreground transition-colors"
                >
                  <PanelRightClose size={12} />
                  Close
                </button>
              </div>
            </div>
            <div className="px-4 py-3 border-b border-border text-xs text-muted-foreground space-y-1">
              <p className="flex items-center gap-1"><ChevronRight size={11} /> Command: {vm.shell.commandId}</p>
              <p className="flex items-center gap-1"><ChevronRight size={11} /> Method: {vm.shell.method}</p>
              <p className="flex items-center gap-1"><ChevronRight size={11} /> Request: {vm.shell.requestId || '-'}</p>
            </div>
            <div className="flex-1 overflow-auto p-4">
              <pre className="text-xs font-mono bg-zinc-950 rounded-md p-4 overflow-x-auto text-green-400 min-h-full">
                {vm.rawJson}
              </pre>
            </div>
          </aside>
        </>
      ) : null}
    </div>
  );
}
