import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_navigation.dart';
import '../../widgets/app_bar_widget.dart';

class AuditLogScreen extends StatefulWidget {
  const AuditLogScreen({super.key});

  @override
  State<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<AuditLogScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _searchQuery = '';
  String _selectedAction = 'All';
  String _selectedRole = 'All';
  String _selectedStatus = 'All';
  bool _showFilters = false;
  final int _currentNavIndex = 3;

  final List<String> _actionFilters = [
    'All',
    'Command',
    'Device',
    'Auth',
    'Policy',
    'Config',
  ];
  final List<String> _roleFilters = [
    'All',
    'Operator',
    'Admin',
    'Viewer',
    'System',
  ];
  final List<String> _statusFilters = [
    'All',
    'Success',
    'Failed',
    'Pending',
    'Denied',
  ];

  static final List<Map<String, dynamic>> _allLogs = [
    {
      'id': 'AUD-2891',
      'timestamp': '2026-04-06 10:41:33',
      'actor': 'operator@quoodle.io',
      'role': 'Operator',
      'action': 'Command',
      'event': 'execute_screenshot',
      'target': 'EDGE-NODE-021',
      'status': 'Success',
      'detail': 'Screenshot captured (1920×1080, 2.4 MB)',
      'ip': '10.0.1.45',
    },
    {
      'id': 'AUD-2890',
      'timestamp': '2026-04-06 10:38:17',
      'actor': 'admin@quoodle.io',
      'role': 'Admin',
      'action': 'Policy',
      'event': 'update_policy',
      'target': 'Fleet-Group-A',
      'status': 'Success',
      'detail': 'Compliance policy v2.4 applied to 14 devices',
      'ip': '10.0.1.12',
    },
    {
      'id': 'AUD-2889',
      'timestamp': '2026-04-06 10:35:02',
      'actor': 'operator@quoodle.io',
      'role': 'Operator',
      'action': 'Command',
      'event': 'collect_filesystem',
      'target': 'PROD-SRV-014',
      'status': 'Failed',
      'detail': 'Connection timeout after 30s — device unreachable',
      'ip': '10.0.1.45',
    },
    {
      'id': 'AUD-2888',
      'timestamp': '2026-04-06 10:29:44',
      'actor': 'system',
      'role': 'System',
      'action': 'Device',
      'event': 'device_offline',
      'target': 'PROD-SRV-014',
      'status': 'Failed',
      'detail': 'Heartbeat missed — device marked offline',
      'ip': '—',
    },
    {
      'id': 'AUD-2887',
      'timestamp': '2026-04-06 10:22:11',
      'actor': 'viewer@quoodle.io',
      'role': 'Viewer',
      'action': 'Auth',
      'event': 'login_attempt',
      'target': 'Auth Service',
      'status': 'Denied',
      'detail': 'Insufficient permissions — admin resource access blocked',
      'ip': '192.168.2.88',
    },
    {
      'id': 'AUD-2886',
      'timestamp': '2026-04-06 10:18:55',
      'actor': 'operator@quoodle.io',
      'role': 'Operator',
      'action': 'Command',
      'event': 'get_process_list',
      'target': 'WKS-FINANCE-07',
      'status': 'Success',
      'detail': '247 processes returned, 3 flagged as suspicious',
      'ip': '10.0.1.45',
    },
    {
      'id': 'AUD-2885',
      'timestamp': '2026-04-06 10:14:30',
      'actor': 'admin@quoodle.io',
      'role': 'Admin',
      'action': 'Config',
      'event': 'update_agent_config',
      'target': 'EDGE-NODE-019',
      'status': 'Success',
      'detail': 'Agent config updated: telemetry_interval=30s, log_level=INFO',
      'ip': '10.0.1.12',
    },
    {
      'id': 'AUD-2884',
      'timestamp': '2026-04-06 10:09:18',
      'actor': 'operator@quoodle.io',
      'role': 'Operator',
      'action': 'Command',
      'event': 'upload_file',
      'target': 'EDGE-NODE-021',
      'status': 'Success',
      'detail': 'patch_v2.1.bin (4.2 MB) uploaded to /tmp/patches/',
      'ip': '10.0.1.45',
    },
    {
      'id': 'AUD-2883',
      'timestamp': '2026-04-06 09:58:44',
      'actor': 'system',
      'role': 'System',
      'action': 'Device',
      'event': 'attestation_failure',
      'target': 'EDGE-NODE-021',
      'status': 'Failed',
      'detail': 'TPM attestation hash mismatch — quarantine enforced',
      'ip': '—',
    },
    {
      'id': 'AUD-2882',
      'timestamp': '2026-04-06 09:45:22',
      'actor': 'admin@quoodle.io',
      'role': 'Admin',
      'action': 'Auth',
      'event': 'user_login',
      'target': 'Auth Service',
      'status': 'Success',
      'detail': 'MFA verified — session established (TTL: 8h)',
      'ip': '10.0.1.12',
    },
    {
      'id': 'AUD-2881',
      'timestamp': '2026-04-06 09:33:07',
      'actor': 'operator@quoodle.io',
      'role': 'Operator',
      'action': 'Command',
      'event': 'get_network_info',
      'target': 'PROD-SRV-014',
      'status': 'Success',
      'detail': '6 interfaces, 142 active connections returned',
      'ip': '10.0.1.45',
    },
    {
      'id': 'AUD-2880',
      'timestamp': '2026-04-06 09:21:55',
      'actor': 'operator@quoodle.io',
      'role': 'Operator',
      'action': 'Command',
      'event': 'reboot_device',
      'target': 'WKS-FINANCE-07',
      'status': 'Pending',
      'detail': 'Reboot scheduled — awaiting device acknowledgment',
      'ip': '10.0.1.45',
    },
    {
      'id': 'AUD-2879',
      'timestamp': '2026-04-06 09:10:33',
      'actor': 'admin@quoodle.io',
      'role': 'Admin',
      'action': 'Policy',
      'event': 'create_policy',
      'target': 'Finance-Group',
      'status': 'Success',
      'detail': 'New isolation policy created for Finance device group',
      'ip': '10.0.1.12',
    },
    {
      'id': 'AUD-2878',
      'timestamp': '2026-04-06 08:55:19',
      'actor': 'viewer@quoodle.io',
      'role': 'Viewer',
      'action': 'Device',
      'event': 'view_device_detail',
      'target': 'EDGE-NODE-019',
      'status': 'Success',
      'detail': 'Device detail page accessed — read-only',
      'ip': '192.168.2.88',
    },
    {
      'id': 'AUD-2877',
      'timestamp': '2026-04-06 08:42:08',
      'actor': 'system',
      'role': 'System',
      'action': 'Device',
      'event': 'device_online',
      'target': 'EDGE-NODE-019',
      'status': 'Success',
      'detail': 'Device reconnected after 4m 22s offline',
      'ip': '—',
    },
  ];

