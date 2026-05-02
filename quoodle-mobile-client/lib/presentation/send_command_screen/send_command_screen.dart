import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:secure_device_control/app/router/app_navigator.dart';
import 'package:secure_device_control/features/commands/presentation/providers/send_command_controller.dart';
import 'package:secure_device_control/features/commands/presentation/providers/send_command_state.dart';
import 'package:secure_device_control/features/devices/presentation/providers/devices_providers.dart';
import '../../theme/app_theme.dart';

// ── Command Method Definitions ───────────────────────────────────────────────
class CommandMethod {
  final String id;
  final String label;
  final String description;
  final IconData icon;
  final Color color;
  final bool sensitive;
  final String policyNote;

  CommandMethod({
    required this.id,
    required this.label,
    required this.description,
    required this.icon,
    required this.color,
    this.sensitive = false,
    this.policyNote = 'Allowed for all operators.',
  });
}

final List<CommandMethod> kCommandMethods = [
  CommandMethod(
    id: 'screenshot_capture',
    label: 'Screenshot',
    description: 'Capture a screenshot of the current screen.',
    icon: Icons.screenshot_rounded,
    color: AppTheme.error,
    sensitive: true,
    policyNote: 'SENSITIVE — Requires admin approval. Logged to audit trail.',
  ),
  CommandMethod(
    id: 'process_list',
    label: 'Process List',
    description: 'Retrieve running processes with resource usage.',
    icon: Icons.account_tree_rounded,
    color: AppTheme.primary,
    policyNote: 'Allowed for all operators.',
  ),
  CommandMethod(
    id: 'running_apps',
    label: 'Running Apps',
    description: 'List all currently running applications.',
    icon: Icons.apps_rounded,
    color: AppTheme.primary,
    policyNote: 'Allowed for all operators.',
  ),
  CommandMethod(
    id: 'filesystem',
    label: 'Filesystem',
    description: 'Browse the device filesystem at a given path.',
    icon: Icons.folder_open_rounded,
    color: AppTheme.warning,
    sensitive: true,
    policyNote: 'SENSITIVE — Requires admin role. Full path access logged.',
  ),
  CommandMethod(
    id: 'system_info',
    label: 'System Info',
    description: 'Collect full system information.',
    icon: Icons.info_outline_rounded,
    color: AppTheme.secondary,
    policyNote: 'Allowed for all operators.',
  ),
  CommandMethod(
    id: 'network_info',
    label: 'Network Info',
    description: 'Retrieve network interfaces, connections, and DNS.',
    icon: Icons.lan_rounded,
    color: AppTheme.secondary,
    policyNote: 'Allowed for all operators.',
  ),
  CommandMethod(
    id: 'collect_telemetry',
    label: 'Telemetry',
    description: 'Trigger an immediate telemetry collection cycle.',
    icon: Icons.analytics_rounded,
    color: AppTheme.secondary,
    policyNote: 'Allowed for all operators.',
  ),
  CommandMethod(
    id: 'lock_screen',
    label: 'Lock Screen',
    description: 'Immediately lock the device screen.',
    icon: Icons.lock_rounded,
    color: AppTheme.warning,
    policyNote: 'Requires operator role or above.',
  ),
  CommandMethod(
    id: 'policy_sync',
    label: 'Policy Sync',
    description: 'Force synchronise the device policy.',
    icon: Icons.sync_rounded,
    color: AppTheme.primary,
    policyNote: 'Allowed for all operators. No approval required.',
  ),
  CommandMethod(
    id: 'upload_file',
    label: 'Upload File',
    description: 'Upload a file from the device to the server.',
    icon: Icons.upload_rounded,
    color: AppTheme.warning,
    sensitive: true,
    policyNote: 'SENSITIVE — Requires admin approval. File content is logged.',
  ),
  CommandMethod(
    id: 'create_file',
    label: 'Create File',
    description: 'Create a file on the device at a specified path.',
    icon: Icons.note_add_rounded,
    color: AppTheme.error,
    sensitive: true,
    policyNote: 'SENSITIVE — Requires admin role. Creates audit entry.',
  ),
  CommandMethod(
    id: 'reboot',
    label: 'Reboot',
    description: 'Initiate a controlled device reboot.',
    icon: Icons.restart_alt_rounded,
    color: AppTheme.error,
    sensitive: true,
    policyNote: 'SENSITIVE — Requires admin approval. Notifies assigned user.',
  ),
];

// ── Main Screen ──────────────────────────────────────────────────────────────
class SendCommandScreen extends ConsumerStatefulWidget {
  const SendCommandScreen({super.key});

  @override
  ConsumerState<SendCommandScreen> createState() => _SendCommandScreenState();
}

