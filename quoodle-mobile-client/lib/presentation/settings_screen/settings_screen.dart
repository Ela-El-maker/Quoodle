import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:secure_device_control/app/router/app_navigator.dart';
import 'package:secure_device_control/features/commands/data/services/offline_command_queue.dart';
import 'package:secure_device_control/features/commands/presentation/providers/offline_command_queue_providers.dart';
import 'package:secure_device_control/features/settings/domain/entities/session_entry.dart';
import 'package:secure_device_control/features/settings/presentation/providers/settings_controller.dart';
import 'package:secure_device_control/features/settings/presentation/providers/settings_state.dart';
import '../../theme/app_theme.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  OfflineCommandQueue get _queue => ref.read(offlineCommandQueueProvider);
  SettingsState get _settingsState => ref.watch(settingsControllerProvider);

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

  @override
  Widget build(BuildContext context) {
    ref.watch(offlineCommandQueueInitializationProvider);
    ref.watch(offlineCommandQueueProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Column(
        children: [
          _buildHeader(),
          _buildTabBar(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildAccountTab(),
                _buildNotificationsTab(),
                _buildCommandQueueTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(bottom: BorderSide(color: AppTheme.border, width: 1)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.maybePop(context),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(8.0),
                    border: Border.all(color: AppTheme.border, width: 1),
                  ),
                  child: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    size: 16,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Settings',
                      style: GoogleFonts.ibmPlexSans(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    Text(
                      'Account, notifications & command queue',
                      style: GoogleFonts.ibmPlexSans(
                        fontSize: 11,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              if (_queue.pendingCount > 0 || _queue.failedCount > 0)
                _QueueStatusPill(queue: _queue),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: AppTheme.surface,
      child: TabBar(
        controller: _tabController,
        indicatorColor: AppTheme.primary,
        indicatorWeight: 2,
        labelColor: AppTheme.primary,
        unselectedLabelColor: AppTheme.textMuted,
        labelStyle: GoogleFonts.ibmPlexSans(
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: GoogleFonts.ibmPlexSans(
          fontSize: 12,
          fontWeight: FontWeight.w400,
        ),
        tabs: [
          const Tab(text: 'Account'),
          const Tab(text: 'Notifications'),
          Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Queue'),
                if (_queue.pendingCount > 0 || _queue.failedCount > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: _queue.failedCount > 0
                          ? AppTheme.errorMuted
                          : AppTheme.primaryDim,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${_queue.pendingCount + _queue.failedCount}',
                      style: GoogleFonts.ibmPlexMono(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: _queue.failedCount > 0
                            ? AppTheme.error
                            : AppTheme.primary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Account Tab ─────────────────────────────────────────────────────────────

  Widget _buildAccountTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildProfileCard(),
        const SizedBox(height: 16),
        _buildRoleCard(),
        const SizedBox(height: 16),
        _buildSessionsCard(),
        const SizedBox(height: 16),
        _buildDangerZone(),
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _buildProfileCard() {
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel(label: 'ACCOUNT INFO'),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppTheme.primary, Color(0xFF0099CC)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: Text(
                    'OP',
                    style: GoogleFonts.ibmPlexSans(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Operator Admin',
                      style: GoogleFonts.ibmPlexSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'operator@quoodle.io',
                      style: GoogleFonts.ibmPlexMono(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.secondaryMuted,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'ACTIVE',
                        style: GoogleFonts.ibmPlexMono(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.secondary,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: AppTheme.borderLight, height: 1),
          const SizedBox(height: 16),
          _InfoRow(label: 'User ID', value: 'usr_8f3a2c91d4e7'),
          const SizedBox(height: 10),
          _InfoRow(label: 'Organization', value: 'Quoodle Fleet Ops'),
          const SizedBox(height: 10),
          _InfoRow(label: 'Member Since', value: 'Jan 15, 2024'),
          const SizedBox(height: 10),
          _InfoRow(label: 'Last Login', value: '2 minutes ago'),
        ],
      ),
    );
  }

  Widget _buildRoleCard() {
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel(label: 'ROLE & PERMISSIONS'),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.warningMuted,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.shield_rounded,
                  color: AppTheme.warning,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Fleet Operator',
                      style: GoogleFonts.ibmPlexSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    Text(
                      'Level 2 — Elevated Access',
                      style: GoogleFonts.ibmPlexSans(
                        fontSize: 12,
                        color: AppTheme.warning,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _PermChip(label: 'View Devices', granted: true),
              _PermChip(label: 'Send Commands', granted: true),
              _PermChip(label: 'View Telemetry', granted: true),
              _PermChip(label: 'Manage Alerts', granted: true),
              _PermChip(label: 'Enroll Devices', granted: true),
              _PermChip(label: 'Admin Panel', granted: false),
              _PermChip(label: 'Delete Devices', granted: false),
              _PermChip(label: 'Sensitive Commands', granted: false),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSessionsCard() {
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _SectionLabel(label: 'ACTIVE SESSIONS'),
              const Spacer(),
              GestureDetector(
                onTap: _revokeAllOtherSessions,
                child: Text(
                  'Revoke All Others',
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.error,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ..._settingsState.sessions.map(
            (s) => _SessionTile(
              session: s,
              onRevoke: s.isCurrent ? null : () => _revokeSession(s.id),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDangerZone() {
    return _GlassCard(
      borderColor: AppTheme.errorMuted,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel(label: 'SESSION', color: AppTheme.error),
          const SizedBox(height: 16),
          _ActionButton(
            icon: Icons.logout_rounded,
            label: 'Sign Out',
            subtitle: 'End your current session',
            color: AppTheme.error,
            onTap: _confirmLogout,
          ),
        ],
      ),
    );
  }

  // ── Notifications Tab ────────────────────────────────────────────────────────

  Widget _buildNotificationsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionLabel(label: 'CRITICAL ALERTS'),
              const SizedBox(height: 12),
              _NotifToggle(
                icon: Icons.crisis_alert_rounded,
                iconColor: AppTheme.error,
                label: 'Critical Alerts',
                subtitle: 'Device quarantine, policy breach, intrusion',
                value: _settingsState.notifCriticalAlerts,
                onChanged: (v) => ref
                    .read(settingsControllerProvider.notifier)
                    .setNotifCriticalAlerts(v),
              ),
              _NotifToggle(
                icon: Icons.wifi_off_rounded,
                iconColor: AppTheme.warning,
                label: 'Device Offline',
                subtitle: 'Notify when a managed device goes offline',
                value: _settingsState.notifDeviceOffline,
                onChanged: (v) => ref
                    .read(settingsControllerProvider.notifier)
                    .setNotifDeviceOffline(v),
              ),
              _NotifToggle(
                icon: Icons.error_outline_rounded,
                iconColor: AppTheme.error,
                label: 'Command Failed',
                subtitle: 'Alert when a dispatched command fails',
                value: _settingsState.notifCommandFailed,
                onChanged: (v) => ref
                    .read(settingsControllerProvider.notifier)
                    .setNotifCommandFailed(v),
              ),
              _NotifToggle(
                icon: Icons.policy_rounded,
                iconColor: AppTheme.critical,
                label: 'Policy Violation',
                subtitle: 'Immediate alert on policy non-compliance',
                value: _settingsState.notifPolicyViolation,
                onChanged: (v) => ref
                    .read(settingsControllerProvider.notifier)
                    .setNotifPolicyViolation(v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionLabel(label: 'OPERATIONAL'),
              const SizedBox(height: 12),
              _NotifToggle(
                icon: Icons.add_circle_outline_rounded,
                iconColor: AppTheme.secondary,
                label: 'New Device Enrolled',
                subtitle: 'When a new device joins the fleet',
                value: _settingsState.notifNewDevice,
                onChanged: (v) => ref
                    .read(settingsControllerProvider.notifier)
                    .setNotifNewDevice(v),
              ),
              _NotifToggle(
                icon: Icons.analytics_outlined,
                iconColor: AppTheme.primary,
                label: 'Telemetry Anomaly',
                subtitle: 'Unusual CPU, memory, or network patterns',
                value: _settingsState.notifTelemetryAnomaly,
                onChanged: (v) => ref
                    .read(settingsControllerProvider.notifier)
                    .setNotifTelemetryAnomaly(v),
              ),
              _NotifToggle(
                icon: Icons.history_rounded,
                iconColor: AppTheme.textSecondary,
                label: 'Audit Events',
                subtitle: 'Log access and sensitive command execution',
                value: _settingsState.notifAuditEvents,
                onChanged: (v) => ref
                    .read(settingsControllerProvider.notifier)
                    .setNotifAuditEvents(v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionLabel(label: 'REPORTS'),
              const SizedBox(height: 12),
              _NotifToggle(
                icon: Icons.summarize_rounded,
                iconColor: AppTheme.secondary,
                label: 'Weekly Fleet Report',
                subtitle: 'Summary of fleet health and activity',
                value: _settingsState.notifWeeklyReport,
                onChanged: (v) => ref
                    .read(settingsControllerProvider.notifier)
                    .setNotifWeeklyReport(v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 80),
      ],
    );
  }

  // ── Command Queue Tab ────────────────────────────────────────────────────────

  Widget _buildCommandQueueTab() {
    final commands = _queue.commands;
    return Column(
      children: [
        _buildQueueHeader(),
        Expanded(
          child: commands.isEmpty
              ? _buildEmptyQueue()
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                  itemCount: commands.length,
                  itemBuilder: (ctx, i) => _CommandQueueTile(
                    command: commands[i],
                    onRetry: () => _queue.retryCommand(commands[i].id),
                    onRemove: () => _queue.removeCommand(commands[i].id),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildQueueHeader() {
    final pending = _queue.pendingCount;
    final failed = _queue.failedCount;
    final success = _queue.commands
        .where((c) => c.status == QueuedCommandStatus.success)
        .length;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _ConnectivityDot(isOnline: _queue.isOnline),
              const SizedBox(width: 8),
              Text(
                _queue.isOnline
                    ? (_queue.isSyncing
                        ? 'Syncing...'
                        : 'Online — Auto-sync active')
                    : 'Offline — Commands queued locally',
                style: GoogleFonts.ibmPlexSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color:
                      _queue.isOnline ? AppTheme.secondary : AppTheme.warning,
                ),
              ),
              const Spacer(),
              if (_queue.commands.any(
                (c) => c.status == QueuedCommandStatus.success,
              ))
                GestureDetector(
                  onTap: _queue.clearCompleted,
                  child: Text(
                    'Clear Done',
                    style: GoogleFonts.ibmPlexSans(
                      fontSize: 11,
                      color: AppTheme.textMuted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _QueueStat(
                label: 'Pending',
                value: pending,
                color: AppTheme.primary,
              ),
              const SizedBox(width: 12),
              _QueueStat(label: 'Failed', value: failed, color: AppTheme.error),
              const SizedBox(width: 12),
              _QueueStat(
                label: 'Sent',
                value: success,
                color: AppTheme.secondary,
              ),
              const SizedBox(width: 12),
              _QueueStat(
                label: 'Total',
                value: _queue.commands.length,
                color: AppTheme.textSecondary,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyQueue() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppTheme.primaryDim,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.check_circle_outline_rounded,
              color: AppTheme.primary,
              size: 28,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Queue is empty',
            style: GoogleFonts.ibmPlexSans(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Commands sent while offline will appear here',
            style: GoogleFonts.ibmPlexSans(
              fontSize: 12,
              color: AppTheme.textMuted,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ── Actions ──────────────────────────────────────────────────────────────────

  void _revokeSession(String sessionId) {
    ref.read(settingsControllerProvider.notifier).revokeSession(sessionId);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Session revoked',
          style: GoogleFonts.ibmPlexSans(fontSize: 13),
        ),
        backgroundColor: AppTheme.surfaceElevated,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _revokeAllOtherSessions() {
    ref.read(settingsControllerProvider.notifier).revokeAllOtherSessions();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'All other sessions revoked',
          style: GoogleFonts.ibmPlexSans(fontSize: 13),
        ),
        backgroundColor: AppTheme.surfaceElevated,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _confirmLogout() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceVariant,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Sign Out',
          style: GoogleFonts.ibmPlexSans(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        content: Text(
          'Are you sure you want to end your current session? Any unsynced queued commands will be preserved.',
          style: GoogleFonts.ibmPlexSans(
            fontSize: 14,
            color: AppTheme.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: GoogleFonts.ibmPlexSans(color: AppTheme.textMuted),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              AppNavigator.replaceStackWith(context, AppRoute.authentication);
            },
            child: Text(
              'Sign Out',
              style: GoogleFonts.ibmPlexSans(
                color: AppTheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sub-widgets ──────────────────────────────────────────────────────────────

class _GlassCard extends StatelessWidget {
  final Widget child;
  final Color? borderColor;
  const _GlassCard({required this.child, this.borderColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor ?? AppTheme.border),
      ),
      child: child,
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  final Color? color;
  const _SectionLabel({required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: GoogleFonts.ibmPlexMono(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        color: color ?? AppTheme.textMuted,
        letterSpacing: 1.2,
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: GoogleFonts.ibmPlexSans(
              fontSize: 12,
              color: AppTheme.textMuted,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: GoogleFonts.ibmPlexMono(
              fontSize: 12,
              color: AppTheme.textSecondary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _PermChip extends StatelessWidget {
  final String label;
  final bool granted;
  const _PermChip({required this.label, required this.granted});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: granted ? AppTheme.secondaryMuted : AppTheme.glassLight,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: granted ? AppTheme.secondary.withAlpha(80) : AppTheme.border,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            granted ? Icons.check_rounded : Icons.close_rounded,
            size: 11,
            color: granted ? AppTheme.secondary : AppTheme.textMuted,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.ibmPlexSans(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: granted ? AppTheme.secondary : AppTheme.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  final SessionEntry session;
  final VoidCallback? onRevoke;
  const _SessionTile({required this.session, this.onRevoke});

  String _formatTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: session.isCurrent ? AppTheme.primaryDim : AppTheme.glassLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: session.isCurrent
              ? AppTheme.primary.withAlpha(80)
              : AppTheme.borderLight,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color:
                  session.isCurrent ? AppTheme.primaryDim : AppTheme.glassLight,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              session.device.contains('iPhone') ||
                      session.device.contains('Android')
                  ? Icons.smartphone_rounded
                  : Icons.computer_rounded,
              size: 18,
              color: session.isCurrent ? AppTheme.primary : AppTheme.textMuted,
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
                        session.device,
                        style: GoogleFonts.ibmPlexSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (session.isCurrent)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryDim,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'CURRENT',
                          style: GoogleFonts.ibmPlexMono(
                            fontSize: 8,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.primary,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${session.location} · ${session.ip}',
                  style: GoogleFonts.ibmPlexMono(
                    fontSize: 10,
                    color: AppTheme.textMuted,
                  ),
                ),
                Text(
                  'Last active ${_formatTime(session.lastActive)}',
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 11,
                    color: AppTheme.textMuted,
                  ),
                ),
              ],
            ),
          ),
          if (onRevoke != null) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onRevoke,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.errorMuted,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Revoke',
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.error,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withAlpha(20),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withAlpha(60)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.ibmPlexSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: GoogleFonts.ibmPlexSans(
                      fontSize: 11,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: color, size: 18),
          ],
        ),
      ),
    );
  }
}

class _NotifToggle extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _NotifToggle({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: iconColor.withAlpha(30),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 16, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                Text(
                  subtitle,
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 11,
                    color: AppTheme.textMuted,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppTheme.primary,
            activeTrackColor: AppTheme.primaryDim,
            inactiveThumbColor: AppTheme.textMuted,
            inactiveTrackColor: AppTheme.glassLight,
          ),
        ],
      ),
    );
  }
}

// ── Queue Widgets ────────────────────────────────────────────────────────────

class _QueueStatusPill extends StatelessWidget {
  final OfflineCommandQueue queue;
  const _QueueStatusPill({required this.queue});

  @override
  Widget build(BuildContext context) {
    final hasFailed = queue.failedCount > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: hasFailed ? AppTheme.errorMuted : AppTheme.primaryDim,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: hasFailed
              ? AppTheme.error.withAlpha(80)
              : AppTheme.primary.withAlpha(80),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasFailed
                ? Icons.error_outline_rounded
                : Icons.cloud_upload_outlined,
            size: 12,
            color: hasFailed ? AppTheme.error : AppTheme.primary,
          ),
          const SizedBox(width: 4),
          Text(
            hasFailed
                ? '${queue.failedCount} failed'
                : '${queue.pendingCount} queued',
            style: GoogleFonts.ibmPlexMono(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: hasFailed ? AppTheme.error : AppTheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectivityDot extends StatefulWidget {
  final bool isOnline;
  const _ConnectivityDot({required this.isOnline});

  @override
  State<_ConnectivityDot> createState() => _ConnectivityDotState();
}

class _ConnectivityDotState extends State<_ConnectivityDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulse = Tween<double>(
      begin: 0.4,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isOnline ? AppTheme.secondary : AppTheme.warning;
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, __) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: color.withAlpha((255 * _pulse.value).toInt()),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: color.withAlpha(80),
              blurRadius: 4,
              spreadRadius: 1,
            ),
          ],
        ),
      ),
    );
  }
}

class _QueueStat extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  const _QueueStat({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            '$value',
            style: GoogleFonts.ibmPlexMono(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          Text(
            label,
            style: GoogleFonts.ibmPlexSans(
              fontSize: 10,
              color: AppTheme.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _CommandQueueTile extends StatelessWidget {
  final QueuedCommand command;
  final VoidCallback onRetry;
  final VoidCallback onRemove;
  const _CommandQueueTile({
    required this.command,
    required this.onRetry,
    required this.onRemove,
  });

  Color get _statusColor {
    switch (command.status) {
      case QueuedCommandStatus.pending:
        return AppTheme.primary;
      case QueuedCommandStatus.syncing:
        return AppTheme.warning;
      case QueuedCommandStatus.success:
        return AppTheme.secondary;
      case QueuedCommandStatus.failed:
        return AppTheme.error;
      case QueuedCommandStatus.retrying:
        return AppTheme.warning;
    }
  }

  IconData get _statusIcon {
    switch (command.status) {
      case QueuedCommandStatus.pending:
        return Icons.schedule_rounded;
      case QueuedCommandStatus.syncing:
        return Icons.sync_rounded;
      case QueuedCommandStatus.success:
        return Icons.check_circle_rounded;
      case QueuedCommandStatus.failed:
        return Icons.error_rounded;
      case QueuedCommandStatus.retrying:
        return Icons.refresh_rounded;
    }
  }

  String get _statusLabel {
    switch (command.status) {
      case QueuedCommandStatus.pending:
        return 'QUEUED';
      case QueuedCommandStatus.syncing:
        return 'SYNCING';
      case QueuedCommandStatus.success:
        return 'SENT';
      case QueuedCommandStatus.failed:
        return 'FAILED';
      case QueuedCommandStatus.retrying:
        return 'RETRYING';
    }
  }

  String _formatTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }

  @override
  Widget build(BuildContext context) {
    final isSyncing = command.status == QueuedCommandStatus.syncing;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _statusColor.withAlpha(60)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: _statusColor.withAlpha(30),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: isSyncing
                    ? Padding(
                        padding: const EdgeInsets.all(7),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: _statusColor,
                        ),
                      )
                    : Icon(_statusIcon, size: 16, color: _statusColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      command.method
                          .replaceAll('_', ' ')
                          .split(' ')
                          .map(
                            (w) => w.isEmpty
                                ? ''
                                : '${w[0].toUpperCase()}${w.substring(1)}',
                          )
                          .join(' '),
                      style: GoogleFonts.ibmPlexSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    Text(
                      command.deviceName,
                      style: GoogleFonts.ibmPlexMono(
                        fontSize: 10,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: _statusColor.withAlpha(25),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _statusLabel,
                  style: GoogleFonts.ibmPlexMono(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: _statusColor,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                Icons.access_time_rounded,
                size: 11,
                color: AppTheme.textMuted,
              ),
              const SizedBox(width: 4),
              Text(
                'Queued ${_formatTime(command.queuedAt)}',
                style: GoogleFonts.ibmPlexSans(
                  fontSize: 11,
                  color: AppTheme.textMuted,
                ),
              ),
              if (command.retryCount > 0) ...[
                const SizedBox(width: 10),
                Icon(Icons.refresh_rounded, size: 11, color: AppTheme.warning),
                const SizedBox(width: 4),
                Text(
                  '${command.retryCount} retries',
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 11,
                    color: AppTheme.warning,
                  ),
                ),
              ],
            ],
          ),
          if (command.errorMessage != null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: AppTheme.errorMuted,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                command.errorMessage!,
                style: GoogleFonts.ibmPlexMono(
                  fontSize: 10,
                  color: AppTheme.error,
                ),
              ),
            ),
          ],
          if (command.status == QueuedCommandStatus.failed ||
              command.status == QueuedCommandStatus.pending) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                if (command.status == QueuedCommandStatus.failed &&
                    command.retryCount < 3)
                  Expanded(
                    child: GestureDetector(
                      onTap: onRetry,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryDim,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AppTheme.primary.withAlpha(60),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.refresh_rounded,
                              size: 13,
                              color: AppTheme.primary,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              'Retry',
                              style: GoogleFonts.ibmPlexSans(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (command.status == QueuedCommandStatus.failed &&
                    command.retryCount < 3)
                  const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    onTap: onRemove,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: AppTheme.errorMuted,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.error.withAlpha(60)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.delete_outline_rounded,
                            size: 13,
                            color: AppTheme.error,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'Remove',
                            style: GoogleFonts.ibmPlexSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.error,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
