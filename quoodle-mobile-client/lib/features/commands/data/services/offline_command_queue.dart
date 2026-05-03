import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:secure_device_control/features/commands/domain/services/control_plane_dispatch_payload.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef OfflineCommandDispatcher = Future<Map<String, dynamic>> Function({
  required String deviceId,
  required String method,
  required Map<String, dynamic> params,
  required bool sensitive,
});

enum QueuedCommandStatus { pending, syncing, success, failed, retrying }

class QueuedCommand {
  final String id;
  final String deviceId;
  final String deviceName;
  final String method;
  final Map<String, dynamic> params;
  final DateTime queuedAt;
  QueuedCommandStatus status;
  String? errorMessage;
  int retryCount;
  DateTime? lastAttemptAt;
  DateTime? completedAt;

  QueuedCommand({
    required this.id,
    required this.deviceId,
    required this.deviceName,
    required this.method,
    required this.params,
    required this.queuedAt,
    this.status = QueuedCommandStatus.pending,
    this.errorMessage,
    this.retryCount = 0,
    this.lastAttemptAt,
    this.completedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'deviceId': deviceId,
        'deviceName': deviceName,
        'method': method,
        'params': params,
        'queuedAt': queuedAt.toIso8601String(),
        'status': status.name,
        'errorMessage': errorMessage,
        'retryCount': retryCount,
        'lastAttemptAt': lastAttemptAt?.toIso8601String(),
        'completedAt': completedAt?.toIso8601String(),
      };

  factory QueuedCommand.fromJson(Map<String, dynamic> json) => QueuedCommand(
        id: json['id'] as String,
        deviceId: json['deviceId'] as String,
        deviceName: json['deviceName'] as String,
        method: json['method'] as String,
        params: Map<String, dynamic>.from(json['params'] as Map),
        queuedAt: DateTime.parse(json['queuedAt'] as String),
        status: QueuedCommandStatus.values.firstWhere(
          (s) => s.name == json['status'],
          orElse: () => QueuedCommandStatus.pending,
        ),
        errorMessage: json['errorMessage'] as String?,
        retryCount: (json['retryCount'] as int?) ?? 0,
        lastAttemptAt: json['lastAttemptAt'] != null
            ? DateTime.parse(json['lastAttemptAt'] as String)
            : null,
        completedAt: json['completedAt'] != null
            ? DateTime.parse(json['completedAt'] as String)
            : null,
      );

  QueuedCommand copyWith({
    QueuedCommandStatus? status,
    String? errorMessage,
    int? retryCount,
    DateTime? lastAttemptAt,
    DateTime? completedAt,
  }) =>
      QueuedCommand(
        id: id,
        deviceId: deviceId,
        deviceName: deviceName,
        method: method,
        params: params,
        queuedAt: queuedAt,
        status: status ?? this.status,
        errorMessage: errorMessage ?? this.errorMessage,
        retryCount: retryCount ?? this.retryCount,
        lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
        completedAt: completedAt ?? this.completedAt,
      );
}

class OfflineCommandQueue extends ChangeNotifier {
  static final OfflineCommandQueue _instance = OfflineCommandQueue._internal();
  factory OfflineCommandQueue() => _instance;
  OfflineCommandQueue._internal();

  static const String _storageKey = 'offline_command_queue';
  static const int _maxRetries = 3;

  final List<QueuedCommand> _commands = [];
  bool _isOnline = true;
  bool _isSyncing = false;
  bool _initialized = false;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  Timer? _syncTimer;
  OfflineCommandDispatcher? _dispatcher;

