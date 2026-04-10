import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Conditional imports for sqflite (not web-compatible)
import 'command_results_db_stub.dart'
    if (dart.library.io) 'command_results_db_native.dart';

/// Represents a persisted command result record.
class CommandResultRecord {
  final String commandId;
  final String method;
  final String deviceId;
  final String deviceName;
  final String initiator;
  final String status; // 'completed' | 'failed' | 'expired'
  final Map<String, dynamic> commandData;
  final DateTime savedAt;

  CommandResultRecord({
    required this.commandId,
    required this.method,
    required this.deviceId,
    required this.deviceName,
    required this.initiator,
    required this.status,
    required this.commandData,
    required this.savedAt,
  });

  Map<String, dynamic> toMap() => {
        'commandId': commandId,
        'method': method,
        'deviceId': deviceId,
        'deviceName': deviceName,
        'initiator': initiator,
        'status': status,
        'commandData': jsonEncode(commandData),
        'savedAt': savedAt.toIso8601String(),
      };

  factory CommandResultRecord.fromMap(Map<String, dynamic> map) =>
      CommandResultRecord(
        commandId: map['commandId'] as String,
        method: map['method'] as String,
        deviceId: map['deviceId'] as String,
        deviceName: map['deviceName'] as String,
        initiator: map['initiator'] as String,
        status: map['status'] as String,
        commandData:
            jsonDecode(map['commandData'] as String) as Map<String, dynamic>,
        savedAt: DateTime.parse(map['savedAt'] as String),
      );
}

/// Platform-aware persistent storage for command results.
/// Uses SQLite on mobile/desktop, SharedPreferences on web.
class CommandResultsDatabase {
  static final CommandResultsDatabase _instance =
      CommandResultsDatabase._internal();
  factory CommandResultsDatabase() => _instance;
  CommandResultsDatabase._internal();

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    if (!kIsWeb) {
      await initNativeDb();
    }
    _initialized = true;
  }

  /// Save or update a command result.
  Future<void> saveResult(CommandResultRecord record) async {
    await initialize();
    if (kIsWeb) {
      await _webSave(record);
    } else {
      await nativeSave(record);
    }
  }

  /// Load a single result by commandId.
  Future<CommandResultRecord?> loadResult(String commandId) async {
    await initialize();
    if (kIsWeb) {
      return _webLoad(commandId);
    } else {
      return nativeLoad(commandId);
    }
  }

  /// Load all saved results, newest first.
  Future<List<CommandResultRecord>> loadAll() async {
    await initialize();
    if (kIsWeb) {
      return _webLoadAll();
    } else {
      return nativeLoadAll();
    }
  }

  /// Load results filtered by deviceId.
  Future<List<CommandResultRecord>> loadByDevice(String deviceId) async {
    await initialize();
    if (kIsWeb) {
      final all = await _webLoadAll();
      return all.where((r) => r.deviceId == deviceId).toList();
    } else {
      return nativeLoadByDevice(deviceId);
    }
  }

  /// Delete a result by commandId.
  Future<void> deleteResult(String commandId) async {
    await initialize();
    if (kIsWeb) {
      await _webDelete(commandId);
    } else {
      await nativeDelete(commandId);
    }
  }

  /// Delete all results older than [days] days.
  Future<void> pruneOlderThan(int days) async {
    await initialize();
    final cutoff = DateTime.now().subtract(Duration(days: days));
    if (kIsWeb) {
      await _webPruneOlderThan(cutoff);
    } else {
      await nativePruneOlderThan(cutoff);
    }
  }

  // ── Web implementation (SharedPreferences) ──────────────────────────────

  static const String _webKey = 'command_results_store';

  Future<Map<String, dynamic>> _webReadStore() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_webKey);
    if (raw == null) return {};
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  Future<void> _webWriteStore(Map<String, dynamic> store) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_webKey, jsonEncode(store));
  }

  Future<void> _webSave(CommandResultRecord record) async {
    final store = await _webReadStore();
    store[record.commandId] = record.toMap();
    await _webWriteStore(store);
  }

  Future<CommandResultRecord?> _webLoad(String commandId) async {
    final store = await _webReadStore();
    final entry = store[commandId];
    if (entry == null) return null;
    try {
      return CommandResultRecord.fromMap(
        Map<String, dynamic>.from(entry as Map),
      );
    } catch (_) {
      return null;
    }
  }

  Future<List<CommandResultRecord>> _webLoadAll() async {
    final store = await _webReadStore();
    final records = <CommandResultRecord>[];
    for (final entry in store.values) {
      try {
        records.add(
          CommandResultRecord.fromMap(Map<String, dynamic>.from(entry as Map)),
        );
      } catch (_) {}
    }
    records.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return records;
  }

  Future<void> _webDelete(String commandId) async {
    final store = await _webReadStore();
    store.remove(commandId);
    await _webWriteStore(store);
  }

  Future<void> _webPruneOlderThan(DateTime cutoff) async {
    final store = await _webReadStore();
    store.removeWhere((_, v) {
      try {
        final map = Map<String, dynamic>.from(v as Map);
        final savedAt = DateTime.parse(map['savedAt'] as String);
        return savedAt.isBefore(cutoff);
      } catch (_) {
        return false;
      }
    });
    await _webWriteStore(store);
  }
}
