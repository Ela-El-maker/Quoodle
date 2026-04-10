import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:secure_device_control/app/router/app_navigator.dart';
import 'package:secure_device_control/features/audit/domain/entities/audit_log_item.dart';
import 'package:secure_device_control/features/audit/presentation/providers/audit_log_providers.dart';
import 'package:secure_device_control/features/audit/presentation/providers/audit_log_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_navigation.dart';

class AuditLogScreen extends ConsumerWidget {
  const AuditLogScreen({super.key});

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
  Widget build(BuildContext context, WidgetRef ref) {
    final isTablet = MediaQuery.of(context).size.width >= 600;
    final auditState = ref.watch(auditLogControllerProvider);
    final logs = auditState.filteredLogs;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Audit Log'),
        actions: [
          IconButton(
            icon: Icon(
              Icons.filter_list_rounded,
              color: auditState.showFilters
                  ? AppTheme.primary
                  : AppTheme.textSecondary,
            ),
            onPressed: () =>
                ref.read(auditLogControllerProvider.notifier).toggleFilters(),
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
                  currentIndex: 3,
                  onTap: (i) => AppNavigator.navigateToTab(
                    context,
                    i,
                    profileTabTarget: ProfileTabTarget.settings,
                  ),
                ),
                Expanded(
                  child: _buildBody(
                    logs: logs,
                    state: auditState,
                    onSearchChanged: (v) => ref
                        .read(auditLogControllerProvider.notifier)
                        .setSearchQuery(v),
                    onActionChanged: (v) => ref
                        .read(auditLogControllerProvider.notifier)
                        .setActionFilter(v),
                    onRoleChanged: (v) => ref
                        .read(auditLogControllerProvider.notifier)
                        .setRoleFilter(v),
                    onStatusChanged: (v) => ref
                        .read(auditLogControllerProvider.notifier)
                        .setStatusFilter(v),
                  ),
                ),
              ],
            )
          : Column(
              children: [
                Expanded(
                  child: _buildBody(
                    logs: logs,
                    state: auditState,
                    onSearchChanged: (v) => ref
                        .read(auditLogControllerProvider.notifier)
                        .setSearchQuery(v),
                    onActionChanged: (v) => ref
                        .read(auditLogControllerProvider.notifier)
                        .setActionFilter(v),
                    onRoleChanged: (v) => ref
                        .read(auditLogControllerProvider.notifier)
                        .setRoleFilter(v),
                    onStatusChanged: (v) => ref
                        .read(auditLogControllerProvider.notifier)
                        .setStatusFilter(v),
                  ),
                ),
                AppNavigation(
                  currentIndex: 3,
                  onTap: (i) => AppNavigator.navigateToTab(
                    context,
                    i,
                    profileTabTarget: ProfileTabTarget.settings,
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildBody({
    required List<AuditLogItem> logs,
    required AuditLogState state,
    required ValueChanged<String> onSearchChanged,
    required ValueChanged<String> onActionChanged,
    required ValueChanged<String> onRoleChanged,
    required ValueChanged<String> onStatusChanged,
  }) {
    return Column(
      children: [
        _buildSearchBar(onSearchChanged),
        if (state.showFilters)
          _buildFilterPanel(
            state: state,
            onActionChanged: onActionChanged,
            onRoleChanged: onRoleChanged,
            onStatusChanged: onStatusChanged,
          ),
        _buildStatsRow(logs),
        Expanded(
          child: logs.isEmpty
              ? _buildEmpty()
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                  itemCount: logs.length,
                  itemBuilder: (ctx, i) => _AuditLogEntry(
                    log: _toMap(logs[i]),
                    statusColor: _statusColor(logs[i].status),
                    actionColor: _actionColor(logs[i].action),
                    actionIcon: _actionIcon(logs[i].action),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildSearchBar(ValueChanged<String> onSearchChanged) {
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
              onChanged: onSearchChanged,
              style: GoogleFonts.ibmPlexSans(
                fontSize: 13,
                color: AppTheme.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: 'Search events, actors, targets...',
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

  Widget _buildFilterPanel({
    required AuditLogState state,
    required ValueChanged<String> onActionChanged,
    required ValueChanged<String> onRoleChanged,
    required ValueChanged<String> onStatusChanged,
  }) {
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
            AuditLogState.actionFilters,
            state.selectedAction,
            onActionChanged,
          ),
          const SizedBox(height: 8),
          _buildFilterRow(
            'Role',
            AuditLogState.roleFilters,
            state.selectedRole,
            onRoleChanged,
          ),
          const SizedBox(height: 8),
          _buildFilterRow(
            'Status',
            AuditLogState.statusFilters,
            state.selectedStatus,
            onStatusChanged,
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
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.w400,
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

  Widget _buildStatsRow(List<AuditLogItem> logs) {
    final success = logs.where((l) => l.status == 'Success').length;
    final failed = logs.where((l) => l.status == 'Failed').length;
    final denied = logs.where((l) => l.status == 'Denied').length;

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
          const Icon(Icons.history_rounded,
              size: 48, color: AppTheme.textMuted),
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

  Map<String, dynamic> _toMap(AuditLogItem log) {
    return <String, dynamic>{
      'id': log.id,
      'timestamp': log.timestamp,
      'actor': log.actor,
      'role': log.role,
      'action': log.action,
      'event': log.event,
      'target': log.target,
      'status': log.status,
      'detail': log.detail,
      'ip': log.ip,
    };
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
            color:
                _expanded ? widget.actionColor.withAlpha(102) : AppTheme.border,
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