  List<QueuedCommand> get commands => List.unmodifiable(_commands);
  bool get isOnline => _isOnline;
  bool get isSyncing => _isSyncing;
  int get pendingCount => _commands
      .where(
        (c) =>
            c.status == QueuedCommandStatus.pending ||
            c.status == QueuedCommandStatus.retrying,
      )
      .length;
  int get failedCount =>
      _commands.where((c) => c.status == QueuedCommandStatus.failed).length;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    await _loadFromStorage();
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final wasOffline = !_isOnline;
      _isOnline = results.any((r) => r != ConnectivityResult.none);
      notifyListeners();
      if (wasOffline && _isOnline) {
        _autoSync();
      }
    });
    // Check initial connectivity
    final initial = await Connectivity().checkConnectivity();
    _isOnline = initial.any((r) => r != ConnectivityResult.none);
    notifyListeners();
  }

  void configureDispatcher(OfflineCommandDispatcher dispatcher) {
    _dispatcher = dispatcher;
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _syncTimer?.cancel();
    _initialized = false;
    super.dispose();
  }

  Future<void> enqueue({
    required String deviceId,
    required String deviceName,
    required String method,
    required Map<String, dynamic> params,
  }) async {
    final cmd = QueuedCommand(
      id: '${DateTime.now().millisecondsSinceEpoch}_$method',
      deviceId: deviceId,
      deviceName: deviceName,
      method: method,
      params: params,
      queuedAt: DateTime.now(),
      status:
          _isOnline ? QueuedCommandStatus.pending : QueuedCommandStatus.pending,
    );
    _commands.insert(0, cmd);
    await _saveToStorage();
    notifyListeners();

    if (_isOnline) {
      _syncCommand(cmd);
    }
  }

  Future<void> retryCommand(String commandId) async {
    final idx = _commands.indexWhere((c) => c.id == commandId);
    if (idx == -1) return;
    final cmd = _commands[idx];
    if (cmd.retryCount >= _maxRetries) return;

    _commands[idx] = cmd.copyWith(
      status: QueuedCommandStatus.retrying,
      errorMessage: null,
    );
    await _saveToStorage();
    notifyListeners();

    if (_isOnline) {
      _syncCommand(_commands[idx]);
    }
  }

  Future<void> removeCommand(String commandId) async {
    _commands.removeWhere((c) => c.id == commandId);
    await _saveToStorage();
    notifyListeners();
  }

  Future<void> clearCompleted() async {
    _commands.removeWhere((c) => c.status == QueuedCommandStatus.success);
    await _saveToStorage();
    notifyListeners();
  }

  Future<void> _autoSync() async {
    if (_isSyncing) return;
    _isSyncing = true;
    notifyListeners();

    final toSync = _commands
        .where(
          (c) =>
              c.status == QueuedCommandStatus.pending ||
              c.status == QueuedCommandStatus.retrying,
        )
        .toList();

    for (final cmd in toSync) {
      if (!_isOnline) break;
      await _syncCommand(cmd);
      await Future.delayed(const Duration(milliseconds: 300));
    }

    _isSyncing = false;
    notifyListeners();
  }

  Future<void> _syncCommand(QueuedCommand cmd) async {
    final idx = _commands.indexWhere((c) => c.id == cmd.id);
    if (idx == -1) return;

    _commands[idx] = _commands[idx].copyWith(
      status: QueuedCommandStatus.syncing,
      lastAttemptAt: DateTime.now(),
    );
    notifyListeners();

    try {
      final dispatcher = _dispatcher;
      if (dispatcher == null) {
        throw Exception('Queue dispatch is not configured.');
      }
      final normalized = normalizeCommandForControlPlane(
        methodId: cmd.method,
        params: cmd.params,
      );
      final response = await dispatcher(
        deviceId: cmd.deviceId,
        method: normalized.methodId,
        params: normalized.params,
        sensitive: false,
      );
      final status = _asString(response['status']);
      if (status != 'accepted') {
        final reason = _asString(response['reason']);
        throw Exception(_messageForDispatchFailureReason(reason));
      }

      _commands[idx] = _commands[idx].copyWith(
        status: QueuedCommandStatus.success,
        completedAt: DateTime.now(),
        errorMessage: null,
      );
    } catch (e) {
      final current = _commands[idx];
      final newRetryCount = current.retryCount + 1;
      _commands[idx] = current.copyWith(
        status: newRetryCount >= _maxRetries
            ? QueuedCommandStatus.failed
            : QueuedCommandStatus.pending,
        errorMessage: e.toString().replaceFirst('Exception: ', ''),
        retryCount: newRetryCount,
      );
    }

    await _saveToStorage();
    notifyListeners();
  }

  Future<void> _loadFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw != null) {
        final list = jsonDecode(raw) as List;
        _commands.clear();
        _commands.addAll(
          list.map((e) => QueuedCommand.fromJson(e as Map<String, dynamic>)),
        );
        // Reset syncing states on load
        for (int i = 0; i < _commands.length; i++) {
          if (_commands[i].status == QueuedCommandStatus.syncing) {
            _commands[i] = _commands[i].copyWith(
              status: QueuedCommandStatus.pending,
            );
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _saveToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _storageKey,
        jsonEncode(_commands.map((c) => c.toJson()).toList()),
      );
    } catch (_) {}
  }

  String _asString(Object? value) {
    if (value is String) {
      return value;
    }
    if (value == null) {
      return '';
    }
    return value.toString();
  }

  String _messageForDispatchFailureReason(String reason) {
    switch (reason) {
      case 'device_not_found':
        return 'Target device was not found.';
      case 'unknown_command':
        return 'Command type is not supported.';
      case 'not_supported_runtime':
        return 'Runtime does not support this command yet.';
      case 'invalid_params':
        return 'Command parameters are invalid.';
      case 'compliance_failed':
        return 'Device compliance checks failed. Command denied.';
      case 'rate_limited':
        return 'Too many requests. Please try again shortly.';
      default:
        return 'Command rejected by policy or backend validation.';
    }
  }
}