class _SendCommandScreenState extends ConsumerState<SendCommandScreen> {
  String _targetDeviceId = 'dev-007';
  String _targetDeviceName = 'WKS-FINANCE-07';
  bool _targetResolved = false;

  SendCommandState get _flowState => ref.read(sendCommandControllerProvider);
  CommandMethod get _selectedMethod => kCommandMethods.firstWhere(
        (m) => m.id == _flowState.selectedMethodId,
        orElse: () => kCommandMethods.first,
      );
  bool get _sensitiveOverride => _flowState.sensitiveOverride;
  bool get _showPolicyPanel => _flowState.showPolicyPanel;
  bool get _submitting => _flowState.submitting;

  // Per-command form state
  // Screenshot
  int _screenshotDisplay = 0;
  String _screenshotQuality = 'high';

  // Process list
  String _processSortBy = 'cpu';
  double _processLimit = 50;

  // Running apps
  bool _includeBackground = true;

  // Filesystem
  final TextEditingController _fsPathController = TextEditingController(
    text: '/',
  );
  double _fsDepth = 2;
  bool _fsIncludeHidden = false;

  // System info
  final Set<String> _sysInfoIncludes = {'hardware', 'os', 'network', 'storage'};

  // Network info
  bool _netIncludeConnections = true;
  bool _netIncludeDns = true;

  // Telemetry
  final Set<String> _telemetryMetrics = {
    'cpu',
    'ram',
    'disk',
    'network',
    'processes',
  };

  // Lock screen
  String _lockReason = 'operator_initiated';

  // Policy sync
  bool _policyForce = true;
  String _policyVersion = 'latest';

  // Upload file
  final TextEditingController _uploadPathController = TextEditingController(
    text: '/path/to/file',
  );
  bool _uploadCompress = true;

  // Create file
  final TextEditingController _createPathController = TextEditingController(
    text: '/path/to/file',
  );
  final TextEditingController _createContentController =
      TextEditingController();
  bool _createOverwrite = false;

