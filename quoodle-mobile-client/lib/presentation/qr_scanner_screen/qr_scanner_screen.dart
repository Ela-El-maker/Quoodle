import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../theme/app_theme.dart';
import '../../routes/app_routes.dart';

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen>
    with SingleTickerProviderStateMixin {
  MobileScannerController? _scannerController;
  bool _isManualEntry = false;
  bool _torchOn = false;
  bool _scanning = true;
  bool _processingCode = false;
  final TextEditingController _tokenController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  late AnimationController _scanLineController;
  late Animation<double> _scanLineAnim;

  @override
  void initState() {
    super.initState();
    _scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
    );
    _scanLineController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _scanLineAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _scanLineController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _scannerController?.dispose();
    _scanLineController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_processingCode || !_scanning) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode?.rawValue == null) return;
    final token = barcode!.rawValue!;
    setState(() {
      _processingCode = true;
      _scanning = false;
    });
    HapticFeedback.mediumImpact();
    _showPairingConfirmation(token);
  }

  void _submitManualToken() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final token = _tokenController.text.trim();
    _showPairingConfirmation(token);
  }

  void _showPairingConfirmation(String token) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PairingConfirmationDialog(
        token: token,
        onConfirm: () {
          Navigator.pop(context); // close dialog
          _navigateToDeviceDetail(token);
        },
        onCancel: () {
          Navigator.pop(context);
          setState(() {
            _processingCode = false;
            _scanning = true;
          });
        },
      ),
    );
  }

  void _navigateToDeviceDetail(String token) {
    Navigator.pushNamedAndRemoveUntil(
      context,
      AppRoutes.deviceDetailScreen,
      (route) => route.settings.name == AppRoutes.devicesScreen,
      arguments: {'pairedToken': token, 'fromPairing': true},
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera / Manual toggle
          if (!_isManualEntry) _buildScannerView() else _buildManualEntryView(),
          // Top bar
          _buildTopBar(),
          // Bottom controls
          if (!_isManualEntry) _buildBottomControls(),
        ],
      ),
    );
  }

  Widget _buildScannerView() {
    return Stack(
      children: [
        // Camera feed
        MobileScanner(controller: _scannerController!, onDetect: _onDetect),
        // Dark overlay with cutout
        CustomPaint(
          painter: _ScannerOverlayPainter(),
          child: const SizedBox.expand(),
        ),
        // Scan line animation
        Positioned.fill(
          child: Center(
            child: SizedBox(
              width: 240,
              height: 240,
              child: AnimatedBuilder(
                animation: _scanLineAnim,
                builder: (_, __) => Stack(
                  children: [
                    // Corner brackets
                    ..._buildCornerBrackets(),
                    // Scan line
                    Positioned(
                      top: _scanLineAnim.value * 220,
                      left: 0,
                      right: 0,
                      child: Container(
                        height: 2,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.transparent,
                              AppTheme.primary,
                              AppTheme.primary,
                              Colors.transparent,
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.primary.withAlpha(102),
                              blurRadius: 6,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Instruction text
        Positioned(
          bottom: 160,
          left: 0,
          right: 0,
          child: Column(
            children: [
              Text(
                'Align QR code within the frame',
                textAlign: TextAlign.center,
                style: GoogleFonts.ibmPlexSans(
                  fontSize: 14,
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Scanning automatically…',
                textAlign: TextAlign.center,
                style: GoogleFonts.ibmPlexSans(
                  fontSize: 12,
                  color: Colors.white54,
                ),
              ),
            ],
          ),
        ),
        if (_processingCode)
          Container(
            color: Colors.black54,
            child: const Center(
              child: CircularProgressIndicator(color: AppTheme.primary),
            ),
          ),
      ],
    );
  }

  List<Widget> _buildCornerBrackets() {
    const size = 24.0;
    const thickness = 3.0;
    final color = AppTheme.primary;
    return [
      // Top-left
      Positioned(
        top: 0,
        left: 0,
        child: _Corner(
          size: size,
          thickness: thickness,
          color: color,
          top: true,
          left: true,
        ),
      ),
      // Top-right
      Positioned(
        top: 0,
        right: 0,
        child: _Corner(
          size: size,
          thickness: thickness,
          color: color,
          top: true,
          left: false,
        ),
      ),
      // Bottom-left
      Positioned(
        bottom: 0,
        left: 0,
        child: _Corner(
          size: size,
          thickness: thickness,
          color: color,
          top: false,
          left: true,
        ),
      ),
      // Bottom-right
      Positioned(
        bottom: 0,
        right: 0,
        child: _Corner(
          size: size,
          thickness: thickness,
          color: color,
          top: false,
          left: false,
        ),
      ),
    ];
  }

  Widget _buildManualEntryView() {
    return Container(
      color: AppTheme.background,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 80, 24, 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryDim,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.primary.withAlpha(102)),
                  ),
                  child: const Icon(
                    Icons.keyboard_rounded,
                    color: AppTheme.primary,
                    size: 26,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Manual Token Entry',
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Enter the pairing token from the device\'s agent dashboard or enrollment email.',
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  'PAIRING TOKEN',
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textMuted,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _tokenController,
                  style: GoogleFonts.ibmPlexMono(
                    fontSize: 14,
                    color: AppTheme.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: 'e.g. QDL-XXXX-XXXX-XXXX',
                    hintStyle: GoogleFonts.ibmPlexMono(
                      fontSize: 13,
                      color: AppTheme.textMuted,
                    ),
                    prefixIcon: const Icon(
                      Icons.vpn_key_rounded,
                      size: 18,
                      color: AppTheme.textMuted,
                    ),
                    suffixIcon: IconButton(
                      icon: const Icon(
                        Icons.paste_rounded,
                        size: 18,
                        color: AppTheme.textMuted,
                      ),
                      onPressed: () async {
                        final data = await Clipboard.getData('text/plain');
                        if (data?.text != null) {
                          _tokenController.text = data!.text!;
                        }
                      },
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Token is required';
                    }
                    if (v.trim().length < 8) {
                      return 'Token must be at least 8 characters';
                    }
                    return null;
                  },
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submitManualToken(),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _submitManualToken,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'Pair Device',
                      style: GoogleFonts.ibmPlexSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: TextButton.icon(
                    onPressed: () => setState(() => _isManualEntry = false),
                    icon: const Icon(
                      Icons.qr_code_scanner_rounded,
                      size: 16,
                      color: AppTheme.primary,
                    ),
                    label: Text(
                      'Switch to QR Scanner',
                      style: GoogleFonts.ibmPlexSans(
                        fontSize: 13,
                        color: AppTheme.primary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            _GlassButton(
              icon: Icons.arrow_back_ios_new_rounded,
              onTap: () => Navigator.pop(context),
            ),
            const Spacer(),
            Text(
              'Pair Device',
              style: GoogleFonts.ibmPlexSans(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const Spacer(),
            _GlassButton(
              icon: _isManualEntry
                  ? Icons.qr_code_scanner_rounded
                  : Icons.keyboard_rounded,
              onTap: () => setState(() => _isManualEntry = !_isManualEntry),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomControls() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 48),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Colors.black.withAlpha(230), Colors.transparent],
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _ControlButton(
              icon: _torchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
              label: 'Torch',
              active: _torchOn,
              onTap: () {
                setState(() => _torchOn = !_torchOn);
                _scannerController?.toggleTorch();
              },
            ),
            _ControlButton(
              icon: Icons.keyboard_rounded,
              label: 'Manual',
              active: false,
              onTap: () => setState(() => _isManualEntry = true),
            ),
            _ControlButton(
              icon: Icons.flip_camera_ios_rounded,
              label: 'Flip',
              active: false,
              onTap: () => _scannerController?.switchCamera(),
            ),
          ],
        ),
      ),
    );
  }
}

class _Corner extends StatelessWidget {
  final double size, thickness;
  final Color color;
  final bool top, left;
  const _Corner({
    required this.size,
    required this.thickness,
    required this.color,
    required this.top,
    required this.left,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _CornerPainter(
          color: color,
          thickness: thickness,
          top: top,
          left: left,
        ),
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  final Color color;
  final double thickness;
  final bool top, left;
  _CornerPainter({
    required this.color,
    required this.thickness,
    required this.top,
    required this.left,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = thickness
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final path = Path();
    if (top && left) {
      path.moveTo(0, size.height);
      path.lineTo(0, 0);
      path.lineTo(size.width, 0);
    } else if (top && !left) {
      path.moveTo(0, 0);
      path.lineTo(size.width, 0);
      path.lineTo(size.width, size.height);
    } else if (!top && left) {
      path.moveTo(0, 0);
      path.lineTo(0, size.height);
      path.lineTo(size.width, size.height);
    } else {
      path.moveTo(0, size.height);
      path.lineTo(size.width, size.height);
      path.lineTo(size.width, 0);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ScannerOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withAlpha(153);
    const cutoutSize = 240.0;
    final cutoutLeft = (size.width - cutoutSize) / 2;
    final cutoutTop = (size.height - cutoutSize) / 2;
    final cutoutRect = Rect.fromLTWH(
      cutoutLeft,
      cutoutTop,
      cutoutSize,
      cutoutSize,
    );
    final fullRect = Rect.fromLTWH(0, 0, size.width, size.height);
    final path = Path()
      ..addRect(fullRect)
      ..addRRect(
        RRect.fromRectAndRadius(cutoutRect, const Radius.circular(12)),
      );
    canvas.drawPath(path, paint..blendMode = BlendMode.srcOver);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _GlassButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _GlassButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.black45,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white24),
        ),
        child: Icon(icon, size: 18, color: Colors.white),
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _ControlButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: active ? AppTheme.primary.withAlpha(51) : Colors.white12,
              shape: BoxShape.circle,
              border: Border.all(
                color: active ? AppTheme.primary : Colors.white24,
              ),
            ),
            child: Icon(
              icon,
              size: 22,
              color: active ? AppTheme.primary : Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: GoogleFonts.ibmPlexSans(fontSize: 11, color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

class _PairingConfirmationDialog extends StatefulWidget {
  final String token;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  const _PairingConfirmationDialog({
    required this.token,
    required this.onConfirm,
    required this.onCancel,
  });

  @override
  State<_PairingConfirmationDialog> createState() =>
      _PairingConfirmationDialogState();
}

class _PairingConfirmationDialogState
    extends State<_PairingConfirmationDialog> {
  bool _isPairing = false;
  bool _paired = false;

  // Simulated device info from token
  final Map<String, String> _deviceInfo = {
    'Device Name': 'WKS-NEW-042',
    'OS': 'Windows 11 Pro',
    'Agent Version': '2.1.4',
    'IP Address': '10.0.5.42',
    'Location': 'HQ – Floor 2',
  };

  Future<void> _confirmPairing() async {
    setState(() => _isPairing = true);
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    setState(() {
      _isPairing = false;
      _paired = true;
    });
    await Future.delayed(const Duration(milliseconds: 800));
    widget.onConfirm();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.surfaceVariant,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _paired
                        ? AppTheme.secondaryMuted
                        : AppTheme.primaryDim,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _paired
                          ? AppTheme.secondary.withAlpha(102)
                          : AppTheme.primary.withAlpha(102),
                    ),
                  ),
                  child: Icon(
                    _paired ? Icons.check_rounded : Icons.devices_rounded,
                    color: _paired ? AppTheme.secondary : AppTheme.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _paired ? 'Device Paired!' : 'Confirm Pairing',
                        style: GoogleFonts.ibmPlexSans(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      Text(
                        _paired
                            ? 'Successfully enrolled'
                            : 'Review device details',
                        style: GoogleFonts.ibmPlexSans(
                          fontSize: 12,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // Token display
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.borderLight),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.vpn_key_rounded,
                    size: 14,
                    color: AppTheme.textMuted,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.token.length > 32
                          ? '${widget.token.substring(0, 32)}…'
                          : widget.token,
                      style: GoogleFonts.ibmPlexMono(
                        fontSize: 11,
                        color: AppTheme.primary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Device info
            ..._deviceInfo.entries.map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Text(
                      e.key,
                      style: GoogleFonts.ibmPlexSans(
                        fontSize: 12,
                        color: AppTheme.textMuted,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      e.value,
                      style: GoogleFonts.ibmPlexSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            if (_isPairing)
              Center(
                child: Column(
                  children: [
                    const CircularProgressIndicator(
                      color: AppTheme.primary,
                      strokeWidth: 2,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Enrolling device…',
                      style: GoogleFonts.ibmPlexSans(
                        fontSize: 12,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              )
            else if (!_paired) ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _confirmPairing,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Confirm & Pair',
                    style: GoogleFonts.ibmPlexSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: widget.onCancel,
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.ibmPlexSans(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
