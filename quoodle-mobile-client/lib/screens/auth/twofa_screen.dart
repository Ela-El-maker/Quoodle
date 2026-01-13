import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../services/session_store.dart';
import '../../utils/api_error_classifier.dart';
import '../devices/device_list_screen.dart';
import 'twofa_enroll_screen.dart';

class TwoFAScreen extends StatefulWidget {
  const TwoFAScreen({super.key, required this.userId, required this.sessionId});

  static const route = '/2fa';
  final String userId;
  final String sessionId;

  @override
  State<TwoFAScreen> createState() => _TwoFAScreenState();
}

class _TwoFAScreenState extends State<TwoFAScreen> {
  final _codeController = TextEditingController();
  final ApiService _api = ApiService();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final resp = await _api.verify2fa(
        userId: widget.userId,
        sessionId: widget.sessionId,
        code: _codeController.text,
      );

      await SessionStore.setAuth(
        userId: widget.userId,
        sessionId: widget.sessionId,
        jwt: resp['jwt'] as String?,
        refreshToken: resp['refresh_token'] as String?,
      );
      if (mounted) {
        Navigator.pushReplacementNamed(context, DeviceListScreen.route);
      }
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
      appBar: AppBar(title: const Text('Two-Factor Authentication')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (_error != null) ...[
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 12),
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _loading
                    ? null
                    : () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => TwoFAEnrollScreen(
                                userId: widget.userId,
                                sessionId: widget.sessionId),
                          ),
                        ),
                child: const Text('Set up 2FA (QR code)'),
              ),
            ),
            TextField(
              controller: _codeController,
              decoration: const InputDecoration(labelText: 'Code'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loading ? null : _submit,
              child: Text(_loading ? 'Verifying...' : 'Verify'),
            ),
          ],
        ),
      ),
    );
  }
}
