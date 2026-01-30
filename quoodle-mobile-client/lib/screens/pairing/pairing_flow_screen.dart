import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../models/qr_pairing_data.dart';
import '../../services/api_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/glass_card.dart';
import '../home/home_screen.dart';

class PairingFlowScreen extends StatefulWidget {
  const PairingFlowScreen({
    super.key,
    this.qrData,
    this.manualToken,
    this.manualSessionId,
  });

  final QrPairingData? qrData;
  final String? manualToken;
  final String? manualSessionId;

  @override
  State<PairingFlowScreen> createState() => _PairingFlowScreenState();
}

class _PairingFlowScreenState extends State<PairingFlowScreen> {
  final ApiService _api = ApiService();
  bool _confirming = false;
  String? _error;
  int _progressIndex = 0;
  bool _completed = false;
  Duration? _expiresIn;

  late final String _token;
  late final String? _sessionId;
  late final String _deviceId;
  late final String _fingerprint;

  @override
  void initState() {
    super.initState();
    _token = widget.qrData?.pairToken ?? widget.manualToken ?? '';
    _sessionId = widget.qrData?.pairSessionId ?? widget.manualSessionId;
    _deviceId = widget.qrData?.deviceId ?? 'Unknown device';
    _fingerprint = _buildFingerprint(_deviceId, _token);
    _expiresIn = _computeExpiry(widget.qrData?.timestamp);
  }

  Future<void> _confirmPairing() async {
    setState(() {
      _confirming = true;
      _error = null;
    });

    try {
      final result = await _api.confirmPairing(
        pairToken: _token,
        pairSessionId: _sessionId,
      );
      final status = result['status'] as String?;
      if (status == 'ok' || status == 'paired') {
        await _runProgressSteps();
      } else {
        final reason = result['reason'] as String? ?? 'Unknown error';
        setState(() {
          _error = 'Pairing failed: $reason';
          _confirming = false;
        });
      }
    } on ApiException catch (e) {
      setState(() {
        _error = 'Pairing failed: ${e.reason ?? e.body}';
        _confirming = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Pairing failed: $e';
        _confirming = false;
      });
    }
  }

  Future<void> _runProgressSteps() async {
    setState(() {
      _progressIndex = 1;
    });
    await Future.delayed(const Duration(milliseconds: 700));
    setState(() {
      _progressIndex = 2;
    });
    await Future.delayed(const Duration(milliseconds: 900));
    setState(() {
      _progressIndex = 3;
      _confirming = false;
      _completed = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pair Device')),
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.backgroundGradient),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            GlassCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Confirm device identity',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(
                    'Verify the fingerprint shown on both devices before pairing.',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 12),
                  _InfoRow(label: 'Device ID', value: _deviceId),
                  if (widget.qrData?.deviceLabel != null)
                    _InfoRow(
                        label: 'Label', value: widget.qrData!.deviceLabel!),
                  if (widget.qrData?.controllerUrl != null)
                    _InfoRow(
                        label: 'Controller',
                        value: widget.qrData!.controllerUrl!),
                  _InfoRow(label: 'Fingerprint', value: _fingerprint),
                  if (_expiresIn != null) ...[
                    const SizedBox(height: 8),
                    _InfoRow(
                      label: 'QR expires',
                      value: _expiresIn!.inSeconds <= 0
                          ? 'Expired'
                          : '${_expiresIn!.inMinutes}m ${_expiresIn!.inSeconds.remainder(60)}s',
                    ),
                  ],
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed:
                        _confirming || _completed ? null : _confirmPairing,
                    icon: const Icon(Icons.verified_user),
                    label: Text(
                        _confirming ? 'Pairing...' : 'Confirm & Pair Device'),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: AppColors.nonCompliant),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            GlassCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Pairing lifecycle',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  _StepRow(
                    label: 'Pairing confirmed',
                    active: _progressIndex >= 1,
                    inProgress: _confirming && _progressIndex == 0,
                  ),
                  _StepRow(
                    label: 'Waiting for device online',
                    active: _progressIndex >= 2,
                    inProgress: _confirming && _progressIndex == 1,
                  ),
                  _StepRow(
                    label: 'Attestation running',
                    active: _progressIndex >= 3,
                    inProgress: _confirming && _progressIndex == 2,
                  ),
                  _StepRow(
                    label: 'Pairing complete',
                    active: _completed,
                    inProgress: false,
                  ),
                  if (_completed) ...[
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: () => Navigator.pushNamedAndRemoveUntil(
                          context, HomeScreen.route, (_) => false),
                      icon: const Icon(Icons.check_circle),
                      label: const Text('Go to Fleet'),
                    ),
                  ]
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _buildFingerprint(String deviceId, String token) {
    final bytes = utf8.encode('$deviceId::$token');
    final hash = base64UrlEncode(bytes).replaceAll('=', '');
    final words = _wordList;
    final parts = <String>[];
    for (var i = 0; i < 4; i++) {
      final idx = hash.codeUnitAt(i * 3) % words.length;
      parts.add(words[idx]);
    }
    return parts.join(' ');
  }

  Duration? _computeExpiry(String? timestamp) {
    if (timestamp == null || timestamp.isEmpty) return null;
    try {
      final ts = DateTime.parse(timestamp).toUtc();
      final expiry = ts.add(const Duration(minutes: 5));
      final remaining = expiry.difference(DateTime.now().toUtc());
      return remaining;
    } catch (_) {
      return null;
    }
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(color: AppColors.textSecondary),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppColors.textPrimary),
            ),
          )
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.label,
    required this.active,
    required this.inProgress,
  });

  final String label;
  final bool active;
  final bool inProgress;

  @override
  Widget build(BuildContext context) {
    final color = active
        ? AppColors.accentMint
        : (inProgress ? AppColors.accentAmber : AppColors.textMuted);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          if (inProgress)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: color,
              ),
            )
          else
            Icon(
              active ? Icons.check_circle : Icons.radio_button_unchecked,
              color: color,
              size: 16,
            ),
          const SizedBox(width: 10),
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

const List<String> _wordList = [
  'anchor',
  'ember',
  'lumen',
  'kepler',
  'nova',
  'orbit',
  'pulse',
  'quartz',
  'ripple',
  'signal',
  'vertex',
  'zenith',
  'aurora',
  'cipher',
  'delta',
  'echo',
  'flux',
  'glow',
  'halo',
  'ion',
  'jolt',
  'kilo',
  'lattice',
  'mosaic',
  'neon',
  'omega',
  'prism',
  'quill',
  'relay',
  'saga',
  'talon',
  'umbra',
  'vivid',
  'watt',
  'xenon',
  'yonder',
  'zen',
];