  // Reboot
  double _rebootDelay = 30;
  bool _rebootForce = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_targetResolved) {
      return;
    }
    _targetResolved = true;
    final args = ModalRoute.of(context)?.settings.arguments;
    final target = _extractTarget(args);
    _targetDeviceId = target.$1;
    _targetDeviceName = target.$2;
  }

  @override
  void dispose() {
    _fsPathController.dispose();
    _uploadPathController.dispose();
    _createPathController.dispose();
    _createContentController.dispose();
    super.dispose();
  }

  void _selectMethod(CommandMethod method) {
    ref.read(sendCommandControllerProvider.notifier).selectMethod(method.id);
  }

  void _onSubmitTap() {
    unawaited(_submitCommand());
  }

  Future<void> _submitCommand() async {
    final dispatchResult =
        await ref.read(sendCommandControllerProvider.notifier).dispatchCommand(
              deviceId: _targetDeviceId,
              deviceName: _targetDeviceName,
              methodId: _selectedMethod.id,
              params: _buildParamsMap(),
              sensitive: _selectedMethod.sensitive,
            );

    if (!mounted) return;
    if (!dispatchResult.success || dispatchResult.timelineArguments == null) {
      final messenger = ScaffoldMessenger.of(context);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              dispatchResult.errorMessage ?? 'Unable to submit command.',
            ),
            backgroundColor: AppTheme.error,
          ),
        );
      return;
    }

    AppNavigator.push(
      context,
      AppRoute.commandTimeline,
      arguments: dispatchResult.timelineArguments,
    );
  }

  Map<String, dynamic> _buildParamsMap() {
    switch (_selectedMethod.id) {
      case 'screenshot_capture':
        return {'display': _screenshotDisplay, 'quality': _screenshotQuality};
      case 'process_list':
        return {'sort_by': _processSortBy, 'limit': _processLimit.toInt()};
      case 'running_apps':
        return {'include_background': _includeBackground};
      case 'filesystem':
        return {
          'path': _fsPathController.text,
          'depth': _fsDepth.toInt(),
          'include_hidden': _fsIncludeHidden,
        };
      case 'system_info':
        return {'include': _sysInfoIncludes.toList()};
      case 'network_info':
        return {
          'include_connections': _netIncludeConnections,
          'include_dns': _netIncludeDns,
        };
      case 'collect_telemetry':
        return {'metrics': _telemetryMetrics.toList()};
      case 'lock_screen':
        return {'reason': _lockReason};
      case 'policy_sync':
        return {'force': _policyForce, 'version': _policyVersion};
      case 'upload_file':
        return {
          'path': _uploadPathController.text,
          'compress': _uploadCompress,
        };
      case 'create_file':
        return {
          'path': _createPathController.text,
          'content': _createContentController.text,
          'overwrite': _createOverwrite,
        };
      case 'reboot':
        return {'delay_seconds': _rebootDelay.toInt(), 'force': _rebootForce};
      default:
        return {};
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(sendCommandControllerProvider);
    final resolvedDevice = ref.watch(deviceDetailProvider(_targetDeviceId));
    final targetDeviceName = resolvedDevice?.name ?? _targetDeviceName;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
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
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Send Command',
              style: GoogleFonts.ibmPlexSans(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
            Text(
              targetDeviceName,
              style: GoogleFonts.ibmPlexMono(
                fontSize: 10,
                color: AppTheme.textMuted,
              ),
            ),
          ],
        ),
        actions: [
          if (_selectedMethod.sensitive)
            Container(
              margin: const EdgeInsets.only(right: 16),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.warningMuted,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.warning.withAlpha(102)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.security_rounded,
                    size: 12,
                    color: AppTheme.warning,
                  ),
                  SizedBox(width: 4),
                  Text(
                    'SENSITIVE',
                    style: GoogleFonts.ibmPlexMono(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.warning,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      body: _buildCommandForm(),
      bottomNavigationBar: _buildSubmitBar(),
    );
  }

  // ── Command Form ────────────────────────────────────────────────────────────
  Widget _buildCommandForm() {
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          sliver: SliverToBoxAdapter(child: _buildMethodSelector()),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          sliver: SliverToBoxAdapter(child: _buildCommandParamsForm()),
        ),
        if (_selectedMethod.sensitive)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            sliver: SliverToBoxAdapter(child: _buildSensitivityBanner()),
          ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
          sliver: SliverToBoxAdapter(child: _buildPolicyPanel()),
        ),
      ],
    );
  }

  // ── Method Selector ─────────────────────────────────────────────────────────
  Widget _buildMethodSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'COMMAND TYPE',
          style: GoogleFonts.ibmPlexSans(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: AppTheme.textMuted,
            letterSpacing: 0.8,
          ),
        ),
        SizedBox(height: 10),
        SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: kCommandMethods.length,
            separatorBuilder: (_, __) => SizedBox(width: 8),
            itemBuilder: (_, i) {
              final method = kCommandMethods[i];
              final selected = method.id == _selectedMethod.id;
              return GestureDetector(
                onTap: () => _selectMethod(method),
                child: AnimatedContainer(
                  duration: Duration(milliseconds: 180),
                  width: 82,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: selected
                        ? method.color.withAlpha(28)
                        : AppTheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected
                          ? method.color.withAlpha(160)
                          : AppTheme.border,
                      width: selected ? 1.5 : 1,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        method.icon,
                        size: 20,
                        color: selected ? method.color : AppTheme.textMuted,
                      ),
                      SizedBox(height: 6),
                      Text(
                        method.label,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.ibmPlexSans(
                          fontSize: 10,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w400,
                          color:
                              selected ? method.color : AppTheme.textSecondary,
                          height: 1.2,
                        ),
                      ),
                      if (method.sensitive) ...[
                        SizedBox(height: 4),
                        Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            color: AppTheme.warning,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.surfaceVariant,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.border),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _selectedMethod.color.withAlpha(24),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _selectedMethod.icon,
                  size: 18,
                  color: _selectedMethod.color,
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _selectedMethod.label,
                      style: GoogleFonts.ibmPlexSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    Text(
                      _selectedMethod.description,
                      style: GoogleFonts.ibmPlexSans(
                        fontSize: 11,
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
      ],
    );
  }

  // ── Per-Command Forms ────────────────────────────────────────────────────────
  Widget _buildCommandParamsForm() {
    switch (_selectedMethod.id) {
      case 'screenshot_capture':
        return _buildScreenshotForm();
      case 'process_list':
        return _buildProcessListForm();
      case 'running_apps':
        return _buildRunningAppsForm();
      case 'filesystem':
        return _buildFilesystemForm();
      case 'system_info':
        return _buildSystemInfoForm();
      case 'network_info':
        return _buildNetworkInfoForm();
      case 'collect_telemetry':
        return _buildTelemetryForm();
      case 'lock_screen':
        return _buildLockScreenForm();
      case 'policy_sync':
        return _buildPolicySyncForm();
      case 'upload_file':
        return _buildUploadFileForm();
      case 'create_file':
        return _buildCreateFileForm();
      case 'reboot':
        return _buildRebootForm();
      default:
        return const SizedBox.shrink();
    }
  }

  // ── Screenshot Form ──────────────────────────────────────────────────────────
  Widget _buildScreenshotForm() {
    return _FormCard(
      title: 'CAPTURE OPTIONS',
      children: [
        _FormLabel('Display'),
        SizedBox(height: 8),
        Row(
          children: [0, 1, 2].map((d) {
            final sel = _screenshotDisplay == d;
            return Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _screenshotDisplay = d),
                child: AnimatedContainer(
                  duration: Duration(milliseconds: 150),
                  margin: EdgeInsets.only(right: d < 2 ? 8 : 0),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color:
                        sel ? AppTheme.primary.withAlpha(24) : AppTheme.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: sel ? AppTheme.primary : AppTheme.border,
                      width: sel ? 1.5 : 1,
                    ),
                  ),
                  child: Text(
                    d == 0 ? 'Primary' : 'Display $d',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.ibmPlexSans(
                      fontSize: 12,
                      fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
                      color: sel ? AppTheme.primary : AppTheme.textSecondary,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        SizedBox(height: 16),
        _FormLabel('Quality'),
        SizedBox(height: 8),
        Row(
          children: ['low', 'medium', 'high'].map((q) {
            final sel = _screenshotQuality == q;
            return Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _screenshotQuality = q),
                child: AnimatedContainer(
                  duration: Duration(milliseconds: 150),
                  margin: EdgeInsets.only(right: q != 'high' ? 8 : 0),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color:
                        sel ? AppTheme.error.withAlpha(24) : AppTheme.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: sel ? AppTheme.error : AppTheme.border,
                      width: sel ? 1.5 : 1,
                    ),
                  ),
                  child: Text(
                    q[0].toUpperCase() + q.substring(1),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.ibmPlexSans(
                      fontSize: 12,
                      fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
                      color: sel ? AppTheme.error : AppTheme.textSecondary,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ── Process List Form ────────────────────────────────────────────────────────
  Widget _buildProcessListForm() {
    return _FormCard(
      title: 'FILTER OPTIONS',
      children: [
        _FormLabel('Sort By'),
        SizedBox(height: 8),
        Row(
          children: ['cpu', 'memory', 'pid', 'name'].map((s) {
            final sel = _processSortBy == s;
            return Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _processSortBy = s),
                child: AnimatedContainer(
                  duration: Duration(milliseconds: 150),
                  margin: EdgeInsets.only(right: s != 'name' ? 6 : 0),
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color:
                        sel ? AppTheme.primary.withAlpha(24) : AppTheme.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: sel ? AppTheme.primary : AppTheme.border,
                      width: sel ? 1.5 : 1,
                    ),
                  ),
                  child: Text(
                    s.toUpperCase(),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.ibmPlexMono(
                      fontSize: 10,
                      fontWeight: sel ? FontWeight.w700 : FontWeight.w400,
                      color: sel ? AppTheme.primary : AppTheme.textSecondary,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        SizedBox(height: 16),
        Row(
          children: [
            _FormLabel('Result Limit'),
            Spacer(),
            Text(
              '${_processLimit.toInt()} processes',
              style: GoogleFonts.ibmPlexMono(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.primary,
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: AppTheme.primary,
            inactiveTrackColor: AppTheme.border,
            thumbColor: AppTheme.primary,
            overlayColor: AppTheme.primary.withAlpha(30),
            trackHeight: 3,
          ),
          child: Slider(
            value: _processLimit,
            min: 10,
            max: 200,
            divisions: 19,
            onChanged: (v) => setState(() => _processLimit = v),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '10',
              style: GoogleFonts.ibmPlexMono(
                fontSize: 10,
                color: AppTheme.textMuted,
              ),
            ),
            Text(
              '200',
              style: GoogleFonts.ibmPlexMono(
                fontSize: 10,
                color: AppTheme.textMuted,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Running Apps Form ────────────────────────────────────────────────────────
  Widget _buildRunningAppsForm() {
    return _FormCard(
      title: 'APP FILTER',
      children: [
        _FormToggleRow(
          label: 'Include Background Apps',
          subtitle: 'Show apps running in the background',
          value: _includeBackground,
          onChanged: (v) => setState(() => _includeBackground = v),
        ),
      ],
    );
  }

  // ── Filesystem Form ──────────────────────────────────────────────────────────
  Widget _buildFilesystemForm() {
    return _FormCard(
      title: 'BROWSE OPTIONS',
      children: [
        _FormLabel('Root Path'),
        SizedBox(height: 8),
        _StyledTextField(
          controller: _fsPathController,
          hint: '/path/to/directory',
          prefix: Icons.folder_outlined,
          monospace: true,
        ),
        SizedBox(height: 8),
        _QuickPathRow(
          paths: ['/', '/home', '/etc', '/var', '/tmp', 'C:\\Users'],
          onSelect: (p) => setState(() => _fsPathController.text = p),
        ),
        SizedBox(height: 16),
        Row(
          children: [
            _FormLabel('Depth'),
            Spacer(),
            Text(
              '${_fsDepth.toInt()} level${_fsDepth.toInt() != 1 ? 's' : ''}',
              style: GoogleFonts.ibmPlexMono(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.warning,
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: AppTheme.warning,
            inactiveTrackColor: AppTheme.border,
            thumbColor: AppTheme.warning,
            overlayColor: AppTheme.warning.withAlpha(30),
            trackHeight: 3,
          ),
          child: Slider(
            value: _fsDepth,
            min: 1,
            max: 5,
            divisions: 4,
            onChanged: (v) => setState(() => _fsDepth = v),
          ),
        ),
        SizedBox(height: 8),
        _FormToggleRow(
          label: 'Include Hidden Files',
          subtitle: 'Show files and folders starting with .',
          value: _fsIncludeHidden,
          onChanged: (v) => setState(() => _fsIncludeHidden = v),
          accentColor: AppTheme.warning,
        ),
      ],
    );
  }

  // ── System Info Form ─────────────────────────────────────────────────────────
  Widget _buildSystemInfoForm() {
    final options = {
      'hardware': 'Hardware',
      'os': 'Operating System',
      'network': 'Network',
      'storage': 'Storage',
      'security': 'Security',
      'users': 'Users',
    };
    return _FormCard(
      title: 'INFORMATION SECTIONS',
      children: [
        Text(
          'Select which sections to include in the report',
          style: GoogleFonts.ibmPlexSans(
            fontSize: 12,
            color: AppTheme.textSecondary,
          ),
        ),
        SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.entries.map((e) {
            final sel = _sysInfoIncludes.contains(e.key);
            return GestureDetector(
              onTap: () => setState(() {
                if (sel) {
                  _sysInfoIncludes.remove(e.key);
                } else {
                  _sysInfoIncludes.add(e.key);
                }
              }),
              child: AnimatedContainer(
                duration: Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color:
                      sel ? AppTheme.secondary.withAlpha(24) : AppTheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: sel ? AppTheme.secondary : AppTheme.border,
                    width: sel ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (sel)
                      Padding(
                        padding: EdgeInsets.only(right: 6),
                        child: Icon(
                          Icons.check_rounded,
                          size: 12,
                          color: AppTheme.secondary,
                        ),
                      ),
                    Text(
                      e.value,
                      style: GoogleFonts.ibmPlexSans(
                        fontSize: 12,
                        fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
                        color:
                            sel ? AppTheme.secondary : AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ── Network Info Form ────────────────────────────────────────────────────────
  Widget _buildNetworkInfoForm() {
    return _FormCard(
      title: 'COLLECTION OPTIONS',
      children: [
        _FormToggleRow(
          label: 'Active Connections',
          subtitle: 'Include TCP/UDP connection table',
          value: _netIncludeConnections,
          onChanged: (v) => setState(() => _netIncludeConnections = v),
          accentColor: AppTheme.secondary,
        ),
        SizedBox(height: 12),
        _FormToggleRow(
          label: 'DNS Configuration',
          subtitle: 'Include DNS servers and search domains',
          value: _netIncludeDns,
          onChanged: (v) => setState(() => _netIncludeDns = v),
          accentColor: AppTheme.secondary,
        ),
      ],
    );
  }

  // ── Telemetry Form ───────────────────────────────────────────────────────────
  Widget _buildTelemetryForm() {
    final options = {
      'cpu': 'CPU',
      'ram': 'Memory',
      'disk': 'Disk',
      'network': 'Network',
      'processes': 'Processes',
      'gpu': 'GPU',
      'battery': 'Battery',
    };
    return _FormCard(
      title: 'METRICS TO COLLECT',
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.entries.map((e) {
            final sel = _telemetryMetrics.contains(e.key);
            return GestureDetector(
              onTap: () => setState(() {
                if (sel) {
                  _telemetryMetrics.remove(e.key);
                } else {
                  _telemetryMetrics.add(e.key);
                }
              }),
              child: AnimatedContainer(
                duration: Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color:
                      sel ? AppTheme.secondary.withAlpha(24) : AppTheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: sel ? AppTheme.secondary : AppTheme.border,
                    width: sel ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (sel)
                      Padding(
                        padding: EdgeInsets.only(right: 6),
                        child: Icon(
                          Icons.check_rounded,
                          size: 12,
                          color: AppTheme.secondary,
                        ),
                      ),
                    Text(
                      e.value,
                      style: GoogleFonts.ibmPlexSans(
                        fontSize: 12,
                        fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
                        color:
                            sel ? AppTheme.secondary : AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ── Lock Screen Form ─────────────────────────────────────────────────────────
  Widget _buildLockScreenForm() {
    final reasons = {
      'operator_initiated': 'Operator Initiated',
      'security_policy': 'Security Policy',
      'inactivity': 'Inactivity Timeout',
      'compliance': 'Compliance Enforcement',
    };
    return _FormCard(
      title: 'LOCK OPTIONS',
      children: [
        _FormLabel('Lock Reason'),
        SizedBox(height: 8),
        ...reasons.entries.map((e) {
          final sel = _lockReason == e.key;
          return GestureDetector(
            onTap: () => setState(() => _lockReason = e.key),
            child: AnimatedContainer(
              duration: Duration(milliseconds: 150),
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: sel ? AppTheme.warning.withAlpha(20) : AppTheme.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: sel ? AppTheme.warning : AppTheme.border,
                  width: sel ? 1.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    sel
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 16,
                    color: sel ? AppTheme.warning : AppTheme.textMuted,
                  ),
                  SizedBox(width: 10),
                  Text(
                    e.value,
                    style: GoogleFonts.ibmPlexSans(
                      fontSize: 13,
                      fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
                      color:
                          sel ? AppTheme.textPrimary : AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  // ── Policy Sync Form ─────────────────────────────────────────────────────────
  Widget _buildPolicySyncForm() {
    return _FormCard(
      title: 'SYNC OPTIONS',
      children: [
        _FormLabel('Target Version'),
        SizedBox(height: 8),
        Row(
          children: ['latest', 'v1.0.4', 'v1.0.3'].map((v) {
            final sel = _policyVersion == v;
            return Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _policyVersion = v),
                child: AnimatedContainer(
                  duration: Duration(milliseconds: 150),
                  margin: EdgeInsets.only(right: v != 'v1.0.3' ? 8 : 0),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color:
                        sel ? AppTheme.primary.withAlpha(24) : AppTheme.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: sel ? AppTheme.primary : AppTheme.border,
                      width: sel ? 1.5 : 1,
                    ),
                  ),
                  child: Text(
                    v,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.ibmPlexMono(
                      fontSize: 11,
                      fontWeight: sel ? FontWeight.w700 : FontWeight.w400,
                      color: sel ? AppTheme.primary : AppTheme.textSecondary,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        SizedBox(height: 16),
        _FormToggleRow(
          label: 'Force Sync',
          subtitle: 'Override local policy cache and force re-apply',
          value: _policyForce,
          onChanged: (v) => setState(() => _policyForce = v),
        ),
      ],
    );
  }

  // ── Upload File Form ─────────────────────────────────────────────────────────
  Widget _buildUploadFileForm() {
    return _FormCard(
      title: 'FILE OPTIONS',
      children: [
        _FormLabel('Remote File Path'),
        SizedBox(height: 8),
        _StyledTextField(
          controller: _uploadPathController,
          hint: '/path/to/file.ext',
          prefix: Icons.insert_drive_file_outlined,
          monospace: true,
        ),
        SizedBox(height: 16),
        _FormToggleRow(
          label: 'Compress Before Upload',
          subtitle: 'Reduces transfer size using gzip compression',
          value: _uploadCompress,
          onChanged: (v) => setState(() => _uploadCompress = v),
          accentColor: AppTheme.warning,
        ),
      ],
    );
  }

  // ── Create File Form ─────────────────────────────────────────────────────────
  Widget _buildCreateFileForm() {
    return _FormCard(
      title: 'FILE DETAILS',
      children: [
        _FormLabel('Destination Path'),
        SizedBox(height: 8),
        _StyledTextField(
          controller: _createPathController,
          hint: '/path/to/newfile.txt',
          prefix: Icons.note_add_outlined,
          monospace: true,
        ),
        SizedBox(height: 16),
        _FormLabel('File Content'),
        SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.border),
          ),
          child: TextField(
            controller: _createContentController,
            maxLines: 5,
            style: GoogleFonts.ibmPlexMono(
              fontSize: 12,
              color: AppTheme.textPrimary,
              height: 1.5,
            ),
            decoration: InputDecoration(
              border: InputBorder.none,
              contentPadding: const EdgeInsets.all(12),
              hintText: 'Enter file content here...',
              hintStyle: GoogleFonts.ibmPlexMono(
                fontSize: 12,
                color: AppTheme.textMuted,
              ),
              filled: false,
            ),
          ),
        ),
        SizedBox(height: 16),
        _FormToggleRow(
          label: 'Overwrite if Exists',
          subtitle: 'Replace existing file at destination path',
          value: _createOverwrite,
          onChanged: (v) => setState(() => _createOverwrite = v),
          accentColor: AppTheme.error,
        ),
      ],
    );
  }

  // ── Reboot Form ──────────────────────────────────────────────────────────────
  Widget _buildRebootForm() {
    return _FormCard(
      title: 'REBOOT OPTIONS',
      children: [
        Row(
          children: [
            _FormLabel('Delay Before Reboot'),
            Spacer(),
            Text(
              '${_rebootDelay.toInt()}s',
              style: GoogleFonts.ibmPlexMono(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppTheme.error,
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: AppTheme.error,
            inactiveTrackColor: AppTheme.border,
            thumbColor: AppTheme.error,
            overlayColor: AppTheme.error.withAlpha(30),
            trackHeight: 3,
          ),
          child: Slider(
            value: _rebootDelay,
            min: 0,
            max: 300,
            divisions: 30,
            onChanged: (v) => setState(() => _rebootDelay = v),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Immediate',
              style: GoogleFonts.ibmPlexMono(
                fontSize: 10,
                color: AppTheme.textMuted,
              ),
            ),
            Text(
              '5 min',
              style: GoogleFonts.ibmPlexMono(
                fontSize: 10,
                color: AppTheme.textMuted,
              ),
            ),
          ],
        ),
        SizedBox(height: 16),
        _FormToggleRow(
          label: 'Force Reboot',
          subtitle: 'Skip graceful shutdown — may cause data loss',
          value: _rebootForce,
          onChanged: (v) => setState(() => _rebootForce = v),
          accentColor: AppTheme.error,
        ),
        if (_rebootForce)
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.errorMuted,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.error.withAlpha(80)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.warning_rounded,
                  size: 16,
                  color: AppTheme.error,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Force reboot may cause unsaved data loss on the target device.',
                    style: GoogleFonts.ibmPlexSans(
                      fontSize: 11,
                      color: AppTheme.error,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ── Sensitivity Banner ───────────────────────────────────────────────────────
  Widget _buildSensitivityBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.warningMuted,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.warning.withAlpha(77)),
      ),
      child: Row(
        children: [
          Icon(Icons.security_rounded, size: 18, color: AppTheme.warning),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sensitive Operation',
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.warning,
                  ),
                ),
                Text(
                  'This command requires elevated privileges and will be fully audited.',
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 10),
          GestureDetector(
            onTap: () => ref
                .read(sendCommandControllerProvider.notifier)
                .toggleSensitiveOverride(),
            child: AnimatedContainer(
              duration: Duration(milliseconds: 200),
              width: 38,
              height: 20,
              decoration: BoxDecoration(
                color: _sensitiveOverride ? AppTheme.warning : AppTheme.border,
                borderRadius: BorderRadius.circular(10),
              ),
              child: AnimatedAlign(
                duration: Duration(milliseconds: 200),
                alignment: _sensitiveOverride
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.all(2),
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Policy Panel ─────────────────────────────────────────────────────────────
  Widget _buildPolicyPanel() {
    final isAllowed = !_selectedMethod.sensitive || _sensitiveOverride;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => ref
              .read(sendCommandControllerProvider.notifier)
              .togglePolicyPanel(),
          child: Row(
            children: [
              Text(
                'POLICY PREVIEW',
                style: GoogleFonts.ibmPlexSans(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textMuted,
                  letterSpacing: 0.8,
                ),
              ),
              Spacer(),
              Icon(
                _showPolicyPanel
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
                size: 16,
                color: AppTheme.textMuted,
              ),
            ],
          ),
        ),
        if (_showPolicyPanel) ...[
          SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isAllowed
                    ? AppTheme.secondary.withAlpha(77)
                    : AppTheme.warning.withAlpha(77),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: isAllowed
                            ? AppTheme.secondaryMuted
                            : AppTheme.warningMuted,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isAllowed
                              ? AppTheme.secondary.withAlpha(102)
                              : AppTheme.warning.withAlpha(102),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isAllowed
                                ? Icons.check_circle_rounded
                                : Icons.pending_rounded,
                            size: 12,
                            color: isAllowed
                                ? AppTheme.secondary
                                : AppTheme.warning,
                          ),
                          SizedBox(width: 5),
                          Text(
                            isAllowed ? 'ALLOW' : 'REQUIRES APPROVAL',
                            style: GoogleFonts.ibmPlexMono(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: isAllowed
                                  ? AppTheme.secondary
                                  : AppTheme.warning,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Spacer(),
                    Text(
                      'Policy v1.0.4',
                      style: GoogleFonts.ibmPlexMono(
                        fontSize: 10,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 10),
                Text(
                  _selectedMethod.policyNote,
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                    height: 1.5,
                  ),
                ),
                SizedBox(height: 10),
                Divider(color: AppTheme.borderLight, height: 1),
                SizedBox(height: 10),
                _PolicyRow(label: 'Command', value: _selectedMethod.id),
                _PolicyRow(label: 'Initiator', value: 'L. Nakamura (operator)'),
                _PolicyRow(label: 'Target', value: _currentTargetDeviceName),
                _PolicyRow(label: 'Audit', value: 'Full logging enabled'),
                _PolicyRow(label: 'TTL', value: '300s'),
              ],
            ),
          ),
        ],
      ],
    );
  }

  (String, String) _extractTarget(Object? arguments) {
    if (arguments is! Map) {
      return (_targetDeviceId, _targetDeviceName);
    }

    final map = arguments.cast<Object?, Object?>();
    final rawDeviceId = map['deviceId'] ?? map['id'];
    final rawDeviceName = map['deviceName'] ?? map['name'];

    final deviceId = rawDeviceId is String && rawDeviceId.trim().isNotEmpty
        ? rawDeviceId.trim()
        : _targetDeviceId;
    final deviceName =
        rawDeviceName is String && rawDeviceName.trim().isNotEmpty
            ? rawDeviceName.trim()
            : _targetDeviceName;

    return (deviceId, deviceName);
  }

  String get _currentTargetDeviceName {
    final resolved = ref.read(deviceDetailProvider(_targetDeviceId));
    return resolved?.name ?? _targetDeviceName;
  }

  // ── Submit Bar ───────────────────────────────────────────────────────────────
  Widget _buildSubmitBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border(top: BorderSide(color: AppTheme.borderLight)),
      ),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _submitting ? null : _onSubmitTap,
          icon: Icon(_selectedMethod.icon, size: 18),
          label: Text(
            'Send ${_selectedMethod.label}',
            style: GoogleFonts.ibmPlexSans(
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor:
                _selectedMethod.sensitive ? AppTheme.warning : AppTheme.primary,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Shared Form Widgets ──────────────────────────────────────────────────────

class _FormCard extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _FormCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.ibmPlexSans(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: AppTheme.textMuted,
            letterSpacing: 0.8,
          ),
        ),
        SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.surfaceVariant,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ],
    );
  }
}

class _FormLabel extends StatelessWidget {
  final String text;
  const _FormLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.ibmPlexSans(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: AppTheme.textSecondary,
      ),
    );
  }
}

class _FormToggleRow extends StatelessWidget {
  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color? accentColor;

  const _FormToggleRow({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.ibmPlexSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textPrimary,
                ),
              ),
              Text(
                subtitle,
                style: GoogleFonts.ibmPlexSans(
                  fontSize: 11,
                  color: AppTheme.textMuted,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
        SizedBox(width: 12),
        GestureDetector(
          onTap: () => onChanged(!value),
          child: AnimatedContainer(
            duration: Duration(milliseconds: 200),
            width: 40,
            height: 22,
            decoration: BoxDecoration(
              color:
                  value ? (accentColor ?? AppTheme.primary) : AppTheme.border,
              borderRadius: BorderRadius.circular(11),
            ),
            child: AnimatedAlign(
              duration: Duration(milliseconds: 200),
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                margin: const EdgeInsets.all(2),
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StyledTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData prefix;
  final bool monospace;

  const _StyledTextField({
    required this.controller,
    required this.hint,
    required this.prefix,
    this.monospace = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Icon(prefix, size: 16, color: AppTheme.textMuted),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              style: monospace
                  ? GoogleFonts.ibmPlexMono(
                      fontSize: 13,
                      color: AppTheme.textPrimary,
                    )
                  : GoogleFonts.ibmPlexSans(
                      fontSize: 13,
                      color: AppTheme.textPrimary,
                    ),
              decoration: InputDecoration(
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                hintText: hint,
                hintStyle: monospace
                    ? GoogleFonts.ibmPlexMono(
                        fontSize: 13,
                        color: AppTheme.textMuted,
                      )
                    : GoogleFonts.ibmPlexSans(
                        fontSize: 13,
                        color: AppTheme.textMuted,
                      ),
                filled: false,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickPathRow extends StatelessWidget {
  final List<String> paths;
  final ValueChanged<String> onSelect;

  const _QuickPathRow({required this.paths, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: paths.map((p) {
          return GestureDetector(
            onTap: () => onSelect(p),
            child: Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppTheme.border),
              ),
              child: Text(
                p,
                style: GoogleFonts.ibmPlexMono(
                  fontSize: 11,
                  color: AppTheme.textSecondary,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _PolicyRow extends StatelessWidget {
  final String label, value;
  const _PolicyRow({required this.label, required this.value});

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
          Spacer(),
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
