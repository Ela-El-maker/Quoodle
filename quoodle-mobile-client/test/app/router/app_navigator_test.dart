import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_device_control/app/router/app_navigator.dart';

void main() {
  testWidgets('popOrGo pops current route when navigator can pop',
      (tester) async {
    final events = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (inner) => Scaffold(
                          body: Center(
                            child: ElevatedButton(
                              onPressed: () {
                                final popped = AppNavigator.popOrGo(
                                  inner,
                                  AppRoute.devices,
                                );
                                events.add(popped ? 'popped' : 'fallback');
                              },
                              child: const Text('back'),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('back'), findsOneWidget);

    await tester.tap(find.text('back'));
    await tester.pumpAndSettle();

    expect(events, contains('popped'));
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('popOrGo returns false when no route to pop', (tester) async {
    var didFallback = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () {
                    didFallback =
                        !AppNavigator.popOrGo(context, AppRoute.devices);
                  },
                  child: const Text('fallback'),
                ),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('fallback'));
    await tester.pump();

    expect(didFallback, isTrue);
  });
}
