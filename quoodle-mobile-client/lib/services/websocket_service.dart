import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../config/environment.dart';
import '../models/ws_connection_state.dart';
import '../models/ws_envelope.dart';
import 'session_store.dart';

/// Factory function to create WebSocket channels (for testing).
typedef WsChannelFactory = WebSocketChannel Function(Uri uri);

/// Configuration for WebSocket reconnection behavior.
class WsConfig {
  const WsConfig({
    this.initialBackoffMs = 1000,
    this.maxBackoffMs = 30000,
    this.backoffMultiplier = 2.0,
    this.maxReconnectAttempts = 10,
    this.heartbeatIntervalSeconds = 30,
    this.connectionTimeoutSeconds = 10,
  });

  final int initialBackoffMs;
  final int maxBackoffMs;
  final double backoffMultiplier;
  final int maxReconnectAttempts;
  final int heartbeatIntervalSeconds;
  final int connectionTimeoutSeconds;
}

/// Robust WebSocket service with reconnection, auth flow, and state management.
class WebsocketService {
  WebsocketService({
    WsChannelFactory? channelFactory,
    WsConfig? config,
    String? wsUrl,
  })  : _channelFactory = channelFactory ?? _defaultChannelFactory,
        _config = config ?? const WsConfig(),
        _wsUrl = wsUrl ?? Environment.wsBaseUrl;

  static WebSocketChannel _defaultChannelFactory(Uri uri) {
    return WebSocketChannel.connect(uri);
  }

  final WsChannelFactory _channelFactory;
  final WsConfig _config;
  final String _wsUrl;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;

  int _reconnectAttempt = 0;
  String? _sessionId;
  String? _deviceId;
  bool _disposed = false;
  bool _manualDisconnect = false;

  // Stream controllers for outbound events
  final _stateController = StreamController<WsStateEvent>.broadcast();
  final _messageController = StreamController<WsEnvelope>.broadcast();
  final _commandController = StreamController<WsEnvelope>.broadcast();
  final _alertController = StreamController<WsEnvelope>.broadcast();
  final _updateController = StreamController<WsEnvelope>.broadcast();

  WsConnectionState _state = WsConnectionState.disconnected;

  /// Current connection state.
  WsConnectionState get state => _state;

  /// Stream of connection state changes.
  Stream<WsStateEvent> get stateStream => _stateController.stream;

  /// Stream of all incoming messages.
  Stream<WsEnvelope> get messageStream => _messageController.stream;

  /// Stream of command delivery messages.
  Stream<WsEnvelope> get commandStream => _commandController.stream;

  /// Stream of alert messages.
  Stream<WsEnvelope> get alertStream => _alertController.stream;

  /// Stream of update/refresh messages.
  Stream<WsEnvelope> get updateStream => _updateController.stream;

  /// Whether the service is fully authenticated.
  bool get isAuthenticated => _state == WsConnectionState.authenticated;

  /// Current session ID (after auth).
  String? get sessionId => _sessionId;

  /// Connect and authenticate with the WebSocket server.
  Future<void> connect({String? deviceId}) async {
    if (_disposed) {
      throw StateError('WebsocketService has been disposed');
    }

    _manualDisconnect = false;
    _deviceId = deviceId;
    _reconnectAttempt = 0;

    await _doConnect();
  }

