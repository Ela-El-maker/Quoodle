import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:secure_device_control/features/commands/domain/entities/command_execution_status.dart';
import 'package:secure_device_control/features/commands/presentation/providers/command_timeline_providers.dart';

import '../../theme/app_theme.dart';
import '../../widgets/status_badge_widget.dart';
import './widgets/command_audit_widget.dart';
import './widgets/command_result_widget.dart';
import './widgets/command_timeline_widget.dart';
import 'package:secure_device_control/app/router/app_navigator.dart';
import '../../widgets/app_navigation.dart';

class CommandTimelineScreen extends ConsumerStatefulWidget {
  const CommandTimelineScreen({super.key});

  @override
  ConsumerState<CommandTimelineScreen> createState() =>
      _CommandTimelineScreenState();
}

class _CommandTimelineScreenState extends ConsumerState<CommandTimelineScreen> {
  bool _initialized = false;

  int _currentNavIndex = 2; // Commands tab

  AppRoute _fallbackRouteForCommand(Map<String, dynamic> command) {
    final deviceId = command['deviceId']?.toString() ?? '';
    return deviceId.isNotEmpty ? AppRoute.deviceDetail : AppRoute.devices;
  }

  Object? _fallbackArgsForCommand(Map<String, dynamic> command) {
    final deviceId = command['deviceId']?.toString() ?? '';
    if (deviceId.isEmpty) {
      return null;
    }
    final deviceName = command['deviceName']?.toString() ?? '';
    return <String, dynamic>{
      'deviceId': deviceId,
      if (deviceName.isNotEmpty) 'deviceName': deviceName,
    };
  }

  void _handleBack(Map<String, dynamic> command) {
    AppNavigator.popOrGo(
      context,
      _fallbackRouteForCommand(command),
      arguments: _fallbackArgsForCommand(command),
    );
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) {
      return;
    }

