import 'dart:convert';

import 'package:flutter/material.dart';

import '../../services/api_service.dart';

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
  final ApiService _api = ApiService();
  bool _sensitive = false;
  bool _loading = false;
  String? _status;

  @override
  void dispose() {
    _method.dispose();
    _params.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    Map<String, dynamic> params = {};
    if (_params.text.isNotEmpty) {
      try {
        params = jsonDecode(_params.text) as Map<String, dynamic>;
      } catch (_) {
        params = {};
      }
    }
    final result = await _api.sendCommand(
      deviceId: widget.deviceId,
      method: _method.text,
      params: params,
      sensitive: _sensitive,
      clientMessageId: DateTime.now().millisecondsSinceEpoch.toString(),
    );
    setState(() {
      _status = '${result.state} (${result.commandId})';
      _loading = false;
    });
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
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _loading ? null : _submit,
                child: Text(_loading ? 'Sending...' : 'Dispatch'),
              ),
              if (_status != null) Text('Status: $_status'),
            ],
          ),
        ),
      ),
    );
  }
}
