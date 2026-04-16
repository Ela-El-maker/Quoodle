import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:secure_device_control/app/di/providers.dart';
import 'package:secure_device_control/app/router/app_navigator.dart';
import 'package:secure_device_control/core/network/endpoints.dart';
import 'package:secure_device_control/models/qr_pairing_data.dart';
import '../../theme/app_theme.dart';

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
    final candidate = _parsePairingCandidate(token);
    if (candidate == null) {
      _resumeScanning();
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PairingConfirmationDialog(
        candidate: candidate,
        onConfirm: () async {
          await _confirmPairing(candidate);
        },
        onSuccess: () {
          Navigator.maybePop(context); // close dialog
          _navigateToDeviceDetail(candidate.rawToken);
        },
        onCancel: () => _resumeScanning(closeDialog: true),
      ),
    );
  }

  _PairingCandidate? _parsePairingCandidate(String rawToken) {
    final trimmed = rawToken.trim();
    if (trimmed.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Scanned value is empty.')),
      );
      return null;
    }

    try {
      final qrData = QrPairingData.fromRawString(trimmed);
      return _PairingCandidate(
        rawToken: trimmed,
        displayToken: qrData.pairToken ?? qrData.pairSessionId,
        pairToken: qrData.pairToken,
        pairSessionId: qrData.pairSessionId.trim().isEmpty
            ? null
            : qrData.pairSessionId.trim(),
        deviceId: qrData.deviceId,
        sourceLabel: 'QR payload',
      );
    } on QrParseException {
      return _PairingCandidate(
        rawToken: trimmed,
        displayToken: trimmed,
        pairToken: trimmed,
        pairSessionId: null,
        deviceId: null,
        sourceLabel: 'Manual token',
      );
    }
  }

  Future<void> _confirmPairing(_PairingCandidate candidate) async {
    final container = ProviderScope.containerOf(context, listen: false);
    final apiClient = container.read(apiClientProvider);

    var pairToken = candidate.pairToken?.trim() ?? '';
    final pairSessionId = candidate.pairSessionId?.trim();
    if (pairToken.isEmpty) {
      if (pairSessionId == null || pairSessionId.isEmpty) {
        throw Exception('QR code is missing pairing credentials.');
      }

      pairToken = await _resolvePairTokenFromSession(apiClient, pairSessionId);
      if (pairToken.isEmpty) {
        throw Exception(
          'Pair token not ready yet. Keep Agent UI on Pair screen and scan again.',
        );
      }
    }

    final payload = <String, dynamic>{
      'pair_token': pairToken,
    };
    if (pairSessionId != null && pairSessionId.isNotEmpty) {
      payload['pair_session_id'] = pairSessionId;
    }

    try {
      final response = await apiClient.post(Endpoints.pairConfirm, data: payload);
      final status = (response['status'] ?? '').toString().toLowerCase();
      if (status.isNotEmpty && status != 'ok') {
        throw Exception(response['reason']?.toString() ?? response['message']?.toString() ?? status);
      }
    } on DioException catch (error) {
      final data = error.response?.data;
      final message = _extractErrorMessage(data) ??
          'Pairing failed (${error.response?.statusCode ?? 'network_error'})';
      throw Exception(message);
    }
  }

  String? _extractErrorMessage(dynamic data) {
    if (data is Map<String, dynamic>) {
      final reason = data['reason']?.toString().trim() ?? '';
      final message = data['message']?.toString().trim() ?? '';
      final status = data['status']?.toString().trim() ?? '';
      if (reason.isNotEmpty && message.isNotEmpty) return '$reason: $message';
      if (reason.isNotEmpty) return reason;
      if (message.isNotEmpty) return message;
      if (status.isNotEmpty) return status;
    }
    if (data is String && data.trim().isNotEmpty) {
      return data.trim();
    }
    return null;
  }

  Future<String> _resolvePairTokenFromSession(
    dynamic apiClient,
    String pairSessionId,
  ) async {
    try {
      final response = await apiClient.get(
        Endpoints.pairSession(Uri.encodeComponent(pairSessionId)),
      );
      return (response['pair_token'] ?? '').toString().trim();
    } on DioException catch (error) {
      final data = error.response?.data;
      final message = _extractErrorMessage(data) ??
          'Unable to resolve pair session (${error.response?.statusCode ?? 'network_error'})';
      throw Exception(message);
    }
  }

  void _resumeScanning({bool closeDialog = false}) {
    if (closeDialog) {
      Navigator.maybePop(context);
    }
    setState(() {
      _processingCode = false;
      _scanning = true;
    });
  }

  void _navigateToDeviceDetail(String token) {
    AppNavigator.pushAndPruneUntil(
      context,
      AppRoute.deviceDetail,
      predicate: (route) =>
          route.settings.name == AppNavigator.pathFor(AppRoute.devices),
      arguments: {'pairedToken': token, 'fromPairing': true},
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (!_isManualEntry) _buildScannerView() else _buildManualEntryView(),
          _buildTopBar(),
          if (!_isManualEntry) _buildBottomControls(),
        ],
      ),
    );
  }

  Widget _buildScannerView() {
    return Stack(
      children: [
        MobileScanner(controller: _scannerController!, onDetect: _onDetect),
        CustomPaint(
          painter: _ScannerOverlayPainter(),
          child: const SizedBox.expand(),
        ),
        Positioned.fill(
          child: Center(
            child: SizedBox(
              width: 240,
              height: 240,
              child: AnimatedBuilder(
                animation: _scanLineAnim,
                builder: (_, __) => Stack(
                  children: [
                    ..._buildCornerBrackets(),
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
                'Scanning automatically...',
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

  Widget _buildManualEntryView() {
    return Container(
      color: AppTheme.background,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                24,
                48,
                24,
                24 + MediaQuery.of(context).viewInsets.bottom,
              ),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: ConstrainedBox(
                constraints:
                    BoxConstraints(minHeight: constraints.maxHeight - 72),
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
                          border: Border.all(
                              color: AppTheme.primary.withAlpha(102)),
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
                              final data =
                                  await Clipboard.getData('text/plain');
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
                          onPressed: () =>
                              setState(() => _isManualEntry = false),
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
            );
          },
        ),
      ),
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

  Widget _buildTopBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            _GlassButton(
              icon: Icons.arrow_back_ios_new_rounded,
              onTap: () => Navigator.maybePop(context),
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

class _PairingCandidate {
  const _PairingCandidate({
    required this.rawToken,
    required this.displayToken,
    required this.pairToken,
    required this.pairSessionId,
    required this.deviceId,
    required this.sourceLabel,
  });

  final String rawToken;
  final String displayToken;
  final String? pairToken;
  final String? pairSessionId;
  final String? deviceId;
  final String sourceLabel;
}

class _PairingConfirmationDialog extends StatefulWidget {
  const _PairingConfirmationDialog({
    required this.candidate,
    required this.onConfirm,
    required this.onSuccess,
    required this.onCancel,
  });

  final _PairingCandidate candidate;
  final Future<void> Function() onConfirm;
  final VoidCallback onSuccess;
  final VoidCallback onCancel;

  @override
  State<_PairingConfirmationDialog> createState() =>
      _PairingConfirmationDialogState();
}

class _PairingConfirmationDialogState extends State<_PairingConfirmationDialog> {
  bool _isPairing = false;
  bool _paired = false;
  String _error = '';

  Future<void> _confirmPairing() async {
    setState(() {
      _isPairing = true;
      _error = '';
    });

    try {
      await widget.onConfirm();
      if (!mounted) return;
      setState(() {
        _isPairing = false;
        _paired = true;
      });
      await Future.delayed(const Duration(milliseconds: 800));
      if (!mounted) return;
      widget.onSuccess();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isPairing = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
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
                    color:
                        _paired ? AppTheme.secondaryMuted : AppTheme.primaryDim,
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
                      widget.candidate.displayToken.length > 32
                          ? '${widget.candidate.displayToken.substring(0, 32)}...'
                          : widget.candidate.displayToken,
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
            ...<MapEntry<String, String>>[
              MapEntry('Source', widget.candidate.sourceLabel),
              if (widget.candidate.deviceId != null &&
                  widget.candidate.deviceId!.isNotEmpty)
                MapEntry('Device ID', widget.candidate.deviceId!),
              MapEntry(
                'Pair Session',
                widget.candidate.pairSessionId?.isNotEmpty == true
                    ? widget.candidate.pairSessionId!
                    : 'not provided',
              ),
            ].map(
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
                    Flexible(
                      child: Text(
                        e.value,
                        textAlign: TextAlign.right,
                        style: GoogleFonts.ibmPlexSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_error.isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.error.withAlpha(20),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.error.withAlpha(90)),
                ),
                child: Text(
                  _error,
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 11,
                    color: AppTheme.error,
                  ),
                ),
              ),
            ],
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
                      'Confirming pairing...',
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
