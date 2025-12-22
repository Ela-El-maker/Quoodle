import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../services/api_service.dart';
import '../../utils/api_error_classifier.dart';

class TwoFAEnrollScreen extends StatefulWidget {
  const TwoFAEnrollScreen(
      {super.key, required this.userId, required this.sessionId});

  final String userId;
  final String sessionId;

  @override
  State<TwoFAEnrollScreen> createState() => _TwoFAEnrollScreenState();
}

class _TwoFAEnrollScreenState extends State<TwoFAEnrollScreen> {
  final ApiService _api = ApiService();
  final TextEditingController _code = TextEditingController();

  bool _loading = false;
  String? _secret;
  String? _otpAuthUri;
  String? _error;

  @override
  void initState() {
    super.initState();
    _setup();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _setup() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final resp = await _api.setup2fa(
          userId: widget.userId, sessionId: widget.sessionId);
      setState(() {
        _secret = resp['secret'] as String?;
        _otpAuthUri = resp['otpauth_uri'] as String?;
      });
    } catch (e) {
      final view = classifyApiError(e);
      setState(() => _error = '${view.title}: ${view.message}');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _confirm() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await _api.confirm2fa(
          userId: widget.userId, sessionId: widget.sessionId, code: _code.text);
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      final view = classifyApiError(e);
      setState(() => _error = '${view.title}: ${view.message}');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Set up 2FA')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            if (_loading) const LinearProgressIndicator(),
            if (_error != null) ...[
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 12),
            ],
            const Text(
                'Scan this QR code with Google/Microsoft Authenticator.'),
            const SizedBox(height: 12),
            if (_otpAuthUri != null)
              Center(
                child: QrImageView(
                  data: _otpAuthUri!,
                  size: 220,
                ),
              )
            else
              const Center(child: Text('QR not ready')),
            const SizedBox(height: 12),
            if (_secret != null) SelectableText('Secret: $_secret'),
            const SizedBox(height: 16),
            TextField(
              controller: _code,
              decoration: const InputDecoration(
                labelText: 'Enter the 6-digit code to confirm',
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _loading ? null : _confirm,
              child: const Text('Confirm & Enable 2FA'),
            ),
            TextButton(
              onPressed: _loading ? null : _setup,
              child: const Text('Regenerate QR'),
            ),
          ],
        ),
      ),
    );
  }
}
