'use client';
import React, { useState } from 'react';
import { Terminal, Monitor, ChevronDown, ChevronRight, Download, Eye, EyeOff, CheckCircle, XCircle, Clock, Loader2, Image as ImageIcon, Folder, File, FolderOpen, RefreshCw, Upload, Trash2, Plus, Info, Copy, AlertTriangle, ChevronUp, Search } from 'lucide-react';
import { toast } from 'sonner';

type CommandResultType =
  | 'system-info' |'screenshot-capture' |'filesystem' |'download-file' |'upload-file' |'create-file' |'create-folder' |'delete-file' |'delete-folder' |'text-output' |'ping' |'lock_screen' |'process-list' |'network-info';

type ResultStatus = 'queued' | 'executing' | 'completed' | 'failed' | 'expired';

interface FileNode {
  name: string;
  type: 'file' | 'folder';
  size?: string;
  modified?: string;
  children?: FileNode[];
}

interface CommandResult {
  id: string;
  commandId: string;
  deviceId: string;
  hostname: string;
  method: CommandResultType;
  actor: string;
  queuedAt: string;
  completedAt: string | null;
  status: ResultStatus;
  rawOutput: string;
  result: Record<string, unknown> | null;
}

const mockFileTree: FileNode[] = [
  { name: 'C:\\', type: 'folder', children: [
    { name: 'Users', type: 'folder', children: [
      { name: 'Administrator', type: 'folder', children: [
        { name: 'Documents', type: 'folder', children: [
          { name: 'report_q1.xlsx', type: 'file', size: '142 KB', modified: '2026-04-01' },
          { name: 'notes.txt', type: 'file', size: '4 KB', modified: '2026-04-03' },
        ]},
        { name: 'Desktop', type: 'folder', children: [
          { name: 'quoodle-agent.exe', type: 'file', size: '8.2 MB', modified: '2026-03-15' },
        ]},
      ]},
    ]},
    { name: 'Program Files', type: 'folder', children: [
      { name: 'Quoodle', type: 'folder', children: [
        { name: 'agent.exe', type: 'file', size: '8.2 MB', modified: '2026-03-15' },
        { name: 'config.json', type: 'file', size: '2 KB', modified: '2026-04-01' },
      ]},
    ]},
    { name: 'Windows', type: 'folder', children: [] },
  ]},
];