  List<Map<String, dynamic>> get _filteredLogs {
    return _allLogs.where((log) {
      final matchSearch =
          _searchQuery.isEmpty ||
          log['event'].toString().toLowerCase().contains(
            _searchQuery.toLowerCase(),
          ) ||
          log['actor'].toString().toLowerCase().contains(
            _searchQuery.toLowerCase(),
          ) ||
          log['target'].toString().toLowerCase().contains(
            _searchQuery.toLowerCase(),
          ) ||
          log['id'].toString().toLowerCase().contains(
            _searchQuery.toLowerCase(),
          );
      final matchAction =
          _selectedAction == 'All' || log['action'] == _selectedAction;
      final matchRole = _selectedRole == 'All' || log['role'] == _selectedRole;
      final matchStatus =
          _selectedStatus == 'All' || log['status'] == _selectedStatus;
      return matchSearch && matchAction && matchRole && matchStatus;
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'Success':
        return AppTheme.secondary;
      case 'Failed':
        return AppTheme.error;
      case 'Pending':
        return AppTheme.warning;
      case 'Denied':
        return AppTheme.critical;
      default:
        return AppTheme.textMuted;
    }
  }

  Color _actionColor(String action) {
    switch (action) {
      case 'Command':
        return AppTheme.primary;
      case 'Device':
        return AppTheme.secondary;
      case 'Auth':
        return AppTheme.warning;
      case 'Policy':
        return const Color(0xFFAB7FF8);
      case 'Config':
        return const Color(0xFF38BDF8);
      default:
        return AppTheme.textMuted;
    }
  }

  IconData _actionIcon(String action) {
    switch (action) {
      case 'Command':
        return Icons.terminal_rounded;
      case 'Device':
        return Icons.devices_rounded;
      case 'Auth':
        return Icons.lock_rounded;
      case 'Policy':
        return Icons.policy_rounded;
      case 'Config':
        return Icons.settings_rounded;
      default:
        return Icons.circle_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.width >= 600;
    final logs = _filteredLogs;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text('Audit Log'),
        actions: [
          IconButton(
            icon: Icon(
              Icons.filter_list_rounded,
              color: _showFilters ? AppTheme.primary : AppTheme.textSecondary,
            ),
            onPressed: () => setState(() => _showFilters = !_showFilters),
            tooltip: 'Filters',
          ),
          IconButton(
            icon: const Icon(
              Icons.download_rounded,
              color: AppTheme.textSecondary,
            ),
            onPressed: () {},
            tooltip: 'Export',
          ),
        ],
      ),
      body: isTablet
          ? Row(
              children: [
                AppNavigation(
                  currentIndex: _currentNavIndex,
                  onTap: (i) {
                    final routes = [
                      '/dashboard-screen',
                      '/devices-screen',
                      '/command-timeline-screen',
                      '/alerts-screen',
                      '/settings-screen',
                    ];
                    Navigator.pushNamedAndRemoveUntil(
                      context,
                      routes[i],
                      (r) => false,
                    );
                  },
                ),
                Expanded(child: _buildBody(logs)),
              ],
            )
          : Column(
              children: [
                Expanded(child: _buildBody(logs)),
                AppNavigation(
                  currentIndex: _currentNavIndex,
                  onTap: (i) {
                    final routes = [
                      '/dashboard-screen',
                      '/devices-screen',
                      '/command-timeline-screen',
                      '/alerts-screen',
                      '/settings-screen',
                    ];
                    Navigator.pushNamedAndRemoveUntil(
                      context,
                      routes[i],
                      (r) => false,
                    );
                  },
                ),
              ],
            ),
    );
  }

