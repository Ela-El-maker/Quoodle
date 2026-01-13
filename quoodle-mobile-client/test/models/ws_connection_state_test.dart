import 'package:flutter_test/flutter_test.dart';
import 'package:secure_device_control/models/ws_connection_state.dart';

void main() {
  group('WsConnectionState', () {
    test('enum has all expected values', () {
      expect(
          WsConnectionState.values,
          containsAll([
            WsConnectionState.disconnected,
            WsConnectionState.connecting,
            WsConnectionState.connected,
            WsConnectionState.authenticating,
            WsConnectionState.authenticated,
            WsConnectionState.reconnecting,
            WsConnectionState.failed,
          ]));
    });
  });

  group('WsStateEvent', () {
    test('isConnected returns true for connected states', () {
      final connected = WsStateEvent(
        state: WsConnectionState.connected,
        timestamp: DateTime.now(),
      );
      final authenticating = WsStateEvent(
        state: WsConnectionState.authenticating,
        timestamp: DateTime.now(),
      );
      final authenticated = WsStateEvent(
        state: WsConnectionState.authenticated,
        timestamp: DateTime.now(),
      );

      expect(connected.isConnected, isTrue);
      expect(authenticating.isConnected, isTrue);
      expect(authenticated.isConnected, isTrue);
    });

    test('isConnected returns false for disconnected states', () {
      final disconnected = WsStateEvent(
        state: WsConnectionState.disconnected,
        timestamp: DateTime.now(),
      );
      final reconnecting = WsStateEvent(
        state: WsConnectionState.reconnecting,
        timestamp: DateTime.now(),
      );
      final failed = WsStateEvent(
        state: WsConnectionState.failed,
        timestamp: DateTime.now(),
      );

      expect(disconnected.isConnected, isFalse);
      expect(reconnecting.isConnected, isFalse);
      expect(failed.isConnected, isFalse);
    });

    test('isAuthenticated returns true only for authenticated state', () {
      final authenticated = WsStateEvent(
        state: WsConnectionState.authenticated,
        timestamp: DateTime.now(),
      );
      final connected = WsStateEvent(
        state: WsConnectionState.connected,
        timestamp: DateTime.now(),
      );

      expect(authenticated.isAuthenticated, isTrue);
      expect(connected.isAuthenticated, isFalse);
    });

    test('isReconnecting returns true only for reconnecting state', () {
      final reconnecting = WsStateEvent(
        state: WsConnectionState.reconnecting,
        timestamp: DateTime.now(),
        reconnectAttempt: 3,
      );
      final connecting = WsStateEvent(
        state: WsConnectionState.connecting,
        timestamp: DateTime.now(),
      );

      expect(reconnecting.isReconnecting, isTrue);
      expect(connecting.isReconnecting, isFalse);
    });

    test('isFailed returns true only for failed state', () {
      final failed = WsStateEvent(
        state: WsConnectionState.failed,
        timestamp: DateTime.now(),
        error: 'Auth rejected',
      );
      final disconnected = WsStateEvent(
        state: WsConnectionState.disconnected,
        timestamp: DateTime.now(),
      );

      expect(failed.isFailed, isTrue);
      expect(disconnected.isFailed, isFalse);
    });

    test('includes error and reconnect attempt info', () {
      final event = WsStateEvent(
        state: WsConnectionState.reconnecting,
        timestamp: DateTime(2024, 1, 1, 12, 0, 0),
        error: 'Connection lost',
        reconnectAttempt: 5,
        sessionId: 'session-123',
      );

      expect(event.error, 'Connection lost');
      expect(event.reconnectAttempt, 5);
      expect(event.sessionId, 'session-123');
    });

    test('toString provides useful debug info', () {
      final event = WsStateEvent(
        state: WsConnectionState.failed,
        timestamp: DateTime.now(),
        error: 'Test error',
        reconnectAttempt: 2,
      );

      final str = event.toString();

      expect(str, contains('failed'));
      expect(str, contains('Test error'));
      expect(str, contains('2'));
    });
  });
}