const mockResults: CommandResult[] = [
  {
    id: 'res-1', commandId: 'CMD-7742', deviceId: 'WKSTN-055', hostname: 'WKSTN-055',
    method: 'system-info', actor: 'chloe.dubois@quoodle.io', queuedAt: '21:06:01', completedAt: '21:06:09',
    status: 'completed',
    rawOutput: '{"hostname":"WKSTN-055","os":"Windows 11 Pro 22H2","build":"22621.3447","cpu":"Intel Core i7-12700K @ 3.60GHz","cores":12,"ram_total":"32 GB","ram_used":"14.2 GB","disk_total":"512 GB","disk_used":"187 GB","uptime":"4d 6h 22m","agent":"0.0.1","ip":"10.0.1.65","mac":"A4:BB:6D:11:22:33"}',
    result: { hostname: 'WKSTN-055', os: 'Windows 11 Pro 22H2', build: '22621.3447', cpu: 'Intel Core i7-12700K @ 3.60GHz', cores: 12, ram_total: '32 GB', ram_used: '14.2 GB', disk_total: '512 GB', disk_used: '187 GB', uptime: '4d 6h 22m', agent: '0.0.1', ip: '10.0.1.65', mac: 'A4:BB:6D:11:22:33' },
  },
  {
    id: 'res-2', commandId: 'CMD-7745', deviceId: 'WKSTN-001', hostname: 'WKSTN-001',
    method: 'screenshot-capture', actor: 'admin@quoodle.io', queuedAt: '21:05:00', completedAt: '21:05:04',
    status: 'completed',
    rawOutput: 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
    result: { screenshot_url: 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==', width: 1920, height: 1080, captured_at: '21:05:04' },
  },
  {
    id: 'res-3', commandId: 'CMD-7746', deviceId: 'WKSTN-042', hostname: 'WKSTN-042',
    method: 'filesystem', actor: 'raj.mehta@quoodle.io', queuedAt: '21:04:00', completedAt: '21:04:08',
    status: 'completed',
    rawOutput: JSON.stringify(mockFileTree),
    result: { tree: mockFileTree },
  },
  {
    id: 'res-4', commandId: 'CMD-7747', deviceId: 'WKSTN-088', hostname: 'WKSTN-088',
    method: 'download-file', actor: 'tom.brennan@quoodle.io', queuedAt: '21:03:00', completedAt: '21:03:12',
    status: 'completed',
    rawOutput: '{"file":"report_q1.xlsx","size":"142 KB","path":"C:\\\\Users\\\\Administrator\\\\Documents\\\\report_q1.xlsx","checksum":"sha256:abc123"}',
    result: { file: 'report_q1.xlsx', size: '142 KB', path: 'C:\\Users\\Administrator\\Documents\\report_q1.xlsx', checksum: 'sha256:abc123' },
  },
  {
    id: 'res-5', commandId: 'CMD-7748', deviceId: 'WKSTN-001', hostname: 'WKSTN-001',
    method: 'upload-file', actor: 'sarah.chen@quoodle.io', queuedAt: '21:02:00', completedAt: '21:02:45',
    status: 'completed',
    rawOutput: '{"file":"policy_update.json","size":"8 KB","destination":"C:\\\\Quoodle\\\\policies\\\\","status":"written","checksum":"sha256:def456"}',
    result: { file: 'policy_update.json', size: '8 KB', destination: 'C:\\Quoodle\\policies\\', status: 'written', checksum: 'sha256:def456' },
  },
  {
    id: 'res-6', commandId: 'CMD-7749', deviceId: 'WKSTN-103', hostname: 'WKSTN-103',
    method: 'create-folder', actor: 'yuki.tanaka@quoodle.io', queuedAt: '21:01:00', completedAt: '21:01:02',
    status: 'completed',
    rawOutput: '{"path":"C:\\\\Quoodle\\\\backups\\\\2026-04-05","created":true}',
    result: { path: 'C:\\Quoodle\\backups\\2026-04-05', created: true },
  },
  {
    id: 'res-7', commandId: 'CMD-7741', deviceId: 'WKSTN-042', hostname: 'WKSTN-042',
    method: 'lock_screen', actor: 'raj.mehta@quoodle.io', queuedAt: '21:01:55', completedAt: null,
    status: 'failed',
    rawOutput: '{"error":"Kernel opcode not supported","code":4004,"method":"lock_screen"}',
    result: null,
  },
  {
    id: 'res-8', commandId: 'CMD-7750', deviceId: 'WKSTN-055', hostname: 'WKSTN-055',
    method: 'process-list', actor: 'admin@quoodle.io', queuedAt: '20:58:00', completedAt: '20:58:03',
    status: 'completed',
    rawOutput: '[{"pid":4,"name":"System","cpu":0.1,"mem":"2 MB"},{"pid":1024,"name":"explorer.exe","cpu":0.8,"mem":"48 MB"},{"pid":2048,"name":"quoodle-agent.exe","cpu":0.2,"mem":"32 MB"},{"pid":3072,"name":"chrome.exe","cpu":4.2,"mem":"512 MB"},{"pid":4096,"name":"vscode.exe","cpu":2.1,"mem":"256 MB"}]',
    result: { processes: [{ pid: 4, name: 'System', cpu: 0.1, mem: '2 MB' }, { pid: 1024, name: 'explorer.exe', cpu: 0.8, mem: '48 MB' }, { pid: 2048, name: 'quoodle-agent.exe', cpu: 0.2, mem: '32 MB' }, { pid: 3072, name: 'chrome.exe', cpu: 4.2, mem: '512 MB' }, { pid: 4096, name: 'vscode.exe', cpu: 2.1, mem: '256 MB' }] },
  },
  {
    id: 'res-9', commandId: 'CMD-7751', deviceId: 'WKSTN-001', hostname: 'WKSTN-001',
    method: 'network-info', actor: 'admin@quoodle.io', queuedAt: '20:55:00', completedAt: '20:55:02',
    status: 'completed',
    rawOutput: '{"interfaces":[{"name":"Ethernet","ip":"10.0.1.11","mac":"A4:BB:6D:11:22:33","speed":"1 Gbps","status":"up"},{"name":"Wi-Fi","ip":"192.168.1.45","mac":"B2:CC:7E:44:55:66","speed":"300 Mbps","status":"up"}],"dns":["8.8.8.8","1.1.1.1"],"gateway":"10.0.1.1"}',
    result: { interfaces: [{ name: 'Ethernet', ip: '10.0.1.11', mac: 'A4:BB:6D:11:22:33', speed: '1 Gbps', status: 'up' }, { name: 'Wi-Fi', ip: '192.168.1.45', mac: 'B2:CC:7E:44:55:66', speed: '300 Mbps', status: 'up' }], dns: ['8.8.8.8', '1.1.1.1'], gateway: '10.0.1.1' },
  },
];

const statusConfig: Record<ResultStatus, { icon: React.ElementType; color: string; label: string }> = {
  queued:    { icon: Clock,     color: 'text-muted-foreground', label: 'Queued' },
  executing: { icon: Loader2,   color: 'text-blue-400',         label: 'Executing' },
  completed: { icon: CheckCircle, color: 'text-green-400',      label: 'Completed' },
  failed:    { icon: XCircle,   color: 'text-red-400',          label: 'Failed' },
  expired:   { icon: AlertTriangle, color: 'text-amber-400',    label: 'Expired' },
};

const methodLabels: Record<CommandResultType, string> = {
  'system-info': 'System Info',
  'screenshot-capture': 'Screenshot',
  'filesystem': 'Filesystem',
  'download-file': 'Download File',
  'upload-file': 'Upload File',
  'create-file': 'Create File',
  'create-folder': 'Create Folder',
  'delete-file': 'Delete File',
  'delete-folder': 'Delete Folder',
  'text-output': 'Text Output',
  'ping': 'Ping',
  'lock_screen': 'Lock Screen',
  'process-list': 'Process List',
  'network-info': 'Network Info',
};

// ─── Sub-renderers ────────────────────────────────────────────────────────────

function SystemInfoRenderer({ data }: { data: Record<string, unknown> }) {
  const fields = [
    { label: 'Hostname', key: 'hostname' }, { label: 'OS', key: 'os' }, { label: 'Build', key: 'build' },
    { label: 'CPU', key: 'cpu' }, { label: 'Cores', key: 'cores' }, { label: 'RAM Total', key: 'ram_total' },
    { label: 'RAM Used', key: 'ram_used' }, { label: 'Disk Total', key: 'disk_total' }, { label: 'Disk Used', key: 'disk_used' },
    { label: 'Uptime', key: 'uptime' }, { label: 'Agent', key: 'agent' }, { label: 'IP', key: 'ip' }, { label: 'MAC', key: 'mac' },
  ];
  return (
    <div className="grid grid-cols-2 md:grid-cols-3 gap-2">
      {fields.map((f) => (
        <div key={f.key} className="bg-muted/30 rounded-md px-3 py-2">
          <p className="text-[10px] text-muted-foreground uppercase tracking-wide">{f.label}</p>
          <p className="text-xs font-mono mt-0.5 text-foreground">{String(data[f.key] ?? '—')}</p>
        </div>
      ))}
    </div>
  );
}

function ScreenshotRenderer({ data }: { data: Record<string, unknown> }) {
  return (
    <div className="space-y-2">
      <div className="flex items-center gap-3 text-xs text-muted-foreground">
        <span>{String(data.width ?? 0)} × {String(data.height ?? 0)}</span>
        <span>Captured at {String(data.captured_at ?? '')}</span>
      </div>
      <div className="bg-muted/30 rounded-lg overflow-hidden border border-border">
        <img
          src={String(data.screenshot_url ?? '')}
          alt="Remote desktop screenshot"
          className="w-full max-h-96 object-contain"
          onError={(e) => { (e.target as HTMLImageElement).style.display = 'none'; }}
        />
        <div className="flex items-center justify-center py-8 text-muted-foreground text-xs gap-2">
          <ImageIcon size={16} />
          <span>Screenshot preview (base64 encoded)</span>
        </div>
      </div>
      <button
        onClick={() => toast.info('Download triggered')}
        className="flex items-center gap-1.5 px-3 py-1.5 text-xs bg-blue-500/10 border border-blue-500/20 text-blue-400 rounded-md hover:bg-blue-500/20 transition-colors"
      >
        <Download size={12} /> Download Screenshot
      </button>
    </div>
  );
}

function FileTreeNode({ node, depth = 0 }: { node: FileNode; depth?: number }) {
  const [open, setOpen] = useState(depth < 2);
  return (
    <div>
      <div
        className="flex items-center gap-1.5 py-0.5 px-2 rounded hover:bg-muted/40 cursor-pointer text-xs group"
        style={{ paddingLeft: `${8 + depth * 16}px` }}
        onClick={() => node.type === 'folder' && setOpen(!open)}
      >
        {node.type === 'folder' ? (
          <>
            {open ? <ChevronDown size={11} className="text-muted-foreground flex-shrink-0" /> : <ChevronRight size={11} className="text-muted-foreground flex-shrink-0" />}
            {open ? <FolderOpen size={13} className="text-amber-400 flex-shrink-0" /> : <Folder size={13} className="text-amber-400 flex-shrink-0" />}
          </>
        ) : (
          <>
            <span className="w-3 flex-shrink-0" />
            <File size={13} className="text-blue-400 flex-shrink-0" />
          </>
        )}
        <span className="flex-1 font-mono">{node.name}</span>
        {node.size && <span className="text-muted-foreground text-[10px] opacity-0 group-hover:opacity-100">{node.size}</span>}
        {node.modified && <span className="text-muted-foreground text-[10px] opacity-0 group-hover:opacity-100 ml-2">{node.modified}</span>}
      </div>
      {node.type === 'folder' && open && node.children?.map((child, i) => (
        <FileTreeNode key={`${child.name}-${i}`} node={child} depth={depth + 1} />
      ))}
    </div>
  );
}

function FilesystemRenderer({ data }: { data: Record<string, unknown> }) {
  const tree = data.tree as FileNode[];
  return (
    <div className="bg-muted/20 border border-border rounded-lg overflow-hidden">
      <div className="flex items-center gap-2 px-3 py-2 border-b border-border bg-muted/30">
        <Folder size={13} className="text-amber-400" />
        <span className="text-xs font-medium">File System Explorer</span>
      </div>
      <div className="py-1 max-h-72 overflow-y-auto scrollbar-thin">
        {tree?.map((node, i) => <FileTreeNode key={`root-${i}`} node={node} />)}
      </div>
    </div>
  );
}

function DownloadFileRenderer({ data }: { data: Record<string, unknown> }) {
  return (
    <div className="bg-muted/20 border border-border rounded-lg p-4 space-y-3">
      <div className="flex items-center gap-3">
        <div className="w-10 h-10 rounded-lg bg-blue-500/10 flex items-center justify-center">
          <File size={18} className="text-blue-400" />
        </div>
        <div>
          <p className="text-sm font-medium">{String(data.file ?? '')}</p>
          <p className="text-xs text-muted-foreground">{String(data.path ?? '')} · {String(data.size ?? '')}</p>
        </div>
      </div>
      <div className="text-[11px] text-muted-foreground font-mono bg-muted/30 px-3 py-1.5 rounded">
        Checksum: {String(data.checksum ?? '')}
      </div>
      <button
        onClick={() => toast.success(`Downloading ${String(data.file ?? '')}…`)}
        className="flex items-center gap-1.5 px-3 py-1.5 text-xs bg-blue-500/10 border border-blue-500/20 text-blue-400 rounded-md hover:bg-blue-500/20 transition-colors"
      >
        <Download size={12} /> Download File
      </button>
    </div>
  );
}

function UploadFileRenderer({ data }: { data: Record<string, unknown> }) {
  return (
    <div className="bg-muted/20 border border-border rounded-lg p-4 space-y-3">
      <div className="flex items-center gap-3">
        <div className="w-10 h-10 rounded-lg bg-green-500/10 flex items-center justify-center">
          <Upload size={18} className="text-green-400" />
        </div>
        <div>
          <p className="text-sm font-medium">{String(data.file ?? '')}</p>
          <p className="text-xs text-muted-foreground">{String(data.destination ?? '')} · {String(data.size ?? '')}</p>
        </div>
      </div>
      <div className="flex items-center gap-2">
        <div className="flex-1 h-2 bg-muted rounded-full overflow-hidden">
          <div className="h-full bg-green-500 rounded-full w-full" />
        </div>
        <span className="text-xs text-green-400 font-medium">100%</span>
      </div>
      <div className="flex items-center gap-2 text-xs text-green-400">
        <CheckCircle size={12} />
        <span>File written successfully · {String(data.checksum ?? '')}</span>
      </div>
    </div>
  );
}

function FolderActionRenderer({ data, method }: { data: Record<string, unknown>; method: string }) {
  const isCreate = method.startsWith('create');
  return (
    <div className="bg-muted/20 border border-border rounded-lg p-4">
      <div className="flex items-center gap-3">
        <div className={`w-10 h-10 rounded-lg flex items-center justify-center ${isCreate ? 'bg-green-500/10' : 'bg-red-500/10'}`}>
          {isCreate ? <Plus size={18} className="text-green-400" /> : <Trash2 size={18} className="text-red-400" />}
        </div>
        <div>
          <p className="text-sm font-medium">{isCreate ? 'Created' : 'Deleted'} Successfully</p>
          <p className="text-xs text-muted-foreground font-mono">{String(data.path ?? '')}</p>
        </div>
      </div>
    </div>
  );
}

function ProcessListRenderer({ data }: { data: Record<string, unknown> }) {
  const processes = data.processes as Array<{ pid: number; name: string; cpu: number; mem: string }>;
  return (
    <div className="bg-muted/20 border border-border rounded-lg overflow-hidden">
      <table className="w-full text-xs">
        <thead>
          <tr className="border-b border-border bg-muted/30">
            <th className="px-3 py-2 text-left text-[10px] uppercase tracking-wide text-muted-foreground">PID</th>
            <th className="px-3 py-2 text-left text-[10px] uppercase tracking-wide text-muted-foreground">Name</th>
            <th className="px-3 py-2 text-left text-[10px] uppercase tracking-wide text-muted-foreground">CPU %</th>
            <th className="px-3 py-2 text-left text-[10px] uppercase tracking-wide text-muted-foreground">Memory</th>
          </tr>
        </thead>
        <tbody className="divide-y divide-border">
          {processes?.map((p) => (
            <tr key={p.pid} className="hover:bg-muted/20">
              <td className="px-3 py-2 font-mono text-muted-foreground">{p.pid}</td>
              <td className="px-3 py-2 font-medium">{p.name}</td>
              <td className="px-3 py-2">
                <div className="flex items-center gap-2">
                  <div className="w-16 h-1.5 bg-muted rounded-full overflow-hidden">
                    <div className="h-full bg-blue-500 rounded-full" style={{ width: `${Math.min(p.cpu * 10, 100)}%` }} />
                  </div>
                  <span className="tabular-nums text-muted-foreground">{p.cpu}%</span>
                </div>
              </td>
              <td className="px-3 py-2 text-muted-foreground">{p.mem}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function NetworkInfoRenderer({ data }: { data: Record<string, unknown> }) {
  const interfaces = data.interfaces as Array<{ name: string; ip: string; mac: string; speed: string; status: string }>;
  return (
    <div className="space-y-3">
      <div className="grid grid-cols-2 gap-2">
        <div className="bg-muted/30 rounded-md px-3 py-2">
          <p className="text-[10px] text-muted-foreground uppercase tracking-wide">Gateway</p>
          <p className="text-xs font-mono mt-0.5">{String(data.gateway ?? '')}</p>
        </div>
        <div className="bg-muted/30 rounded-md px-3 py-2">
          <p className="text-[10px] text-muted-foreground uppercase tracking-wide">DNS Servers</p>
          <p className="text-xs font-mono mt-0.5">{(data.dns as string[])?.join(', ')}</p>
        </div>
      </div>
      <div className="bg-muted/20 border border-border rounded-lg overflow-hidden">
        <table className="w-full text-xs">
          <thead>
            <tr className="border-b border-border bg-muted/30">
              <th className="px-3 py-2 text-left text-[10px] uppercase tracking-wide text-muted-foreground">Interface</th>
              <th className="px-3 py-2 text-left text-[10px] uppercase tracking-wide text-muted-foreground">IP</th>
              <th className="px-3 py-2 text-left text-[10px] uppercase tracking-wide text-muted-foreground">MAC</th>
              <th className="px-3 py-2 text-left text-[10px] uppercase tracking-wide text-muted-foreground">Speed</th>
              <th className="px-3 py-2 text-left text-[10px] uppercase tracking-wide text-muted-foreground">Status</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-border">
            {interfaces?.map((iface) => (
              <tr key={iface.name} className="hover:bg-muted/20">
                <td className="px-3 py-2 font-medium">{iface.name}</td>
                <td className="px-3 py-2 font-mono text-muted-foreground">{iface.ip}</td>
                <td className="px-3 py-2 font-mono text-muted-foreground text-[10px]">{iface.mac}</td>
                <td className="px-3 py-2 text-muted-foreground">{iface.speed}</td>
                <td className="px-3 py-2">
                  <span className={`text-[10px] px-1.5 py-0.5 rounded-full ${iface.status === 'up' ? 'bg-green-500/10 text-green-400' : 'bg-muted text-muted-foreground'}`}>
                    {iface.status}
                  </span>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}

function TextOutputRenderer({ rawOutput }: { rawOutput: string }) {
  return (
    <pre className="bg-zinc-950 border border-border rounded-lg px-4 py-3 text-xs font-mono text-green-400 overflow-x-auto whitespace-pre-wrap max-h-64 scrollbar-thin">
      {rawOutput}
    </pre>
  );
}

function ResultRenderer({ result }: { result: CommandResult }) {
  const [showRaw, setShowRaw] = useState(false);

  const renderContent = () => {
    if (result.status === 'failed') {
      return (
        <div className="bg-red-500/10 border border-red-500/20 rounded-lg p-4">
          <div className="flex items-center gap-2 mb-2">
            <XCircle size={14} className="text-red-400" />
            <span className="text-sm font-medium text-red-400">Command Failed</span>
          </div>
          <pre className="text-xs font-mono text-red-300/80 whitespace-pre-wrap">{result.rawOutput}</pre>
        </div>
      );
    }
    if (!result.result) return <TextOutputRenderer rawOutput={result.rawOutput} />;

    switch (result.method) {
      case 'system-info': return <SystemInfoRenderer data={result.result} />;
      case 'screenshot-capture': return <ScreenshotRenderer data={result.result} />;
      case 'filesystem': return <FilesystemRenderer data={result.result} />;
      case 'download-file': return <DownloadFileRenderer data={result.result} />;
      case 'upload-file': return <UploadFileRenderer data={result.result} />;
      case 'create-file': case 'create-folder': case 'delete-file': case 'delete-folder':
        return <FolderActionRenderer data={result.result} method={result.method} />;
      case 'process-list': return <ProcessListRenderer data={result.result} />;
      case 'network-info': return <NetworkInfoRenderer data={result.result} />;
      default: return <TextOutputRenderer rawOutput={result.rawOutput} />;
    }
  };

  return (
    <div className="space-y-2">
      <div className="flex items-center justify-between">
        <span className="text-xs text-muted-foreground">Output</span>
        <button
          onClick={() => setShowRaw(!showRaw)}
          className="flex items-center gap-1 text-xs text-muted-foreground hover:text-foreground transition-colors"
        >
          {showRaw ? <Eye size={11} /> : <EyeOff size={11} />}
          {showRaw ? 'Rendered' : 'Raw JSON'}
        </button>
      </div>
      {showRaw ? (
        <pre className="bg-zinc-950 border border-border rounded-lg px-4 py-3 text-xs font-mono text-green-400 overflow-x-auto whitespace-pre-wrap max-h-64 scrollbar-thin">
          {result.rawOutput}
        </pre>
      ) : renderContent()}
    </div>
  );
}

// ─── Main Component ───────────────────────────────────────────────────────────

export default function CommandResultsContent() {
  const [results] = useState<CommandResult[]>(mockResults);
  const [expandedIds, setExpandedIds] = useState<Set<string>>(new Set(['res-1']));
  const [search, setSearch] = useState('');
  const [deviceFilter, setDeviceFilter] = useState('all');
  const [statusFilter, setStatusFilter] = useState<ResultStatus | 'all'>('all');
  const [methodFilter, setMethodFilter] = useState('all');

  const devices = Array.from(new Set(results.map((r) => r.hostname)));
  const methods = Array.from(new Set(results.map((r) => r.method)));

  const filtered = results.filter((r) => {
    if (deviceFilter !== 'all' && r.hostname !== deviceFilter) return false;
    if (statusFilter !== 'all' && r.status !== statusFilter) return false;
    if (methodFilter !== 'all' && r.method !== methodFilter) return false;
    if (search && !r.commandId.toLowerCase().includes(search.toLowerCase()) &&
        !r.hostname.toLowerCase().includes(search.toLowerCase()) &&
        !r.actor.toLowerCase().includes(search.toLowerCase())) return false;
    return true;
  });

  const toggleExpand = (id: string) => {
    setExpandedIds((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id); else next.add(id);
      return next;
    });
  };

  return (
    <div className="space-y-4 fade-in">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">Command Results</h1>
          <p className="text-sm text-muted-foreground mt-0.5">
            Rich output viewer for all executed commands · {results.length} results
          </p>
        </div>
        <button
          onClick={() => toast.info('Results refreshed')}
          className="flex items-center gap-1.5 px-3 py-1.5 text-xs text-muted-foreground border border-border rounded-md hover:bg-muted/60 transition-colors"
        >
          <RefreshCw size={13} /> Refresh
        </button>
      </div>

      {/* Filters */}
      <div className="flex flex-wrap items-center gap-2">
        <div className="relative">
          <Search size={13} className="absolute left-2.5 top-1/2 -translate-y-1/2 text-muted-foreground" />
          <input
            placeholder="Search command, device, actor…"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="pl-8 pr-3 py-1.5 text-xs bg-muted/60 border border-border rounded-md text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-1 focus:ring-primary/50 w-52"
          />
        </div>
        <select
          value={deviceFilter}
          onChange={(e) => setDeviceFilter(e.target.value)}
          className="text-xs bg-muted/60 border border-border rounded-md px-2.5 py-1.5 text-foreground focus:outline-none focus:ring-1 focus:ring-primary/50"
        >
          <option value="all">All Devices</option>
          {devices.map((d) => <option key={d} value={d}>{d}</option>)}
        </select>
        <select
          value={statusFilter}
          onChange={(e) => setStatusFilter(e.target.value as ResultStatus | 'all')}
          className="text-xs bg-muted/60 border border-border rounded-md px-2.5 py-1.5 text-foreground focus:outline-none focus:ring-1 focus:ring-primary/50"
        >
          <option value="all">All Status</option>
          <option value="completed">Completed</option>
          <option value="failed">Failed</option>
          <option value="executing">Executing</option>
          <option value="queued">Queued</option>
        </select>
        <select
          value={methodFilter}
          onChange={(e) => setMethodFilter(e.target.value)}
          className="text-xs bg-muted/60 border border-border rounded-md px-2.5 py-1.5 text-foreground focus:outline-none focus:ring-1 focus:ring-primary/50"
        >
          <option value="all">All Commands</option>
          {methods.map((m) => <option key={m} value={m}>{methodLabels[m] ?? m}</option>)}
        </select>
        {(search || deviceFilter !== 'all' || statusFilter !== 'all' || methodFilter !== 'all') && (
          <button
            onClick={() => { setSearch(''); setDeviceFilter('all'); setStatusFilter('all'); setMethodFilter('all'); }}
            className="flex items-center gap-1 text-xs text-muted-foreground hover:text-foreground"
          >
            <XCircle size={12} /> Clear
          </button>
        )}
      </div>

      {/* Results feed */}
      <div className="space-y-3">
        {filtered.length === 0 ? (
          <div className="bg-card border border-border rounded-lg px-4 py-12 text-center">
            <Terminal size={32} className="mx-auto text-muted-foreground/30 mb-3" />
            <p className="text-sm font-medium text-muted-foreground">No results match your filters</p>
          </div>
        ) : (
          filtered.map((result) => {
            const expanded = expandedIds.has(result.id);
            const StatusIcon = statusConfig[result.status].icon;
            return (
              <div key={result.id} className="bg-card border border-border rounded-lg overflow-hidden">
                {/* Result header */}
                <div
                  className="flex items-center gap-3 px-4 py-3 cursor-pointer hover:bg-muted/20 transition-colors"
                  onClick={() => toggleExpand(result.id)}
                >
                  <StatusIcon
                    size={15}
                    className={`flex-shrink-0 ${statusConfig[result.status].color} ${result.status === 'executing' ? 'animate-spin' : ''}`}
                  />
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2 flex-wrap">
                      <span className="text-sm font-medium font-mono">{result.commandId}</span>
                      <span className="text-xs text-muted-foreground bg-muted/60 px-2 py-0.5 rounded">
                        {methodLabels[result.method] ?? result.method}
                      </span>
                      <span className={`text-[10px] font-semibold uppercase tracking-wider px-1.5 py-0.5 rounded-full ${
                        result.status === 'completed' ? 'bg-green-500/10 text-green-400' :
                        result.status === 'failed' ? 'bg-red-500/10 text-red-400' :
                        result.status === 'executing'? 'bg-blue-500/10 text-blue-400' : 'bg-muted text-muted-foreground'
                      }`}>
                        {statusConfig[result.status].label}
                      </span>
                    </div>
                    <div className="flex items-center gap-3 mt-0.5 text-[11px] text-muted-foreground">
                      <span className="flex items-center gap-1"><Monitor size={10} /> {result.hostname}</span>
                      <span>{result.actor}</span>
                      <span className="flex items-center gap-1"><Clock size={10} /> {result.queuedAt}{result.completedAt ? ` → ${result.completedAt}` : ''}</span>
                    </div>
                  </div>
                  <div className="flex items-center gap-2">
                    <button
                      onClick={(e) => { e.stopPropagation(); navigator.clipboard.writeText(result.rawOutput); toast.success('Raw output copied'); }}
                      className="p-1.5 text-muted-foreground hover:text-foreground transition-colors"
                      title="Copy raw output"
                    >
                      <Copy size={13} />
                    </button>
                    {expanded ? <ChevronUp size={14} className="text-muted-foreground" /> : <ChevronDown size={14} className="text-muted-foreground" />}
                  </div>
                </div>

                {/* Expanded result */}
                {expanded && (
                  <div className="border-t border-border px-4 py-4">
                    <ResultRenderer result={result} />
                  </div>
                )}
              </div>
            );
          })
        )}
      </div>
    </div>
  );
}
