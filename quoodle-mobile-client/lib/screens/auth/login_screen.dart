import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../services/mobile_identity_service.dart';
import '../../services/session_store.dart';
import '../../theme/app_colors.dart';
import '../../widgets/glass_card.dart';
import '../home/home_screen.dart';
import 'register_screen.dart';
import 'twofa_screen.dart';

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
  final ApiService _api = ApiService();
  final MobileIdentityService _identity = MobileIdentityService();
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _twoFactorController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await _identity.ensureKeypair();
      final deviceFingerprint = await _identity.deviceFingerprint();
      final response = await _api.login(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        twoFactorCode: _twoFactorController.text.trim().isEmpty
            ? null
            : _twoFactorController.text.trim(),
        deviceFingerprint: deviceFingerprint,
        pushToken: null,
      );

      final userId = response['user_id'] as String?;
      final sessionId = response['session_id'] as String?;
      final jwt = response['jwt'] as String?;
      final refresh = response['refresh_token'] as String?;
      final userRole = response['user_role'] as String?;
      if (userId != null && sessionId != null) {
        await SessionStore.setAuth(
          userId: userId,
          sessionId: sessionId,
          jwt: jwt,
          refreshToken: refresh,
          userRole: userRole,
        );
      }

      if (!mounted) return;
      if (response['two_factor_required'] == true) {
        Navigator.pushReplacementNamed(context, TwoFAScreen.route, arguments: {
          'user_id': response['user_id'],
          'session_id': response['session_id'],
          'user_role': userRole,
        });
      } else {
        Navigator.pushReplacementNamed(context, HomeScreen.route);
      }
    } catch (error) {
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
                        Text('Welcome back',
                            style: Theme.of(context).textTheme.headlineSmall),
                        const SizedBox(height: 8),
                        Text(
                          'Sign in to manage your devices securely.',
                          style: Theme.of(context)
                              .textTheme
                              .bodyLarge
                              ?.copyWith(color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 24),
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(labelText: 'Email'),
                          validator: (value) =>
                              value != null && value.contains('@')
                                  ? null
                                  : 'Enter a valid email address.',
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: true,
                          decoration:
                              const InputDecoration(labelText: 'Password'),
                          validator: (value) =>
                              value != null && value.length >= 8
                                  ? null
                                  : 'Use at least 8 characters.',
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _twoFactorController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'Verification code (optional)'),
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
                          onPressed: _isLoading ? null : _submit,
                          child: Text(_isLoading ? 'Signing in...' : 'Sign in'),
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: _isLoading
                              ? null
                              : () => Navigator.pushNamed(
                                  context, RegisterScreen.route),
                          child: const Text('Create account'),
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
