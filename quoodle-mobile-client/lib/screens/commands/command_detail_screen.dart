import 'package:flutter/material.dart';

import 'command_timeline_screen.dart';

class CommandDetailScreen extends StatefulWidget {
  const CommandDetailScreen({super.key, required this.commandId});

  final String commandId;

  @override
  State<CommandDetailScreen> createState() => _CommandDetailScreenState();
}

class _CommandDetailScreenState extends State<CommandDetailScreen> {
  @override
  Widget build(BuildContext context) {
    return CommandTimelineScreen(commandId: widget.commandId);
  }
}
