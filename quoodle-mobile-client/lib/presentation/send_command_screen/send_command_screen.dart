import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../routes/app_routes.dart';

// All supported command types
class CommandMethod {
  final String id;
  final String label;
  final String description;
  final IconData icon;
  final Color color;
  final bool sensitive;
  final String defaultParams;
  final String policyNote;

  const CommandMethod({
    required this.id,
    required this.label,
    required this.description,
    required this.icon,
    required this.color,
    this.sensitive = false,
    this.defaultParams = '{}',
    this.policyNote = 'Allowed for all operators.',
  });
}

const List<CommandMethod> kCommandMethods = [
  CommandMethod(
    id: 'policy_sync',
    label: 'Policy Sync',
    description: 'Force synchronise the device policy to the latest version.',
    icon: Icons.sync_rounded,
    color: AppTheme.primary,
    defaultParams: '{"force": true, "version": "latest"}',
    policyNote: 'Allowed for all operators. No approval required.',
  ),
  CommandMethod(
    id: 'collect_telemetry',
    label: 'Collect Telemetry',
    description: 'Trigger an immediate telemetry collection cycle.',
    icon: Icons.analytics_rounded,
    color: AppTheme.secondary,
    defaultParams:
        '{"metrics": ["cpu", "ram", "disk", "network", "processes"]}',
    policyNote: 'Allowed for all operators.',
  ),
  CommandMethod(
    id: 'lock_screen',
    label: 'Lock Screen',
    description: 'Immediately lock the device screen.',
    icon: Icons.lock_rounded,
    color: AppTheme.warning,
    defaultParams: '{"reason": "operator_initiated"}',
    policyNote: 'Requires operator role or above.',
  ),
  CommandMethod(
    id: 'screenshot_capture',
    label: 'Screenshot',
    description: 'Capture a screenshot of the current screen.',
    icon: Icons.screenshot_rounded,
    color: AppTheme.error,
    sensitive: true,
    defaultParams: '{"display": 0, "quality": "high"}',
    policyNote: 'SENSITIVE — Requires admin approval. Logged to audit trail.',
  ),
  CommandMethod(
    id: 'process_list',
    label: 'Process List',
    description: 'Retrieve the list of running processes with resource usage.',
    icon: Icons.account_tree_rounded,
    color: AppTheme.primary,
    defaultParams: '{"sort_by": "cpu", "limit": 50}',
    policyNote: 'Allowed for all operators.',
  ),
  CommandMethod(
    id: 'system_info',
    label: 'System Info',
    description:
        'Collect full system information including hardware and OS details.',
    icon: Icons.info_outline_rounded,
    color: AppTheme.secondary,
    defaultParams: '{"include": ["hardware", "os", "network", "storage"]}',
    policyNote: 'Allowed for all operators.',
  ),
  CommandMethod(
    id: 'running_apps',
    label: 'Running Apps',
    description: 'List all currently running applications.',
    icon: Icons.apps_rounded,
    color: AppTheme.primary,
    defaultParams: '{"include_background": true}',
    policyNote: 'Allowed for all operators.',
  ),
  CommandMethod(
    id: 'filesystem',
    label: 'Filesystem',
    description: 'Browse or snapshot the device filesystem at a given path.',
    icon: Icons.folder_open_rounded,
    color: AppTheme.warning,
    sensitive: true,
    defaultParams: '{"path": "/", "depth": 2, "include_hidden": false}',
    policyNote: 'SENSITIVE — Requires admin role. Full path access logged.',
  ),
  CommandMethod(
    id: 'network_info',
    label: 'Network Info',
    description: 'Retrieve network interfaces, connections, and DNS config.',
    icon: Icons.lan_rounded,
    color: AppTheme.secondary,
    defaultParams: '{"include_connections": true, "include_dns": true}',
    policyNote: 'Allowed for all operators.',
  ),
  CommandMethod(
    id: 'upload_file',
    label: 'Upload File',
    description: 'Upload a file from the device to the management server.',
    icon: Icons.upload_rounded,
    color: AppTheme.warning,
    sensitive: true,
    defaultParams: '{"path": "/path/to/file", "compress": true}',
    policyNote: 'SENSITIVE — Requires admin approval. File content is logged.',
  ),
  CommandMethod(
    id: 'create_file',
    label: 'Create File',
    description: 'Create a file on the device at the specified path.',
    icon: Icons.note_add_rounded,
    color: AppTheme.error,
    sensitive: true,
    defaultParams:
        '{"path": "/path/to/file", "content": "", "overwrite": false}',
    policyNote: 'SENSITIVE — Requires admin role. Creates audit entry.',
  ),
  CommandMethod(
    id: 'reboot',
    label: 'Reboot',
    description: 'Initiate a controlled device reboot.',
    icon: Icons.restart_alt_rounded,
    color: AppTheme.error,
    sensitive: true,
    defaultParams: '{"delay_seconds": 30, "force": false}',
    policyNote: 'SENSITIVE — Requires admin approval. Notifies assigned user.',
  ),
];

