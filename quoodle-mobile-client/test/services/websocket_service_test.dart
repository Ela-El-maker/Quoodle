import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:secure_device_control/models/ws_connection_state.dart';
import 'package:secure_device_control/models/ws_envelope.dart';
import 'package:secure_device_control/services/session_store.dart';
import 'package:secure_device_control/services/websocket_service.dart';

/// Mock WebSocket channel for testing.
class MockWebSocketChannel implements WebSocketChannel {
  MockWebSocketChannel();

  final StreamController<dynamic> _streamController =
      StreamController<dynamic>.broadcast();
  final MockWebSocketSink _sink = MockWebSocketSink();
  bool _closed = false;

  @override
  Stream<dynamic> get stream => _streamController.stream;

  @override
  WebSocketSink get sink => _sink;

  @override
  int? get closeCode => _closed ? 1000 : null;

  @override
  String? get closeReason => _closed ? 'Normal closure' : null;

  @override
  String? get protocol => null;

  @override
  Future<void> get ready => Future.value();

  /// Simulate receiving a message from server.
  void receiveMessage(Map<String, dynamic> json) {
    if (!_streamController.isClosed) {
      _streamController.add(jsonEncode(json));
    }
  }

  /// Simulate connection closing.
  void close() {
    _closed = true;
    if (!_streamController.isClosed) {
      _streamController.close();
    }
  }

  /// Simulate an error.
  void addError(Object error) {
    if (!_streamController.isClosed) {
      _streamController.addError(error);
    }
  }

  /// Get sent messages.
  List<dynamic> get sentMessages => _sink.messages;

  // StreamChannel mixin methods - use noSuchMethod for unneeded methods
  @override
  dynamic noSuchMethod(Invocation invocation) {
    // Return null for any unimplemented methods
    return null;
  }
}

class MockWebSocketSink implements WebSocketSink {
  final List<dynamic> messages = [];
  bool _closed = false;

