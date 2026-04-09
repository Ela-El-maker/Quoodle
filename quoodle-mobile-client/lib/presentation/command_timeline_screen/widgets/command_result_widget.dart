import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/status_badge_widget.dart';

class CommandResultWidget extends StatelessWidget {
  final Map<String, dynamic> command;
  final CommandStatus status;

  const CommandResultWidget({
    super.key,
    required this.command,
    required this.status,
  });

  bool get _isSuccess => status == CommandStatus.completed;
  bool get _isFailed => status == CommandStatus.failed;

  Color get _statusColor => _isSuccess ? AppTheme.secondary : AppTheme.error;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
        border: Border(
          left: BorderSide(color: _statusColor, width: 3),
          top: const BorderSide(color: AppTheme.border, width: 1),
          right: const BorderSide(color: AppTheme.border, width: 1),
          bottom: const BorderSide(color: AppTheme.border, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Result header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Row(
              children: [
                Icon(
                  _isSuccess
                      ? Icons.check_circle_rounded
                      : Icons.cancel_rounded,
                  color: _statusColor,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Text(
                  _isSuccess ? 'Command Completed' : 'Command Failed',
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _statusColor,
                  ),
                ),
                const Spacer(),
                if (command.containsKey('executionTimeMs'))
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppTheme.border, width: 1),
                    ),
                    child: Text(
                      '${command['executionTimeMs']}ms',
                      style: GoogleFonts.ibmPlexMono(
                        fontSize: 10,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppTheme.borderLight),
          // Type-aware result content
          if (_isSuccess)
            _buildTypedResult(context)
          else if (_isFailed)
            _buildFailureContent(context),
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
      case 'system_info':
        return _SystemInfoResultView(command: command);
      case 'running_apps':
        return _RunningAppsResultView(command: command);
      case 'filesystem':
        return _FilesystemResultView(command: command);
      case 'network_info':
        return _NetworkInfoResultView(command: command);
      case 'upload_file':
      case 'create_file':
        return _FileOpResultView(command: command);
      case 'collect_telemetry':
        return _TelemetryResultView(command: command);
      default:
        return _GenericResultView(command: command);
    }
  }

  Widget _buildFailureContent(BuildContext context) {
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
              border: Border.all(color: AppTheme.error.withAlpha(77), width: 1),
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

// ── Generic text result ─────────────────────────────────────────────────────
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
          Text(
            'OUTPUT',
            style: GoogleFonts.ibmPlexSans(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: AppTheme.textMuted,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.borderLight, width: 1),
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
          Row(
            children: [
              _ResultAction(
                icon: Icons.copy_rounded,
                label: 'Copy',
                onTap: () => Clipboard.setData(ClipboardData(text: notes)),
              ),
              const SizedBox(width: 8),
              _ResultAction(
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

// ── Screenshot result ───────────────────────────────────────────────────────
class _ScreenshotResultView extends StatelessWidget {
  final Map<String, dynamic> command;
  const _ScreenshotResultView({required this.command});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'SCREENSHOT',
                style: GoogleFonts.ibmPlexSans(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textMuted,
                  letterSpacing: 0.8,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.warningMuted,
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: AppTheme.warning.withAlpha(102)),
                ),
                child: Text(
                  'SENSITIVE',
                  style: GoogleFonts.ibmPlexMono(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.warning,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Screenshot preview placeholder
          Container(
            width: double.infinity,
            height: 180,
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.border),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                children: [
                  Image.network(
                    'https://images.unsplash.com/photo-1551288049-bebda4e38f71?w=600&q=80',
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
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
                  // Overlay with file info
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      color: Colors.black54,
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
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _ResultAction(
                icon: Icons.download_rounded,
                label: 'Download',
                onTap: () {},
              ),
              const SizedBox(width: 8),
              _ResultAction(
                icon: Icons.zoom_in_rounded,
                label: 'Full Screen',
                onTap: () {},
              ),
              const SizedBox(width: 8),
              _ResultAction(
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

// ── Process list result ─────────────────────────────────────────────────────
class _ProcessListResultView extends StatelessWidget {
  final Map<String, dynamic> command;
  const _ProcessListResultView({required this.command});

  static final List<Map<String, dynamic>> _processes = [
    {'pid': 4, 'name': 'System', 'cpu': 0.1, 'mem': 0.2, 'status': 'running'},
    {
      'pid': 892,
      'name': 'svchost.exe',
      'cpu': 2.3,
      'mem': 1.4,
      'status': 'running',
    },
    {
      'pid': 1204,
      'name': 'chrome.exe',
      'cpu': 18.7,
      'mem': 12.3,
      'status': 'running',
    },
    {
      'pid': 2048,
      'name': 'explorer.exe',
      'cpu': 0.8,
      'mem': 3.1,
      'status': 'running',
    },
    {
      'pid': 3312,
      'name': 'antivirus.exe',
      'cpu': 4.2,
      'mem': 5.8,
      'status': 'running',
    },
    {
      'pid': 4096,
      'name': 'outlook.exe',
      'cpu': 1.1,
      'mem': 8.4,
      'status': 'running',
    },
    {
      'pid': 5120,
      'name': 'quoodle-agent',
      'cpu': 0.3,
      'mem': 0.9,
      'status': 'running',
    },
    {
      'pid': 6144,
      'name': 'teams.exe',
      'cpu': 6.5,
      'mem': 15.2,
      'status': 'running',
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
              Text(
                'PROCESS LIST',
                style: GoogleFonts.ibmPlexSans(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textMuted,
                  letterSpacing: 0.8,
                ),
              ),
              const Spacer(),
              Text(
                '${_processes.length} processes',
                style: GoogleFonts.ibmPlexMono(
                  fontSize: 10,
                  color: AppTheme.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Table header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: const BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
              border: Border(
                top: BorderSide(color: AppTheme.border),
                left: BorderSide(color: AppTheme.border),
                right: BorderSide(color: AppTheme.border),
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 50,
                  child: Text(
                    'PID',
                    style: GoogleFonts.ibmPlexMono(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    'NAME',
                    style: GoogleFonts.ibmPlexMono(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ),
                SizedBox(
                  width: 50,
                  child: Text(
                    'CPU%',
                    style: GoogleFonts.ibmPlexMono(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textMuted,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
                SizedBox(
                  width: 50,
                  child: Text(
                    'MEM%',
                    style: GoogleFonts.ibmPlexMono(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textMuted,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: AppTheme.border),
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(10),
              ),
            ),
            child: Column(
              children: _processes.asMap().entries.map((entry) {
                final p = entry.value;
                final cpu = p['cpu'] as double;
                final mem = p['mem'] as double;
                final cpuColor = cpu > 10
                    ? AppTheme.error
                    : cpu > 5
                    ? AppTheme.warning
                    : AppTheme.secondary;
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: entry.key.isEven
                        ? AppTheme.surfaceVariant
                        : AppTheme.surface,
                    borderRadius: entry.key == _processes.length - 1
                        ? const BorderRadius.vertical(
                            bottom: Radius.circular(9),
                          )
                        : BorderRadius.zero,
                    border: entry.key < _processes.length - 1
                        ? const Border(
                            bottom: BorderSide(color: AppTheme.borderLight),
                          )
                        : null,
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 50,
                        child: Text(
                          '${p['pid']}',
                          style: GoogleFonts.ibmPlexMono(
                            fontSize: 11,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          p['name'] as String,
                          style: GoogleFonts.ibmPlexMono(
                            fontSize: 11,
                            color: AppTheme.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      SizedBox(
                        width: 50,
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
                        width: 50,
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
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _ResultAction(
                icon: Icons.copy_rounded,
                label: 'Copy',
                onTap: () {},
              ),
              const SizedBox(width: 8),
              _ResultAction(
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

// ── System info result ──────────────────────────────────────────────────────
class _SystemInfoResultView extends StatelessWidget {
  final Map<String, dynamic> command;
  const _SystemInfoResultView({required this.command});

  @override
  Widget build(BuildContext context) {
    final sections = {
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
      },
      'Network': {
        'Hostname': 'WKSFINANCE07',
        'Primary IP': '10.0.3.22',
        'MAC': 'A4:C3:F0:12:34:56',
        'DNS': '10.0.0.1, 8.8.8.8',
      },
    };

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SYSTEM INFORMATION',
            style: GoogleFonts.ibmPlexSans(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: AppTheme.textMuted,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 10),
          ...sections.entries.map(
            (section) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryDim,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(10),
                    ),
                    border: Border.all(color: AppTheme.primary.withAlpha(77)),
                  ),
                  child: Row(
                    children: [
                      Text(
                        section.key.toUpperCase(),
                        style: GoogleFonts.ibmPlexSans(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primary,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(color: AppTheme.primary.withAlpha(77)),
                      right: BorderSide(color: AppTheme.primary.withAlpha(77)),
                      bottom: BorderSide(color: AppTheme.primary.withAlpha(77)),
                    ),
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(10),
                    ),
                  ),
                  child: Column(
                    children: section.value.entries
                        .map(
                          (e) => Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            decoration: const BoxDecoration(
                              border: Border(
                                bottom: BorderSide(color: AppTheme.borderLight),
                              ),
                            ),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 100,
                                  child: Text(
                                    e.key,
                                    style: GoogleFonts.ibmPlexSans(
                                      fontSize: 11,
                                      color: AppTheme.textMuted,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    e.value,
                                    style: GoogleFonts.ibmPlexMono(
                                      fontSize: 11,
                                      color: AppTheme.textPrimary,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
          Row(
            children: [
              _ResultAction(
                icon: Icons.copy_rounded,
                label: 'Copy',
                onTap: () {},
              ),
              const SizedBox(width: 8),
              _ResultAction(
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

// ── Running apps result ─────────────────────────────────────────────────────
class _RunningAppsResultView extends StatelessWidget {
  final Map<String, dynamic> command;
  const _RunningAppsResultView({required this.command});

  static final List<Map<String, dynamic>> _apps = [
    {
      'name': 'Google Chrome',
      'version': '120.0.6099',
      'icon': Icons.language_rounded,
      'color': AppTheme.primary,
    },
    {
      'name': 'Microsoft Outlook',
      'version': '16.0.17029',
      'icon': Icons.email_rounded,
      'color': AppTheme.secondary,
    },
    {
      'name': 'Microsoft Teams',
      'version': '1.6.00.31396',
      'icon': Icons.groups_rounded,
      'color': AppTheme.primary,
    },
    {
      'name': 'Windows Explorer',
      'version': '10.0.19041',
      'icon': Icons.folder_rounded,
      'color': AppTheme.warning,
    },
    {
      'name': 'Quoodle Agent',
      'version': '2.0.9',
      'icon': Icons.security_rounded,
      'color': AppTheme.secondary,
    },
    {
      'name': 'Antivirus Suite',
      'version': '22.3.1',
      'icon': Icons.shield_rounded,
      'color': AppTheme.secondary,
    },
    {
      'name': 'Notepad++',
      'version': '8.6.2',
      'icon': Icons.edit_note_rounded,
      'color': AppTheme.textSecondary,
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
              Text(
                'RUNNING APPLICATIONS',
                style: GoogleFonts.ibmPlexSans(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textMuted,
                  letterSpacing: 0.8,
                ),
              ),
              const Spacer(),
              Text(
                '${_apps.length} apps',
                style: GoogleFonts.ibmPlexMono(
                  fontSize: 10,
                  color: AppTheme.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ..._apps.map(
            (app) => Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.borderLight),
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: (app['color'] as Color).withAlpha(26),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      app['icon'] as IconData,
                      size: 16,
                      color: app['color'] as Color,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          app['name'] as String,
                          style: GoogleFonts.ibmPlexSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        Text(
                          'v${app['version']}',
                          style: GoogleFonts.ibmPlexMono(
                            fontSize: 10,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: AppTheme.secondary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _ResultAction(
                icon: Icons.copy_rounded,
                label: 'Copy',
                onTap: () {},
              ),
              const SizedBox(width: 8),
              _ResultAction(
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

// ── Filesystem result ───────────────────────────────────────────────────────
class _FilesystemResultView extends StatelessWidget {
  final Map<String, dynamic> command;
  const _FilesystemResultView({required this.command});

  static final List<Map<String, dynamic>> _entries = [
    {'name': 'Windows', 'type': 'dir', 'size': null, 'modified': '2026-01-10'},
    {'name': 'Users', 'type': 'dir', 'size': null, 'modified': '2026-04-01'},
    {
      'name': 'Program Files',
      'type': 'dir',
      'size': null,
      'modified': '2026-03-22',
    },
    {
      'name': 'Program Files (x86)',
      'type': 'dir',
      'size': null,
      'modified': '2026-02-14',
    },
    {
      'name': 'pagefile.sys',
      'type': 'file',
      'size': '2.0 GB',
      'modified': '2026-04-06',
    },
    {
      'name': 'hiberfil.sys',
      'type': 'file',
      'size': '8.0 GB',
      'modified': '2026-04-06',
    },
    {
      'name': 'bootmgr',
      'type': 'file',
      'size': '408 KB',
      'modified': '2025-11-12',
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
              Text(
                'FILESYSTEM',
                style: GoogleFonts.ibmPlexSans(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textMuted,
                  letterSpacing: 0.8,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.warningMuted,
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: AppTheme.warning.withAlpha(102)),
                ),
                child: Text(
                  'SENSITIVE',
                  style: GoogleFonts.ibmPlexMono(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.warning,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Path breadcrumb
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.borderLight),
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
                  'C:\\',
                  style: GoogleFonts.ibmPlexMono(
                    fontSize: 12,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: AppTheme.border),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: _entries.asMap().entries.map((entry) {
                final e = entry.value;
                final isDir = e['type'] == 'dir';
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: entry.key.isEven
                        ? AppTheme.surfaceVariant
                        : AppTheme.surface,
                    borderRadius: entry.key == 0
                        ? const BorderRadius.vertical(top: Radius.circular(9))
                        : entry.key == _entries.length - 1
                        ? const BorderRadius.vertical(
                            bottom: Radius.circular(9),
                          )
                        : BorderRadius.zero,
                    border: entry.key < _entries.length - 1
                        ? const Border(
                            bottom: BorderSide(color: AppTheme.borderLight),
                          )
                        : null,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isDir
                            ? Icons.folder_rounded
                            : Icons.insert_drive_file_rounded,
                        size: 16,
                        color: isDir ? AppTheme.warning : AppTheme.textMuted,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          e['name'] as String,
                          style: GoogleFonts.ibmPlexMono(
                            fontSize: 11,
                            color: AppTheme.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (e['size'] != null)
                        Text(
                          e['size'] as String,
                          style: GoogleFonts.ibmPlexMono(
                            fontSize: 10,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      const SizedBox(width: 10),
                      Text(
                        e['modified'] as String,
                        style: GoogleFonts.ibmPlexMono(
                          fontSize: 10,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _ResultAction(
                icon: Icons.copy_rounded,
                label: 'Copy Path',
                onTap: () {},
              ),
              const SizedBox(width: 8),
              _ResultAction(
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

// ── Network info result ─────────────────────────────────────────────────────
class _NetworkInfoResultView extends StatelessWidget {
  final Map<String, dynamic> command;
  const _NetworkInfoResultView({required this.command});

  @override
  Widget build(BuildContext context) {
    final interfaces = [
      {
        'name': 'Ethernet',
        'ip': '10.0.3.22',
        'mac': 'A4:C3:F0:12:34:56',
        'status': 'up',
        'speed': '1 Gbps',
      },
      {
        'name': 'Wi-Fi',
        'ip': '192.168.1.105',
        'mac': 'B8:27:EB:AB:CD:EF',
        'status': 'up',
        'speed': '300 Mbps',
      },
      {
        'name': 'Loopback',
        'ip': '127.0.0.1',
        'mac': '—',
        'status': 'up',
        'speed': '—',
      },
    ];
    final connections = [
      {
        'local': '10.0.3.22:443',
        'remote': '142.250.80.46:443',
        'state': 'ESTABLISHED',
        'proc': 'chrome.exe',
      },
      {
        'local': '10.0.3.22:52341',
        'remote': '10.0.0.1:53',
        'state': 'TIME_WAIT',
        'proc': 'svchost.exe',
      },
      {
        'local': '10.0.3.22:8443',
        'remote': '10.0.0.50:8443',
        'state': 'ESTABLISHED',
        'proc': 'quoodle-agent',
      },
    ];

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'NETWORK INTERFACES',
            style: GoogleFonts.ibmPlexSans(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: AppTheme.textMuted,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),
          ...interfaces.map(
            (iface) => Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.borderLight),
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryDim,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.lan_rounded,
                      size: 16,
                      color: AppTheme.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              iface['name']!,
                              style: GoogleFonts.ibmPlexSans(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              width: 5,
                              height: 5,
                              decoration: BoxDecoration(
                                color: iface['status'] == 'up'
                                    ? AppTheme.secondary
                                    : AppTheme.error,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          '${iface['ip']}  ·  ${iface['mac']}  ·  ${iface['speed']}',
                          style: GoogleFonts.ibmPlexMono(
                            fontSize: 10,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'ACTIVE CONNECTIONS',
            style: GoogleFonts.ibmPlexSans(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: AppTheme.textMuted,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: AppTheme.border),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: connections.asMap().entries.map((entry) {
                final c = entry.value;
                final stateColor = c['state'] == 'ESTABLISHED'
                    ? AppTheme.secondary
                    : AppTheme.warning;
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: entry.key.isEven
                        ? AppTheme.surfaceVariant
                        : AppTheme.surface,
                    borderRadius: entry.key == 0
                        ? const BorderRadius.vertical(top: Radius.circular(9))
                        : entry.key == connections.length - 1
                        ? const BorderRadius.vertical(
                            bottom: Radius.circular(9),
                          )
                        : BorderRadius.zero,
                    border: entry.key < connections.length - 1
                        ? const Border(
                            bottom: BorderSide(color: AppTheme.borderLight),
                          )
                        : null,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          c['local']!,
                          style: GoogleFonts.ibmPlexMono(
                            fontSize: 10,
                            color: AppTheme.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Icon(
                        Icons.arrow_forward_rounded,
                        size: 10,
                        color: AppTheme.textMuted,
                      ),
                      Expanded(
                        child: Text(
                          c['remote']!,
                          style: GoogleFonts.ibmPlexMono(
                            fontSize: 10,
                            color: AppTheme.textMuted,
                          ),
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: stateColor.withAlpha(26),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          c['state']!,
                          style: GoogleFonts.ibmPlexMono(
                            fontSize: 9,
                            color: stateColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _ResultAction(
                icon: Icons.copy_rounded,
                label: 'Copy',
                onTap: () {},
              ),
              const SizedBox(width: 8),
              _ResultAction(
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

// ── File operation result ───────────────────────────────────────────────────
class _FileOpResultView extends StatelessWidget {
  final Map<String, dynamic> command;
  const _FileOpResultView({required this.command});

  @override
  Widget build(BuildContext context) {
    final isUpload = (command['method'] as String?) == 'upload_file';
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isUpload ? 'FILE UPLOAD' : 'FILE CREATED',
            style: GoogleFonts.ibmPlexSans(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: AppTheme.textMuted,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.secondaryMuted,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.secondary.withAlpha(77)),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppTheme.secondaryMuted,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppTheme.secondary.withAlpha(102),
                    ),
                  ),
                  child: Icon(
                    isUpload ? Icons.upload_rounded : Icons.note_add_rounded,
                    size: 22,
                    color: AppTheme.secondary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isUpload ? 'report_q1_2026.pdf' : 'config_backup.json',
                        style: GoogleFonts.ibmPlexMono(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      Text(
                        isUpload
                            ? 'Uploaded to /uploads/2026/04/'
                            : 'Created at /etc/quoodle/',
                        style: GoogleFonts.ibmPlexSans(
                          fontSize: 11,
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
          ),
          const SizedBox(height: 12),
          _InfoRow(label: 'Size', value: isUpload ? '2.4 MB' : '1.2 KB'),
          _InfoRow(label: 'Checksum', value: 'sha256:7f3a9e…c114'),
          _InfoRow(label: 'Timestamp', value: '2026-04-06 10:41:31'),
          const SizedBox(height: 12),
          Row(
            children: [
              _ResultAction(
                icon: Icons.copy_rounded,
                label: 'Copy Path',
                onTap: () {},
              ),
              const SizedBox(width: 8),
              if (isUpload)
                _ResultAction(
                  icon: Icons.download_rounded,
                  label: 'Download',
                  onTap: () {},
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Telemetry result ────────────────────────────────────────────────────────
class _TelemetryResultView extends StatelessWidget {
  final Map<String, dynamic> command;
  const _TelemetryResultView({required this.command});

  @override
  Widget build(BuildContext context) {
    final metrics = {
      'CPU Usage': '61.4%',
      'RAM Usage': '74.2%',
      'Disk Usage': '58.8%',
      'Temperature': '52.3°C',
      'Network TX': '1.2 MB/s',
      'Network RX': '3.8 MB/s',
      'Open Ports': '14',
      'Active Processes': '87',
    };
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'TELEMETRY SNAPSHOT',
            style: GoogleFonts.ibmPlexSans(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: AppTheme.textMuted,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: metrics.entries
                .map(
                  (e) => Container(
                    width: (MediaQuery.of(context).size.width - 64) / 2,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.borderLight),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          e.key,
                          style: GoogleFonts.ibmPlexSans(
                            fontSize: 10,
                            color: AppTheme.textMuted,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          e.value,
                          style: GoogleFonts.ibmPlexMono(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _ResultAction(
                icon: Icons.copy_rounded,
                label: 'Copy',
                onTap: () {},
              ),
              const SizedBox(width: 8),
              _ResultAction(
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

// ── Shared helpers ──────────────────────────────────────────────────────────
class _InfoRow extends StatelessWidget {
  final String label, value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Text(
            label,
            style: GoogleFonts.ibmPlexSans(
              fontSize: 11,
              color: AppTheme.textMuted,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: GoogleFonts.ibmPlexMono(
              fontSize: 11,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ResultAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.border, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: AppTheme.textSecondary),
            const SizedBox(width: 6),
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

class _RecommendedAction extends StatelessWidget {
  final IconData icon;
  final String label, description;
  const _RecommendedAction({
    required this.icon,
    required this.label,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.borderLight, width: 1),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppTheme.primary),
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
                    fontSize: 10,
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
