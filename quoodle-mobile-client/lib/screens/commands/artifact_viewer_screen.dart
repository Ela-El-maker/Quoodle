import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../models/command.dart';
import '../../theme/app_colors.dart';
import '../../widgets/glass_card.dart';

class ArtifactViewerScreen extends StatefulWidget {
  const ArtifactViewerScreen({super.key, required this.command});

  final CommandState command;

  @override
  State<ArtifactViewerScreen> createState() => _ArtifactViewerScreenState();
}

class _ArtifactViewerScreenState extends State<ArtifactViewerScreen> {
  bool _loading = false;
  String? _result;

  Future<void> _verify() async {
    final url = widget.command.artifactUrl;
    if (url == null) return;

    setState(() {
      _loading = true;
      _result = null;
    });

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode >= 400) {
        throw Exception('HTTP ${response.statusCode}');
      }
      final bytes = response.bodyBytes;
      final digest = await Sha256().hash(bytes);
      final hex = _toHex(digest.bytes);
      final expected = widget.command.artifactChecksum;
      if (expected != null && expected.isNotEmpty) {
        if (hex.toLowerCase() == expected.toLowerCase()) {
          setState(() => _result = 'Integrity verified');
        } else {
          setState(() => _result = 'Checksum mismatch');
        }
      } else {
        setState(() => _result = 'Downloaded, no checksum provided');
      }
    } catch (e) {
      setState(() => _result = 'Verification failed: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final command = widget.command;
    return Scaffold(
      appBar: AppBar(title: const Text('Artifacts & Results')),
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
                  Text('Signed results',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  _BadgeRow(
                    label: 'Signed by agent',
                    color: AppColors.accentMint,
                  ),
                  _BadgeRow(
                    label: 'Verified by control plane',
                    color: AppColors.accentCyan,
                  ),
                  _BadgeRow(
                    label: 'Recorded in audit ledger',
                    color: AppColors.accentAmber,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Artifact URL',
                    style: Theme.of(context)
                        .textTheme
                        .labelLarge
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 4),
                  SelectableText(command.artifactUrl ?? 'No artifact URL'),
                  const SizedBox(height: 10),
                  Text(
                    'Checksum',
                    style: Theme.of(context)
                        .textTheme
                        .labelLarge
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 4),
                  SelectableText(command.artifactChecksum ?? 'Not provided'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            GlassCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Integrity verification',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(
                    'Download the artifact and validate checksum before using it.',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _loading ? null : _verify,
                    icon: const Icon(Icons.verified),
                    label: Text(_loading ? 'Verifying...' : 'Verify integrity'),
                  ),
                  if (_result != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _result!,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: AppColors.textPrimary),
                    ),
                  ]
                ],
              ),
            ),
            if (command.resultData != null && command.resultData!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: GlassCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Result data',
                          style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 8),
                      Text(
                        const JsonEncoder.withIndent('  ')
                            .convert(command.resultData),
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _toHex(List<int> bytes) {
    final buffer = StringBuffer();
    for (final b in bytes) {
      buffer.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }
}

class _BadgeRow extends StatelessWidget {
  const _BadgeRow({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(Icons.verified, color: color, size: 18),
          const SizedBox(width: 8),
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
