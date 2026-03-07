import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../models/device.dart';
import '../../services/api_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/api_error_classifier.dart';
import '../../utils/rbac.dart';
import '../../models/command.dart';
import '../../widgets/command_status_stepper.dart';
import '../../widgets/glass_card.dart';
import '../../services/session_store.dart';
import '../../widgets/offline_banner.dart';
import '../../widgets/permission_gate.dart';
import 'command_timeline_screen.dart';

class SendCommandScreen extends StatefulWidget {
  const SendCommandScreen({super.key, required this.deviceId});

  final String deviceId;
  static const route = '/commands/send';

  @override
  State<SendCommandScreen> createState() => _SendCommandScreenState();
}

class _SendCommandScreenState extends State<SendCommandScreen> {
  final _formKey = GlobalKey<FormState>();
  final _method = TextEditingController(text: 'lock_screen');
  final _params = TextEditingController(text: '{}');
  final _twoFactor = TextEditingController();
  final ApiService _api = ApiService();
  Future<Device>? _deviceFuture;
  Device? _device;
  bool _sensitive = false;
  bool _loading = false;
  String? _status;
  String? _policyDecisionText;
  String? _policyReason;
  bool _policyLoading = false;
  Timer? _poll;
  String? _lastCommandId;
  String? _commandState;
  String? _commandError;
  CommandState? _lastCommand;

  @override
  void dispose() {
    _poll?.cancel();
    _method.dispose();
    _params.dispose();
    _twoFactor.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _deviceFuture = _loadDevice();
  }

  Future<Device> _loadDevice() async {
    final device = await _api.fetchDevice(widget.deviceId);
    if (mounted) {
      setState(() => _device = device);
    }
    return device;
  }

  void _startPolling(String commandId) {
    _poll?.cancel();
    _lastCommandId = commandId;
    _poll = Timer.periodic(const Duration(seconds: 1), (_) async {
      try {
        final cmd = await _api.fetchCommand(commandId);
        if (!mounted) return;

        final done = (cmd.completedAt != null && cmd.completedAt!.isNotEmpty) ||
            (cmd.state == 'completed' || cmd.state == 'failed');

        setState(() {
          _status = '${cmd.state ?? '-'} (${cmd.commandId ?? commandId})';
          _commandState = cmd.state;
          _commandError = cmd.errorMessage;
          _lastCommand = cmd;
        });

        if (done) {
          _poll?.cancel();
        }
      } catch (_) {
        // Ignore transient errors.
      }
    });
  }

