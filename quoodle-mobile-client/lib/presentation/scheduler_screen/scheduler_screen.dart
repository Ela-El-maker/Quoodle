import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:secure_device_control/app/router/app_navigator.dart';
import 'package:secure_device_control/features/scheduler/data/services/scheduler_service.dart';
import 'package:secure_device_control/features/scheduler/presentation/providers/scheduler_providers.dart';

import '../../theme/app_theme.dart';
import '../../widgets/app_bar_widget.dart';
import '../../widgets/app_navigation.dart';
import '../../widgets/empty_state_widget.dart';

class SchedulerScreen extends ConsumerStatefulWidget {
  const SchedulerScreen({super.key});

  @override
  ConsumerState<SchedulerScreen> createState() => _SchedulerScreenState();
}

class _SchedulerScreenState extends ConsumerState<SchedulerScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _currentNavIndex = 2;

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

  void _onNavTap(int index) {
    if (index != _currentNavIndex) {
      setState(() => _currentNavIndex = index);
      AppNavigator.navigateToTab(
        context,
        index,
        profileTabTarget: ProfileTabTarget.settings,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheduler = ref.watch(schedulerServiceProvider);
    final schedulerInit = ref.watch(schedulerInitializationProvider);
    final jobs = scheduler.jobs;
    final activeJobs =
        jobs.where((j) => j.status == ScheduledJobStatus.active).toList();
    final pausedJobs =
        jobs.where((j) => j.status == ScheduledJobStatus.paused).toList();
    final historyJobs = jobs
        .where(
          (j) =>
              j.status == ScheduledJobStatus.completed ||
              j.status == ScheduledJobStatus.cancelled ||
              j.status == ScheduledJobStatus.failed,
        )
        .toList();

    return Scaffold(
      backgroundColor: AppTheme.background,
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          SizedBox(height: MediaQuery.of(context).padding.top + 56),
          _buildStatsRow(jobs),
          _buildTabBar(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildJobList(
                  activeJobs,
                  'active',
                  isInitializing: schedulerInit.isLoading,
                ),
                _buildJobList(
                  pausedJobs,
                  'paused',
                  isInitializing: schedulerInit.isLoading,
                ),
                _buildHistoryList(
                  historyJobs,
                  isInitializing: schedulerInit.isLoading,
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: _buildFab(),
      bottomNavigationBar: AppNavigation(
        currentIndex: _currentNavIndex,
        onTap: _onNavTap,
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return GlassAppBar(
      title: 'Scheduler',
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded, size: 20),
          onPressed: () => setState(() {}),
          tooltip: 'Refresh',
        ),
      ],
    );
  }

  Widget _buildStatsRow(List<ScheduledJob> jobs) {
    final active =
        jobs.where((j) => j.status == ScheduledJobStatus.active).length;
    final paused =
        jobs.where((j) => j.status == ScheduledJobStatus.paused).length;
    final totalRuns = jobs.fold(0, (s, j) => s + j.runCount);
    final successRuns = jobs.fold(0, (s, j) => s + j.successCount);
    final successRate =
        totalRuns > 0 ? (successRuns / totalRuns * 100).round() : 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            SizedBox(
              width: 92,
              child: _statChip(
                Icons.play_circle_rounded,
                '$active',
                'Active',
                AppTheme.secondary,
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 92,
              child: _statChip(
                Icons.pause_circle_rounded,
                '$paused',
                'Paused',
                AppTheme.warning,
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 92,
              child: _statChip(
                Icons.check_circle_rounded,
                '$successRate%',
                'Success',
                AppTheme.primary,
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 92,
              child: _statChip(
                Icons.history_rounded,
                '$totalRuns',
                'Runs',
                AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statChip(IconData icon, String value, String label, Color color) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12.0),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            color: AppTheme.glassSurface,
            borderRadius: BorderRadius.circular(12.0),
            border: Border.all(color: AppTheme.border, width: 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(height: 4),
              Text(
                value,
                style: GoogleFonts.ibmPlexMono(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              Text(
                label,
                style: GoogleFonts.ibmPlexSans(
                  fontSize: 9,
                  color: AppTheme.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12.0),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.glassSurface,
              borderRadius: BorderRadius.circular(12.0),
              border: Border.all(color: AppTheme.border, width: 1),
            ),
            child: TabBar(
              controller: _tabController,
              indicatorColor: AppTheme.primary,
              indicatorSize: TabBarIndicatorSize.tab,
              labelColor: AppTheme.primary,
              unselectedLabelColor: AppTheme.textMuted,
              dividerColor: Colors.transparent,
              labelStyle: GoogleFonts.ibmPlexSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              unselectedLabelStyle: GoogleFonts.ibmPlexSans(fontSize: 12),
              tabs: const [
                Tab(text: 'Active'),
                Tab(text: 'Paused'),
                Tab(text: 'History'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildJobList(
    List<ScheduledJob> jobs,
    String type, {
    required bool isInitializing,
  }) {
    if (isInitializing) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      );
    }
    if (jobs.isEmpty) {
      return EmptyStateWidget(
        icon: type == 'active'
            ? Icons.schedule_rounded
            : Icons.pause_circle_outline_rounded,
        title: type == 'active' ? 'No Active Jobs' : 'No Paused Jobs',
        subtitle: type == 'active'
            ? 'Tap + to schedule a new command'
            : 'Paused jobs will appear here',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      itemCount: jobs.length,
      itemBuilder: (ctx, i) => _JobCard(
        job: jobs[i],
        onPause: () => ref.read(schedulerServiceProvider).pauseJob(jobs[i].id),
        onResume: () =>
            ref.read(schedulerServiceProvider).resumeJob(jobs[i].id),
        onCancel: () => _confirmCancel(jobs[i]),
        onRunNow: () => ref.read(schedulerServiceProvider).runNow(jobs[i].id),
        onViewHistory: () => _showJobHistory(jobs[i]),
      ),
    );
  }

  Widget _buildHistoryList(
    List<ScheduledJob> jobs, {
    required bool isInitializing,
  }) {
    if (isInitializing) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      );
    }
    if (jobs.isEmpty) {
      return const EmptyStateWidget(
        icon: Icons.history_rounded,
        title: 'No Job History',
        subtitle: 'Completed and cancelled jobs appear here',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      itemCount: jobs.length,
      itemBuilder: (ctx, i) => _JobCard(
        job: jobs[i],
        isHistory: true,
        onViewHistory: () => _showJobHistory(jobs[i]),
      ),
    );
  }

  Widget _buildFab() {
    return FloatingActionButton.extended(
      onPressed: _showCreateJobSheet,
      icon: const Icon(Icons.add_rounded, size: 18),
      label: Text(
        'Schedule',
        style: GoogleFonts.ibmPlexSans(
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  void _confirmCancel(ScheduledJob job) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceVariant,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Cancel Job',
          style: GoogleFonts.ibmPlexSans(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
        content: Text(
          'Cancel "${job.name}"? This cannot be undone.',
          style: GoogleFonts.ibmPlexSans(
            fontSize: 14,
            color: AppTheme.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Keep',
              style: GoogleFonts.ibmPlexSans(color: AppTheme.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(schedulerServiceProvider).cancelJob(job.id);
            },
            child: Text(
              'Cancel Job',
              style: GoogleFonts.ibmPlexSans(color: AppTheme.error),
            ),
          ),
        ],
      ),
    );
  }

  void _showJobHistory(ScheduledJob job) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceVariant,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.3,
        expand: false,
        builder: (_, scrollCtrl) => Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      job.name,
                      style: GoogleFonts.ibmPlexSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                  _RunBadge(
                    success: job.successCount,
                    failure: job.failureCount,
                  ),
                ],
              ),
            ),
            const Divider(color: AppTheme.border, height: 1),
            Expanded(
              child: job.history.isEmpty
                  ? const EmptyStateWidget(
                      icon: Icons.history_rounded,
                      title: 'No Runs Yet',
                      subtitle: 'Run history will appear here',
                    )
                  : ListView.builder(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.all(16),
                      itemCount: job.history.length,
                      itemBuilder: (_, i) =>
                          _RunHistoryTile(run: job.history[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCreateJobSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceVariant,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      isScrollControlled: true,
      builder: (ctx) => _CreateJobSheet(
        onCreated: (job) {
          ref.read(schedulerServiceProvider).addJob(job);
          Navigator.pop(ctx);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Job "${job.name}" scheduled',
                style: GoogleFonts.ibmPlexSans(color: AppTheme.textPrimary),
              ),
              backgroundColor: AppTheme.surfaceElevated,
            ),
          );
        },
      ),
    );
  }
}

// ── Job Card ─────────────────────────────────────────────────────────────────

class _JobCard extends StatelessWidget {
  final ScheduledJob job;
  final bool isHistory;
  final VoidCallback? onPause;
  final VoidCallback? onResume;
  final VoidCallback? onCancel;
  final VoidCallback? onRunNow;
  final VoidCallback? onViewHistory;

  const _JobCard({
    required this.job,
    this.isHistory = false,
    this.onPause,
    this.onResume,
    this.onCancel,
    this.onRunNow,
    this.onViewHistory,
  });

  Color get _statusColor {
    switch (job.status) {
      case ScheduledJobStatus.active:
        return AppTheme.secondary;
      case ScheduledJobStatus.paused:
        return AppTheme.warning;
      case ScheduledJobStatus.completed:
        return AppTheme.primary;
      case ScheduledJobStatus.cancelled:
        return AppTheme.textMuted;
      case ScheduledJobStatus.failed:
        return AppTheme.error;
    }
  }

  String get _statusLabel {
    switch (job.status) {
      case ScheduledJobStatus.active:
        return 'ACTIVE';
      case ScheduledJobStatus.paused:
        return 'PAUSED';
      case ScheduledJobStatus.completed:
        return 'DONE';
      case ScheduledJobStatus.cancelled:
        return 'CANCELLED';
      case ScheduledJobStatus.failed:
        return 'FAILED';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(color: _statusColor.withAlpha(60), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: _statusColor.withAlpha(30),
                    borderRadius: BorderRadius.circular(6.0),
                    border: Border.all(
                      color: _statusColor.withAlpha(80),
                      width: 1,
                    ),
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
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    job.name,
                    style: GoogleFonts.ibmPlexSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (onViewHistory != null)
                  GestureDetector(
                    onTap: onViewHistory,
                    child: const Icon(
                      Icons.history_rounded,
                      size: 18,
                      color: AppTheme.textMuted,
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: Text(
              job.description,
              style: GoogleFonts.ibmPlexSans(
                fontSize: 12,
                color: AppTheme.textSecondary,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                _MetaChip(
                  icon: Icons.terminal_rounded,
                  label: job.commandMethod.replaceAll('_', ' '),
                ),
                _MetaChip(
                  icon: Icons.devices_rounded,
                  label: job.targetDeviceName,
                ),
                _MetaChip(
                  icon: Icons.repeat_rounded,
                  label: job.recurrence.displayLabel,
                ),
              ],
            ),
          ),
          if (job.nextRunAt != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: Row(
                children: [
                  const Icon(
                    Icons.schedule_rounded,
                    size: 12,
                    color: AppTheme.textMuted,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Next: ${_formatDateTime(job.nextRunAt!)}',
                    style: GoogleFonts.ibmPlexMono(
                      fontSize: 11,
                      color: AppTheme.textMuted,
                    ),
                  ),
                  const Spacer(),
                  _RunBadge(
                    success: job.successCount,
                    failure: job.failureCount,
                  ),
                ],
              ),
            ),
          if (!isHistory)
            Container(
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: AppTheme.borderLight, width: 1),
                ),
              ),
              child: Row(
                children: [
                  if (job.status == ScheduledJobStatus.active) ...[
                    _ActionBtn(
                      icon: Icons.pause_rounded,
                      label: 'Pause',
                      color: AppTheme.warning,
                      onTap: onPause,
                    ),
                    _ActionBtn(
                      icon: Icons.play_arrow_rounded,
                      label: 'Run Now',
                      color: AppTheme.primary,
                      onTap: onRunNow,
                    ),
                    _ActionBtn(
                      icon: Icons.cancel_rounded,
                      label: 'Cancel',
                      color: AppTheme.error,
                      onTap: onCancel,
                    ),
                  ] else if (job.status == ScheduledJobStatus.paused) ...[
                    _ActionBtn(
                      icon: Icons.play_arrow_rounded,
                      label: 'Resume',
                      color: AppTheme.secondary,
                      onTap: onResume,
                    ),
                    _ActionBtn(
                      icon: Icons.cancel_rounded,
                      label: 'Cancel',
                      color: AppTheme.error,
                      onTap: onCancel,
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    final now = DateTime.now();
    final diff = dt.difference(now);
    if (diff.inMinutes < 60) return 'in ${diff.inMinutes}m';
    if (diff.inHours < 24) return 'in ${diff.inHours}h';
    return 'in ${diff.inDays}d';
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MetaChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.glassLight,
        borderRadius: BorderRadius.circular(6.0),
        border: Border.all(color: AppTheme.border, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: AppTheme.textMuted),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.ibmPlexSans(
              fontSize: 10,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8.0),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(height: 2),
              Text(
                label,
                style: GoogleFonts.ibmPlexSans(
                  fontSize: 10,
                  color: color,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RunBadge extends StatelessWidget {
  final int success;
  final int failure;
  const _RunBadge({required this.success, required this.failure});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.check_circle_rounded, size: 12, color: AppTheme.secondary),
        const SizedBox(width: 2),
        Text(
          '$success',
          style: GoogleFonts.ibmPlexMono(
            fontSize: 10,
            color: AppTheme.secondary,
          ),
        ),
        const SizedBox(width: 6),
        Icon(Icons.cancel_rounded, size: 12, color: AppTheme.error),
        const SizedBox(width: 2),
        Text(
          '$failure',
          style: GoogleFonts.ibmPlexMono(fontSize: 10, color: AppTheme.error),
        ),
      ],
    );
  }
}

class _RunHistoryTile extends StatelessWidget {
  final ScheduledJobRun run;
  const _RunHistoryTile({required this.run});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(
          color: run.success
              ? AppTheme.secondary.withAlpha(60)
              : AppTheme.error.withAlpha(60),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            run.success ? Icons.check_circle_rounded : Icons.error_rounded,
            size: 16,
            color: run.success ? AppTheme.secondary : AppTheme.error,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _formatTime(run.startedAt),
                  style: GoogleFonts.ibmPlexMono(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                  ),
                ),
                if (run.output != null)
                  Text(
                    run.output!,
                    style: GoogleFonts.ibmPlexSans(
                      fontSize: 11,
                      color: AppTheme.secondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (run.error != null)
                  Text(
                    run.error!,
                    style: GoogleFonts.ibmPlexSans(
                      fontSize: 11,
                      color: AppTheme.error,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (run.completedAt != null)
            Text(
              '${run.completedAt!.difference(run.startedAt).inSeconds}s',
              style: GoogleFonts.ibmPlexMono(
                fontSize: 10,
                color: AppTheme.textMuted,
              ),
            ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final d = '${dt.day}/${dt.month}';
    return '$d $h:$m';
  }
}

// ── Create Job Sheet ──────────────────────────────────────────────────────────

class _CreateJobSheet extends StatefulWidget {
  final void Function(ScheduledJob) onCreated;
  const _CreateJobSheet({required this.onCreated});

  @override
  State<_CreateJobSheet> createState() => _CreateJobSheetState();
}

class _CreateJobSheetState extends State<_CreateJobSheet> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String _selectedMethod = 'collect_telemetry';
  String _selectedDevice = 'PROD-SRV-001';
  String _selectedDeviceId = 'dev-001';
  RecurrenceType _recurrenceType = RecurrenceType.daily;
  int _interval = 1;
  TimeOfDay _scheduledTime = TimeOfDay.now();
  final List<int> _selectedDays = [1, 3, 5];

  static const List<String> _methods = [
    'collect_telemetry',
    'process_list',
    'system_info',
    'running_apps',
    'filesystem',
    'network_info',
    'screenshot_capture',
    'policy_sync',
    'upload_file',
    'create_file',
  ];

  static const List<Map<String, String>> _devices = [
    {'id': 'dev-001', 'name': 'PROD-SRV-001'},
    {'id': 'dev-007', 'name': 'WKS-FINANCE-07'},
    {'id': 'dev-014', 'name': 'PROD-SRV-014'},
    {'id': 'dev-019', 'name': 'EDGE-NODE-019'},
    {'id': 'dev-021', 'name': 'EDGE-NODE-021'},
  ];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  String get _cronPreview {
    switch (_recurrenceType) {
      case RecurrenceType.once:
        return 'Runs once at ${_scheduledTime.format(context)}';
      case RecurrenceType.minutely:
        return '*/$_interval * * * *';
      case RecurrenceType.hourly:
        return '0 */$_interval * * *';
      case RecurrenceType.daily:
        return '0 ${_scheduledTime.hour} */$_interval * *';
      case RecurrenceType.weekly:
        final days = _selectedDays.map((d) => d.toString()).join(',');
        return '0 ${_scheduledTime.hour} * * $days';
      case RecurrenceType.monthly:
        return '0 ${_scheduledTime.hour} 1 */$_interval *';
      case RecurrenceType.custom:
        return '* * * * *';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: DraggableScrollableSheet(
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        expand: false,
        builder: (_, scrollCtrl) => Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  Text(
                    'New Scheduled Job',
                    style: GoogleFonts.ibmPlexSans(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(
                      Icons.close_rounded,
                      color: AppTheme.textMuted,
                    ),
                    onPressed: () => Navigator.maybePop(context),
                  ),
                ],
              ),
            ),
            const Divider(color: AppTheme.border, height: 1),
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.all(16),
                children: [
                  _sectionLabel('Job Details'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _nameCtrl,
                    style: GoogleFonts.ibmPlexSans(
                      color: AppTheme.textPrimary,
                      fontSize: 14,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Job Name',
                      hintText: 'e.g. Daily Telemetry Sweep',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _descCtrl,
                    style: GoogleFonts.ibmPlexSans(
                      color: AppTheme.textPrimary,
                      fontSize: 14,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Description (optional)',
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 16),
                  _sectionLabel('Command Template'),
                  const SizedBox(height: 8),
                  _DropdownField<String>(
                    label: 'Command Method',
                    value: _selectedMethod,
                    items: _methods
                        .map(
                          (m) => DropdownMenuItem(
                            value: m,
                            child: Text(
                              m.replaceAll('_', ' '),
                              style: GoogleFonts.ibmPlexSans(
                                fontSize: 13,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _selectedMethod = v ?? _selectedMethod),
                  ),
                  const SizedBox(height: 10),
                  _DropdownField<String>(
                    label: 'Target Device',
                    value: _selectedDevice,
                    items: _devices
                        .map(
                          (d) => DropdownMenuItem(
                            value: d['name'],
                            child: Text(
                              d['name']!,
                              style: GoogleFonts.ibmPlexSans(
                                fontSize: 13,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() {
                        _selectedDevice = v;
                        _selectedDeviceId = _devices.firstWhere(
                          (d) => d['name'] == v,
                        )['id']!;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  _sectionLabel('Recurrence'),
                  const SizedBox(height: 8),
                  _RecurrenceSelector(
                    selected: _recurrenceType,
                    onChanged: (t) => setState(() => _recurrenceType = t),
                  ),
                  const SizedBox(height: 10),
                  if (_recurrenceType != RecurrenceType.once &&
                      _recurrenceType != RecurrenceType.custom) ...[
                    Row(
                      children: [
                        Text(
                          'Every',
                          style: GoogleFonts.ibmPlexSans(
                            fontSize: 13,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        _IntervalStepper(
                          value: _interval,
                          onChanged: (v) => setState(() => _interval = v),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _recurrenceType.name,
                          style: GoogleFonts.ibmPlexSans(
                            fontSize: 13,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (_recurrenceType == RecurrenceType.weekly) ...[
                    _DaySelector(
                      selected: _selectedDays,
                      onChanged: (days) => setState(
                        () => _selectedDays
                          ..clear()
                          ..addAll(days),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (_recurrenceType != RecurrenceType.minutely)
                    InkWell(
                      onTap: () async {
                        final t = await showTimePicker(
                          context: context,
                          initialTime: _scheduledTime,
                        );
                        if (t != null) setState(() => _scheduledTime = t);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.glassLight,
                          borderRadius: BorderRadius.circular(12.0),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.access_time_rounded,
                              size: 16,
                              color: AppTheme.textMuted,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Scheduled at ${_scheduledTime.format(context)}',
                              style: GoogleFonts.ibmPlexSans(
                                fontSize: 13,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            const Spacer(),
                            const Icon(
                              Icons.chevron_right_rounded,
                              size: 16,
                              color: AppTheme.textMuted,
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  _sectionLabel('Cron Preview'),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.background,
                      borderRadius: BorderRadius.circular(10.0),
                      border: Border.all(color: AppTheme.primary.withAlpha(60)),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.code_rounded,
                          size: 14,
                          color: AppTheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _cronPreview,
                            style: GoogleFonts.ibmPlexMono(
                              fontSize: 12,
                              color: AppTheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12.0),
                        ),
                      ),
                      child: Text(
                        'Schedule Job',
                        style: GoogleFonts.ibmPlexSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
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

  Widget _sectionLabel(String label) => Text(
        label,
        style: GoogleFonts.ibmPlexSans(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppTheme.textMuted,
          letterSpacing: 0.8,
        ),
      );

  void _submit() {
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please enter a job name',
            style: GoogleFonts.ibmPlexSans(color: AppTheme.textPrimary),
          ),
          backgroundColor: AppTheme.surfaceElevated,
        ),
      );
      return;
    }
    final now = DateTime.now();
    final scheduled = DateTime(
      now.year,
      now.month,
      now.day,
      _scheduledTime.hour,
      _scheduledTime.minute,
    );
    final rule = RecurrenceRule(
      type: _recurrenceType,
      interval: _interval,
      daysOfWeek: _recurrenceType == RecurrenceType.weekly
          ? List.from(_selectedDays)
          : null,
    );
    final job = ScheduledJob(
      id: 'job_${DateTime.now().millisecondsSinceEpoch}',
      name: _nameCtrl.text.trim(),
      description: _descCtrl.text.trim(),
      commandMethod: _selectedMethod,
      commandParams: {},
      targetDeviceId: _selectedDeviceId,
      targetDeviceName: _selectedDevice,
      scheduledAt: scheduled,
      recurrence: rule,
      createdAt: now,
      createdBy: 'operator',
    );
    widget.onCreated(job);
  }
}

class _DropdownField<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final void Function(T?) onChanged;
  const _DropdownField({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      items: items,
      onChanged: onChanged,
      dropdownColor: AppTheme.surfaceVariant,
      decoration: InputDecoration(labelText: label),
      style: GoogleFonts.ibmPlexSans(fontSize: 13, color: AppTheme.textPrimary),
    );
  }
}

class _RecurrenceSelector extends StatelessWidget {
  final RecurrenceType selected;
  final void Function(RecurrenceType) onChanged;
  const _RecurrenceSelector({required this.selected, required this.onChanged});

  static const _types = [
    (RecurrenceType.once, 'Once'),
    (RecurrenceType.minutely, 'Minutely'),
    (RecurrenceType.hourly, 'Hourly'),
    (RecurrenceType.daily, 'Daily'),
    (RecurrenceType.weekly, 'Weekly'),
    (RecurrenceType.monthly, 'Monthly'),
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: _types.map((t) {
        final isSelected = t.$1 == selected;
        return GestureDetector(
          onTap: () => onChanged(t.$1),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isSelected ? AppTheme.primaryDim : AppTheme.glassLight,
              borderRadius: BorderRadius.circular(20.0),
              border: Border.all(
                color: isSelected
                    ? AppTheme.primary.withAlpha(100)
                    : AppTheme.border,
              ),
            ),
            child: Text(
              t.$2,
              style: GoogleFonts.ibmPlexSans(
                fontSize: 12,
                color: isSelected ? AppTheme.primary : AppTheme.textSecondary,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _IntervalStepper extends StatelessWidget {
  final int value;
  final void Function(int) onChanged;
  const _IntervalStepper({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StepBtn(
          icon: Icons.remove_rounded,
          onTap: value > 1 ? () => onChanged(value - 1) : null,
        ),
        Container(
          width: 36,
          alignment: Alignment.center,
          child: Text(
            '$value',
            style: GoogleFonts.ibmPlexMono(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
        ),
        _StepBtn(
          icon: Icons.add_rounded,
          onTap: value < 99 ? () => onChanged(value + 1) : null,
        ),
      ],
    );
  }
}

class _StepBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _StepBtn({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: AppTheme.glassLight,
          borderRadius: BorderRadius.circular(8.0),
          border: Border.all(color: AppTheme.border),
        ),
        child: Icon(
          icon,
          size: 14,
          color: onTap != null ? AppTheme.textPrimary : AppTheme.textDisabled,
        ),
      ),
    );
  }
}

class _DaySelector extends StatelessWidget {
  final List<int> selected;
  final void Function(List<int>) onChanged;
  const _DaySelector({required this.selected, required this.onChanged});

  static const _days = [
    (1, 'M'),
    (2, 'T'),
    (3, 'W'),
    (4, 'T'),
    (5, 'F'),
    (6, 'S'),
    (7, 'S'),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: _days.map((d) {
        final isSelected = selected.contains(d.$1);
        return GestureDetector(
          onTap: () {
            final updated = List<int>.from(selected);
            isSelected ? updated.remove(d.$1) : updated.add(d.$1);
            onChanged(updated);
          },
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isSelected ? AppTheme.primaryDim : AppTheme.glassLight,
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected
                    ? AppTheme.primary.withAlpha(100)
                    : AppTheme.border,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              d.$2,
              style: GoogleFonts.ibmPlexSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isSelected ? AppTheme.primary : AppTheme.textSecondary,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
