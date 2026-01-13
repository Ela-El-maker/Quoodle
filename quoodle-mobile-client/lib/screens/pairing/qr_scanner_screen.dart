import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../models/qr_pairing_data.dart';
import '../../services/api_service.dart';
import '../devices/device_list_screen.dart';

/// QR code scanning screen for device pairing.
///
/// Supports:
/// - Real camera scanning with mobile_scanner
/// - Manual token entry fallback
/// - Permission handling
/// - Flashlight toggle
/// - Camera switch (front/back)
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  static const route = '/pairing/qr';

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen>
    with WidgetsBindingObserver {
  final ApiService _api = ApiService();

  // Scanner controller
  MobileScannerController? _scannerController;

  // UI state
  bool _hasPermission = false;
  bool _permissionDenied = false;
  bool _isProcessing = false;
  bool _showManualEntry = false;
  bool _torchEnabled = false;
  String? _errorMessage;
  String? _successMessage;
  QrPairingData? _scannedData;

  // Manual entry
  final _manualTokenController = TextEditingController();
  final _manualSessionController = TextEditingController();

  // Debounce duplicate scans
  String? _lastScannedCode;
  DateTime? _lastScanTime;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scannerController?.dispose();
    _manualTokenController.dispose();
    _manualSessionController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Handle app lifecycle for camera resource management
    if (_scannerController == null) return;

    switch (state) {
      case AppLifecycleState.resumed:
        _scannerController?.start();
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        _scannerController?.stop();
        break;
      default:
        break;
    }
  }

  Future<void> _checkPermission() async {
    // Check camera permission
    final status = await Permission.camera.status;

    if (status.isGranted) {
      setState(() => _hasPermission = true);
      _initScanner();
    } else if (status.isDenied) {
      // Request permission
      final result = await Permission.camera.request();
      if (result.isGranted) {
        setState(() => _hasPermission = true);
        _initScanner();
      } else {
        setState(() => _permissionDenied = true);
      }
    } else if (status.isPermanentlyDenied) {
      setState(() => _permissionDenied = true);
    }
  }

  void _initScanner() {
    _scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      torchEnabled: false,
    );
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isProcessing || _scannedData != null) return;

    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final barcode = barcodes.first;
    final rawValue = barcode.rawValue;
    if (rawValue == null || rawValue.isEmpty) return;

    // Debounce: ignore same code within 2 seconds
    final now = DateTime.now();
    if (_lastScannedCode == rawValue &&
        _lastScanTime != null &&
        now.difference(_lastScanTime!).inSeconds < 2) {
      return;
    }
    _lastScannedCode = rawValue;
    _lastScanTime = now;

    // Haptic feedback on successful scan
    HapticFeedback.mediumImpact();

    _processQrCode(rawValue);
  }

  Future<void> _processQrCode(String rawValue) async {
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      // Parse QR data
      final pairingData = QrPairingData.fromRawString(rawValue);

      setState(() {
        _scannedData = pairingData;
      });

      // Pause scanner while confirming
      _scannerController?.stop();

      // Show confirmation dialog
      if (mounted) {
        final confirm = await _showConfirmDialog(pairingData);
        if (confirm == true) {
          await _confirmPairing(pairingData);
        } else {
          // User cancelled, resume scanning
          setState(() {
            _scannedData = null;
            _isProcessing = false;
          });
          _scannerController?.start();
        }
      }
    } on QrParseException catch (e) {
      setState(() {
        _errorMessage = e.message;
        _isProcessing = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to process QR code: $e';
        _isProcessing = false;
      });
    }
  }

  Future<bool?> _showConfirmDialog(QrPairingData data) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Pair Device?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Device ID: ${data.deviceId}'),
            if (data.deviceLabel != null) Text('Label: ${data.deviceLabel}'),
            const SizedBox(height: 8),
            const Text(
              'This will link the device to your account.',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Pair'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmPairing(QrPairingData data) async {
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      final result = await _api.confirmPairing(
        pairToken: data.pairToken,
        pairSessionId: data.pairSessionId,
      );

      final status = result['status'] as String?;
      if (status == 'ok' || status == 'paired') {
        setState(() {
          _successMessage = 'Device paired successfully!';
          _isProcessing = false;
        });

        // Navigate to device list after short delay
        await Future.delayed(const Duration(milliseconds: 800));
        if (mounted) {
          Navigator.pushReplacementNamed(context, DeviceListScreen.route);
        }
      } else {
        final reason = result['reason'] as String? ?? 'Unknown error';
        setState(() {
          _errorMessage = 'Pairing failed: $reason';
          _scannedData = null;
          _isProcessing = false;
        });
        _scannerController?.start();
      }
    } on ApiException catch (e) {
      setState(() {
        _errorMessage = 'Pairing failed: ${e.reason ?? e.body}';
        _scannedData = null;
        _isProcessing = false;
      });
      _scannerController?.start();
    } catch (e) {
      setState(() {
        _errorMessage = 'Pairing failed: $e';
        _scannedData = null;
        _isProcessing = false;
      });
      _scannerController?.start();
    }
  }

  Future<void> _confirmManualPairing() async {
    final token = _manualTokenController.text.trim();
    final sessionId = _manualSessionController.text.trim();

    if (token.isEmpty) {
      setState(() => _errorMessage = 'Please enter the pair token');
      return;
    }

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      final result = await _api.confirmPairing(
        pairToken: token,
        pairSessionId: sessionId.isEmpty ? null : sessionId,
      );

      final status = result['status'] as String?;
      if (status == 'ok' || status == 'paired') {
        setState(() {
          _successMessage = 'Device paired successfully!';
          _isProcessing = false;
        });

        await Future.delayed(const Duration(milliseconds: 800));
        if (mounted) {
          Navigator.pushReplacementNamed(context, DeviceListScreen.route);
        }
      } else {
        final reason = result['reason'] as String? ?? 'Unknown error';
        setState(() {
          _errorMessage = 'Pairing failed: $reason';
          _isProcessing = false;
        });
      }
    } on ApiException catch (e) {
      setState(() {
        _errorMessage = 'Pairing failed: ${e.reason ?? e.body}';
        _isProcessing = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Pairing failed: $e';
        _isProcessing = false;
      });
    }
  }

  void _toggleFlash() {
    _scannerController?.toggleTorch();
    _torchEnabled = !_torchEnabled;
  }

  void _switchCamera() {
    _scannerController?.switchCamera();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pair Device'),
        actions: [
          if (_hasPermission && !_showManualEntry)
            IconButton(
              icon: const Icon(Icons.keyboard),
              tooltip: 'Enter manually',
              onPressed: () => setState(() => _showManualEntry = true),
            ),
          if (_showManualEntry)
            IconButton(
              icon: const Icon(Icons.qr_code_scanner),
              tooltip: 'Scan QR code',
              onPressed: () => setState(() => _showManualEntry = false),
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    // Success state
    if (_successMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 64),
            const SizedBox(height: 16),
            Text(
              _successMessage!,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ],
        ),
      );
    }

    // Manual entry mode
    if (_showManualEntry) {
      return _buildManualEntry();
    }

    // Permission denied
    if (_permissionDenied) {
      return _buildPermissionDenied();
    }

    // Waiting for permission
    if (!_hasPermission) {
      return const Center(child: CircularProgressIndicator());
    }

    // Scanner view
    return _buildScannerView();
  }

  Widget _buildScannerView() {
    return Stack(
      children: [
        // Camera preview
        MobileScanner(
          controller: _scannerController,
          onDetect: _onDetect,
          errorBuilder: (context, error, child) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error, color: Colors.red, size: 48),
                  const SizedBox(height: 16),
                  Text('Camera error: ${error.errorCode}'),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: () => setState(() => _showManualEntry = true),
                    child: const Text('Enter manually'),
                  ),
                ],
              ),
            );
          },
        ),

        // Scan overlay
        _buildScanOverlay(),

        // Controls at bottom
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: _buildControls(),
        ),

        // Processing indicator
        if (_isProcessing)
          Container(
            color: Colors.black54,
            child: const Center(child: CircularProgressIndicator()),
          ),
      ],
    );
  }

  Widget _buildScanOverlay() {
    return CustomPaint(
      painter: _ScanOverlayPainter(),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Point camera at device QR code',
                style: TextStyle(color: Colors.white),
              ),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 32),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade800,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.white),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildControls() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black87],
        ),
      ),
      child: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // Flash toggle
            StatefulBuilder(
              builder: (context, setLocalState) {
                return IconButton(
                  icon: Icon(
                    _torchEnabled ? Icons.flash_on : Icons.flash_off,
                    color: Colors.white,
                    size: 28,
                  ),
                  onPressed: () {
                    _toggleFlash();
                    setLocalState(() {});
                  },
                  tooltip: 'Toggle flash',
                );
              },
            ),

            // Camera switch
            IconButton(
              icon: const Icon(
                Icons.cameraswitch,
                color: Colors.white,
                size: 28,
              ),
              onPressed: _switchCamera,
              tooltip: 'Switch camera',
            ),

            // Manual entry
            IconButton(
              icon: const Icon(
                Icons.keyboard,
                color: Colors.white,
                size: 28,
              ),
              onPressed: () => setState(() => _showManualEntry = true),
              tooltip: 'Enter manually',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildManualEntry() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.keyboard_alt_outlined, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            'Manual Pairing',
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            'Enter the pairing token displayed on the device.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 32),
          TextField(
            controller: _manualTokenController,
            decoration: const InputDecoration(
              labelText: 'Pair Token',
              hintText: 'Enter the token from the device',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.vpn_key),
            ),
            enabled: !_isProcessing,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _manualSessionController,
            decoration: const InputDecoration(
              labelText: 'Session ID (optional)',
              hintText: 'Enter session ID if provided',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.tag),
            ),
            enabled: !_isProcessing,
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.red.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(color: Colors.red.shade700),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _isProcessing ? null : _confirmManualPairing,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: _isProcessing
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Pair Device'),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionDenied() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.camera_alt, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              'Camera Permission Required',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'To scan QR codes, please grant camera access in your device settings.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => openAppSettings(),
              icon: const Icon(Icons.settings),
              label: const Text('Open Settings'),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => setState(() => _showManualEntry = true),
              child: const Text('Enter token manually'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Custom painter for the scan area overlay with darkened corners.
class _ScanOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black54
      ..style = PaintingStyle.fill;

    final scanAreaSize = 250.0;
    final centerX = size.width / 2;
    final centerY = size.height / 2;

    final scanRect = Rect.fromCenter(
      center: Offset(centerX, centerY),
      width: scanAreaSize,
      height: scanAreaSize,
    );

    // Draw darkened area around scan box
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(RRect.fromRectAndRadius(scanRect, const Radius.circular(12)))
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(path, paint);

    // Draw corner accents
    final accentPaint = Paint()
      ..color = Colors.indigo
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    const cornerLength = 30.0;
    final left = scanRect.left;
    final top = scanRect.top;
    final right = scanRect.right;
    final bottom = scanRect.bottom;

    // Top-left corner
    canvas.drawLine(
        Offset(left, top + cornerLength), Offset(left, top), accentPaint);
    canvas.drawLine(
        Offset(left, top), Offset(left + cornerLength, top), accentPaint);

    // Top-right corner
    canvas.drawLine(
        Offset(right - cornerLength, top), Offset(right, top), accentPaint);
    canvas.drawLine(
        Offset(right, top), Offset(right, top + cornerLength), accentPaint);

    // Bottom-left corner
    canvas.drawLine(
        Offset(left, bottom - cornerLength), Offset(left, bottom), accentPaint);
    canvas.drawLine(
        Offset(left, bottom), Offset(left + cornerLength, bottom), accentPaint);

    // Bottom-right corner
    canvas.drawLine(Offset(right - cornerLength, bottom), Offset(right, bottom),
        accentPaint);
    canvas.drawLine(Offset(right, bottom), Offset(right, bottom - cornerLength),
        accentPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