    _initialized = true;
    final args = ModalRoute.of(context)?.settings.arguments;
    Future<void>.microtask(
      () =>
          ref.read(commandTimelineControllerProvider.notifier).initialize(args),
    );
  }

  @override
  Widget build(BuildContext context) {
    final timelineState = ref.watch(commandTimelineControllerProvider);
    final command = timelineState.command;
    final currentStatus = _toLegacyStatus(timelineState.status);
    final isTerminal = timelineState.isTerminal;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          return;
        }
        _handleBack(command);
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        extendBody: true,
        appBar: _buildAppBar(context, command, currentStatus),
        body: CustomScrollView(
          slivers: [
            if (timelineState.loadedFromCache)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                sliver: SliverToBoxAdapter(child: _buildCachedBanner()),
              ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                16,
                timelineState.loadedFromCache ? 8 : 16,
                16,
                0,
              ),
              sliver: SliverToBoxAdapter(
                child: _buildCommandHeaderCard(context, command),
              ),
            ),
            if (!isTerminal)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                sliver: SliverToBoxAdapter(
                  child:
                      _buildPollingIndicator(timelineState.secondsSinceUpdate),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              sliver: SliverToBoxAdapter(
                child: CommandTimelineWidget(
                  currentStatus: currentStatus,
                  command: command,
                ),
              ),
            ),
            if (isTerminal)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                sliver: SliverToBoxAdapter(
                  child: CommandResultWidget(
                    command: command,
                    status: currentStatus,
                  ),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              sliver: SliverToBoxAdapter(
                child: CommandAuditWidget(command: command),
              ),
            ),
          ],
        ),
        bottomNavigationBar: AppNavigation(
          currentIndex: _currentNavIndex,
          onTap: _onNavTap,
        ),
      ),
    );
  }

  Widget _buildCachedBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.primaryDim,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.primary.withAlpha(77), width: 1),
      ),
      child: Row(
        children: [
          Icon(Icons.storage_rounded, size: 14, color: AppTheme.primary),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Restored from local storage - available offline',
              style: GoogleFonts.ibmPlexSans(
                fontSize: 11,
                color: AppTheme.primary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    Map<String, dynamic> command,
    CommandStatus status,
  ) {
    return AppBar(
      backgroundColor: AppTheme.surface,
      elevation: 0,
      scrolledUnderElevation: 1,
      surfaceTintColor: Colors.transparent,
      shadowColor: AppTheme.border,
      leading: IconButton(
        icon: Icon(
          Icons.arrow_back_ios_new_rounded,
          size: 18,
          color: AppTheme.textPrimary,
        ),
        onPressed: () => _handleBack(command),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Command Tracking',
            style: GoogleFonts.ibmPlexSans(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          Text(
            command['id']?.toString() ?? 'cmd-unknown',
            style: GoogleFonts.ibmPlexMono(
              fontSize: 10,
              color: AppTheme.textMuted,
            ),
          ),
        ],
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: StatusBadgeWidget.command(status),
        ),
      ],
    );
  }

  Widget _buildCommandHeaderCard(
    BuildContext context,
    Map<String, dynamic> command,
  ) {
    final method = command['method']?.toString() ?? 'unknown_method';
    final deviceName = command['deviceName']?.toString() ?? 'Unknown Device';
    final initiator = command['initiator']?.toString() ?? 'Unknown';
    final params = command['params']?.toString() ?? '{}';
    final policyDecision = command['policyDecision']?.toString() ?? 'unknown';
    final deviceId = command['deviceId']?.toString() ?? 'dev-unknown';
    final isSensitive = command['sensitive'] == true;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border, width: 1),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.primaryDim,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppTheme.primary.withAlpha(102),
                    width: 1,
                  ),
                ),
                child: Icon(
                  Icons.sync_rounded,
                  color: AppTheme.primary,
                  size: 22,
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      method,
                      style: GoogleFonts.ibmPlexMono(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '$deviceName  ·  $initiator',
                      style: GoogleFonts.ibmPlexSans(
                        fontSize: 12,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.borderLight, width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PARAMETERS',
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textMuted,
                    letterSpacing: 0.8,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  params,
                  style: GoogleFonts.ibmPlexMono(
                    fontSize: 12,
                    color: AppTheme.primary,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _HeaderTag(
                icon: Icons.policy_rounded,
                label: 'Policy: $policyDecision',
                color: AppTheme.secondary,
              ),
              _HeaderTag(
                icon: Icons.devices_rounded,
                label: deviceId,
                color: AppTheme.primary,
              ),
              if (isSensitive)
                _HeaderTag(
                  icon: Icons.security_rounded,
                  label: 'Sensitive',
                  color: AppTheme.warning,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPollingIndicator(int secondsSinceUpdate) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.warningMuted,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.warning.withAlpha(77), width: 1),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: AppTheme.warning,
            ),
          ),
          SizedBox(width: 10),
          Text(
            'Polling for updates...  Last refresh: ${secondsSinceUpdate}s ago',
            style: GoogleFonts.ibmPlexSans(
              fontSize: 11,
              color: AppTheme.warning,
            ),
          ),
        ],
      ),
    );
  }

  CommandStatus _toLegacyStatus(CommandExecutionStatus status) {
    switch (status) {
      case CommandExecutionStatus.queued:
        return CommandStatus.queued;
      case CommandExecutionStatus.dispatched:
        return CommandStatus.dispatched;
      case CommandExecutionStatus.acked:
        return CommandStatus.acked;
      case CommandExecutionStatus.executing:
        return CommandStatus.executing;
      case CommandExecutionStatus.completed:
        return CommandStatus.completed;
      case CommandExecutionStatus.failed:
        return CommandStatus.failed;
      case CommandExecutionStatus.expired:
        return CommandStatus.expired;
    }
  }
}

class _HeaderTag extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _HeaderTag({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(26),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color.withAlpha(64), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          SizedBox(width: 5),
          Text(
            label,
            style: GoogleFonts.ibmPlexMono(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