  Future<void> _doConnect() async {
    if (_disposed || _manualDisconnect) return;

    _updateState(WsConnectionState.connecting);

    try {
      final uri = Uri.parse(_wsUrl);
      _channel = _channelFactory(uri);

      _subscription = _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
        cancelOnError: false,
      );

      _updateState(WsConnectionState.connected);

      // Send AUTH immediately after connection
      await _sendAuth();
    } catch (e) {
      _updateState(WsConnectionState.disconnected, error: e.toString());
      _scheduleReconnect();
    }
  }

  Future<void> _sendAuth() async {
    if (_channel == null) return;

    _updateState(WsConnectionState.authenticating);

    final jwt = SessionStore.jwt;
    if (jwt == null || jwt.isEmpty) {
      _updateState(WsConnectionState.failed, error: 'No JWT available');
      return;
    }

    final nonce = _generateNonce();
    final messageId = 'm-auth-${DateTime.now().millisecondsSinceEpoch}';
    final deviceId = _deviceId ?? 'mobile-${SessionStore.userId ?? 'unknown'}';

    final authEnvelope = {
      'type': 'AUTH',
      'from': 'mobile',
      'device_id': deviceId,
      'message_id': messageId,
      'session_id': null,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'body': {
        'auth': {
          'jwt': jwt,
          'nonce': nonce,
        },
        'agent_info': {
          'agent_version': '1.0.0',
          'os_build': 'mobile-flutter',
          'hwid_hash': deviceId,
          'attestation_hash': null,
        },
      },
      'sig':
          'mobile-sig-placeholder', // Mobile uses JWT auth, signature optional
    };

    _send(authEnvelope);
  }

  void _onMessage(dynamic data) {
    if (_disposed) return;

    try {
      final json =
          data is String ? jsonDecode(data) : data as Map<String, dynamic>;
      final envelope = WsEnvelope.fromJson(json as Map<String, dynamic>);

      // Emit to general message stream
      if (!_messageController.isClosed) {
        _messageController.add(envelope);
      }

      // Handle message based on type
      switch (envelope.type) {
        case WsMessageType.authAck:
          _handleAuthAck(envelope);
          break;
        case WsMessageType.authError:
          _handleAuthError(envelope);
          break;
        case WsMessageType.commandDelivery:
          _handleCommandDelivery(envelope);
          break;
        case WsMessageType.alert:
          _handleAlert(envelope);
          break;
        case WsMessageType.update:
          _handleUpdate(envelope);
          break;
        default:
          // Other message types can be handled by subscribers
          break;
      }
    } catch (e) {
      // Log parse error but don't disconnect
      // ignore: avoid_print
      print('WebSocket message parse error: $e');
    }
  }

  void _handleAuthAck(WsEnvelope envelope) {
    final ack = AuthAckBody.fromJson(envelope.body);

    if (ack.isOk) {
      _sessionId = ack.sessionId;
      _reconnectAttempt = 0;
      _updateState(WsConnectionState.authenticated);

      // Start heartbeat timer
      _startHeartbeat(ack.heartbeatIntervalSeconds);
    } else {
      _updateState(WsConnectionState.failed,
          error: 'Auth not OK: ${ack.status}');
    }
  }

  void _handleAuthError(WsEnvelope envelope) {
    final error = AuthErrorBody.fromJson(envelope.body);
    _updateState(
      WsConnectionState.failed,
      error: '${error.errorCode}: ${error.errorMessage}',
    );
    // Don't reconnect on auth failure
    _manualDisconnect = true;
  }

  void _handleCommandDelivery(WsEnvelope envelope) {
    if (!_commandController.isClosed) {
      _commandController.add(envelope);
    }
  }

  void _handleAlert(WsEnvelope envelope) {
    if (!_alertController.isClosed) {
      _alertController.add(envelope);
    }
  }

  void _handleUpdate(WsEnvelope envelope) {
    if (!_updateController.isClosed) {
      _updateController.add(envelope);
    }
  }

  void _onError(Object error) {
    if (_disposed) return;
    _updateState(WsConnectionState.disconnected, error: error.toString());
    _scheduleReconnect();
  }

  void _onDone() {
    if (_disposed || _manualDisconnect) return;
    _updateState(WsConnectionState.disconnected);
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed || _manualDisconnect) return;
    if (_reconnectAttempt >= _config.maxReconnectAttempts) {
      _updateState(
        WsConnectionState.failed,
        error: 'Max reconnect attempts reached',
      );
      return;
    }

    _reconnectAttempt++;
    final backoff = _calculateBackoff();

    _updateState(
      WsConnectionState.reconnecting,
      reconnectAttempt: _reconnectAttempt,
    );

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(milliseconds: backoff), () {
      if (!_disposed && !_manualDisconnect) {
        _doConnect();
      }
    });
  }

  int _calculateBackoff() {
    final base = _config.initialBackoffMs *
        pow(_config.backoffMultiplier, _reconnectAttempt - 1);
    final jitter = Random().nextInt(500);
    return min(base.toInt() + jitter, _config.maxBackoffMs);
  }

  void _startHeartbeat(int intervalSeconds) {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      Duration(seconds: intervalSeconds),
      (_) => _sendHeartbeat(),
    );
  }

  void _sendHeartbeat() {
    if (_state != WsConnectionState.authenticated) return;

    final heartbeat = {
      'type': 'HEARTBEAT',
      'from': 'mobile',
      'device_id': _deviceId ?? 'mobile-unknown',
      'message_id': 'm-hb-${DateTime.now().millisecondsSinceEpoch}',
      'session_id': _sessionId,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'body': {
        'status': 'healthy',
      },
      'sig': 'mobile-sig-heartbeat',
    };

    _send(heartbeat);
  }

  /// Send a raw message envelope.
  void _send(Map<String, dynamic> envelope) {
    if (_channel == null) return;
    try {
      _channel!.sink.add(jsonEncode(envelope));
    } catch (e) {
      // ignore: avoid_print
      print('WebSocket send error: $e');
    }
  }

  /// Send a command acknowledgment.
  void sendCommandAck({
    required String commandMessageId,
    required String status,
  }) {
    if (_state != WsConnectionState.authenticated) return;

    final ack = {
      'type': 'COMMAND_ACK',
      'from': 'mobile',
      'device_id': _deviceId ?? 'mobile-unknown',
      'message_id': 'm-ack-${DateTime.now().millisecondsSinceEpoch}',
      'session_id': _sessionId,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'body': {
        'command_message_id': commandMessageId,
        'status': status,
      },
      'sig': 'mobile-sig-ack',
    };

    _send(ack);
  }

  /// Disconnect from the WebSocket server.
  Future<void> disconnect() async {
    _manualDisconnect = true;
    await _cleanup();
    _updateState(WsConnectionState.disconnected);
  }

  Future<void> _cleanup() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
  }

  void _updateState(
    WsConnectionState newState, {
    String? error,
    int? reconnectAttempt,
  }) {
    _state = newState;

    if (!_stateController.isClosed) {
      _stateController.add(WsStateEvent(
        state: newState,
        timestamp: DateTime.now(),
        error: error,
        reconnectAttempt: reconnectAttempt,
        sessionId: _sessionId,
      ));
    }
  }

  String _generateNonce() {
    final random = Random.secure();
    final bytes = List.generate(16, (_) => random.nextInt(256));
    return base64Encode(bytes);
  }

  /// Dispose the service and release all resources.
  Future<void> dispose() async {
    _disposed = true;
    await _cleanup();
    await _stateController.close();
    await _messageController.close();
    await _commandController.close();
    await _alertController.close();
    await _updateController.close();
  }
}
