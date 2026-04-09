import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../routes/app_routes.dart';

class AuthenticationScreen extends StatefulWidget {
  const AuthenticationScreen({super.key});

  @override
  State<AuthenticationScreen> createState() => _AuthenticationScreenState();
}

class _AuthenticationScreenState extends State<AuthenticationScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _errorMessage;
  bool _show2FA = false;
  final _twoFAController = TextEditingController();

  // Particle animation
  late AnimationController _particleController;
  late List<_Particle> _particles;

  // Mock credentials
  static const _demoEmail = 'operator@quoodle.io';
  static const _demoPassword = 'Qd0pS3cur3!';

  @override
  void initState() {
    super.initState();
    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();
    _particles = List.generate(55, (_) => _Particle.random());
  }

  @override
  void dispose() {
    _particleController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _twoFAController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;
    // TODO: Replace with Riverpod/Bloc auth state for production
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    await Future.delayed(const Duration(milliseconds: 1200));

    if (_emailController.text.trim() == _demoEmail &&
        _passwordController.text == _demoPassword) {
      if (!_show2FA) {
        setState(() {
          _isLoading = false;
          _show2FA = true;
        });
        return;
      }
    }

    if (_show2FA && _twoFAController.text == '123456') {
      setState(() => _isLoading = false);
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(
          context,
          AppRoutes.dashboardScreen,
          (r) => false,
        );
      }
      return;
    }

    setState(() {
      _isLoading = false;
      _errorMessage = _show2FA
          ? 'Invalid verification code. Try: 123456'
          : 'Invalid credentials. Try: $_demoEmail / $_demoPassword';
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isTablet = size.width >= 600;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Stack(
        children: [
          // Particle field background
          AnimatedBuilder(
            animation: _particleController,
            builder: (_, __) {
              return CustomPaint(
                size: size,
                painter: _ParticleFieldPainter(
                  particles: _particles,
                  progress: _particleController.value,
                ),
              );
            },
          ),
          // Gradient overlay
          Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.topRight,
                radius: 1.2,
                colors: [
                  AppTheme.primary.withAlpha(15),
                  Colors.transparent,
                  AppTheme.background.withAlpha(102),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 32,
                ),
                child: SizedBox(
                  width: isTablet ? 480 : double.infinity,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildLogoSection(),
                      const SizedBox(height: 40),
                      _buildFormCard(),
                      const SizedBox(height: 16),
                      _buildDemoCredentials(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogoSection() {
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: AppTheme.primaryDim,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: AppTheme.primary.withAlpha(102),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primary.withAlpha(51),
                blurRadius: 24,
                spreadRadius: 2,
              ),
            ],
          ),
          child: const Icon(
            Icons.shield_rounded,
            color: AppTheme.primary,
            size: 32,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Quoodle',
          style: GoogleFonts.ibmPlexSans(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Device Fleet Management Console',
          style: GoogleFonts.ibmPlexSans(
            fontSize: 13,
            fontWeight: FontWeight.w400,
            color: AppTheme.textMuted,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }

  Widget _buildFormCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.glassSurface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.border.withAlpha(153), width: 1),
          ),
          padding: const EdgeInsets.all(28),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _show2FA ? 'Two-Factor Authentication' : 'Sign In',
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _show2FA
                      ? 'Enter the 6-digit code from your authenticator app'
                      : 'Access your fleet management console',
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 13,
                    color: AppTheme.textMuted,
                  ),
                ),
                const SizedBox(height: 24),
                if (!_show2FA) ...[
                  _buildGlassField(
                    controller: _emailController,
                    label: 'Email Address',
                    hint: 'operator@company.io',
                    icon: Icons.alternate_email_rounded,
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Email is required';
                      if (!v.contains('@')) return 'Enter a valid email';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  _buildGlassField(
                    controller: _passwordController,
                    label: 'Password',
                    hint: '••••••••••',
                    icon: Icons.lock_outline_rounded,
                    obscureText: _obscurePassword,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        size: 18,
                        color: AppTheme.textMuted,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Password is required';
                      if (v.length < 6) return 'Password too short';
                      return null;
                    },
                  ),
                ] else ...[
                  _buildGlassField(
                    controller: _twoFAController,
                    label: 'Verification Code',
                    hint: '000000',
                    icon: Icons.pin_rounded,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    validator: (v) {
                      if (v == null || v.length != 6) {
                        return 'Enter 6-digit code';
                      }
                      return null;
                    },
                  ),
                ],
                if (_errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.errorMuted,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppTheme.error.withAlpha(102),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          color: AppTheme.error,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: GoogleFonts.ibmPlexSans(
                              fontSize: 12,
                              color: AppTheme.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                _buildSubmitButton(),
                if (_show2FA) ...[
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => setState(() {
                      _show2FA = false;
                      _errorMessage = null;
                    }),
                    child: Text(
                      'Back to login',
                      style: GoogleFonts.ibmPlexSans(
                        fontSize: 13,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGlassField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    bool obscureText = false,
    Widget? suffixIcon,
    String? Function(String?)? validator,
    int? maxLength,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.ibmPlexSans(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          maxLength: maxLength,
          style: GoogleFonts.ibmPlexSans(
            fontSize: 14,
            color: AppTheme.textPrimary,
          ),
          decoration: InputDecoration(
            hintText: hint,
            counterText: '',
            prefixIcon: Icon(icon, size: 18, color: AppTheme.textMuted),
            suffixIcon: suffixIcon,
          ),
          validator: validator,
        ),
      ],
    );
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      height: 48,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _handleLogin,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primary,
          foregroundColor: Colors.black,
          disabledBackgroundColor: AppTheme.primaryMuted,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.black,
                  ),
                )
              : Text(
                  _show2FA ? 'Verify Code' : 'Sign In',
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildDemoCredentials() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.primary.withAlpha(15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary.withAlpha(51), width: 1),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: AppTheme.primary,
            size: 16,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: GoogleFonts.ibmPlexSans(
                  fontSize: 11.5,
                  color: AppTheme.textMuted,
                ),
                children: [
                  const TextSpan(text: 'Demo  '),
                  TextSpan(
                    text: _demoEmail,
                    style: GoogleFonts.ibmPlexMono(
                      fontSize: 11,
                      color: AppTheme.primary,
                    ),
                  ),
                  const TextSpan(text: '  ·  '),
                  TextSpan(
                    text: _demoPassword,
                    style: GoogleFonts.ibmPlexMono(
                      fontSize: 11,
                      color: AppTheme.primary,
                    ),
                  ),
                  const TextSpan(text: '  ·  2FA: '),
                  TextSpan(
                    text: '123456',
                    style: GoogleFonts.ibmPlexMono(
                      fontSize: 11,
                      color: AppTheme.secondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Particle System ──────────────────────────────────────────────────────────

class _Particle {
  double x, y, size, speed, opacity, angle;

  _Particle({
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.opacity,
    required this.angle,
  });

  factory _Particle.random() {
    final rng = math.Random();
    return _Particle(
      x: rng.nextDouble(),
      y: rng.nextDouble(),
      size: rng.nextDouble() * 2.5 + 0.5,
      speed: rng.nextDouble() * 0.008 + 0.002,
      opacity: rng.nextDouble() * 0.5 + 0.1,
      angle: rng.nextDouble() * math.pi * 2,
    );
  }
}

class _ParticleFieldPainter extends CustomPainter {
  final List<_Particle> particles;
  final double progress;

  _ParticleFieldPainter({required this.particles, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final px = (p.x + math.cos(p.angle) * p.speed * progress * 50) % 1.0;
      final py = (p.y + math.sin(p.angle) * p.speed * progress * 50) % 1.0;
      final paint = Paint()
        ..color = AppTheme.primary.withOpacity(p.opacity * 0.6)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(
        Offset(px * size.width, py * size.height),
        p.size,
        paint,
      );
    }
    // Connection lines
    final linePaint = Paint()
      ..color = AppTheme.primary.withAlpha(10)
      ..strokeWidth = 0.5;
    for (int i = 0; i < particles.length; i++) {
      for (int j = i + 1; j < particles.length; j++) {
        final p1 = particles[i];
        final p2 = particles[j];
        final dx = (p1.x - p2.x) * size.width;
        final dy = (p1.y - p2.y) * size.height;
        final dist = math.sqrt(dx * dx + dy * dy);
        if (dist < 100) {
          canvas.drawLine(
            Offset(p1.x * size.width, p1.y * size.height),
            Offset(p2.x * size.width, p2.y * size.height),
            linePaint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_ParticleFieldPainter old) => old.progress != progress;
}
