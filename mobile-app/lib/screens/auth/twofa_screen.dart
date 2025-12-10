import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../devices/device_list_screen.dart';

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

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _loading = true);
    await _api.verify2fa(
      userId: widget.userId,
      sessionId: widget.sessionId,
      code: _codeController.text,
    );
    if (mounted) {
      Navigator.pushReplacementNamed(context, DeviceListScreen.route);
    }
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Two-Factor Authentication')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
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
