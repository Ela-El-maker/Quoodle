import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../services/mobile_identity_service.dart';
import '../devices/device_list_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  static const route = '/register';

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _displayName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final ApiService _api = ApiService();
  final MobileIdentityService _identity = MobileIdentityService();
  bool _loading = false;

  @override
  void dispose() {
    _displayName.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    await _identity.ensureKeypair();
    final pub = await _identity.publicKeyBase64();
    await _api.register(
      displayName: _displayName.text,
      email: _email.text,
      password: _password.text,
      pubkey: pub,
    );
    if (mounted) {
      Navigator.pushReplacementNamed(context, DeviceListScreen.route);
    }
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Account')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _displayName,
                decoration: const InputDecoration(labelText: 'Display Name'),
                validator: (v) => v != null && v.isNotEmpty ? null : 'Required',
              ),
              TextFormField(
                controller: _email,
                decoration: const InputDecoration(labelText: 'Email'),
                validator: (v) =>
                    v != null && v.contains('@') ? null : 'Enter valid email',
              ),
              TextFormField(
                controller: _password,
                decoration: const InputDecoration(labelText: 'Password'),
                obscureText: true,
                validator: (v) =>
                    v != null && v.length >= 8 ? null : 'Min 8 chars',
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loading ? null : _submit,
                child: Text(_loading ? 'Creating...' : 'Register'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
