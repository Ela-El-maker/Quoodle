import 'package:flutter/material.dart';

import '../../models/command.dart';
import '../../services/api_service.dart';

class CommandDetailScreen extends StatefulWidget {
  const CommandDetailScreen({super.key, required this.commandId});

  final String commandId;

  @override
  State<CommandDetailScreen> createState() => _CommandDetailScreenState();
}

class _CommandDetailScreenState extends State<CommandDetailScreen> {
  final ApiService _api = ApiService();
  late Future<CommandState> _command;

  @override
  void initState() {
    super.initState();
    _command = _api.fetchCommand(widget.commandId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Command Detail')),
      body: FutureBuilder<CommandState>(
        future: _command,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final c = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Command: ${c.commandId ?? '-'}',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text('Device: ${c.deviceId ?? '-'}'),
              Text('Method: ${c.method ?? '-'}'),
              Text('State: ${c.state ?? '-'}'),
              Text('Queued: ${c.queuedAt ?? '-'}'),
              Text('Completed: ${c.completedAt ?? '-'}'),
              const SizedBox(height: 12),
              Text('Result: ${c.resultStatus ?? '-'}'),
              if (c.errorCode != null) Text('Error code: ${c.errorCode}'),
              if (c.errorMessage != null && c.errorMessage!.isNotEmpty)
                Text('Error: ${c.errorMessage}'),
              const SizedBox(height: 16),
              Text('Audit', style: Theme.of(context).textTheme.titleMedium),
              Text('Server seq: ${c.serverSeq ?? '-'}'),
              if (c.requestSig != null)
                SelectableText('Request sig: ${c.requestSig}'),
              if (c.envelopeSig != null)
                SelectableText('Envelope sig: ${c.envelopeSig}'),
            ],
          );
        },
      ),
    );
  }
}
