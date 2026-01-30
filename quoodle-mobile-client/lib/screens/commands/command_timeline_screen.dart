import 'package:flutter/material.dart';

import '../../models/command.dart';
import '../../services/api_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/command_timeline.dart';
import '../../widgets/glass_card.dart';
import 'artifact_viewer_screen.dart';

class CommandTimelineScreen extends StatefulWidget {
  const CommandTimelineScreen({super.key, required this.commandId});

  final String commandId;

  @override
  State<CommandTimelineScreen> createState() => _CommandTimelineScreenState();
}

class _CommandTimelineScreenState extends State<CommandTimelineScreen> {
  final ApiService _api = ApiService();
  late Future<CommandState> _command;

  @override
  void initState() {
    super.initState();
    _command = _api.fetchCommand(widget.commandId);
  }

  Future<void> _refresh() async {
    setState(() {
      _command = _api.fetchCommand(widget.commandId);
    });
    await _command;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Command Timeline')),
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.backgroundGradient),
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: FutureBuilder<CommandState>(
            future: _command,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return ListView(
                  children: const [
                    SizedBox(
                        height: 320,
                        child: Center(child: CircularProgressIndicator()))
                  ],
                );
              }

              final c = snapshot.data!;
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  GlassCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Command ${c.commandId ?? '-'}',
                            style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 6),
                        Text(
                          '${c.method ?? '-'} · ${c.state ?? '-'}',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 12),
                        CommandTimeline(command: c),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  GlassCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Policy & signatures',
                            style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 8),
                        _InfoRow(label: 'Server seq', value: '${c.serverSeq ?? '-'}'),
                        _InfoRow(label: 'Request sig', value: c.requestSig ?? '-'),
                        _InfoRow(label: 'Envelope sig', value: c.envelopeSig ?? '-'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  GlassCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Result',
                            style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 8),
                        _InfoRow(label: 'Status', value: c.resultStatus ?? '-'),
                        if (c.resultNotes != null)
                          _InfoRow(label: 'Notes', value: c.resultNotes ?? '-'),
                        if (c.errorMessage != null && c.errorMessage!.isNotEmpty)
                          _InfoRow(label: 'Error', value: c.errorMessage!),
                        const SizedBox(height: 12),
                        if (c.artifactUrl != null)
                          ElevatedButton.icon(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ArtifactViewerScreen(command: c),
                              ),
                            ),
                            icon: const Icon(Icons.download),
                            label: const Text('View artifacts'),
                          )
                        else
                          Text(
                            'No artifacts attached to this command.',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: AppColors.textMuted),
                          )
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
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
            width: 110,
            child: Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(color: AppColors.textSecondary),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
