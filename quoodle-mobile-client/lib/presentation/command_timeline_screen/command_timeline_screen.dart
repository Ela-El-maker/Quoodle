import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_theme.dart';
import '../../widgets/status_badge_widget.dart';
import './widgets/command_audit_widget.dart';
import './widgets/command_result_widget.dart';
import './widgets/command_timeline_widget.dart';

class CommandTimelineScreen extends StatefulWidget {
  const CommandTimelineScreen({super.key});

  @override
  State<CommandTimelineScreen> createState() => _CommandTimelineScreenState();
}

class _CommandTimelineScreenState extends State<CommandTimelineScreen> {
  // TODO: Replace with Riverpod/Bloc polling service for production
  Timer? _pollTimer;
  int _pollCount = 0;
  int _secondsSinceUpdate = 0;

  // Simulated command — starts executing, completes after a few polls
  static const Map<String, dynamic> _commandBase = {
    'id': 'cmd-0091',
    'method': 'policy_sync',
    'deviceId': 'dev-007',
    'deviceName': 'WKS-FINANCE-07',
    'initiator': 'L. Nakamura',
    'role': 'operator',
    'sensitive': false,
    'params': '{"force": true, "version": "1.0.4"}',
    'policyDecision': 'allow',
    'queuedAt': '2026-04-06T10:41:03Z',
    'dispatchedAt': '2026-04-06T10:41:04Z',
    'ackedAt': '2026-04-06T10:41:05Z',
    'executingAt': '2026-04-06T10:41:06Z',
  };

  late Map<String, dynamic> _command;
  CommandStatus _currentStatus = CommandStatus.executing;

  // Method-to-result-type mapping
  static const Map<String, String> _methodResultTypes = {
    'screenshot_capture': 'screenshot',
    'process_list': 'process_list',
    'system_info': 'system_info',
    'running_apps': 'running_apps',
    'filesystem': 'filesystem',
    'network_info': 'network_info',
    'upload_file': 'file_op',
    'create_file': 'file_op',
    'collect_telemetry': 'telemetry',
  };

  @override
  void initState() {
    super.initState();
    // Accept arguments from navigation (from command history or send command)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map<String, dynamic>) {
        setState(() {
          _command = {
            ..._commandBase,
            if (args.containsKey('method')) 'method': args['method'],
            if (args.containsKey('params')) 'params': args['params'],
            if (args.containsKey('sensitive')) 'sensitive': args['sensitive'],
            if (args.containsKey('id')) 'id': args['id'],
            if (args.containsKey('initiator')) 'initiator': args['initiator'],
          };
        });
      }
    });
    _command = Map.from(_commandBase);
    _startPolling();
  }

  void _startPolling() {
    // TODO: Replace with real GET /api/commands/{id} polling for production
    Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _secondsSinceUpdate++);
    });

    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted) return;
      _pollCount++;
      // Simulate progression: executing → completed after 3 polls
      if (_pollCount >= 3 && _currentStatus == CommandStatus.executing) {
        final method = _command['method'] as String? ?? 'policy_sync';
        final resultType = _methodResultTypes[method];
        setState(() {
          _currentStatus = CommandStatus.completed;
          _command = {
            ..._command,
            'completedAt': '2026-04-06T10:41:14Z',
            'executionTimeMs': 8210,
            'resultStatus': 'success',
            'resultNotes': 'Command executed successfully.',
            if (resultType != null) 'resultType': resultType,
          };
          _secondsSinceUpdate = 0;
        });
        _pollTimer?.cancel();
      }
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isTerminal =
        _currentStatus == CommandStatus.completed ||
        _currentStatus == CommandStatus.failed ||
        _currentStatus == CommandStatus.expired;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: _buildAppBar(context, isTerminal),
      body: CustomScrollView(
        slivers: [
          // Command header card
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            sliver: SliverToBoxAdapter(child: _buildCommandHeaderCard(context)),
          ),
          // Polling status
          if (!isTerminal)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              sliver: SliverToBoxAdapter(child: _buildPollingIndicator()),
            ),
          // Timeline
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            sliver: SliverToBoxAdapter(
              child: CommandTimelineWidget(
                currentStatus: _currentStatus,
                command: _command,
              ),
            ),
          ),
          // Result section (terminal states only)
          if (isTerminal)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              sliver: SliverToBoxAdapter(
                child: CommandResultWidget(
                  command: _command,
                  status: _currentStatus,
                ),
              ),
            ),
          // Audit section
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            sliver: SliverToBoxAdapter(
              child: CommandAuditWidget(command: _command),
            ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, bool isTerminal) {
    return AppBar(
      backgroundColor: AppTheme.surface,
      elevation: 0,
      scrolledUnderElevation: 1,
      surfaceTintColor: Colors.transparent,
      shadowColor: AppTheme.border,
      leading: IconButton(
        icon: const Icon(
          Icons.arrow_back_ios_new_rounded,
          size: 18,
          color: AppTheme.textPrimary,
        ),
        onPressed: () => Navigator.pop(context),
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
            _command['id'] as String,
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
          child: StatusBadgeWidget.command(_currentStatus),
        ),
      ],
    );
  }

  Widget _buildCommandHeaderCard(BuildContext context) {
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
                child: const Icon(
                  Icons.sync_rounded,
                  color: AppTheme.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _command['method'] as String,
                      style: GoogleFonts.ibmPlexMono(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_command['deviceName']}  ·  ${_command['initiator']}',
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
          const SizedBox(height: 14),
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
                const SizedBox(height: 6),
                Text(
                  _command['params'] as String,
                  style: GoogleFonts.ibmPlexMono(
                    fontSize: 12,
                    color: AppTheme.primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _HeaderTag(
                icon: Icons.policy_rounded,
                label: 'Policy: ${_command['policyDecision']}',
                color: AppTheme.secondary,
              ),
              const SizedBox(width: 8),
              _HeaderTag(
                icon: Icons.devices_rounded,
                label: _command['deviceId'] as String,
                color: AppTheme.primary,
              ),
              if (_command['sensitive'] as bool) ...[
                const SizedBox(width: 8),
                _HeaderTag(
                  icon: Icons.security_rounded,
                  label: 'Sensitive',
                  color: AppTheme.warning,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPollingIndicator() {
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
          const SizedBox(width: 10),
          Text(
            'Polling for updates…  Last refresh: ${_secondsSinceUpdate}s ago',
            style: GoogleFonts.ibmPlexSans(
              fontSize: 11,
              color: AppTheme.warning,
            ),
          ),
        ],
      ),
    );
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
          const SizedBox(width: 5),
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
