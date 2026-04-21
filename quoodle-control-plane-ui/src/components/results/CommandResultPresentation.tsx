'use client';

import React, { useCallback, useMemo, useState } from 'react';
import {
  AlertTriangle,
  Bug,
  ChevronLeft,
  ChevronRight,
  ChevronUp,
  Copy,
  Folder,
  File,
  PanelRightClose,
  PanelRightOpen,
  Search,
} from 'lucide-react';
import { toast } from 'sonner';
import StatusBadge from '@/components/ui/StatusBadge';
import { formatLocalDateTime } from '@/lib/dateTime';
import {
  type CommandDetailApi,
  mergeCommandDetail,
  type NormalizedCommandResult,
  toRawResultJson,
} from '@/lib/commandResults';
import {
  isResultsRendererV2Enabled,
  renderResult,
  type ResultDiagnosticsItem,
  type ResultFilesystemDefinition,
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
                    {state.sortBy === column ? (state.sortDirection === 'asc' ? '^' : 'v') : ''}
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

function normalizeExplorerPath(value: string | null | undefined): string {
  const raw = String(value ?? '').trim();
  if (!raw) return '/';
  const normalized = raw.replace(/[\\/]+/g, '/').replace(/\/+$/, '');
  return normalized || '/';
}

function explorerParentPath(path: string): string | null {
  const normalized = normalizeExplorerPath(path);
  if (normalized === '/') return null;
  const parts = normalized.split('/').filter(Boolean);
  if (parts.length <= 1) return null;
  return parts.slice(0, -1).join('/');
}

function formatBytes(value: number | null): string {
  if (value == null || !Number.isFinite(value)) return '-';
  if (value < 1024) return `${value} B`;
  if (value < 1024 * 1024) return `${(value / 1024).toFixed(1)} KB`;
  if (value < 1024 * 1024 * 1024) return `${(value / (1024 * 1024)).toFixed(1)} MB`;
  return `${(value / (1024 * 1024 * 1024)).toFixed(2)} GB`;
}

const LAZY_ATTEMPT_TTL_MS = 300_000;
const lazyAttemptGate = new Map<string, number>();
const lazyBlockedPaths = new Set<string>();

function toWindowsPath(path: string): string {
  const normalized = normalizeExplorerPath(path);
  if (normalized === '/') return '\\';
  return normalized.replace(/\//g, '\\');
}

function normalizeExplorerEntries(entries: ResultFilesystemDefinition['entries']) {
  return entries
    .map((entry) => ({
      ...entry,
      path: normalizeExplorerPath(entry.path),
      parentPath: entry.parentPath ? normalizeExplorerPath(entry.parentPath) : explorerParentPath(entry.path),
    }))
    .filter((entry) => entry.path !== '/');
}

function FileExplorerSection({
  filesystem,
  baseRow,
  autoHydrate,
}: {
  filesystem: ResultFilesystemDefinition;
  baseRow: NormalizedCommandResult;
  autoHydrate: boolean;
}) {
  const rootPath = useMemo(() => normalizeExplorerPath(filesystem.rootPath), [filesystem.rootPath]);
  const initialEntries = useMemo(() => normalizeExplorerEntries(filesystem.entries), [filesystem.entries]);
  const usersCandidatePath = useMemo(() => {
    const wanted = `${rootPath}/Users`.toLowerCase();
    const candidate = initialEntries.find((entry) => entry.path.toLowerCase() === wanted);
    return candidate?.path ?? rootPath;
  }, [initialEntries, rootPath]);
  const explorerBootKey = `${baseRow.commandId}:${rootPath}`;
  const initialEntriesRef = React.useRef(initialEntries);

  const [entries, setEntries] = useState(initialEntries);
  const [currentPath, setCurrentPath] = useState(usersCandidatePath);
  const [selectedPath, setSelectedPath] = useState<string | null>(null);
  const [backStack, setBackStack] = useState<string[]>(usersCandidatePath !== rootPath ? [rootPath] : []);
  const [forwardStack, setForwardStack] = useState<string[]>([]);
  const [search, setSearch] = useState('');
  const [sortBy, setSortBy] = useState<'name' | 'modifiedAt' | 'size' | 'type'>('name');
  const [sortDirection, setSortDirection] = useState<'asc' | 'desc'>('asc');
  const [showHidden, setShowHidden] = useState(false);
  const [showSystem, setShowSystem] = useState(false);
  const [viewMode, setViewMode] = useState<'list' | 'grid'>('list');
  const [expandedPaths, setExpandedPaths] = useState<Set<string>>(new Set([rootPath, usersCandidatePath]));
  const [hydratingPath, setHydratingPath] = useState<string | null>(null);
  const [hydrationError, setHydrationError] = useState<string | null>(null);
  const hydratedPathsRef = React.useRef<Set<string>>(new Set());
  const attemptedPathsRef = React.useRef<Set<string>>(new Set());

  React.useEffect(() => {
    initialEntriesRef.current = initialEntries;
  }, [initialEntries]);

  React.useEffect(() => {
    const bootEntries = initialEntriesRef.current;
    const materialized = new Set<string>();
    for (const entry of bootEntries) {
      if (entry.parentPath) {
        materialized.add(normalizeExplorerPath(entry.parentPath));
      }
    }
    hydratedPathsRef.current = materialized;
    attemptedPathsRef.current = new Set(materialized);
    setEntries(bootEntries);
    setCurrentPath(usersCandidatePath);
    setSelectedPath(null);
    setBackStack(usersCandidatePath !== rootPath ? [rootPath] : []);
    setForwardStack([]);
    setExpandedPaths(new Set([rootPath, usersCandidatePath]));
    setHydratingPath(null);
    setHydrationError(null);
  }, [explorerBootKey, rootPath, usersCandidatePath]);

  const childrenByParent = useMemo(() => {
    const map = new Map<string, typeof entries>();
    for (const entry of entries) {
      const parent = entry.parentPath ?? rootPath;
      const key = normalizeExplorerPath(parent);
      const list = map.get(key) ?? [];
      list.push(entry);
      map.set(key, list);
    }
    return map;
  }, [entries, rootPath]);

  const isDirectoryLike = useCallback((entry: ResultFilesystemDefinition['entries'][number]): boolean => {
    return entry.type === 'directory' || childrenByParent.has(entry.path);
  }, [childrenByParent]);

  const visibleCurrentChildren = useMemo(() => {
    const lowered = search.trim().toLowerCase();
    const children = childrenByParent.get(normalizeExplorerPath(currentPath)) ?? [];
    const filtered = children.filter((entry) => {
      if (!showHidden && entry.isHidden) return false;
      if (!showSystem && entry.isSystem) return false;
      if (!lowered) return true;
      return (
        entry.name.toLowerCase().includes(lowered) ||
        entry.path.toLowerCase().includes(lowered) ||
        (entry.extension ?? '').toLowerCase().includes(lowered)
      );
    });

    filtered.sort((a, b) => {
      const aDirectoryLike = isDirectoryLike(a);
      const bDirectoryLike = isDirectoryLike(b);
      if (aDirectoryLike !== bDirectoryLike) {
        if (aDirectoryLike) return -1;
        if (bDirectoryLike) return 1;
      }
      let cmp = 0;
      if (sortBy === 'name') cmp = a.name.localeCompare(b.name, undefined, { sensitivity: 'base' });
      if (sortBy === 'type') cmp = (a.extension ?? a.type).localeCompare(b.extension ?? b.type, undefined, { sensitivity: 'base' });
      if (sortBy === 'size') cmp = (a.size ?? -1) - (b.size ?? -1);
      if (sortBy === 'modifiedAt') cmp = (a.modifiedAt ?? '').localeCompare(b.modifiedAt ?? '');
      return sortDirection === 'asc' ? cmp : -cmp;
    });
    return filtered;
  }, [childrenByParent, currentPath, isDirectoryLike, search, showHidden, showSystem, sortBy, sortDirection]);

  const breadcrumbs = useMemo(() => {
    const normalized = normalizeExplorerPath(currentPath);
    if (normalized === '/') return ['/'];
    const parts = normalized.split('/').filter(Boolean);
    const crumbs: string[] = [];
    for (let index = 0; index < parts.length; index += 1) {
      crumbs.push(parts.slice(0, index + 1).join('/'));
    }
    return crumbs;
  }, [currentPath]);

  const selectedEntry = useMemo(() => {
    if (!selectedPath) return null;
    return entries.find((entry) => entry.path === selectedPath) ?? null;
  }, [entries, selectedPath]);

  const navigateTo = (nextPath: string) => {
    const normalized = normalizeExplorerPath(nextPath);
    if (normalized === currentPath) return;
    setBackStack((prev) => [...prev, currentPath]);
    setForwardStack([]);
    setCurrentPath(normalized);
    setSelectedPath(null);
    setExpandedPaths((prev) => new Set(prev).add(normalized));
  };

  const goBack = () => {
    if (backStack.length === 0) return;
    const previous = backStack[backStack.length - 1];
    setBackStack((prev) => prev.slice(0, -1));
    setForwardStack((prev) => [...prev, currentPath]);
    setCurrentPath(previous);
    setSelectedPath(null);
  };

  const goForward = () => {
    if (forwardStack.length === 0) return;
    const next = forwardStack[forwardStack.length - 1];
    setForwardStack((prev) => prev.slice(0, -1));
    setBackStack((prev) => [...prev, currentPath]);
    setCurrentPath(next);
    setSelectedPath(null);
  };

  const goUp = () => {
    const parent = explorerParentPath(currentPath);
    if (!parent) return;
    navigateTo(parent);
  };

  const toggleExpanded = (path: string) => {
    setExpandedPaths((prev) => {
      const next = new Set(prev);
      if (next.has(path)) next.delete(path);
      else next.add(path);
      return next;
    });
  };

  const copyDownloadPayload = async () => {
    if (!selectedEntry || !selectedEntry.downloadable || !selectedEntry.downloadMethod) return;
    const payload = {
      method: selectedEntry.downloadMethod,
      params: { path: selectedEntry.path },
    };
    await navigator.clipboard.writeText(JSON.stringify(payload, null, 2));
    toast.success('Download command payload copied');
  };

  const copyBrowsePayload = async (path: string) => {
    const payload = {
      method: 'list_files',
      params: {
        path,
        recursive: false,
        max_depth: 1,
        limit: 200,
        include_hidden: false,
        include_system: false,
        follow_symlinks: false,
      },
    };
    await navigator.clipboard.writeText(JSON.stringify(payload, null, 2));
    toast.success('Browse command payload copied');
  };

  const hydratePath = useCallback(async (
    path: string,
    options?: { force?: boolean; showToastOnError?: boolean; showToastOnSuccess?: boolean },
  ) => {
    const force = options?.force === true;
    const showToastOnError = options?.showToastOnError === true;
    const showToastOnSuccess = options?.showToastOnSuccess === true;
    const normalizedPath = normalizeExplorerPath(path);
    const attemptKey = `${baseRow.deviceId}:${normalizedPath}`;
    if (force) lazyBlockedPaths.delete(attemptKey);
    if (!filesystem.partial) return;
    if (hydratingPath === normalizedPath) return;
    if (!force && lazyBlockedPaths.has(attemptKey)) return;
    if (!force && attemptedPathsRef.current.has(normalizedPath)) return;
    if (!force) {
      const lastAttempt = lazyAttemptGate.get(attemptKey);
      if (typeof lastAttempt === 'number' && Date.now() - lastAttempt < LAZY_ATTEMPT_TTL_MS) {
        return;
      }
    }
    if (hydratedPathsRef.current.has(normalizedPath)) return;

    attemptedPathsRef.current.add(normalizedPath);
    lazyAttemptGate.set(attemptKey, Date.now());
    setHydratingPath(normalizedPath);
    setHydrationError(null);
    try {
      const dispatchResponse = await fetch('/api/commands', {
        method: 'POST',
        credentials: 'include',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          client_message_id: crypto.randomUUID(),
          device_id: baseRow.deviceId,
          method: 'list_files',
          params: {
            path: toWindowsPath(normalizedPath),
            recursive: false,
            max_depth: 1,
            limit: 200,
            include_hidden: false,
            include_system: false,
            follow_symlinks: false,
          },
          sensitive: false,
        }),
      });

      if (!dispatchResponse.ok) {
        const text = (await dispatchResponse.text()).trim();
        throw new Error(text || 'Failed to dispatch lazy folder browse command.');
      }

      const dispatchPayload = (await dispatchResponse.json()) as { command_id?: string };
      const commandId = String(dispatchPayload.command_id ?? '').trim();
      if (!commandId) {
        throw new Error('Missing command_id from lazy browse dispatch response.');
      }

      const startedAt = Date.now();
      const timeoutMs = 90_000;
      let detailPayload: CommandDetailApi | null = null;
      while (Date.now() - startedAt < timeoutMs) {
        const detailResponse = await fetch(`/api/commands/${encodeURIComponent(commandId)}`, {
          credentials: 'include',
          cache: 'no-store',
        });
        if (!detailResponse.ok) {
          const text = (await detailResponse.text()).trim();
          throw new Error(text || 'Failed to load lazy browse command status.');
        }
        const detail = (await detailResponse.json()) as CommandDetailApi;
        detailPayload = detail;
        const normalizedState = String(detail.state ?? '').trim().toLowerCase();
        if (['completed', 'failed', 'expired', 'rejected'].includes(normalizedState)) {
          break;
        }
        await new Promise((resolve) => setTimeout(resolve, 1000));
      }

      if (!detailPayload) {
        throw new Error('Lazy browse command returned no detail payload.');
      }

      const merged = mergeCommandDetail(baseRow, detailPayload);
      const lazyVm = renderResult('list_files', merged);
      const lazyFilesystem = lazyVm.sections.find((section) => section.widget === 'filesystem')?.filesystem;
      if (!lazyFilesystem) {
        throw new Error('Lazy browse command did not return filesystem data.');
      }

      const incoming = normalizeExplorerEntries(lazyFilesystem.entries);
      setEntries((prev) => {
        const map = new Map(prev.map((entry) => [entry.path, entry]));
        for (const next of incoming) {
          const existing = map.get(next.path);
          map.set(next.path, existing ? { ...existing, ...next } : next);
        }
        return Array.from(map.values());
      });

      for (const next of incoming) {
        if (next.parentPath) hydratedPathsRef.current.add(normalizeExplorerPath(next.parentPath));
      }
      hydratedPathsRef.current.add(normalizedPath);
      if (showToastOnSuccess) {
        toast.success(`Loaded folder snapshot for ${normalizedPath}`, {
          id: `lazy-filesystem-success-${baseRow.deviceId}-${normalizedPath}`,
        });
      }
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Failed to lazy-load folder.';
      const lower = message.toLowerCase();
      if (lower.includes('invalid_params') || lower.includes('limit field must not be greater than 1000')) {
        lazyBlockedPaths.add(attemptKey);
      }
      setHydrationError(message);
      if (showToastOnError) {
        toast.error(message, {
          id: `lazy-filesystem-error-${baseRow.deviceId}-${normalizedPath}`,
        });
      }
    } finally {
      setHydratingPath((prev) => (prev === normalizedPath ? null : prev));
    }
  }, [baseRow, filesystem.partial, hydratingPath]);

  React.useEffect(() => {
    if (!autoHydrate) return;
    if (!filesystem.partial) return;
    const normalizedCurrent = normalizeExplorerPath(currentPath);
    const hasChildren = (childrenByParent.get(normalizedCurrent)?.length ?? 0) > 0;
    if (hasChildren) return;
    if (hydratedPathsRef.current.has(normalizedCurrent)) return;
    void hydratePath(normalizedCurrent, { showToastOnError: false, showToastOnSuccess: false });
  }, [autoHydrate, childrenByParent, currentPath, filesystem.partial, hydratePath]);

  const renderTree = (path: string, depth = 0): React.ReactNode => {
    const children = (childrenByParent.get(path) ?? []).filter((entry) => isDirectoryLike(entry));
    const visibleChildren = children.filter((entry) => (showHidden || !entry.isHidden) && (showSystem || !entry.isSystem));
    const isExpanded = expandedPaths.has(path);
    const isCurrent = normalizeExplorerPath(path) === normalizeExplorerPath(currentPath);
    const displayName = path === rootPath ? rootPath : path.split('/').slice(-1)[0];

    return (
      <div key={`tree-${path}`}>
        <div className="flex items-center gap-1 py-0.5" style={{ paddingLeft: `${depth * 12}px` }}>
          {visibleChildren.length > 0 ? (
            <button
              type="button"
              onClick={() => toggleExpanded(path)}
              className="text-muted-foreground hover:text-foreground text-[10px] w-4"
            >
              {isExpanded ? 'v' : '>'}
            </button>
          ) : (
            <span className="w-4" />
          )}
          <button
            type="button"
            onClick={() => navigateTo(path)}
            className={`inline-flex items-center gap-1 rounded px-1.5 py-0.5 text-xs ${
              isCurrent ? 'bg-primary/20 text-primary' : 'text-muted-foreground hover:text-foreground hover:bg-muted/30'
            }`}
          >
            <Folder size={12} />
            <span className="truncate max-w-[180px]">{displayName || '/'}</span>
          </button>
        </div>
        {isExpanded ? visibleChildren.map((child) => renderTree(child.path, depth + 1)) : null}
      </div>
    );
  };

  return (
    <div className="space-y-3 max-w-full overflow-x-hidden">
      {filesystem.partial ? (
        <div className="rounded-md border border-amber-500/30 bg-amber-500/10 px-3 py-2 text-xs text-amber-200">
          Partial filesystem snapshot. Showing a bounded result set for this command. Default scope is <span className="font-mono">C:\Users</span>; use
          {' '}<span className="font-mono">{`{"path":"C:\\\\"}`}</span>{' '}to request a full-drive root scan.
        </div>
      ) : null}
      {hydrationError ? (
        <div className="rounded-md border border-red-500/30 bg-red-500/10 px-3 py-2 text-xs text-red-200">
          Lazy load failed: {hydrationError}
        </div>
      ) : null}

      <div className="flex flex-wrap items-center gap-2">
        <button type="button" onClick={goBack} disabled={backStack.length === 0} className="inline-flex items-center gap-1 rounded-md border border-border bg-muted/40 px-2 py-1 text-xs disabled:opacity-40">
          <ChevronLeft size={12} />
          Back
        </button>
        <button type="button" onClick={goForward} disabled={forwardStack.length === 0} className="inline-flex items-center gap-1 rounded-md border border-border bg-muted/40 px-2 py-1 text-xs disabled:opacity-40">
          <ChevronRight size={12} />
          Forward
        </button>
        <button type="button" onClick={goUp} disabled={!explorerParentPath(currentPath)} className="inline-flex items-center gap-1 rounded-md border border-border bg-muted/40 px-2 py-1 text-xs disabled:opacity-40">
          <ChevronUp size={12} />
          Up
        </button>
        <button
          type="button"
          onClick={() => navigateTo(rootPath)}
          className={`inline-flex items-center gap-1 rounded-md border border-border bg-muted/40 px-2 py-1 text-xs ${currentPath === rootPath ? 'text-primary border-primary/40 bg-primary/10' : ''}`}
        >
          C:
        </button>
        <button
          type="button"
          onClick={() => navigateTo(`${rootPath}/Users`)}
          className={`inline-flex items-center gap-1 rounded-md border border-border bg-muted/40 px-2 py-1 text-xs ${currentPath.toLowerCase() === `${rootPath}/users`.toLowerCase() ? 'text-primary border-primary/40 bg-primary/10' : ''}`}
        >
          Users
        </button>
        <div className="flex flex-wrap items-center gap-1 rounded-md border border-border bg-muted/30 px-2 py-1">
          {breadcrumbs.map((crumb, index) => (
            <React.Fragment key={`crumb-${crumb}`}>
              <button type="button" onClick={() => navigateTo(crumb)} className="text-xs text-muted-foreground hover:text-foreground">
                {index === 0 ? crumb : crumb.split('/').slice(-1)[0]}
              </button>
              {index < breadcrumbs.length - 1 ? <ChevronRight size={11} className="text-muted-foreground" /> : null}
            </React.Fragment>
          ))}
        </div>
        <div className="relative ml-auto min-w-[220px]">
          <Search size={12} className="absolute left-2 top-1/2 -translate-y-1/2 text-muted-foreground" />
          <input
            value={search}
            onChange={(event) => setSearch(event.target.value)}
            placeholder="Search this folder..."
            className="w-full rounded-md border border-border bg-muted/40 pl-7 pr-2 py-1.5 text-xs text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-1 focus:ring-primary/40"
          />
        </div>
      </div>

      <div className="flex flex-wrap items-center gap-2 text-xs text-muted-foreground">
        <button type="button" onClick={() => setShowHidden((prev) => !prev)} className={`rounded-md border px-2 py-1 ${showHidden ? 'border-primary/40 text-primary bg-primary/10' : 'border-border bg-muted/30'}`}>
          Hidden: {showHidden ? 'On' : 'Off'}
        </button>
        <button type="button" onClick={() => setShowSystem((prev) => !prev)} className={`rounded-md border px-2 py-1 ${showSystem ? 'border-primary/40 text-primary bg-primary/10' : 'border-border bg-muted/30'}`}>
          System: {showSystem ? 'On' : 'Off'}
        </button>
        <button type="button" onClick={() => setViewMode((prev) => (prev === 'list' ? 'grid' : 'list'))} className="rounded-md border border-border bg-muted/30 px-2 py-1">
          View: {viewMode === 'list' ? 'List' : 'Grid'}
        </button>
        <button
          type="button"
          onClick={() => {
            const nextSort: Array<'name' | 'modifiedAt' | 'size' | 'type'> = ['name', 'modifiedAt', 'size', 'type'];
            const currentIndex = nextSort.indexOf(sortBy);
            setSortBy(nextSort[(currentIndex + 1) % nextSort.length]);
          }}
          className="rounded-md border border-border bg-muted/30 px-2 py-1"
        >
          Sort: {sortBy}
        </button>
        <button type="button" onClick={() => setSortDirection((prev) => (prev === 'asc' ? 'desc' : 'asc'))} className="rounded-md border border-border bg-muted/30 px-2 py-1">
          Direction: {sortDirection}
        </button>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-12 gap-3">
        <div className="lg:col-span-4 xl:col-span-3 min-w-0 rounded-lg border border-border bg-muted/20 p-2 max-h-[440px] overflow-y-auto overflow-x-hidden">
          <p className="text-[10px] uppercase tracking-wide text-muted-foreground mb-2">Folders</p>
          {renderTree(rootPath)}
        </div>

        <div className="lg:col-span-8 xl:col-span-6 min-w-0 rounded-lg border border-border bg-muted/20 p-2 max-h-[440px] overflow-y-auto overflow-x-hidden">
          <p className="text-[10px] uppercase tracking-wide text-muted-foreground mb-2">Contents | {currentPath}</p>
          {visibleCurrentChildren.length === 0 ? (
            <div className="space-y-2 px-2 py-3">
              {hydratingPath === normalizeExplorerPath(currentPath) ? (
                <p className="text-xs text-blue-300">Loading folder contents...</p>
              ) : null}
              <p className="text-xs text-muted-foreground">No entries found in this folder.</p>
              {filesystem.partial ? (
                <div className="rounded-md border border-amber-500/30 bg-amber-500/10 px-2.5 py-2">
                  <p className="text-[11px] text-amber-200">
                    This is a bounded partial snapshot. This folder may exist but its children were not materialized in this result set.
                  </p>
                  <div className="mt-2 flex flex-wrap gap-2">
                    <button
                      type="button"
                      onClick={() =>
                        void hydratePath(currentPath, {
                          showToastOnError: true,
                          showToastOnSuccess: true,
                        })
                      }
                      disabled={hydratingPath === normalizeExplorerPath(currentPath)}
                      className="rounded-md border border-amber-400/40 bg-amber-400/10 px-2 py-1 text-[11px] text-amber-100 hover:bg-amber-400/15 disabled:opacity-50"
                    >
                      {hydratingPath === normalizeExplorerPath(currentPath) ? 'Loading...' : 'Load this folder now'}
                    </button>
                    <button
                      type="button"
                      onClick={() => copyBrowsePayload(currentPath)}
                      className="rounded-md border border-amber-400/40 bg-amber-400/10 px-2 py-1 text-[11px] text-amber-100 hover:bg-amber-400/15"
                    >
                      Copy `list_files` payload for this path
                    </button>
                  </div>
                </div>
              ) : null}
            </div>
          ) : viewMode === 'list' ? (
            <div className="space-y-1">
              {visibleCurrentChildren.map((entry) => {
                const active = selectedPath === entry.path;
                return (
                  <button
                    key={entry.path}
                    type="button"
                    onClick={() => setSelectedPath(entry.path)}
                    onDoubleClick={() => isDirectoryLike(entry) && navigateTo(entry.path)}
                    className={`w-full text-left rounded-md border px-2 py-1.5 transition-colors ${
                      active ? 'border-primary/40 bg-primary/10' : 'border-border bg-muted/20 hover:bg-muted/40'
                    }`}
                  >
                    <div className="flex items-center justify-between gap-2">
                      <div className="min-w-0 inline-flex items-center gap-2">
                        {isDirectoryLike(entry) ? <Folder size={13} className="text-blue-300" /> : <File size={13} className="text-emerald-300" />}
                        <span className="text-xs font-medium truncate">{entry.name}</span>
                        {entry.isHidden ? <span className="text-[10px] rounded bg-amber-500/15 text-amber-300 px-1">hidden</span> : null}
                        {entry.isSystem ? <span className="text-[10px] rounded bg-amber-500/15 text-amber-300 px-1">system</span> : null}
                      </div>
                      <div className="text-[11px] text-muted-foreground">{isDirectoryLike(entry) ? '-' : formatBytes(entry.size)}</div>
                    </div>
                    <div className="mt-1 text-[11px] text-muted-foreground truncate">{entry.path}</div>
                  </button>
                );
              })}
            </div>
          ) : (
            <div className="grid grid-cols-2 md:grid-cols-3 gap-2">
              {visibleCurrentChildren.map((entry) => (
                <button
                  key={entry.path}
                  type="button"
                  onClick={() => setSelectedPath(entry.path)}
                  onDoubleClick={() => isDirectoryLike(entry) && navigateTo(entry.path)}
                  className={`rounded-md border p-2 text-left ${selectedPath === entry.path ? 'border-primary/40 bg-primary/10' : 'border-border bg-muted/20 hover:bg-muted/40'}`}
                >
                  <div className="inline-flex items-center gap-1">
                    {isDirectoryLike(entry) ? <Folder size={13} className="text-blue-300" /> : <File size={13} className="text-emerald-300" />}
                    <span className="text-xs font-medium truncate">{entry.name}</span>
                  </div>
                  <p className="mt-1 text-[11px] text-muted-foreground">{isDirectoryLike(entry) ? 'Folder' : formatBytes(entry.size)}</p>
                </button>
              ))}
            </div>
          )}
        </div>

        <div className="lg:col-span-12 xl:col-span-3 min-w-0 rounded-lg border border-border bg-muted/20 p-2 max-h-[440px] overflow-y-auto overflow-x-hidden">
          <p className="text-[10px] uppercase tracking-wide text-muted-foreground mb-2">Details</p>
          {!selectedEntry ? (
            <p className="text-xs text-muted-foreground px-1">Select a file or folder to inspect metadata.</p>
          ) : (
            <div className="space-y-2">
              {[
                ['Name', selectedEntry.name],
                ['Path', selectedEntry.path],
                ['Type', selectedEntry.type],
                ['Size', selectedEntry.type === 'file' ? formatBytes(selectedEntry.size) : '-'],
                ['Modified', selectedEntry.modifiedAt || '-'],
                ['Created', selectedEntry.createdAt || '-'],
                ['Extension', selectedEntry.extension || '-'],
                ['Hidden', selectedEntry.isHidden ? 'Yes' : 'No'],
                ['System', selectedEntry.isSystem ? 'Yes' : 'No'],
                ['Symlink', selectedEntry.isSymlink ? 'Yes' : 'No'],
                ['Target', selectedEntry.targetPath || '-'],
                ['Download', selectedEntry.downloadable ? (selectedEntry.downloadMethod || 'download_file') : 'Not supported'],
              ].map(([label, value]) => (
                <div key={`${selectedEntry.path}-${label}`} className="rounded-md border border-border bg-muted/30 px-2 py-1.5">
                  <p className="text-[10px] uppercase tracking-wide text-muted-foreground">{label}</p>
                  <p className="text-xs mt-0.5 break-all">{value}</p>
                </div>
              ))}
              <div className="flex flex-wrap gap-2 pt-1">
                <button
                  type="button"
                  onClick={async () => {
                    await navigator.clipboard.writeText(selectedEntry.path);
                    toast.success('Path copied');
                  }}
                  className="rounded-md border border-border bg-muted/30 px-2 py-1 text-xs"
                >
                  Copy Path
                </button>
                <button
                  type="button"
                  disabled={!selectedEntry.downloadable || !selectedEntry.downloadMethod}
                  onClick={copyDownloadPayload}
                  className="rounded-md border border-border bg-muted/30 px-2 py-1 text-xs disabled:opacity-40"
                >
                  Prepare Download
                </button>
              </div>
            </div>
          )}
        </div>
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
    if (section.widget === 'filesystem') {
      if (!section.filesystem) {
        return <p className="text-xs text-muted-foreground">{section.emptySummary ?? 'No filesystem data available.'}</p>;
      }
      return <FileExplorerSection filesystem={section.filesystem} baseRow={row} autoHydrate={compact} />;
    }
    if (section.widget === 'artifact') {
      const artifact = section.artifact;
      const artifactUrl = artifact?.url?.trim() || '';
      const checksum = artifact?.checksum?.trim() || '';
      const contentType = artifact?.contentType?.toLowerCase() || '';
      const isImage = contentType.startsWith('image/') || /\.(png|jpe?g|gif|webp)$/i.test(artifactUrl);
      return (
        <div className="space-y-3">
          {!artifactUrl ? (
            <p className="text-xs text-muted-foreground">{section.emptySummary ?? 'No artifact available.'}</p>
          ) : (
            <>
              <div className="flex flex-wrap items-center gap-2">
                <a
                  href={artifactUrl}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="inline-flex items-center gap-1 rounded-md border border-border bg-muted/40 px-2 py-1 text-xs text-foreground hover:bg-muted/60 transition-colors"
                >
                  Open Artifact
                </a>
                <a
                  href={artifactUrl}
                  download
                  className="inline-flex items-center gap-1 rounded-md border border-border bg-muted/40 px-2 py-1 text-xs text-foreground hover:bg-muted/60 transition-colors"
                >
                  Download
                </a>
                {checksum ? (
                  <span className="text-[11px] text-muted-foreground break-all">Checksum: {checksum}</span>
                ) : null}
              </div>
              {isImage ? (
                <div className="rounded-lg border border-border bg-black/30 p-2">
                  {/* eslint-disable-next-line @next/next/no-img-element */}
                  <img
                    src={artifactUrl}
                    alt="Screenshot artifact preview"
                    loading="lazy"
                    className="max-h-80 w-auto rounded object-contain"
                  />
                </div>
              ) : null}
            </>
          )}
        </div>
      );
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
                <p className="font-medium">{item.field ? `${item.field} | ${item.reason}` : item.reason}</p>
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