  Widget _buildBody(List<Map<String, dynamic>> logs) {
    return Column(
      children: [
        _buildSearchBar(),
        if (_showFilters) _buildFilterPanel(),
        _buildStatsRow(logs),
        Expanded(
          child: logs.isEmpty
              ? _buildEmpty()
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                  itemCount: logs.length,
                  itemBuilder: (ctx, i) => _AuditLogEntry(
                    log: logs[i],
                    statusColor: _statusColor(logs[i]['status']),
                    actionColor: _actionColor(logs[i]['action']),
                    actionIcon: _actionIcon(logs[i]['action']),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.glassSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.border),
            ),
            child: TextField(
              onChanged: (v) => setState(() => _searchQuery = v),
              style: GoogleFonts.ibmPlexSans(
                fontSize: 13,
                color: AppTheme.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: 'Search events, actors, targets…',
                hintStyle: GoogleFonts.ibmPlexSans(
                  fontSize: 13,
                  color: AppTheme.textMuted,
                ),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: AppTheme.textMuted,
                  size: 18,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterPanel() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFilterRow(
            'Action',
            _actionFilters,
            _selectedAction,
            (v) => setState(() => _selectedAction = v),
          ),
          const SizedBox(height: 8),
          _buildFilterRow(
            'Role',
            _roleFilters,
            _selectedRole,
            (v) => setState(() => _selectedRole = v),
          ),
          const SizedBox(height: 8),
          _buildFilterRow(
            'Status',
            _statusFilters,
            _selectedStatus,
            (v) => setState(() => _selectedStatus = v),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterRow(
    String label,
    List<String> options,
    String selected,
    ValueChanged<String> onChanged,
  ) {
    return Row(
      children: [
        SizedBox(
          width: 52,
          child: Text(
            label,
            style: GoogleFonts.ibmPlexSans(
              fontSize: 11,
              color: AppTheme.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: options.map((opt) {
                final isSelected = opt == selected;
                return GestureDetector(
                  onTap: () => onChanged(opt),
                  child: Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppTheme.primaryDim
                          : AppTheme.glassLight,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected
                            ? AppTheme.primary.withAlpha(153)
                            : AppTheme.border,
                      ),
                    ),
                    child: Text(
                      opt,
                      style: GoogleFonts.ibmPlexSans(
                        fontSize: 11,
                        color: isSelected
                            ? AppTheme.primary
                            : AppTheme.textSecondary,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatsRow(List<Map<String, dynamic>> logs) {
    final success = logs.where((l) => l['status'] == 'Success').length;
    final failed = logs.where((l) => l['status'] == 'Failed').length;
    final denied = logs.where((l) => l['status'] == 'Denied').length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          _StatChip(
            label: '${logs.length} Events',
            color: AppTheme.textSecondary,
          ),
          const SizedBox(width: 8),
          _StatChip(label: '$success OK', color: AppTheme.secondary),
          const SizedBox(width: 8),
          _StatChip(label: '$failed Fail', color: AppTheme.error),
          const SizedBox(width: 8),
          _StatChip(label: '$denied Denied', color: AppTheme.critical),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history_rounded, size: 48, color: AppTheme.textMuted),
          const SizedBox(height: 12),
          Text(
            'No audit events match filters',
            style: GoogleFonts.ibmPlexSans(
              fontSize: 14,
              color: AppTheme.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final Color color;
  const _StatChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(26),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withAlpha(77)),
      ),
      child: Text(
        label,
        style: GoogleFonts.ibmPlexSans(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _AuditLogEntry extends StatefulWidget {
  final Map<String, dynamic> log;
  final Color statusColor;
  final Color actionColor;
  final IconData actionIcon;

  const _AuditLogEntry({
    required this.log,
    required this.statusColor,
    required this.actionColor,
    required this.actionIcon,
  });

  @override
  State<_AuditLogEntry> createState() => _AuditLogEntryState();
}

class _AuditLogEntryState extends State<_AuditLogEntry> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final log = widget.log;
    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: AppTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _expanded
                ? widget.actionColor.withAlpha(102)
                : AppTheme.border,
          ),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Action icon
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: widget.actionColor.withAlpha(26),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: widget.actionColor.withAlpha(77),
                      ),
                    ),
                    child: Icon(
                      widget.actionIcon,
                      size: 16,
                      color: widget.actionColor,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                log['event'],
                                style: GoogleFonts.ibmPlexMono(
                                  fontSize: 12,
                                  color: AppTheme.textPrimary,
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            _StatusPill(
                              status: log['status'],
                              color: widget.statusColor,
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.person_outline_rounded,
                              size: 11,
                              color: AppTheme.textMuted,
                            ),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(
                                '${log['actor']} · ${log['role']}',
                                style: GoogleFonts.ibmPlexSans(
                                  fontSize: 11,
                                  color: AppTheme.textSecondary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(
                              Icons.devices_outlined,
                              size: 11,
                              color: AppTheme.textMuted,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              log['target'],
                              style: GoogleFonts.ibmPlexSans(
                                fontSize: 11,
                                color: AppTheme.textMuted,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              log['timestamp'],
                              style: GoogleFonts.ibmPlexMono(
                                fontSize: 10,
                                color: AppTheme.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 16,
                    color: AppTheme.textMuted,
                  ),
                ],
              ),
            ),
            if (_expanded) ...[
              Container(height: 1, color: AppTheme.borderLight),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _DetailRow(label: 'Event ID', value: log['id'], mono: true),
                    const SizedBox(height: 6),
                    _DetailRow(label: 'Detail', value: log['detail']),
                    const SizedBox(height: 6),
                    _DetailRow(
                      label: 'Source IP',
                      value: log['ip'],
                      mono: true,
                    ),
                    const SizedBox(height: 6),
                    _DetailRow(
                      label: 'Timestamp',
                      value: log['timestamp'],
                      mono: true,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String status;
  final Color color;
  const _StatusPill({required this.status, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(26),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withAlpha(102)),
      ),
      child: Text(
        status,
        style: GoogleFonts.ibmPlexSans(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool mono;
  const _DetailRow({
    required this.label,
    required this.value,
    this.mono = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: GoogleFonts.ibmPlexSans(
              fontSize: 11,
              color: AppTheme.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: mono
                ? GoogleFonts.ibmPlexMono(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                  )
                : GoogleFonts.ibmPlexSans(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                  ),
          ),
        ),
      ],
    );
  }
}