  Future<void> _submit() async {
    if (_formKey.currentState?.validate() != true) return;

    if (_sensitive && _twoFactor.text.isEmpty) {
      final code = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        builder: (context) {
          final ctrl = TextEditingController();
          return Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Enter TOTP code',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                const Text('Sensitive commands require a 6-digit code.'),
                const SizedBox(height: 12),
                TextField(
                  controller: ctrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '6-digit code'),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, ctrl.text),
                    child: const Text('Continue'),
                  ),
                ),
              ],
            ),
          );
        },
      );

      if (code == null || code.trim().isEmpty) return;
      _twoFactor.text = code.trim();
    }

    setState(() => _loading = true);
    Map<String, dynamic> params = {};
    if (_params.text.isNotEmpty) {
      try {
        params = jsonDecode(_params.text) as Map<String, dynamic>;
      } catch (_) {
        params = {};
      }
    }
    try {
      final result = await _api.sendCommand(
        deviceId: widget.deviceId,
        method: _method.text,
        params: params,
        sensitive: _sensitive,
        clientMessageId: DateTime.now().millisecondsSinceEpoch.toString(),
        twoFactorCode: _twoFactor.text.isEmpty ? null : _twoFactor.text,
      );
      setState(() {
        _status = '${result.state} (${result.commandId})';
        _commandState = result.state;
        _commandError = result.errorMessage;
        _lastCommand = result;
        _loading = false;
      });
      if (result.commandId != null && result.commandId!.isNotEmpty) {
        _startPolling(result.commandId!);
      }
    } on ApiException catch (e) {
      final view = classifyApiError(e);
      setState(() {
        _status = '${view.title}: ${view.message}';
        _commandError = view.message;
        _lastCommand = null;
        _loading = false;
      });

      if (_sensitive &&
          view.retryable &&
          (e.reason == 'invalid_2fa' || e.reason == '2fa_required')) {
        setState(() => _twoFactor.clear());
      }
    }
  }

  Future<void> _runPolicyPreview() async {
    final device = _device;
    if (device == null) return;
    final role = SessionStore.userRole ?? 'viewer';
    if (!Rbac.hasAtLeast(UserRole.admin)) {
      setState(() {
        _policyDecisionText = 'Unavailable';
        _policyReason = 'Admin role required for policy preview.';
      });
      return;
    }

    setState(() {
      _policyLoading = true;
      _policyDecisionText = null;
      _policyReason = null;
    });

    final params = jsonDecodeSafe(_params.text.isEmpty ? '{}' : _params.text);
    final reported = device.reportedPolicyHash ?? device.policyHash ?? '';
    final expected = device.policyHash ?? '';
    try {
      final result = await _api.evaluatePolicy(
        deviceId: device.deviceId,
        deviceLifecycleState: device.lifecycleState,
        method: _method.text,
        params: params,
        policyHash: reported.isNotEmpty ? reported : expected,
        expectedPolicyHash: expected.isNotEmpty ? expected : null,
        userId: SessionStore.userId ?? 'unknown',
        userRole: role,
        twoFactorVerified: _twoFactor.text.isNotEmpty,
      );
      setState(() {
        _policyDecisionText = (result['decision'] as String?) ?? 'unknown';
        _policyReason = (result['reason'] as String?) ?? 'unknown';
      });
    } catch (e) {
      setState(() {
        _policyDecisionText = 'error';
        _policyReason = e.toString();
      });
    } finally {
      setState(() => _policyLoading = false);
    }
  }

  String _riskTier() {
    final method = _method.text.toLowerCase();
    if (method == 'lock_screen' ||
        method == 'show_message' ||
        method == 'set_wallpaper' ||
        method == 'sysinfo') {
      return 'Low';
    }
    if (method.contains('wipe') || method.contains('shutdown')) {
      return 'Critical';
    }
    if (method.contains('reboot') ||
        method.contains('disable_input') ||
        method.contains('quarantine') ||
        method.contains('isolate')) {
      return 'High';
    }
    if (method.contains('download') ||
        method.contains('update') ||
        method.contains('logout') ||
        method.contains('sessions') ||
        method.contains('process') ||
        method.contains('network')) {
      return 'Medium';
    }
    return 'Low';
  }

  String _policyDecision() {
    if (_sensitive) return 'Requires confirmation';
    return 'Allowed';
  }

  @override
  Widget build(BuildContext context) {
    final riskTier = _riskTier();
    final riskColor = _riskColor(riskTier);
    return Scaffold(
      appBar: AppBar(title: const Text('Send command')),
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.backgroundGradient),
        child: FutureBuilder<Device>(
          future: _deviceFuture,
          builder: (context, snapshot) {
            final device = snapshot.data ?? _device;
            if (snapshot.connectionState == ConnectionState.waiting &&
                device == null) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError && device == null) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: GlassCard(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Unable to load device',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${snapshot.error}',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _deviceFuture = _loadDevice();
                            });
                          },
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            return PermissionGate(
              requiredRole: UserRole.operator,
              reason:
                  'Command execution is restricted to Operator or Admin roles.',
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                    const OfflineBanner(),
                    GlassCard(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('1. Choose the command',
                              style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 8),
                          Text(
                            'Configure one action carefully, then review its risk before sending.',
                            style: Theme.of(context)
                                .textTheme
                                .bodyLarge
                                ?.copyWith(color: AppColors.textSecondary),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _method,
                            decoration: const InputDecoration(
                                labelText: 'Command method'),
                            validator: (v) =>
                                v == null || v.isEmpty ? 'Required' : null,
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _params,
                            decoration: const InputDecoration(
                                labelText: 'Parameters (JSON)'),
                            maxLines: 4,
                          ),
                          const SizedBox(height: 12),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Sensitive command'),
                            subtitle: const Text(
                                'Requires a second confirmation and may require 2FA.'),
                            value: _sensitive,
                            onChanged: (v) => setState(() => _sensitive = v),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    GlassCard(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('2. Review risk',
                              style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: riskColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Risk: $riskTier',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelLarge
                                    ?.copyWith(color: riskColor),
                              ),
                              const Spacer(),
                              Text(
                                _policyDecision(),
                                style: Theme.of(context)
                                    .textTheme
                                    .labelLarge
                                    ?.copyWith(color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          if (device != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              'Compliance: ${device.complianceStatus ?? 'unknown'}',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelLarge
                                  ?.copyWith(color: AppColors.textSecondary),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Lifecycle: ${device.lifecycleState}',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelLarge
                                  ?.copyWith(color: AppColors.textSecondary),
                            ),
                            const SizedBox(height: 6),
                          ],
                          Text(
                            'Policy evaluation uses device compliance and your role to approve commands. Sensitive actions may require MFA.',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: AppColors.textSecondary),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              ElevatedButton.icon(
                                onPressed:
                                    _policyLoading ? null : _runPolicyPreview,
                                icon: const Icon(Icons.rule),
                                label: Text(_policyLoading
                                    ? 'Checking...'
                                    : 'Run policy preview'),
                              ),
                              if (_policyDecisionText != null)
                                Text(
                                  _policyDecisionText!,
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelLarge
                                      ?.copyWith(color: AppColors.textPrimary),
                                ),
                            ],
                          ),
                          if (_policyReason != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              _policyReason!,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: AppColors.textMuted),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    GlassCard(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('3. Review the payload',
                              style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceRaised,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              _jsonPreview(),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: AppColors.textSecondary),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_commandState != null)
                      GlassCard(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Execution status',
                                style: Theme.of(context).textTheme.titleLarge),
                            const SizedBox(height: 16),
                            CommandStatusStepper(
                              currentState: _commandState,
                              errorMessage: _commandError,
                            ),
                            if (_lastCommand != null) ...[
                              const SizedBox(height: 16),
                              _CommandResultView(command: _lastCommand!),
                              if (_lastCommand!.commandId != null &&
                                  _lastCommand!.commandId!.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: TextButton.icon(
                                    onPressed: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => CommandTimelineScreen(
                                          commandId: _lastCommand!.commandId!,
                                        ),
                                      ),
                                    ),
                                    icon: const Icon(Icons.timeline),
                                    label: const Text('View full timeline'),
                                  ),
                                ),
                              ],
                            ],
                          ],
                        ),
                      ),
                    if (_commandState != null) const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _loading ? null : _submit,
                      child:
                          Text(_loading ? 'Sending...' : '4. Confirm and send'),
                    ),
                    if (_status != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text('Status: $_status'),
                      ),
                    if (_lastCommandId != null)
                      TextButton(
                        onPressed: _loading
                            ? null
                            : () {
                                _startPolling(_lastCommandId!);
                              },
                        child: const Text('Refresh status'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  String _jsonPreview() {
    final params = _params.text.isEmpty ? '{}' : _params.text;
    return jsonEncode({
      'device_id': widget.deviceId,
      'method': _method.text,
      'params': jsonDecodeSafe(params),
      'sensitive': _sensitive,
    });
  }

  Map<String, dynamic> jsonDecodeSafe(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return {};
  }

  Color _riskColor(String tier) {
    switch (tier.toLowerCase()) {
      case 'critical':
        return AppColors.riskCritical;
      case 'high':
        return AppColors.riskHigh;
      case 'medium':
        return AppColors.riskMedium;
      default:
        return AppColors.riskLow;
    }
  }
}

class _CommandResultView extends StatelessWidget {
  const _CommandResultView({required this.command});

  final CommandState command;

  @override
  Widget build(BuildContext context) {
    final resultData = command.resultData;
    final hasResultData = resultData != null && resultData.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Returned result',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        _ResultRow(label: 'Command', value: command.method ?? '-'),
        _ResultRow(label: 'State', value: command.state ?? '-'),
        _ResultRow(label: 'Result', value: command.resultStatus ?? '-'),
        if (command.completedAt != null && command.completedAt!.isNotEmpty)
          _ResultRow(label: 'Completed', value: command.completedAt!),
        if (command.resultNotes != null && command.resultNotes!.isNotEmpty)
          _ResultRow(label: 'Notes', value: command.resultNotes!),
        if (command.errorMessage != null && command.errorMessage!.isNotEmpty)
          _ResultRow(label: 'Error', value: command.errorMessage!),
        if (hasResultData) ...[
          const SizedBox(height: 12),
          Text(
            'Payload',
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surfaceRaised,
              borderRadius: BorderRadius.circular(12),
            ),
            child: SelectableText(
              const JsonEncoder.withIndent('  ').convert(resultData),
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.textPrimary),
            ),
          ),
        ],
      ],
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(color: AppColors.textSecondary),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
