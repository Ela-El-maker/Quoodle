import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_device_control/presentation/authentication_screen/authentication_screen.dart';

void main() {
  testWidgets('Authentication screen renders sign-in heading', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: AuthenticationScreen(),
        ),
      ),
    );

    expect(find.text('Sign In'), findsAtLeastNWidgets(1));
    expect(find.text('Quoodle'), findsOneWidget);
  });
}
