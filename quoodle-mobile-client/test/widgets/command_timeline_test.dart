import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_device_control/widgets/status_badge_widget.dart';

void main() {
  testWidgets('StatusBadgeWidget.command renders completed state',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatusBadgeWidget.command(CommandStatus.completed),
        ),
      ),
    );

    expect(find.text('Completed'), findsOneWidget);
  });
}
