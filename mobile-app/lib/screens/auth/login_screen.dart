import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../devices/device_list_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  static const route = '/login';

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _twoFactorController = TextEditingController();
  bool _isLoading = false;
  final ApiService _api = ApiService();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _twoFactorController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    await _api.login(
      email: _emailController.text,
      password: _passwordController.text,
      twoFactorCode: _twoFactorController.text.isEmpty ? null : _twoFactorController.text,
      deviceFingerprint: 'mobile-fingerprint-placeholder',
      pushToken: null,
    );
    if (mounted) {
      Navigator.pushReplacementNamed(context, DeviceListScreen.route);
    }
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(labelText: 'Email'),
                validator: (v) => v != null && v.contains('@') ? null : 'Enter valid email',
              ),
              TextFormField(
                controller: _passwordController,
                decoration: const InputDecoration(labelText: 'Password'),
                obscureText: true,
                validator: (v) => v != null && v.length >= 8 ? null : 'Min 8 chars',
              ),
              TextFormField(
                controller: _twoFactorController,
                decoration: const InputDecoration(labelText: '2FA Code (if required)'),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _submit,
                  child: Text(_isLoading ? 'Signing in...' : 'Login'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
