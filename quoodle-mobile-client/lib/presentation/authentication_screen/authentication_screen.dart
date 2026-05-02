import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:secure_device_control/features/auth/presentation/providers/auth_providers.dart';
import 'package:secure_device_control/features/auth/presentation/providers/auth_state.dart';

import '../../theme/app_theme.dart';

class AuthenticationScreen extends ConsumerStatefulWidget {
  const AuthenticationScreen({super.key});

  @override
  ConsumerState<AuthenticationScreen> createState() =>
      _AuthenticationScreenState();
}

class _AuthenticationScreenState extends ConsumerState<AuthenticationScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _otpController = TextEditingController();

  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 600),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _fadeController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _emailController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _handlePrimaryAction(bool isOtpStep) async {
    if (!_formKey.currentState!.validate()) return;

    final authController = ref.read(authControllerProvider.notifier);
    if (isOtpStep) {
      await authController.verifyEmailOtp(_otpController.text.trim());
      return;
    }

    await authController.requestEmailOtp(
      email: _emailController.text.trim(),
    );
  }

  Future<void> _handleGoogleSignIn() async {
    await ref.read(authControllerProvider.notifier).signInWithGoogle();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final isOtpStep = authState.requiresOtpCode;
    final isLoading = authState.isLoading;
    final errorMessage = authState.errorMessage;

    final size = MediaQuery.of(context).size;
    final isTablet = size.width >= 600;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: FadeTransition(
          opacity: _fadeAnimation,
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
                child: SizedBox(
                  width: isTablet ? 440 : double.infinity,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _buildLogoSection(),
                      SizedBox(height: 32),
                      _buildFormCard(
                        authState: authState,
                        isOtpStep: isOtpStep,
                        isLoading: isLoading,
                        errorMessage: errorMessage,
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

  Widget _buildLogoSection() {
    return Column(
      children: <Widget>[
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.border, width: 1),
          ),
          child: Icon(
            Icons.shield_rounded,
            color: AppTheme.primary,
            size: 28,
          ),
        ),
        SizedBox(height: 16),
        Text(
          'Quoodle',
          style: GoogleFonts.ibmPlexSans(
            fontSize: 28,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
            letterSpacing: -0.3,
          ),
        ),
        SizedBox(height: 4),
        Text(
          'Passwordless Operator Access',
          style: GoogleFonts.ibmPlexSans(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: AppTheme.textMuted,
          ),
        ),
      ],
    );
  }

  Widget _buildFormCard({
    required AuthSessionState authState,
    required bool isOtpStep,
    required bool isLoading,
    required String? errorMessage,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border, width: 1),
      ),
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              isOtpStep ? 'Verify Email Code' : 'Sign In',
              style: GoogleFonts.ibmPlexSans(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
            SizedBox(height: 4),
            Text(
              isOtpStep
                  ? 'Enter the one-time code sent to ${authState.pendingEmail ?? _emailController.text.trim()}.'
                  : 'Use Google Sign-In or receive a code via email.',
              style: GoogleFonts.ibmPlexSans(
                fontSize: 14,
                color: AppTheme.textMuted,
              ),
            ),
            SizedBox(height: 24),
            if (!isOtpStep) ...<Widget>[
              _buildField(
                controller: _emailController,
                label: 'Work Email',
                hint: 'operator@company.io',
                icon: Icons.alternate_email_rounded,
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  final email = value?.trim() ?? '';
                  if (email.isEmpty) return 'Email is required';
                  if (!email.contains('@')) return 'Enter a valid email';
                  return null;
                },
              ),
              SizedBox(height: 16),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed:
                      isLoading ? null : () => _handlePrimaryAction(isOtpStep),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.black,
                    disabledBackgroundColor: AppTheme.primaryDim,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                  ),
                  child: isLoading
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black,
                          ),
                        )
                      : Text(
                          'Send Email Code',
                          style: GoogleFonts.ibmPlexSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
              SizedBox(height: 12),
              _buildOrDivider(),
              SizedBox(height: 12),
              SizedBox(
                height: 48,
                child: OutlinedButton(
                  onPressed: isLoading ? null : _handleGoogleSignIn,
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: AppTheme.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceVariant,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: Text(
                            'G',
                            style: GoogleFonts.ibmPlexSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: 10),
                      Text(
                        'Continue with Google',
                        style: GoogleFonts.ibmPlexSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ] else ...<Widget>[
              _buildField(
                controller: _otpController,
                label: 'Verification Code',
                hint: '000000',
                icon: Icons.pin_outlined,
                keyboardType: TextInputType.number,
                maxLength: 6,
                validator: (value) {
                  final otp = value?.trim() ?? '';
                  if (otp.length != 6) return 'Enter 6-digit code';
                  return null;
                },
              ),
              SizedBox(height: 16),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed:
                      isLoading ? null : () => _handlePrimaryAction(isOtpStep),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.black,
                    disabledBackgroundColor: AppTheme.primaryDim,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                  ),
                  child: isLoading
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black,
                          ),
                        )
                      : Text(
                          'Verify and Sign In',
                          style: GoogleFonts.ibmPlexSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
              SizedBox(height: 8),
              TextButton(
                onPressed: isLoading
                    ? null
                    : () async {
                        final email = authState.pendingEmail ??
                            _emailController.text.trim();
                        if (email.isNotEmpty) {
                          await ref
                              .read(authControllerProvider.notifier)
                              .requestEmailOtp(email: email);
                        }
                      },
                child: Text(
                  'Resend code',
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
              TextButton(
                onPressed: isLoading
                    ? null
                    : () {
                        _otpController.clear();
                        ref
                            .read(authControllerProvider.notifier)
                            .resetToEmailStep();
                      },
                child: Text(
                  'Use another email',
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
            ],
            if (errorMessage != null && errorMessage.isNotEmpty) ...<Widget>[
              SizedBox(height: 12),
              _buildErrorBanner(errorMessage),
            ],
            if (isOtpStep &&
                authState.resendAfterSeconds != null &&
                authState.resendAfterSeconds! > 0) ...<Widget>[
              SizedBox(height: 10),
              Text(
                'Resend available in ~${authState.resendAfterSeconds}s',
                textAlign: TextAlign.center,
                style: GoogleFonts.ibmPlexSans(
                  fontSize: 12,
                  color: AppTheme.textMuted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    int? maxLength,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLength: maxLength,
      style: GoogleFonts.ibmPlexSans(fontSize: 14, color: AppTheme.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 18, color: AppTheme.textMuted),
        counterText: '',
        filled: true,
        fillColor: AppTheme.surfaceVariant,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppTheme.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppTheme.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppTheme.primary, width: 1),
        ),
      ),
      validator: validator,
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.errorMuted,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppTheme.error.withAlpha(80),
          width: 1,
        ),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.error_outline_rounded, size: 16, color: AppTheme.error),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.ibmPlexSans(
                fontSize: 12,
                color: AppTheme.error,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrDivider() {
    return Row(
      children: <Widget>[
        Expanded(
          child: Divider(color: AppTheme.border, thickness: 1),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            'or',
            style: GoogleFonts.ibmPlexSans(
              fontSize: 12,
              color: AppTheme.textMuted,
            ),
          ),
        ),
        Expanded(
          child: Divider(color: AppTheme.border, thickness: 1),
        ),
      ],
    );
  }
}
