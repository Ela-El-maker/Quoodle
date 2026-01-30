import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secure_device_control/models/command.dart';
import 'package:secure_device_control/widgets/command_timeline.dart';

void main() {
  testWidgets('CommandTimeline renders steps', (tester) async {
    const command = CommandState(
      commandId: 'cmd-1',
      deviceId: 'device-1',
      method: 'lock_screen',
      state: 'acked',
      queuedAt: '2026-01-01T00:00:00Z',
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CommandTimeline(command: command),
        ),
      ),
    );

    expect(find.text('INTENT'), findsOneWidget);
    expect(find.text('DISPATCHED'), findsOneWidget);
    expect(find.text('ACK'), findsOneWidget);
    expect(find.text('RESULT'), findsOneWidget);
  });
}
