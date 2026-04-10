import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../theme/app_theme.dart';
import '../../../widgets/status_badge_widget.dart';

// ── Public Entry Point ───────────────────────────────────────────────────────
class CommandResultWidget extends StatelessWidget {
  final Map<String, dynamic> command;
  final CommandStatus status;

  const CommandResultWidget({
    super.key,
    required this.command,
    required this.status,
  });

  bool get _isSuccess => status == CommandStatus.completed;
  bool get _isFailed =>
      status == CommandStatus.failed || status == CommandStatus.expired;

  Color get _statusColor => _isSuccess ? AppTheme.secondary : AppTheme.error;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ResultHeader(
            command: command,
            isSuccess: _isSuccess,
            statusColor: _statusColor,
          ),
          const Divider(height: 1, color: AppTheme.borderLight),
          if (_isSuccess)
            _buildTypedResult(context)
          else if (_isFailed)
            _FailureView(command: command),
        ],
      ),
    );
  }

  Widget _buildTypedResult(BuildContext context) {
    final method = command['method'] as String? ?? '';
    switch (method) {
      case 'screenshot_capture':
        return _ScreenshotResultView(command: command);
      case 'process_list':
        return _ProcessListResultView(command: command);
      case 'running_apps':
        return _RunningAppsResultView(command: command);
      case 'filesystem':
        return _FilesystemResultView(command: command);
      case 'system_info':
        return _SystemInfoResultView(command: command);
      case 'network_info':
        return _NetworkInfoResultView(command: command);
      case 'upload_file':
      case 'create_file':
        return _FileOpResultView(command: command);
      case 'collect_telemetry':
        return _TelemetryResultView(command: command);
      case 'lock_screen':
      case 'policy_sync':
      case 'reboot':
        return _ActionResultView(command: command);
      default:
        return _GenericResultView(command: command);
    }
  }
}

// ── Result Header ────────────────────────────────────────────────────────────
class _ResultHeader extends StatelessWidget {
  final Map<String, dynamic> command;
  final bool isSuccess;
  final Color statusColor;

  const _ResultHeader({
    required this.command,
    required this.isSuccess,
    required this.statusColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Row(
        children: [
          Icon(
            isSuccess ? Icons.check_circle_rounded : Icons.cancel_rounded,
            color: statusColor,
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(
            isSuccess ? 'Command Completed' : 'Command Failed',
            style: GoogleFonts.ibmPlexSans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: statusColor,
            ),
          ),
          const Spacer(),
          if (command.containsKey('executionTimeMs'))
            _MetaChip(
              label: '${command['executionTimeMs']}ms',
              monospace: true,
            ),
        ],
      ),
    );
  }
}

// ── Screenshot Result ────────────────────────────────────────────────────────
class _ScreenshotResultView extends StatefulWidget {
  final Map<String, dynamic> command;
  const _ScreenshotResultView({required this.command});

  @override
  State<_ScreenshotResultView> createState() => _ScreenshotResultViewState();
}

