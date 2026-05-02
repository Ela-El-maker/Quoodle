import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_device_control/core/network/api_client.dart';
import 'package:secure_device_control/features/commands/data/datasources/commands_remote_data_source.dart';
import 'package:secure_device_control/features/commands/presentation/providers/commands_api_providers.dart';
import 'package:secure_device_control/features/commands/presentation/providers/send_command_controller.dart';

class _FakeApiClient implements ApiClient {
  _FakeApiClient({Map<String, dynamic>? postResponse})
      : _postResponse = postResponse ??
            const <String, dynamic>{
              'status': 'accepted',
              'command_id': 'cmd-001',
              'queued_at': '2026-04-13T10:00:00Z',
            };

  final Map<String, dynamic> _postResponse;
  String? lastPostPath;
  Map<String, dynamic>? lastPostData;
  Map<String, String>? lastPostHeaders;

  @override
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
  }) async {
    return const <String, dynamic>{};
  }

  @override
  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? data,
    Map<String, String>? headers,
  }) async {
    lastPostPath = path;
    lastPostData = data;
    lastPostHeaders = headers;
    return _postResponse;
  }
}

void main() {
  test('SendCommandController handles selection and policy state', () async {
    final container = ProviderContainer();
    final sub = container.listen(
      sendCommandControllerProvider,
      (_, __) {},
      fireImmediately: true,
    );
    addTearDown(sub.close);
    addTearDown(container.dispose);

    final controller = container.read(sendCommandControllerProvider.notifier);

    controller.selectMethod('policy_sync');
    expect(container.read(sendCommandControllerProvider).selectedMethodId,
        'policy_sync');

    controller.togglePolicyPanel();
    expect(
        container.read(sendCommandControllerProvider).showPolicyPanel, isFalse);

    expect(container.read(sendCommandControllerProvider).submitting, isFalse);
  });

  test('dispatch normalizes reboot command to control-plane method', () async {
    final fakeApi = _FakeApiClient();
    final container = ProviderContainer(
      overrides: [
        commandsRemoteDataSourceProvider.overrideWithValue(
          CommandsRemoteDataSource(fakeApi),
        ),
      ],
    );
    final sub = container.listen(
      sendCommandControllerProvider,
      (_, __) {},
      fireImmediately: true,
    );
    addTearDown(sub.close);
    addTearDown(container.dispose);

    final result = await container
        .read(sendCommandControllerProvider.notifier)
        .dispatchCommand(
          deviceId: 'dev-007',
          deviceName: 'WKS-FINANCE-07',
          methodId: 'reboot',
          params: const <String, dynamic>{
            'delay_seconds': 45,
            'force': true,
          },
          sensitive: true,
        );

    expect(result.success, isTrue);
    expect(result.timelineArguments?['method'], 'reboot_device');
    expect(fakeApi.lastPostPath, '/commands');
    expect(fakeApi.lastPostData?['method'], 'reboot_device');
    expect(fakeApi.lastPostData?['params'], const <String, dynamic>{
      'delay_seconds': 45,
    });
    expect(
      fakeApi.lastPostHeaders?['X-Quoodle-Client-Channel'],
      'mobile_app',
    );
  });

  test('dispatch normalizes filesystem path for control-plane validation',
      () async {
    final fakeApi = _FakeApiClient();
    final container = ProviderContainer(
      overrides: [
        commandsRemoteDataSourceProvider.overrideWithValue(
          CommandsRemoteDataSource(fakeApi),
        ),
      ],
    );
    final sub = container.listen(
      sendCommandControllerProvider,
      (_, __) {},
      fireImmediately: true,
    );
    addTearDown(sub.close);
    addTearDown(container.dispose);

    final result = await container
        .read(sendCommandControllerProvider.notifier)
        .dispatchCommand(
          deviceId: 'dev-007',
          deviceName: 'WKS-FINANCE-07',
          methodId: 'filesystem',
          params: const <String, dynamic>{
            'path': '/etc',
            'depth': 2,
            'include_hidden': false,
          },
          sensitive: true,
        );

    expect(result.success, isTrue);
    expect(result.timelineArguments?['method'], 'list_files');
    expect(fakeApi.lastPostData?['method'], 'list_files');
    expect(fakeApi.lastPostData?['params'], const <String, dynamic>{
      'path': 'etc',
      'recursive': true,
      'limit': 200,
    });
  });
}
