import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../services/session_store.dart';
import '../../theme/app_colors.dart';
import '../../utils/api_error_classifier.dart';
import '../../widgets/glass_card.dart';
import '../home/home_screen.dart';
import 'twofa_enroll_screen.dart';

class TwoFAScreen extends StatefulWidget {
  const TwoFAScreen({
    super.key,
    required this.userId,
    required this.sessionId,
    this.userRole,
  });

  static const route = '/2fa';
  final String userId;
  final String sessionId;
  final String? userRole;

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
        userRole: widget.userRole,
      );
      if (mounted) {
        Navigator.pushReplacementNamed(context, HomeScreen.route);
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Verification',
                          style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 8),
                      Text(
                        'Enter the 6-digit code from your authenticator app.',
                        style: Theme.of(context)
                            .textTheme
                            .bodyLarge
                            ?.copyWith(color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 24),
                      TextField(
                        controller: _codeController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            labelText: 'Verification code'),
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
                        child: Text(_loading ? 'Verifying...' : 'Continue'),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: _loading
                            ? null
                            : () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => TwoFAEnrollScreen(
                                      userId: widget.userId,
                                      sessionId: widget.sessionId,
                                    ),
                                  ),
                                ),
                        child: const Text('Set up 2FA'),
                      ),
                    ],
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