class _ScreenshotResultViewState extends State<_ScreenshotResultView> {
  bool _fullscreen = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _SectionLabel('SCREENSHOT'),
              const Spacer(),
              _MetaChip(label: 'SENSITIVE', color: AppTheme.warning),
            ],
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => setState(() => _fullscreen = !_fullscreen),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: double.infinity,
              height: _fullscreen ? 280 : 180,
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.border),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(
                      'https://images.unsplash.com/photo-1551288049-bebda4e38f71?w=800&q=80',
                      fit: BoxFit.cover,
                      semanticLabel:
                          'Screenshot of device screen showing dashboard with charts and data tables',
                      errorBuilder: (_, __, ___) => Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.screenshot_rounded,
                              size: 32,
                              color: AppTheme.textMuted,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'screenshot_20260406_104131.png',
                              style: GoogleFonts.ibmPlexMono(
                                fontSize: 10,
                                color: AppTheme.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              Colors.black.withAlpha(180),
                              Colors.transparent,
                            ],
                          ),
                        ),
                        child: Row(
                          children: [
                            Text(
                              '1920×1080  ·  PNG  ·  2.4 MB',
                              style: GoogleFonts.ibmPlexMono(
                                fontSize: 10,
                                color: Colors.white70,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '10:41:31',
                              style: GoogleFonts.ibmPlexMono(
                                fontSize: 10,
                                color: Colors.white54,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(
                          _fullscreen
                              ? Icons.zoom_out_rounded
                              : Icons.zoom_in_rounded,
                          size: 14,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _ActionRow(
            actions: [
              _ActionButton(
                icon: Icons.download_rounded,
                label: 'Download',
                onTap: () {},
              ),
              _ActionButton(
                icon: Icons.zoom_in_rounded,
                label: _fullscreen ? 'Collapse' : 'Expand',
                onTap: () => setState(() => _fullscreen = !_fullscreen),
              ),
              _ActionButton(
                icon: Icons.share_rounded,
                label: 'Export',
                onTap: () {},
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Process List Result ──────────────────────────────────────────────────────
class _ProcessListResultView extends StatefulWidget {
  final Map<String, dynamic> command;
  const _ProcessListResultView({required this.command});

  @override
  State<_ProcessListResultView> createState() => _ProcessListResultViewState();
}

class _ProcessListResultViewState extends State<_ProcessListResultView> {
  String _sortBy = 'cpu';
  String _filter = '';

  static final List<Map<String, dynamic>> _allProcesses = [
    {
      'pid': 4,
      'name': 'System',
      'cpu': 0.1,
      'mem': 0.2,
      'user': 'SYSTEM',
      'status': 'running',
    },
    {
      'pid': 892,
      'name': 'svchost.exe',
      'cpu': 2.3,
      'mem': 1.4,
      'user': 'SYSTEM',
      'status': 'running',
    },
    {
      'pid': 1204,
      'name': 'chrome.exe',
      'cpu': 18.7,
      'mem': 12.3,
      'user': 'lnakamura',
      'status': 'running',
    },
    {
      'pid': 2048,
      'name': 'explorer.exe',
      'cpu': 0.8,
      'mem': 3.1,
      'user': 'lnakamura',
      'status': 'running',
    },
    {
      'pid': 3312,
      'name': 'antivirus.exe',
      'cpu': 4.2,
      'mem': 5.8,
      'user': 'SYSTEM',
      'status': 'running',
    },
    {
      'pid': 4096,
      'name': 'outlook.exe',
      'cpu': 1.1,
      'mem': 8.4,
      'user': 'lnakamura',
      'status': 'running',
    },
    {
      'pid': 5120,
      'name': 'quoodle-agent',
      'cpu': 0.3,
      'mem': 0.9,
      'user': 'SYSTEM',
      'status': 'running',
    },
    {
      'pid': 6144,
      'name': 'teams.exe',
      'cpu': 6.5,
      'mem': 15.2,
      'user': 'lnakamura',
      'status': 'running',
    },
    {
      'pid': 7200,
      'name': 'winlogon.exe',
      'cpu': 0.0,
      'mem': 0.6,
      'user': 'SYSTEM',
      'status': 'running',
    },
    {
      'pid': 8192,
      'name': 'slack.exe',
      'cpu': 3.1,
      'mem': 9.7,
      'user': 'lnakamura',
      'status': 'running',
    },
  ];

  List<Map<String, dynamic>> get _filtered {
    var list = _allProcesses.where((p) {
      if (_filter.isEmpty) return true;
      return (p['name'] as String).toLowerCase().contains(
            _filter.toLowerCase(),
          );
    }).toList();
    list.sort((a, b) {
      if (_sortBy == 'cpu') {
        return (b['cpu'] as double).compareTo(a['cpu'] as double);
      } else if (_sortBy == 'mem') {
        return (b['mem'] as double).compareTo(a['mem'] as double);
      } else {
        return (a['pid'] as int).compareTo(b['pid'] as int);
      }
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final processes = _filtered;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _SectionLabel('PROCESS LIST'),
              const Spacer(),
              _MetaChip(label: '${processes.length} processes'),
            ],
          ),
          const SizedBox(height: 10),
          // Search + sort bar
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Row(
                    children: [
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Icon(
                          Icons.search_rounded,
                          size: 14,
                          color: AppTheme.textMuted,
                        ),
                      ),
                      Expanded(
                        child: TextField(
                          onChanged: (v) => setState(() => _filter = v),
                          style: GoogleFonts.ibmPlexSans(
                            fontSize: 12,
                            color: AppTheme.textPrimary,
                          ),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            hintText: 'Filter processes...',
                            hintStyle: GoogleFonts.ibmPlexSans(
                              fontSize: 12,
                              color: AppTheme.textMuted,
                            ),
                            filled: false,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 8,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _SortChip(
                label: 'CPU',
                active: _sortBy == 'cpu',
                onTap: () => setState(() => _sortBy = 'cpu'),
              ),
              const SizedBox(width: 4),
              _SortChip(
                label: 'MEM',
                active: _sortBy == 'mem',
                onTap: () => setState(() => _sortBy = 'mem'),
              ),
              const SizedBox(width: 4),
              _SortChip(
                label: 'PID',
                active: _sortBy == 'pid',
                onTap: () => setState(() => _sortBy = 'pid'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Table
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.border),
            ),
            child: Column(
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: const BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(9),
                    ),
                  ),
                  child: Row(
                    children: [
                      _TableHeader('PID', width: 48),
                      _TableHeader('PROCESS', flex: 2),
                      _TableHeader('USER', flex: 1),
                      _TableHeader('CPU%', width: 48, right: true),
                      _TableHeader('MEM%', width: 48, right: true),
                    ],
                  ),
                ),
                const Divider(height: 1, color: AppTheme.borderLight),
                ...processes.asMap().entries.map((entry) {
                  final i = entry.key;
                  final p = entry.value;
                  final cpu = p['cpu'] as double;
                  final mem = p['mem'] as double;
                  final cpuColor = cpu > 10
                      ? AppTheme.error
                      : cpu > 5
                          ? AppTheme.warning
                          : AppTheme.secondary;
                  final isLast = i == processes.length - 1;
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color:
                          i.isEven ? AppTheme.surfaceVariant : AppTheme.surface,
                      borderRadius: isLast
                          ? const BorderRadius.vertical(
                              bottom: Radius.circular(9),
                            )
                          : BorderRadius.zero,
                      border: !isLast
                          ? const Border(
                              bottom: BorderSide(color: AppTheme.borderLight),
                            )
                          : null,
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 48,
                          child: Text(
                            '${p['pid']}',
                            style: GoogleFonts.ibmPlexMono(
                              fontSize: 11,
                              color: AppTheme.textMuted,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            p['name'] as String,
                            style: GoogleFonts.ibmPlexMono(
                              fontSize: 11,
                              color: AppTheme.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Text(
                            p['user'] as String,
                            style: GoogleFonts.ibmPlexSans(
                              fontSize: 10,
                              color: AppTheme.textMuted,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        SizedBox(
                          width: 48,
                          child: Text(
                            cpu.toStringAsFixed(1),
                            style: GoogleFonts.ibmPlexMono(
                              fontSize: 11,
                              color: cpuColor,
                            ),
                            textAlign: TextAlign.right,
                          ),
                        ),
                        SizedBox(
                          width: 48,
                          child: Text(
                            mem.toStringAsFixed(1),
                            style: GoogleFonts.ibmPlexMono(
                              fontSize: 11,
                              color: AppTheme.primary,
                            ),
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _ActionRow(
            actions: [
              _ActionButton(
                icon: Icons.copy_rounded,
                label: 'Copy',
                onTap: () {},
              ),
              _ActionButton(
                icon: Icons.download_rounded,
                label: 'Export CSV',
                onTap: () {},
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Running Apps Result ──────────────────────────────────────────────────────
class _RunningAppsResultView extends StatelessWidget {
  final Map<String, dynamic> command;
  const _RunningAppsResultView({required this.command});

  static final List<Map<String, dynamic>> _apps = [
    {
      'name': 'Google Chrome',
      'bundle': 'com.google.chrome',
      'version': '120.0.6099',
      'status': 'foreground',
      'memory': '312 MB',
      'icon': Icons.language_rounded,
    },
    {
      'name': 'Microsoft Teams',
      'bundle': 'com.microsoft.teams',
      'version': '1.6.0.28861',
      'status': 'background',
      'memory': '245 MB',
      'icon': Icons.groups_rounded,
    },
    {
      'name': 'Microsoft Outlook',
      'bundle': 'com.microsoft.outlook',
      'version': '16.0.17029',
      'status': 'background',
      'memory': '198 MB',
      'icon': Icons.email_rounded,
    },
    {
      'name': 'Slack',
      'bundle': 'com.tinyspeck.slackmacgap',
      'version': '4.35.126',
      'status': 'background',
      'memory': '156 MB',
      'icon': Icons.chat_bubble_rounded,
    },
    {
      'name': 'Quoodle Agent',
      'bundle': 'com.quoodle.agent',
      'version': '2.1.4',
      'status': 'system',
      'memory': '24 MB',
      'icon': Icons.security_rounded,
    },
    {
      'name': 'Windows Defender',
      'bundle': 'com.microsoft.defender',
      'version': '4.18.2311',
      'status': 'system',
      'memory': '89 MB',
      'icon': Icons.shield_rounded,
    },
  ];

  Color _statusColor(String s) {
    switch (s) {
      case 'foreground':
        return AppTheme.secondary;
      case 'background':
        return AppTheme.primary;
      case 'system':
        return AppTheme.textMuted;
      default:
        return AppTheme.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _SectionLabel('RUNNING APPS'),
              const Spacer(),
              _MetaChip(label: '${_apps.length} apps'),
            ],
          ),
          const SizedBox(height: 10),
          ..._apps.map((app) {
            final statusColor = _statusColor(app['status'] as String);
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.borderLight),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: statusColor.withAlpha(20),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      app['icon'] as IconData,
                      size: 18,
                      color: statusColor,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          app['name'] as String,
                          style: GoogleFonts.ibmPlexSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        Text(
                          app['bundle'] as String,
                          style: GoogleFonts.ibmPlexMono(
                            fontSize: 10,
                            color: AppTheme.textMuted,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withAlpha(20),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          (app['status'] as String).toUpperCase(),
                          style: GoogleFonts.ibmPlexMono(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: statusColor,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        app['memory'] as String,
                        style: GoogleFonts.ibmPlexMono(
                          fontSize: 10,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 4),
          _ActionRow(
            actions: [
              _ActionButton(
                icon: Icons.copy_rounded,
                label: 'Copy',
                onTap: () {},
              ),
              _ActionButton(
                icon: Icons.download_rounded,
                label: 'Export',
                onTap: () {},
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Filesystem Result ────────────────────────────────────────────────────────
class _FilesystemResultView extends StatefulWidget {
  final Map<String, dynamic> command;
  const _FilesystemResultView({required this.command});

  @override
  State<_FilesystemResultView> createState() => _FilesystemResultViewState();
}

class _FilesystemResultViewState extends State<_FilesystemResultView> {
  final Set<String> _expanded = {'/home', '/etc'};

  static final Map<String, dynamic> _tree = {
    '/': {
      'type': 'dir',
      'children': {
        'home': {
          'type': 'dir',
          'children': {
            'lnakamura': {
              'type': 'dir',
              'children': {
                'Documents': {'type': 'dir', 'size': '—'},
                'Downloads': {'type': 'dir', 'size': '—'},
                '.bashrc': {'type': 'file', 'size': '3.2 KB'},
                '.ssh': {'type': 'dir', 'size': '—'},
              },
            },
          },
        },
        'etc': {
          'type': 'dir',
          'children': {
            'passwd': {'type': 'file', 'size': '2.1 KB'},
            'hosts': {'type': 'file', 'size': '312 B'},
            'resolv.conf': {'type': 'file', 'size': '128 B'},
            'ssh': {'type': 'dir', 'size': '—'},
          },
        },
        'var': {
          'type': 'dir',
          'children': {
            'log': {'type': 'dir', 'size': '—'},
            'tmp': {'type': 'dir', 'size': '—'},
          },
        },
        'tmp': {'type': 'dir', 'children': {}},
      },
    },
  };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _SectionLabel('FILESYSTEM'),
              const Spacer(),
              _MetaChip(label: 'SENSITIVE', color: AppTheme.warning),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Path bar
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: AppTheme.borderLight),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.folder_rounded,
                        size: 14,
                        color: AppTheme.warning,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '/',
                        style: GoogleFonts.ibmPlexMono(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: _buildTreeNode(
                    '/',
                    _tree['/'] as Map<String, dynamic>,
                    0,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _ActionRow(
            actions: [
              _ActionButton(
                icon: Icons.copy_rounded,
                label: 'Copy Path',
                onTap: () {},
              ),
              _ActionButton(
                icon: Icons.download_rounded,
                label: 'Export Tree',
                onTap: () {},
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTreeNode(String name, Map<String, dynamic> node, int depth) {
    final isDir = node['type'] == 'dir';
    final children = node['children'] as Map<String, dynamic>?;
    final isExpanded = _expanded.contains(name);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: isDir
              ? () => setState(() {
                    if (isExpanded) {
                      _expanded.remove(name);
                    } else {
                      _expanded.add(name);
                    }
                  })
              : null,
          child: Padding(
            padding: EdgeInsets.only(left: depth * 16.0, top: 3, bottom: 3),
            child: Row(
              children: [
                if (isDir)
                  Icon(
                    isExpanded
                        ? Icons.expand_more_rounded
                        : Icons.chevron_right_rounded,
                    size: 14,
                    color: AppTheme.textMuted,
                  )
                else
                  const SizedBox(width: 14),
                const SizedBox(width: 4),
                Icon(
                  isDir
                      ? (isExpanded
                          ? Icons.folder_open_rounded
                          : Icons.folder_rounded)
                      : Icons.insert_drive_file_outlined,
                  size: 14,
                  color: isDir ? AppTheme.warning : AppTheme.textMuted,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    name,
                    style: GoogleFonts.ibmPlexMono(
                      fontSize: 12,
                      color:
                          isDir ? AppTheme.textPrimary : AppTheme.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (!isDir && node.containsKey('size'))
                  Text(
                    node['size'] as String,
                    style: GoogleFonts.ibmPlexMono(
                      fontSize: 10,
                      color: AppTheme.textMuted,
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (isDir && isExpanded && children != null)
          ...children.entries.map(
            (e) => _buildTreeNode(
              e.key,
              e.value as Map<String, dynamic>,
              depth + 1,
            ),
          ),
      ],
    );
  }
}

// ── System Info Result ───────────────────────────────────────────────────────
class _SystemInfoResultView extends StatelessWidget {
  final Map<String, dynamic> command;
  const _SystemInfoResultView({required this.command});

  static final Map<String, Map<String, String>> _sections = {
    'Hardware': {
      'CPU': 'Intel Core i7-10700 @ 2.90GHz (8 cores)',
      'RAM': '16 GB DDR4-3200',
      'Storage': '512 GB NVMe SSD',
      'GPU': 'Intel UHD Graphics 630',
    },
    'Operating System': {
      'OS': 'Windows 10 Pro 22H2',
      'Build': '19045.3803',
      'Architecture': 'x86_64',
      'Uptime': '3d 14h 22m',
      'Last Boot': '2026-04-07 19:38:12',
    },
    'Network': {
      'Hostname': 'WKSFINANCE07',
      'Primary IP': '10.0.3.22',
      'MAC': 'A4:C3:F0:12:34:56',
      'DNS': '10.0.0.1, 8.8.8.8',
      'Gateway': '10.0.3.1',
    },
    'Storage': {
      'C:\\ Total': '512 GB',
      'C:\\ Used': '287 GB (56%)',
      'C:\\ Free': '225 GB',
      'Filesystem': 'NTFS',
    },
  };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel('SYSTEM INFORMATION'),
          const SizedBox(height: 12),
          ..._sections.entries.map(
            (section) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 3,
                      height: 14,
                      decoration: BoxDecoration(
                        color: AppTheme.secondary,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      section.key,
                      style: GoogleFonts.ibmPlexSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.borderLight),
                  ),
                  child: Column(
                    children: section.value.entries
                        .toList()
                        .asMap()
                        .entries
                        .map((entry) {
                      final i = entry.key;
                      final kv = entry.value;
                      final isLast = i == section.value.length - 1;
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          border: !isLast
                              ? const Border(
                                  bottom: BorderSide(
                                    color: AppTheme.borderLight,
                                  ),
                                )
                              : null,
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 110,
                              child: Text(
                                kv.key,
                                style: GoogleFonts.ibmPlexSans(
                                  fontSize: 12,
                                  color: AppTheme.textMuted,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                kv.value,
                                style: GoogleFonts.ibmPlexMono(
                                  fontSize: 12,
                                  color: AppTheme.textPrimary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
          _ActionRow(
            actions: [
              _ActionButton(
                icon: Icons.copy_rounded,
                label: 'Copy',
                onTap: () {},
              ),
              _ActionButton(
                icon: Icons.download_rounded,
                label: 'Export JSON',
                onTap: () {},
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Network Info Result ──────────────────────────────────────────────────────
class _NetworkInfoResultView extends StatefulWidget {
  final Map<String, dynamic> command;
  const _NetworkInfoResultView({required this.command});

  @override
  State<_NetworkInfoResultView> createState() => _NetworkInfoResultViewState();
}

class _NetworkInfoResultViewState extends State<_NetworkInfoResultView> {
  int _tab = 0;

  static final List<Map<String, String>> _interfaces = [
    {
      'name': 'Ethernet',
      'ip': '10.0.3.22',
      'mask': '255.255.255.0',
      'mac': 'A4:C3:F0:12:34:56',
      'status': 'up',
      'speed': '1 Gbps',
    },
    {
      'name': 'Wi-Fi',
      'ip': '—',
      'mask': '—',
      'mac': 'B2:D1:E3:45:67:89',
      'status': 'down',
      'speed': '—',
    },
    {
      'name': 'Loopback',
      'ip': '127.0.0.1',
      'mask': '255.0.0.0',
      'mac': '—',
      'status': 'up',
      'speed': '—',
    },
  ];

  static final List<Map<String, String>> _connections = [
    {
      'proto': 'TCP',
      'local': '10.0.3.22:443',
      'remote': '52.114.74.45:443',
      'state': 'ESTABLISHED',
      'proc': 'teams.exe',
    },
    {
      'proto': 'TCP',
      'local': '10.0.3.22:52341',
      'remote': '142.250.80.46:443',
      'state': 'ESTABLISHED',
      'proc': 'chrome.exe',
    },
    {
      'proto': 'TCP',
      'local': '10.0.3.22:49152',
      'remote': '10.0.0.1:443',
      'state': 'ESTABLISHED',
      'proc': 'quoodle-agent',
    },
    {
      'proto': 'UDP',
      'local': '0.0.0.0:5353',
      'remote': '*:*',
      'state': 'LISTEN',
      'proc': 'svchost.exe',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _SectionLabel('NETWORK INFO'),
              const Spacer(),
              _MetaChip(label: '${_interfaces.length} interfaces'),
            ],
          ),
          const SizedBox(height: 10),
          // Tab bar
          Row(
            children: [
              _TabButton(
                label: 'Interfaces',
                active: _tab == 0,
                onTap: () => setState(() => _tab = 0),
              ),
              const SizedBox(width: 8),
              _TabButton(
                label: 'Connections',
                active: _tab == 1,
                onTap: () => setState(() => _tab = 1),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_tab == 0) _buildInterfaces() else _buildConnections(),
          const SizedBox(height: 12),
          _ActionRow(
            actions: [
              _ActionButton(
                icon: Icons.copy_rounded,
                label: 'Copy',
                onTap: () {},
              ),
              _ActionButton(
                icon: Icons.download_rounded,
                label: 'Export',
                onTap: () {},
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInterfaces() {
    return Column(
      children: _interfaces.map((iface) {
        final isUp = iface['status'] == 'up';
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.borderLight),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    iface['name'] == 'Wi-Fi'
                        ? Icons.wifi_rounded
                        : iface['name'] == 'Loopback'
                            ? Icons.loop_rounded
                            : Icons.cable_rounded,
                    size: 16,
                    color: isUp ? AppTheme.secondary : AppTheme.textMuted,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    iface['name']!,
                    style: GoogleFonts.ibmPlexSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: isUp ? AppTheme.secondaryMuted : AppTheme.border,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      iface['status']!.toUpperCase(),
                      style: GoogleFonts.ibmPlexMono(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: isUp ? AppTheme.secondary : AppTheme.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
              if (isUp) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    _InfoPill(label: 'IP', value: iface['ip']!),
                    const SizedBox(width: 8),
                    _InfoPill(label: 'MASK', value: iface['mask']!),
                    if (iface['speed'] != '—') ...[
                      const SizedBox(width: 8),
                      _InfoPill(label: 'SPEED', value: iface['speed']!),
                    ],
                  ],
                ),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildConnections() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(9)),
            ),
            child: Row(
              children: [
                _TableHeader('PROTO', width: 44),
                _TableHeader('LOCAL', flex: 2),
                _TableHeader('REMOTE', flex: 2),
                _TableHeader('STATE', flex: 1),
              ],
            ),
          ),
          const Divider(height: 1, color: AppTheme.border),
          ..._connections.asMap().entries.map((entry) {
            final i = entry.key;
            final c = entry.value;
            final isLast = i == _connections.length - 1;
            final stateColor = c['state'] == 'ESTABLISHED'
                ? AppTheme.secondary
                : AppTheme.primary;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: i.isEven ? AppTheme.surfaceVariant : AppTheme.surface,
                borderRadius: isLast
                    ? const BorderRadius.vertical(bottom: Radius.circular(9))
                    : BorderRadius.zero,
                border: !isLast
                    ? const Border(
                        bottom: BorderSide(color: AppTheme.borderLight),
                      )
                    : null,
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 44,
                    child: Text(
                      c['proto']!,
                      style: GoogleFonts.ibmPlexMono(
                        fontSize: 10,
                        color: AppTheme.primary,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      c['local']!,
                      style: GoogleFonts.ibmPlexMono(
                        fontSize: 10,
                        color: AppTheme.textSecondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      c['remote']!,
                      style: GoogleFonts.ibmPlexMono(
                        fontSize: 10,
                        color: AppTheme.textSecondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Expanded(
                    flex: 1,
                    child: Text(
                      c['state']!,
                      style: GoogleFonts.ibmPlexMono(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: stateColor,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ── File Op Result ───────────────────────────────────────────────────────────
class _FileOpResultView extends StatelessWidget {
  final Map<String, dynamic> command;
  const _FileOpResultView({required this.command});

  @override
  Widget build(BuildContext context) {
    final isUpload = command['method'] == 'upload_file';
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel(isUpload ? 'FILE UPLOAD' : 'FILE CREATED'),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.secondary.withAlpha(80)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppTheme.secondaryMuted,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        isUpload
                            ? Icons.upload_file_rounded
                            : Icons.note_add_rounded,
                        size: 22,
                        color: AppTheme.secondary,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isUpload
                                ? 'report_q4_2025.pdf'
                                : 'config_override.json',
                            style: GoogleFonts.ibmPlexMono(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            isUpload
                                ? '/home/lnakamura/Documents/'
                                : '/etc/quoodle/',
                            style: GoogleFonts.ibmPlexMono(
                              fontSize: 10,
                              color: AppTheme.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.check_circle_rounded,
                      size: 20,
                      color: AppTheme.secondary,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Divider(color: AppTheme.borderLight, height: 1),
                const SizedBox(height: 14),
                Row(
                  children: [
                    _InfoPill(
                      label: 'SIZE',
                      value: isUpload ? '2.4 MB' : '1.2 KB',
                    ),
                    const SizedBox(width: 8),
                    _InfoPill(label: 'TYPE', value: isUpload ? 'PDF' : 'JSON'),
                    const SizedBox(width: 8),
                    _InfoPill(label: 'TIME', value: '0.8s'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _ActionRow(
            actions: [
              _ActionButton(
                icon: Icons.copy_rounded,
                label: 'Copy Path',
                onTap: () {},
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Telemetry Result ─────────────────────────────────────────────────────────
class _TelemetryResultView extends StatelessWidget {
  final Map<String, dynamic> command;
  const _TelemetryResultView({required this.command});

  static final List<Map<String, dynamic>> _metrics = [
    {
      'label': 'CPU Usage',
      'value': '34%',
      'sub': '8 cores · 2.90 GHz',
      'icon': Icons.memory_rounded,
      'color': AppTheme.primary,
      'pct': 0.34,
    },
    {
      'label': 'Memory',
      'value': '9.2 GB',
      'sub': '16 GB total · 57%',
      'icon': Icons.storage_rounded,
      'color': AppTheme.secondary,
      'pct': 0.57,
    },
    {
      'label': 'Disk I/O',
      'value': '12 MB/s',
      'sub': '512 GB · 56% used',
      'icon': Icons.disc_full_rounded,
      'color': AppTheme.warning,
      'pct': 0.56,
    },
    {
      'label': 'Network',
      'value': '2.4 MB/s',
      'sub': 'Down · 0.3 MB/s Up',
      'icon': Icons.wifi_rounded,
      'color': AppTheme.primary,
      'pct': 0.24,
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel('TELEMETRY SNAPSHOT'),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 2.2,
            children: _metrics.map((m) {
              final color = m['color'] as Color;
              final pct = m['pct'] as double;
              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.borderLight),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(m['icon'] as IconData, size: 14, color: color),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            m['label'] as String,
                            style: GoogleFonts.ibmPlexSans(
                              fontSize: 10,
                              color: AppTheme.textMuted,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      m['value'] as String,
                      style: GoogleFonts.ibmPlexMono(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: pct,
                        backgroundColor: AppTheme.border,
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                        minHeight: 3,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          _ActionRow(
            actions: [
              _ActionButton(
                icon: Icons.copy_rounded,
                label: 'Copy',
                onTap: () {},
              ),
              _ActionButton(
                icon: Icons.download_rounded,
                label: 'Export',
                onTap: () {},
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Action Result (lock/reboot/policy) ──────────────────────────────────────
class _ActionResultView extends StatelessWidget {
  final Map<String, dynamic> command;
  const _ActionResultView({required this.command});

  @override
  Widget build(BuildContext context) {
    final method = command['method'] as String? ?? '';
    final label = method == 'lock_screen'
        ? 'Screen Locked'
        : method == 'reboot'
            ? 'Reboot Initiated'
            : 'Policy Synced';
    final sub = method == 'lock_screen'
        ? 'Device screen has been locked successfully.'
        : method == 'reboot'
            ? 'Device will reboot in 30 seconds.'
            : 'Policy v1.0.4 applied successfully.';
    final icon = method == 'lock_screen'
        ? Icons.lock_rounded
        : method == 'reboot'
            ? Icons.restart_alt_rounded
            : Icons.sync_rounded;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.secondaryMuted,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.secondary.withAlpha(80)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppTheme.secondary.withAlpha(30),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 22, color: AppTheme.secondary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.ibmPlexSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.secondary,
                    ),
                  ),
                  Text(
                    sub,
                    style: GoogleFonts.ibmPlexSans(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Generic Result ───────────────────────────────────────────────────────────
class _GenericResultView extends StatelessWidget {
  final Map<String, dynamic> command;
  const _GenericResultView({required this.command});

  @override
  Widget build(BuildContext context) {
    final notes =
        command['resultNotes'] as String? ?? 'Command executed successfully.';
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel('OUTPUT'),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.borderLight),
            ),
            child: Text(
              notes,
              style: GoogleFonts.ibmPlexMono(
                fontSize: 12,
                color: AppTheme.secondary,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 12),
          _ActionRow(
            actions: [
              _ActionButton(
                icon: Icons.copy_rounded,
                label: 'Copy',
                onTap: () => Clipboard.setData(ClipboardData(text: notes)),
              ),
              _ActionButton(
                icon: Icons.share_rounded,
                label: 'Export',
                onTap: () {},
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Failure View ─────────────────────────────────────────────────────────────
class _FailureView extends StatelessWidget {
  final Map<String, dynamic> command;
  const _FailureView({required this.command});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.errorMuted,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.error.withAlpha(77)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Error Code: ${command['errorCode'] ?? 'AGENT_UNREACHABLE'}',
                  style: GoogleFonts.ibmPlexMono(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.error,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  command['errorMessage'] as String? ??
                      'The agent did not respond within the command TTL window. Device may be offline or network path is disrupted.',
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'RECOMMENDED ACTIONS',
            style: GoogleFonts.ibmPlexSans(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: AppTheme.textMuted,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),
          _RecommendedAction(
            icon: Icons.refresh_rounded,
            label: 'Retry command',
            description: 'Submit the same command again',
          ),
          _RecommendedAction(
            icon: Icons.devices_rounded,
            label: 'Check device status',
            description: 'Verify device is online in fleet view',
          ),
          _RecommendedAction(
            icon: Icons.bug_report_rounded,
            label: 'Investigate agent logs',
            description: 'Review agent-side error logs',
          ),
        ],
      ),
    );
  }
}

// ── Shared Helper Widgets ────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.ibmPlexSans(
        fontSize: 9,
        fontWeight: FontWeight.w600,
        color: AppTheme.textMuted,
        letterSpacing: 0.8,
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final String label;
  final Color? color;
  final bool monospace;
  const _MetaChip({required this.label, this.color, this.monospace = false});

  @override
  Widget build(BuildContext context) {
    final textColor = color ?? AppTheme.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: textColor.withAlpha(20),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: monospace
            ? GoogleFonts.ibmPlexMono(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: textColor,
              )
            : GoogleFonts.ibmPlexSans(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final List<Widget> actions;
  const _ActionRow({required this.actions});

  @override
  Widget build(BuildContext context) {
    return Row(children: actions);
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: AppTheme.textMuted),
            const SizedBox(width: 5),
            Text(
              label,
              style: GoogleFonts.ibmPlexSans(
                fontSize: 11,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SortChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _SortChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: active ? AppTheme.primaryDim : AppTheme.surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: active ? AppTheme.primary : AppTheme.border,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.ibmPlexMono(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: active ? AppTheme.primary : AppTheme.textMuted,
          ),
        ),
      ),
    );
  }
}

class _TableHeader extends StatelessWidget {
  final String label;
  final double? width;
  final int? flex;
  final bool right;
  const _TableHeader(this.label, {this.width, this.flex, this.right = false});

  @override
  Widget build(BuildContext context) {
    final text = Text(
      label,
      style: GoogleFonts.ibmPlexSans(
        fontSize: 9,
        fontWeight: FontWeight.w600,
        color: AppTheme.textMuted,
        letterSpacing: 0.5,
      ),
      textAlign: right ? TextAlign.right : TextAlign.left,
    );
    if (width != null) {
      return SizedBox(width: width, child: text);
    }
    return Expanded(flex: flex ?? 1, child: text);
  }
}

class _InfoPill extends StatelessWidget {
  final String label;
  final String value;
  const _InfoPill({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.borderLight),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: GoogleFonts.ibmPlexSans(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: AppTheme.textMuted,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            value,
            style: GoogleFonts.ibmPlexMono(
              fontSize: 11,
              color: AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _TabButton({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? AppTheme.primaryDim : AppTheme.surface,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: active ? AppTheme.primary : AppTheme.border,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.ibmPlexSans(
            fontSize: 12,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            color: active ? AppTheme.primary : AppTheme.textMuted,
          ),
        ),
      ),
    );
  }
}

class _RecommendedAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final String description;
  const _RecommendedAction({
    required this.icon,
    required this.label,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.border),
            ),
            child: Icon(icon, size: 15, color: AppTheme.textMuted),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textPrimary,
                  ),
                ),
                Text(
                  description,
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 11,
                    color: AppTheme.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
