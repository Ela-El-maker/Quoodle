/// Connection states for the WebSocket service.
enum WsConnectionState {
  /// Not connected and not attempting to connect.
  disconnected,

  /// Attempting to establish a connection.
  connecting,

  /// Socket connected, but not yet authenticated.
  connected,

  /// Auth message sent, waiting for AUTH_ACK/AUTH_ERROR.
  authenticating,

  /// Fully authenticated and ready to send/receive messages.
  authenticated,

  /// Connection lost, will attempt to reconnect.
  reconnecting,

  /// Permanently failed (e.g., auth rejected).
  failed,
}

/// Event emitted when connection state changes.
class WsStateEvent {
  const WsStateEvent({
    required this.state,
    required this.timestamp,
    this.error,
    this.reconnectAttempt,
    this.sessionId,
  });

  final WsConnectionState state;
  final DateTime timestamp;
  final String? error;
  final int? reconnectAttempt;
  final String? sessionId;

  bool get isConnected =>
      state == WsConnectionState.connected ||
      state == WsConnectionState.authenticated ||
      state == WsConnectionState.authenticating;

  bool get isAuthenticated => state == WsConnectionState.authenticated;

  bool get isReconnecting => state == WsConnectionState.reconnecting;

  bool get isFailed => state == WsConnectionState.failed;

  @override
  String toString() => 'WsStateEvent(state: $state, error: $error, '
      'reconnectAttempt: $reconnectAttempt)';
}
