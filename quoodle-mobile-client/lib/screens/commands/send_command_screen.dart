import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../utils/api_error_classifier.dart';

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
  bool _sensitive = false;
  bool _loading = false;
  String? _status;
  Timer? _poll;
  String? _lastCommandId;

  @override
  void dispose() {
    _poll?.cancel();
    _method.dispose();
    _params.dispose();
    _twoFactor.dispose();
    super.dispose();
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
    if (!_formKey.currentState!.validate()) return;

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
        _loading = false;
      });
      if (result.commandId != null && result.commandId!.isNotEmpty) {
        _startPolling(result.commandId!);
      }
    } on ApiException catch (e) {
      final view = classifyApiError(e);
      setState(() {
        _status = '${view.title}: ${view.message}';
        _loading = false;
      });

      if (_sensitive &&
          view.retryable &&
          (e.reason == 'invalid_2fa' || e.reason == '2fa_required')) {
        setState(() => _twoFactor.clear());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Send Command')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _method,
                decoration: const InputDecoration(labelText: 'Method'),
                validator: (v) => v == null || v.isEmpty ? 'Required' : null,
              ),
              TextFormField(
                controller: _params,
                decoration: const InputDecoration(labelText: 'Params (JSON)'),
                maxLines: 3,
              ),
              SwitchListTile(
                title: const Text('Sensitive'),
                value: _sensitive,
                onChanged: (v) => setState(() => _sensitive = v),
              ),
              if (_sensitive)
                Row(
                  children: [
                    const Icon(Icons.shield),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _twoFactor.text.isEmpty
                            ? '2FA required (will prompt)'
                            : '2FA code entered',
                      ),
                    ),
                    TextButton(
                      onPressed: _loading
                          ? null
                          : () {
                              setState(() => _twoFactor.clear());
                            },
                      child: const Text('Clear'),
                    )
                  ],
                ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _loading ? null : _submit,
                child: Text(_loading ? 'Sending...' : 'Dispatch'),
              ),
              if (_status != null) Text('Status: $_status'),
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
  }
}
