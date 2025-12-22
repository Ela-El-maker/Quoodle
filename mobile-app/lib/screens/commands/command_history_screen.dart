import 'package:flutter/material.dart';

import '../../models/command.dart';
import '../../services/api_service.dart';
import 'command_detail_screen.dart';

class CommandHistoryScreen extends StatefulWidget {
  const CommandHistoryScreen({super.key, required this.deviceId});

  final String deviceId;

  @override
  State<CommandHistoryScreen> createState() => _CommandHistoryScreenState();
}

class _CommandHistoryScreenState extends State<CommandHistoryScreen> {
  final ApiService _api = ApiService();
  late Future<List<CommandState>> _commands;

  @override
  void initState() {
    super.initState();
    _commands = _api.fetchDeviceCommands(widget.deviceId);
  }

  Future<void> _refresh() async {
    setState(() {
      _commands = _api.fetchDeviceCommands(widget.deviceId);
    });
    await _commands;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Command History')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<CommandState>>(
          future: _commands,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return ListView(children: const [
                SizedBox(
                    height: 300,
                    child: Center(child: CircularProgressIndicator()))
              ]);
            }
            final list = snapshot.data!;
            if (list.isEmpty) {
              return ListView(children: const [
                SizedBox(
                    height: 300, child: Center(child: Text('No commands yet')))
              ]);
            }

            return ListView.separated(
              itemCount: list.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, idx) {
                final c = list[idx];
                return ListTile(
                  leading: const Icon(Icons.bolt),
                  title: Text(c.method ?? '-'),
                  subtitle:
                      Text('State: ${c.state ?? '-'} • ${c.queuedAt ?? '-'}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: c.commandId == null
                      ? null
                      : () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => CommandDetailScreen(
                                    commandId: c.commandId!)),
                          ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
