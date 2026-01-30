import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secure_device_control/services/session_store.dart';
import 'package:secure_device_control/utils/rbac.dart';
import 'package:secure_device_control/widgets/permission_gate.dart';

void main() {
  testWidgets('PermissionGate shows child for allowed role', (tester) async {
    SessionStore.userRole = 'admin';
    await tester.pumpWidget(
      const MaterialApp(
        home: PermissionGate(
          requiredRole: UserRole.operator,
          child: Text('Allowed'),
        ),
      ),
    );

    expect(find.text('Allowed'), findsOneWidget);
    expect(find.text('Action restricted'), findsNothing);
  });

  testWidgets('PermissionGate shows restriction for viewer', (tester) async {
    SessionStore.userRole = 'viewer';
    await tester.pumpWidget(
      const MaterialApp(
        home: PermissionGate(
          requiredRole: UserRole.operator,
          child: Text('Allowed'),
        ),
      ),
    );

    expect(find.text('Action restricted'), findsOneWidget);
  });
}