  @override
  void add(dynamic data) {
    if (!_closed) {
      messages.add(data);
    }
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<dynamic> addStream(Stream<dynamic> stream) async {
    await for (final data in stream) {
      add(data);
    }
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    _closed = true;
  }

  @override
  Future<dynamic> get done => Future.value();
}

void main() {
  late MockWebSocketChannel mockChannel;
  late WebsocketService service;

  Map<String, dynamic> createAuthAckMessage({
    String status = 'ok',
    String sessionId = 'test-session-123',
  }) {
    return {
      'type': 'AUTH_ACK',
      'from': 'controller',
      'device_id': 'test-device',
      'message_id': 'msg-auth-ack-1',
      'session_id': sessionId,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'body': {
        'status': status,
        'session_id': sessionId,
        'heartbeat_interval_seconds': 30,
        'telemetry_interval_seconds': 60,
        'policy_hash': 'test-hash',
      },
      'sig': 'test-sig',
    };
  }

  Map<String, dynamic> createAuthErrorMessage({
    String errorCode = 'AUTH_FAILED',
    String errorMessage = 'Invalid JWT',
  }) {
    return {
      'type': 'AUTH_ERROR',
      'from': 'controller',
      'device_id': 'test-device',
      'message_id': 'msg-auth-err-1',
      'session_id': null,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'body': {
        'status': 'error',
        'error_code': errorCode,
        'error_message': errorMessage,
      },
      'sig': 'test-sig',
    };
  }

  Map<String, dynamic> createCommandDeliveryMessage() {
    return {
      'type': 'COMMAND_DELIVERY',
      'from': 'controller',
      'device_id': 'test-device',
      'message_id': 'msg-cmd-1',
      'session_id': 'test-session-123',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'body': {
        'command_message_id': 'cmd-123',
        'method': 'scan_device',
        'params': {},
        'priority': 'normal',
        'ttl_seconds': 300,
        'requires_ack': true,
      },
      'sig': 'test-sig',
    };
  }

  Map<String, dynamic> createAlertMessage() {
    return {
      'type': 'ALERT',
      'from': 'controller',
      'device_id': 'test-device',
      'message_id': 'msg-alert-1',
      'session_id': 'test-session-123',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'body': {
        'alert_id': 'alert-456',
        'severity': 'high',
        'category': 'security',
        'message': 'Suspicious activity detected',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      },
      'sig': 'test-sig',
    };
  }

  setUp(() {
    mockChannel = MockWebSocketChannel();

    // Set up SessionStore with test JWT
    SessionStore.jwt = 'test-jwt-token';
    SessionStore.userId = 'test-user';
    SessionStore.sessionId = 'test-session';

    service = WebsocketService(
      channelFactory: (_) => mockChannel,
      config: const WsConfig(
        initialBackoffMs: 10,
        maxBackoffMs: 100,
        maxReconnectAttempts: 3,
        heartbeatIntervalSeconds: 1,
      ),
      wsUrl: 'ws://test.example.com/ws',
    );
  });

  tearDown(() async {
    await service.dispose();
    SessionStore.jwt = null;
    SessionStore.userId = null;
    SessionStore.sessionId = null;
  });

  group('WebsocketService connection', () {
    test('connect transitions through states correctly', () async {
      final states = <WsConnectionState>[];
      service.stateStream.listen((event) => states.add(event.state));

      await service.connect(deviceId: 'test-device');

      // Allow time for state transitions
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // Should go through connecting -> connected -> authenticating
      expect(states, contains(WsConnectionState.connecting));
      expect(states, contains(WsConnectionState.connected));
      expect(states, contains(WsConnectionState.authenticating));
    });

    test('connect sends AUTH message', () async {
      await service.connect(deviceId: 'test-device');

      // Allow time for message to be sent
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(mockChannel.sentMessages, isNotEmpty);

      final authMessage = jsonDecode(mockChannel.sentMessages.first as String);
      expect(authMessage['type'], 'AUTH');
      expect(authMessage['from'], 'mobile');
      expect(authMessage['body']['auth']['jwt'], 'test-jwt-token');
    });

    test('handles AUTH_ACK and transitions to authenticated', () async {
      final states = <WsConnectionState>[];
      service.stateStream.listen((event) => states.add(event.state));

      await service.connect(deviceId: 'test-device');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      mockChannel.receiveMessage(createAuthAckMessage());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(states, contains(WsConnectionState.authenticated));
      expect(service.isAuthenticated, isTrue);
      expect(service.sessionId, 'test-session-123');
    });

    test('handles AUTH_ERROR and transitions to failed', () async {
      final states = <WsConnectionState>[];
      final errors = <String?>[];
      service.stateStream.listen((event) {
        states.add(event.state);
        errors.add(event.error);
      });

      await service.connect(deviceId: 'test-device');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      mockChannel.receiveMessage(createAuthErrorMessage());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(states, contains(WsConnectionState.failed));
      expect(errors.where((e) => e != null && e.contains('AUTH_FAILED')),
          isNotEmpty);
    });
  });

  group('WebsocketService message handling', () {
    test('commandStream receives COMMAND_DELIVERY messages', () async {
      final commands = <WsEnvelope>[];
      service.commandStream.listen(commands.add);

      await service.connect(deviceId: 'test-device');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      mockChannel.receiveMessage(createAuthAckMessage());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      mockChannel.receiveMessage(createCommandDeliveryMessage());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(commands, hasLength(1));
      expect(commands.first.type, WsMessageType.commandDelivery);
    });

    test('alertStream receives ALERT messages', () async {
      final alerts = <WsEnvelope>[];
      service.alertStream.listen(alerts.add);

      await service.connect(deviceId: 'test-device');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      mockChannel.receiveMessage(createAuthAckMessage());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      mockChannel.receiveMessage(createAlertMessage());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(alerts, hasLength(1));
      expect(alerts.first.type, WsMessageType.alert);
    });

    test('messageStream receives all messages', () async {
      final messages = <WsEnvelope>[];
      service.messageStream.listen(messages.add);

      await service.connect(deviceId: 'test-device');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      mockChannel.receiveMessage(createAuthAckMessage());
      mockChannel.receiveMessage(createCommandDeliveryMessage());
      mockChannel.receiveMessage(createAlertMessage());
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(messages.length, greaterThanOrEqualTo(3));
    });
  });

  group('WebsocketService command acknowledgment', () {
    test('sendCommandAck sends ACK when authenticated', () async {
      await service.connect(deviceId: 'test-device');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      mockChannel.receiveMessage(createAuthAckMessage());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final sentBefore = mockChannel.sentMessages.length;

      service.sendCommandAck(
        commandMessageId: 'cmd-123',
        status: 'received',
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(mockChannel.sentMessages.length, greaterThan(sentBefore));

      final ackMessage = jsonDecode(mockChannel.sentMessages.last as String)
          as Map<String, dynamic>;
      expect(ackMessage['type'], 'COMMAND_ACK');
      expect(ackMessage['body']['command_message_id'], 'cmd-123');
      expect(ackMessage['body']['status'], 'received');
    });

    test('sendCommandAck does nothing when not authenticated', () async {
      await service.connect(deviceId: 'test-device');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Not sending AUTH_ACK, so still in authenticating state
      final sentBefore = mockChannel.sentMessages.length;

      service.sendCommandAck(
        commandMessageId: 'cmd-123',
        status: 'received',
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Should not have sent additional message
      expect(mockChannel.sentMessages.length, sentBefore);
    });
  });

  group('WebsocketService disconnect', () {
    test('disconnect transitions to disconnected state', () async {
      final states = <WsConnectionState>[];
      service.stateStream.listen((event) => states.add(event.state));

      await service.connect(deviceId: 'test-device');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      mockChannel.receiveMessage(createAuthAckMessage());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await service.disconnect();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(states.last, WsConnectionState.disconnected);
      expect(service.isAuthenticated, isFalse);
    });

    test('disconnect prevents reconnection', () async {
      final states = <WsConnectionState>[];
      service.stateStream.listen((event) => states.add(event.state));

      await service.connect(deviceId: 'test-device');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await service.disconnect();
      await Future<void>.delayed(const Duration(milliseconds: 200));

      // Should not have reconnecting state after manual disconnect
      expect(states.where((s) => s == WsConnectionState.reconnecting), isEmpty);
    });
  });

  group('WebsocketService configuration', () {
    test('uses custom config values', () {
      const config = WsConfig(
        initialBackoffMs: 500,
        maxBackoffMs: 5000,
        backoffMultiplier: 1.5,
        maxReconnectAttempts: 5,
        heartbeatIntervalSeconds: 15,
        connectionTimeoutSeconds: 20,
      );

      expect(config.initialBackoffMs, 500);
      expect(config.maxBackoffMs, 5000);
      expect(config.backoffMultiplier, 1.5);
      expect(config.maxReconnectAttempts, 5);
      expect(config.heartbeatIntervalSeconds, 15);
      expect(config.connectionTimeoutSeconds, 20);
    });

    test('default config has sensible values', () {
      const config = WsConfig();

      expect(config.initialBackoffMs, 1000);
      expect(config.maxBackoffMs, 30000);
      expect(config.backoffMultiplier, 2.0);
      expect(config.maxReconnectAttempts, 10);
      expect(config.heartbeatIntervalSeconds, 30);
      expect(config.connectionTimeoutSeconds, 10);
    });
  });

  group('WebsocketService no JWT', () {
    test('transitions to failed when no JWT available', () async {
      SessionStore.jwt = null;

      final states = <WsConnectionState>[];
      final errors = <String?>[];
      service.stateStream.listen((event) {
        states.add(event.state);
        errors.add(event.error);
      });

      await service.connect(deviceId: 'test-device');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(states, contains(WsConnectionState.failed));
      expect(errors.where((e) => e != null && e.contains('JWT')), isNotEmpty);
    });
  });
}
