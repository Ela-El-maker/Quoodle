import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../services/mobile_identity_service.dart';
import '../../services/session_store.dart';
import '../../theme/app_colors.dart';
import '../../widgets/glass_card.dart';
import '../home/home_screen.dart';

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
  String? _error;

  @override
  void dispose() {
    _displayName.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await _identity.ensureKeypair();
      final pub = await _identity.publicKeyBase64();
      final response = await _api.register(
        displayName: _displayName.text.trim(),
        email: _email.text.trim(),
        password: _password.text,
        pubkey: pub,
      );
      final role = response['user_role'] as String?;
      if (role != null && role.isNotEmpty) {
        await SessionStore.setRole(role);
      }
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, HomeScreen.route);
    } catch (error) {
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.backgroundGradient),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: GlassCard(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Create account',
                            style: Theme.of(context).textTheme.headlineSmall),
                        const SizedBox(height: 8),
                        Text(
                          'Your signing identity stays on this phone. We only register the public key.',
                          style: Theme.of(context)
                              .textTheme
                              .bodyLarge
                              ?.copyWith(color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 24),
                        TextFormField(
                          controller: _displayName,
                          decoration:
                              const InputDecoration(labelText: 'Display name'),
                          validator: (value) =>
                              value != null && value.trim().isNotEmpty
                                  ? null
                                  : 'Enter a name.',
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(labelText: 'Email'),
                          validator: (value) =>
                              value != null && value.contains('@')
                                  ? null
                                  : 'Enter a valid email address.',
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _password,
                          obscureText: true,
                          decoration:
                              const InputDecoration(labelText: 'Password'),
                          validator: (value) =>
                              value != null && value.length >= 8
                                  ? null
                                  : 'Use at least 8 characters.',
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 16),
                          Text(
                            _error!,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: AppColors.nonCompliant),
                          ),
                        ],
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: _loading ? null : _submit,
                          child:
                              Text(_loading ? 'Creating...' : 'Create account'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
