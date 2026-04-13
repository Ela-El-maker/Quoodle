import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_device_control/features/commands/data/services/command_artifact_download_service.dart';
import 'package:secure_device_control/features/commands/presentation/providers/commands_api_providers.dart';
import 'package:secure_device_control/presentation/command_timeline_screen/widgets/command_result_widget.dart';
import 'package:secure_device_control/widgets/status_badge_widget.dart';

class _FakeArtifactDownloader implements CommandArtifactDownloader {
  int callCount = 0;

  @override
  Future<DownloadedArtifact> download({
    required String artifactUrl,
    String? checksum,
  }) async {
    callCount += 1;
    return const DownloadedArtifact(
      filePath: '/tmp/fake.png',
      fileName: 'fake.png',
      sizeBytes: 10,
      checksumVerified: true,
    );
  }
}

void main() {
  Widget _build(Widget child, {List<Override> overrides = const []}) {
    return ProviderScope(
      overrides: overrides,
      child: MaterialApp(home: Scaffold(body: child)),
    );
  }

  testWidgets('renders screenshot actions when artifact is present',
      (tester) async {
    final fakeDownloader = _FakeArtifactDownloader();
    await tester.pumpWidget(
      _build(
        CommandResultWidget(
          status: CommandStatus.completed,
          command: const <String, dynamic>{
            'method': 'screenshot',
            'executionState': 'completed',
            'result': <String, dynamic>{
              'status': 'ok',
              'artifact_url': 'https://example.com/api/artifact/abc',
              'artifact_checksum': '123',
              'data': <String, dynamic>{
                'capture': <String, dynamic>{'width': 1920, 'height': 1080},
              },
            },
          },
        ),
        overrides: [
          commandArtifactDownloaderProvider.overrideWithValue(fakeDownloader),
        ],
      ),
    );

    expect(find.text('Download'), findsOneWidget);
    expect(find.text('Copy URL'), findsOneWidget);
  });

  testWidgets(
      'renders process list table and remains overflow-safe on narrow width',
      (tester) async {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.window.physicalSizeTestValue = const Size(320, 700);
    binding.window.devicePixelRatioTestValue = 1.0;
    addTearDown(() {
      binding.window.clearPhysicalSizeTestValue();
      binding.window.clearDevicePixelRatioTestValue();
    });

    await tester.pumpWidget(
      _build(
        CommandResultWidget(
          status: CommandStatus.completed,
          command: const <String, dynamic>{
            'method': 'list_processes',
            'executionState': 'completed',
            'result': <String, dynamic>{
              'status': 'ok',
              'data': <String, dynamic>{
                'processes': <Map<String, dynamic>>[
                  <String, dynamic>{'pid': 1, 'name': 'init', 'user': 'root'},
                  <String, dynamic>{'pid': 2, 'name': 'bash', 'user': 'ela'},
                ],
              },
            },
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('PROCESS LIST'), findsOneWidget);
    expect(find.text('init'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders filesystem explorer for snapshot entries',
      (tester) async {
    await tester.pumpWidget(
      _build(
        CommandResultWidget(
          status: CommandStatus.completed,
          command: const <String, dynamic>{
            'method': 'list_files',
            'executionState': 'completed',
            'result': <String, dynamic>{
              'status': 'ok',
              'data': <String, dynamic>{
                'entries': <Map<String, dynamic>>[
                  <String, dynamic>{'path': 'tmp', 'is_dir': true},
                  <String, dynamic>{
                    'path': 'tmp/file.txt',
                    'is_dir': false,
                    'size': 100
                  },
                ],
              },
            },
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('FILESYSTEM'), findsOneWidget);
    expect(find.text('tmp'), findsWidgets);
  });
}