class SendCommandScreen extends StatefulWidget {
  const SendCommandScreen({super.key});

  @override
  State<SendCommandScreen> createState() => _SendCommandScreenState();
}

class _SendCommandScreenState extends State<SendCommandScreen> {
  CommandMethod _selectedMethod = kCommandMethods.first;
  late TextEditingController _paramsController;
  bool _sensitiveOverride = false;
  bool _showPolicyPanel = true;
  bool _jsonValid = true;
  String _jsonError = '';
  bool _submitting = false;

  // 2FA state
  bool _show2FA = false;
  final TextEditingController _otpController = TextEditingController();
  bool _otpError = false;

  @override
  void initState() {
    super.initState();
    _paramsController = TextEditingController(
      text: _selectedMethod.defaultParams,
    );
    _paramsController.addListener(_validateJson);
  }

  @override
  void dispose() {
    _paramsController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  void _validateJson() {
    final text = _paramsController.text.trim();
    if (text.isEmpty) {
      setState(() {
        _jsonValid = true;
        _jsonError = '';
      });
      return;
    }
    // Basic JSON validation
    try {
      if (!text.startsWith('{') && !text.startsWith('[')) {
        throw Exception('Must start with { or [');
      }
      int depth = 0;
      for (final c in text.runes) {
        if (c == 123 || c == 91) depth++;
        if (c == 125 || c == 93) depth--;
        if (depth < 0) throw Exception('Unexpected closing bracket');
      }
      if (depth != 0) throw Exception('Unclosed brackets');
      setState(() {
        _jsonValid = true;
        _jsonError = '';
      });
    } catch (e) {
      setState(() {
        _jsonValid = false;
        _jsonError = e.toString();
      });
    }
  }

  void _selectMethod(CommandMethod method) {
    setState(() {
      _selectedMethod = method;
      _paramsController.text = method.defaultParams;
      _sensitiveOverride = false;
    });
  }

  bool get _requiresSensitiveConfirm =>
      _selectedMethod.sensitive && !_sensitiveOverride;

  void _onSubmitTap() {
    if (!_jsonValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Fix JSON errors before submitting',
            style: GoogleFonts.ibmPlexSans(fontSize: 13),
          ),
        ),
      );
      return;
    }
    if (_requiresSensitiveConfirm) {
      _showSensitiveWarning();
      return;
    }
    setState(() => _show2FA = true);
  }

  void _showSensitiveWarning() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surfaceVariant,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: AppTheme.warning,
              size: 22,
            ),
            const SizedBox(width: 10),
            Text(
              'Sensitive Command',
              style: GoogleFonts.ibmPlexSans(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
          ],
        ),
        content: Text(
          '${_selectedMethod.label} is a sensitive operation. ${_selectedMethod.policyNote}\n\nDo you want to proceed?',
          style: GoogleFonts.ibmPlexSans(
            fontSize: 13,
            color: AppTheme.textSecondary,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: GoogleFonts.ibmPlexSans(color: AppTheme.textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _sensitiveOverride = true;
                _show2FA = true;
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.warning,
              foregroundColor: Colors.black,
            ),
            child: Text(
              'Proceed',
              style: GoogleFonts.ibmPlexSans(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _verify2FA() async {
    final otp = _otpController.text.trim();
    if (otp.length < 6) {
      setState(() => _otpError = true);
      return;
    }
    setState(() {
      _submitting = true;
      _otpError = false;
    });
    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;
    setState(() => _submitting = false);
    // Navigate to command timeline
    Navigator.pushNamedAndRemoveUntil(
      context,
      AppRoutes.commandTimelineScreen,
      (route) =>
          route.settings.name == AppRoutes.deviceDetailScreen ||
          route.settings.name == AppRoutes.devicesScreen,
      arguments: {
        'method': _selectedMethod.id,
        'params': _paramsController.text,
        'sensitive': _selectedMethod.sensitive,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
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
              'Send Command',
              style: GoogleFonts.ibmPlexSans(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
            Text(
              'WKS-FINANCE-07',
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
                  const Icon(
                    Icons.security_rounded,
                    size: 12,
                    color: AppTheme.warning,
                  ),
                  const SizedBox(width: 4),
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
      body: _show2FA ? _build2FAView() : _buildCommandForm(),
      bottomNavigationBar: _show2FA ? null : _buildSubmitBar(),
    );
  }

  Widget _buildCommandForm() {
    return CustomScrollView(
      slivers: [
        // Method selector
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          sliver: SliverToBoxAdapter(child: _buildMethodSelector()),
        ),
        // JSON editor
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          sliver: SliverToBoxAdapter(child: _buildJsonEditor()),
        ),
        // Sensitivity toggle
        if (_selectedMethod.sensitive)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            sliver: SliverToBoxAdapter(child: _buildSensitivityToggle()),
          ),
        // Policy preview
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
          sliver: SliverToBoxAdapter(child: _buildPolicyPanel()),
        ),
      ],
    );
  }

  Widget _buildMethodSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'COMMAND METHOD',
          style: GoogleFonts.ibmPlexSans(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: AppTheme.textMuted,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 100,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: kCommandMethods.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final method = kCommandMethods[i];
              final selected = method.id == _selectedMethod.id;
              return GestureDetector(
                onTap: () => _selectMethod(method),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 90,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: selected
                        ? method.color.withAlpha(31)
                        : AppTheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: selected
                          ? method.color.withAlpha(153)
                          : AppTheme.border,
                      width: selected ? 1.5 : 1,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        method.icon,
                        size: 22,
                        color: selected ? method.color : AppTheme.textMuted,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        method.label,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.ibmPlexSans(
                          fontSize: 10,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: selected
                              ? method.color
                              : AppTheme.textSecondary,
                          height: 1.2,
                        ),
                      ),
                      if (method.sensitive) ...[
                        const SizedBox(height: 4),
                        Container(
                          width: 5,
                          height: 5,
                          decoration: const BoxDecoration(
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
        const SizedBox(height: 12),
        // Selected method description
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.surfaceVariant,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.border),
          ),
          child: Row(
            children: [
              Icon(
                _selectedMethod.icon,
                size: 18,
                color: _selectedMethod.color,
              ),
              const SizedBox(width: 10),
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

  Widget _buildJsonEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'PARAMETERS (JSON)',
              style: GoogleFonts.ibmPlexSans(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: AppTheme.textMuted,
                letterSpacing: 0.8,
              ),
            ),
            const Spacer(),
            if (!_jsonValid)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.errorMuted,
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: AppTheme.error.withAlpha(102)),
                ),
                child: Text(
                  'INVALID JSON',
                  style: GoogleFonts.ibmPlexMono(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.error,
                  ),
                ),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.secondaryMuted,
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: AppTheme.secondary.withAlpha(102)),
                ),
                child: Text(
                  'VALID',
                  style: GoogleFonts.ibmPlexMono(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.secondary,
                  ),
                ),
              ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                _paramsController.text = _selectedMethod.defaultParams;
              },
              child: Text(
                'Reset',
                style: GoogleFonts.ibmPlexSans(
                  fontSize: 11,
                  color: AppTheme.primary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _jsonValid ? AppTheme.border : AppTheme.error,
              width: _jsonValid ? 1 : 1.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Editor toolbar
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
                    Text(
                      'params.json',
                      style: GoogleFonts.ibmPlexMono(
                        fontSize: 11,
                        color: AppTheme.textMuted,
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () {
                        Clipboard.setData(
                          ClipboardData(text: _paramsController.text),
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Copied to clipboard',
                              style: GoogleFonts.ibmPlexSans(fontSize: 12),
                            ),
                          ),
                        );
                      },
                      child: const Icon(
                        Icons.copy_rounded,
                        size: 14,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              // Text editor
              TextField(
                controller: _paramsController,
                style: GoogleFonts.ibmPlexMono(
                  fontSize: 12,
                  color: AppTheme.secondary,
                  height: 1.6,
                ),
                maxLines: 8,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.all(12),
                  hintText: '{\n  "key": "value"\n}',
                  hintStyle: GoogleFonts.ibmPlexMono(
                    fontSize: 12,
                    color: AppTheme.textMuted,
                  ),
                  filled: false,
                ),
              ),
              if (!_jsonValid && _jsonError.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: const BoxDecoration(
                    border: Border(
                      top: BorderSide(color: AppTheme.borderLight),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        size: 12,
                        color: AppTheme.error,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _jsonError,
                          style: GoogleFonts.ibmPlexMono(
                            fontSize: 10,
                            color: AppTheme.error,
                          ),
                          overflow: TextOverflow.ellipsis,
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

  Widget _buildSensitivityToggle() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.warningMuted,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.warning.withAlpha(77)),
      ),
      child: Row(
        children: [
          const Icon(Icons.security_rounded, size: 18, color: AppTheme.warning),
          const SizedBox(width: 10),
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
          const SizedBox(width: 10),
          GestureDetector(
            onTap: () =>
                setState(() => _sensitiveOverride = !_sensitiveOverride),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 38,
              height: 20,
              decoration: BoxDecoration(
                color: _sensitiveOverride ? AppTheme.warning : AppTheme.border,
                borderRadius: BorderRadius.circular(10),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 200),
                alignment: _sensitiveOverride
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.all(2),
                  width: 16,
                  height: 16,
                  decoration: const BoxDecoration(
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

  Widget _buildPolicyPanel() {
    final isAllowed = !_selectedMethod.sensitive || _sensitiveOverride;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => setState(() => _showPolicyPanel = !_showPolicyPanel),
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
              const Spacer(),
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
          const SizedBox(height: 8),
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
                          const SizedBox(width: 5),
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
                    const Spacer(),
                    Text(
                      'Policy v1.0.4',
                      style: GoogleFonts.ibmPlexMono(
                        fontSize: 10,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  _selectedMethod.policyNote,
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 10),
                const Divider(color: AppTheme.borderLight, height: 1),
                const SizedBox(height: 10),
                _PolicyRow(label: 'Command', value: _selectedMethod.id),
                _PolicyRow(label: 'Initiator', value: 'L. Nakamura (operator)'),
                _PolicyRow(label: 'Target', value: 'WKS-FINANCE-07'),
                _PolicyRow(label: 'Audit', value: 'Full logging enabled'),
                _PolicyRow(label: 'TTL', value: '300s'),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _build2FAView() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppTheme.primaryDim,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.primary.withAlpha(102)),
            ),
            child: const Icon(
              Icons.shield_rounded,
              color: AppTheme.primary,
              size: 26,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            '2FA Verification',
            style: GoogleFonts.ibmPlexSans(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Enter the 6-digit code from your authenticator app to authorise this command.',
            style: GoogleFonts.ibmPlexSans(
              fontSize: 13,
              color: AppTheme.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          // Command summary
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(
              children: [
                Icon(
                  _selectedMethod.icon,
                  size: 18,
                  color: _selectedMethod.color,
                ),
                const SizedBox(width: 10),
                Column(
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
                      'WKS-FINANCE-07',
                      style: GoogleFonts.ibmPlexMono(
                        fontSize: 10,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                if (_selectedMethod.sensitive)
                  const Icon(
                    Icons.security_rounded,
                    size: 14,
                    color: AppTheme.warning,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'VERIFICATION CODE',
            style: GoogleFonts.ibmPlexSans(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppTheme.textMuted,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _otpController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            style: GoogleFonts.ibmPlexMono(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
              letterSpacing: 8,
            ),
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              counterText: '',
              hintText: '000000',
              hintStyle: GoogleFonts.ibmPlexMono(
                fontSize: 24,
                color: AppTheme.textMuted,
                letterSpacing: 8,
              ),
              errorText: _otpError ? 'Enter a valid 6-digit code' : null,
            ),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => setState(() => _otpError = false),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _submitting ? null : _verify2FA,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.black,
                      ),
                    )
                  : Text(
                      'Verify & Submit',
                      style: GoogleFonts.ibmPlexSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: () => setState(() {
                _show2FA = false;
                _otpController.clear();
                _otpError = false;
              }),
              child: Text(
                'Back to Command',
                style: GoogleFonts.ibmPlexSans(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(top: BorderSide(color: AppTheme.borderLight)),
      ),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _onSubmitTap,
          icon: Icon(_selectedMethod.icon, size: 18),
          label: Text(
            'Send ${_selectedMethod.label}',
            style: GoogleFonts.ibmPlexSans(
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: _selectedMethod.sensitive
                ? AppTheme.warning
                : AppTheme.primary,
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
