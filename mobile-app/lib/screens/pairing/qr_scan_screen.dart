import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../devices/device_list_screen.dart';

class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  static const route = '/pairing/qr';

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final ApiService _api = ApiService();
  String? _pairSessionId;
  String? _pairToken;
  final _tokenController = TextEditingController();
  bool _loading = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final res = await _api.initPairing();
    setState(() {
      _pairSessionId = res['pair_session_id'] as String?;
      _pairToken = res['pair_token'] as String?;
      _tokenController.text = _pairToken ?? '';
    });
  }

  Future<void> _confirm() async {
    setState(() => _loading = true);
    final res = await _api.confirmPairing(pairToken: _tokenController.text, pairSessionId: _pairSessionId);
    setState(() {
      _status = res['status'] as String?;
      _loading = false;
    });
    if (res['status'] == 'ok' && mounted) {
      Navigator.pushReplacementNamed(context, DeviceListScreen.route);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pair Device')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Pair Session: ${_pairSessionId ?? '-'}'),
            const SizedBox(height: 8),
            TextField(
              controller: _tokenController,
              decoration: const InputDecoration(labelText: 'Pair Token'),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loading ? null : _confirm,
              child: Text(_loading ? 'Pairing...' : 'Confirm Pairing'),
            ),
            if (_status != null) Text('Status: $_status'),
          ],
        ),
      ),
    );
  }
}
