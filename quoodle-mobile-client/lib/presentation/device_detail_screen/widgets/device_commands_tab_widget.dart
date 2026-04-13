import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:secure_device_control/app/router/app_navigator.dart';
import 'package:secure_device_control/features/commands/presentation/providers/commands_api_providers.dart';
import 'package:secure_device_control/features/devices/presentation/providers/devices_providers.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/empty_state_widget.dart';
import '../../../widgets/status_badge_widget.dart';

class DeviceCommandsTabWidget extends ConsumerStatefulWidget {
  final String deviceId;
  const DeviceCommandsTabWidget({super.key, required this.deviceId});

  @override
  ConsumerState<DeviceCommandsTabWidget> createState() =>
      _DeviceCommandsTabWidgetState();
}

class _DeviceCommandsTabWidgetState
    extends ConsumerState<DeviceCommandsTabWidget> {
  static const _refreshInterval = Duration(seconds: 5);
  static const _sensitiveMethods = <String>{
    'screenshot_capture',
    'screenshot',
    'filesystem',
    'list_files',
    'upload_file',
    'create_file',
    'reboot',
    'reboot_device',
  };

  static const _methodResultTypes = <String, String>{
    'screenshot_capture': 'screenshot',
    'screenshot': 'screenshot',
    'process_list': 'process_list',
    'list_processes': 'process_list',
    'system_info': 'system_info',
    'collect_system_info': 'system_info',
    'running_apps': 'running_apps',
    'filesystem': 'filesystem',
    'list_files': 'filesystem',
    'network_info': 'network_info',
    'upload_file': 'file_op',
    'download_file': 'file_op',
    'create_file': 'file_op',
    'collect_telemetry': 'telemetry',
    'health_check': 'telemetry',
    'policy_probe': 'action',
    'reboot_device': 'action',
  };

  final List<Map<String, dynamic>> _commandMaps = <Map<String, dynamic>>[];
  Timer? _refreshTimer;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    unawaited(_loadCommands());
    _refreshTimer = Timer.periodic(_refreshInterval, (_) {
      unawaited(_loadCommands(silent: true));
    });
  }

  @override
  void didUpdateWidget(covariant DeviceCommandsTabWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.deviceId != widget.deviceId) {
      unawaited(_loadCommands());
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadCommands({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      final rows = await ref
          .read(commandsRemoteDataSourceProvider)
          .fetchDeviceCommands(widget.deviceId, limit: 50);
      final mapped = rows.map(_mapCommandRow).toList(growable: false);

      if (!mounted) {
        return;
      }
      setState(() {
        _commandMaps
          ..clear()
          ..addAll(mapped);
        _isLoading = false;
        _errorMessage = null;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        if (_commandMaps.isEmpty) {
          _errorMessage = 'Unable to load command history.';
        }
      });
    }
  }

  Map<String, dynamic> _mapCommandRow(Map<String, dynamic> row) {
    final method = _asString(row['method']).ifEmpty('unknown_method');
    final stateRaw = _asString(row['execution_state']).ifEmpty(
      _asString(row['state']),
    );
    final normalizedStatus = _normalizeStatus(stateRaw);
    final queuedAtIso = _asString(row['queued_at']);
    final dispatchedAtIso = _asString(row['dispatched_at']);
    final completedAtIso = _asString(row['completed_at']);
    final params = row['params'];

    final commandMap = <String, dynamic>{
      'id': _asString(row['command_id']).ifEmpty('cmd-unknown'),
      'method': method,
      'status': normalizedStatus,
      'state': _asString(row['state']).ifEmpty(stateRaw),
      'executionState': stateRaw,
      'initiator': _asString(row['actor_email']).ifEmpty('System'),
      'queuedAt': queuedAtIso,
      'queuedAtLabel': _formatCompactTime(queuedAtIso),
      'dispatchedAt': dispatchedAtIso,
      'completedAt': completedAtIso,
      'sensitive': _sensitiveMethods.contains(method),
      'resultType':
          normalizedStatus == 'completed' ? _methodResultTypes[method] : null,
      'deviceId': _asString(row['device_id']).ifEmpty(widget.deviceId),
      'deviceName': _asString(row['device_name']),
      'params': params is Map || params is List ? params : _asString(params),
      'result': row['result'],
      'resultStatus': _asString(row['result_status']),
      'resultNotes': _asString(row['result_notes']),
      'artifactUrl': _asString(row['artifact_url']),
      'artifactChecksum': _asString(row['artifact_checksum']),
      'errorCode': _asString(row['error_code']),
      'errorMessage': _asString(row['error_message']),
      'reason': _asString(row['reason']),
      'policyDecision': normalizedStatus == 'failed' ? 'deny' : 'allow',
      'role': 'operator',
    };

    return commandMap;
  }

  String _normalizeStatus(String raw) {
    switch (raw) {
      case 'queued':
        return 'queued';
      case 'dispatched':
      case 'sent':
        return 'dispatched';
      case 'ack_received':
      case 'acked':
      case 'acknowledged':
        return 'acked';
      case 'executing':
      case 'partial':
        return 'executing';
      case 'completed':
        return 'completed';
      case 'failed':
      case 'rejected':
        return 'failed';
      case 'expired':
        return 'expired';
      default:
        return 'queued';
    }
  }

  String _formatCompactTime(String isoLike) {
    if (isoLike.isEmpty) {
      return '--';
    }
    final parsed = DateTime.tryParse(isoLike);
    if (parsed == null) {
      return isoLike;
    }
    final local = parsed.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final suffix = local.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $suffix';
  }

  String _asString(Object? value) {
    if (value is String) {
      return value;
    }
    if (value == null) {
      return '';
    }
    return value.toString();
  }

  @override
  Widget build(BuildContext context) {
    final device = ref.watch(deviceDetailProvider(widget.deviceId));
    final deviceName = device?.name ?? '';

    if (_isLoading && _commandMaps.isEmpty) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppTheme.primary,
          ),
        ),
      );
    }

    if (_commandMaps.isEmpty) {
      if (_errorMessage != null) {
        return EmptyStateWidget(
          icon: Icons.cloud_off_rounded,
          title: 'Command history unavailable',
          subtitle: _errorMessage!,
        );
      }
      return const EmptyStateWidget(
        icon: Icons.terminal_rounded,
        title: 'No commands yet',
        subtitle:
            'Commands sent to this device will appear here with their full execution history.',
      );
    }

    return Column(
      children: [
        _buildSummaryBar(context, _commandMaps, deviceName),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _loadCommands(),
            color: AppTheme.primary,
            backgroundColor: AppTheme.surface,
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
              itemCount: _commandMaps.length,
              itemBuilder: (ctx, i) {
                final cmd = _commandMaps[i];
                return _CommandHistoryCard(
                  command: cmd,
                  onTap: () => AppNavigator.push(
                    ctx,
                    AppRoute.commandTimeline,
                    arguments: cmd,
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryBar(
    BuildContext context,
    List<Map<String, dynamic>> commandMaps,
    String deviceName,
  ) {
    final total = commandMaps.length;
    final completed =
        commandMaps.where((c) => c['status'] == 'completed').length;
    final failed = commandMaps.where((c) => c['status'] == 'failed').length;
    final executing =
        commandMaps.where((c) => c['status'] == 'executing').length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(bottom: BorderSide(color: AppTheme.borderLight)),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _SummaryChip(
                      label: '$total Total', color: AppTheme.textMuted),
                  const SizedBox(width: 8),
                  _SummaryChip(
                    label: '$completed OK',
                    color: AppTheme.secondary,
                  ),
                  const SizedBox(width: 8),
                  if (executing > 0) ...[
                    _SummaryChip(
                      label: '$executing Running',
                      color: AppTheme.warning,
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (failed > 0)
                    _SummaryChip(
                      label: '$failed Failed',
                      color: AppTheme.error,
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => AppNavigator.push(
              context,
              AppRoute.sendCommand,
              arguments: <String, dynamic>{
                'deviceId': widget.deviceId,
                if (deviceName.isNotEmpty) 'deviceName': deviceName,
              },
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.primaryDim,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.primary.withAlpha(102)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.add_rounded,
                    size: 14,
                    color: AppTheme.primary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'New',
                    style: GoogleFonts.ibmPlexSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final String label;
  final Color color;
  const _SummaryChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(26),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(77)),
      ),
      child: Text(
        label,
        style: GoogleFonts.ibmPlexMono(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _CommandHistoryCard extends StatelessWidget {
  final Map<String, dynamic> command;
  final VoidCallback onTap;
  const _CommandHistoryCard({required this.command, required this.onTap});

  CommandStatus get _status {
    switch (_asString(command['status'])) {
      case 'queued':
        return CommandStatus.queued;
      case 'dispatched':
        return CommandStatus.dispatched;
      case 'acked':
        return CommandStatus.acked;
      case 'executing':
        return CommandStatus.executing;
      case 'completed':
        return CommandStatus.completed;
      case 'failed':
        return CommandStatus.failed;
      default:
        return CommandStatus.expired;
    }
  }

  IconData get _methodIcon {
    switch (_asString(command['method'])) {
      case 'lock_screen':
        return Icons.lock_rounded;
      case 'reboot':
      case 'reboot_device':
        return Icons.restart_alt_rounded;
      case 'collect_telemetry':
      case 'health_check':
        return Icons.analytics_rounded;
      case 'policy_sync':
      case 'policy_probe':
        return Icons.sync_rounded;
      case 'screenshot_capture':
      case 'screenshot':
        return Icons.screenshot_rounded;
      case 'process_list':
      case 'list_processes':
        return Icons.account_tree_rounded;
      case 'system_info':
      case 'collect_system_info':
        return Icons.info_outline_rounded;
      case 'running_apps':
        return Icons.apps_rounded;
      case 'filesystem':
      case 'list_files':
        return Icons.folder_open_rounded;
      case 'network_info':
        return Icons.lan_rounded;
      case 'upload_file':
      case 'download_file':
        return Icons.upload_rounded;
      case 'create_file':
        return Icons.note_add_rounded;
      default:
        return Icons.terminal_rounded;
    }
  }

  Color get _methodColor {
    switch (_asString(command['method'])) {
      case 'screenshot_capture':
      case 'screenshot':
      case 'filesystem':
      case 'list_files':
      case 'upload_file':
      case 'download_file':
      case 'create_file':
      case 'reboot':
      case 'reboot_device':
        return AppTheme.warning;
      case 'lock_screen':
        return AppTheme.error;
      case 'collect_telemetry':
      case 'health_check':
      case 'system_info':
      case 'collect_system_info':
      case 'running_apps':
      case 'network_info':
        return AppTheme.secondary;
      default:
        return AppTheme.primary;
    }
  }

  String get _resultTypeLabel {
    final rt = _asString(command['resultType']);
    switch (rt) {
      case 'screenshot':
        return 'Screenshot';
      case 'process_list':
        return 'Process Table';
      case 'system_info':
        return 'System Report';
      case 'running_apps':
        return 'App List';
      case 'filesystem':
        return 'File Tree';
      case 'network_info':
        return 'Network Map';
      case 'file_op':
        return 'File Op';
      case 'telemetry':
        return 'Metrics';
      case 'action':
        return 'Action';
      default:
        return '';
    }
  }

  String _displayTime() {
    final queuedAtLabel = _asString(command['queuedAtLabel']);
    if (queuedAtLabel.isNotEmpty) {
      return queuedAtLabel;
    }
    final raw = _asString(command['queuedAt']);
    if (raw.isEmpty) {
      return '--';
    }
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) {
      return raw;
    }
    final local = parsed.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final suffix = local.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $suffix';
  }

  bool _asBool(Object? value) {
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      return normalized == 'true' || normalized == '1' || normalized == 'yes';
    }
    return false;
  }

  String _asString(Object? value) {
    if (value is String) {
      return value;
    }
    if (value == null) {
      return '';
    }
    return value.toString();
  }

  @override
  Widget build(BuildContext context) {
    final hasResult = _asString(command['resultType']).isNotEmpty &&
        _asString(command['status']) == 'completed';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      splashColor: AppTheme.primaryDim,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.border, width: 1),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: _methodColor.withAlpha(26),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _methodColor.withAlpha(64)),
              ),
              child: Icon(_methodIcon, size: 17, color: _methodColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          _asString(command['method'])
                              .ifEmpty('unknown_method'),
                          style: GoogleFonts.ibmPlexMono(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (_asBool(command['sensitive'])) ...[
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.security_rounded,
                          size: 11,
                          color: AppTheme.warning,
                        ),
                      ],
                      if (hasResult) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryDim,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _resultTypeLabel,
                            style: GoogleFonts.ibmPlexSans(
                              fontSize: 9,
                              color: AppTheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: _asString(command['id']).ifEmpty('cmd-unknown'),
                          style: GoogleFonts.ibmPlexMono(
                            fontSize: 10,
                            color: AppTheme.textMuted,
                          ),
                        ),
                        TextSpan(
                          text:
                              ' · ${_asString(command['initiator']).ifEmpty('System')}',
                          style: GoogleFonts.ibmPlexSans(
                            fontSize: 10,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                StatusBadgeWidget.command(_status),
                const SizedBox(height: 4),
                Text(
                  _displayTime(),
                  style: GoogleFonts.ibmPlexMono(
                    fontSize: 9,
                    color: AppTheme.textMuted,
                  ),
                ),
                const SizedBox(height: 2),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 14,
                  color: AppTheme.textMuted,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
