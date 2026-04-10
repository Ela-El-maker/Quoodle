import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import './command_results_database.dart';

// Native (mobile/desktop) implementation using sqflite.

Database? _db;

Future<Database> _getDb() async {
  if (_db != null) return _db!;
  final dbPath = await getDatabasesPath();
  final fullPath = p.join(dbPath, 'command_results.db');
  _db = await openDatabase(
    fullPath,
    version: 1,
    onCreate: (db, version) async {
      await db.execute('''
        CREATE TABLE command_results (
          commandId   TEXT PRIMARY KEY,
          method      TEXT NOT NULL,
          deviceId    TEXT NOT NULL,
          deviceName  TEXT NOT NULL,
          initiator   TEXT NOT NULL,
          status      TEXT NOT NULL,
          commandData TEXT NOT NULL,
          savedAt     TEXT NOT NULL
        )
      ''');
      await db.execute(
        'CREATE INDEX idx_deviceId ON command_results (deviceId)',
      );
      await db.execute('CREATE INDEX idx_savedAt ON command_results (savedAt)');
    },
  );
  return _db!;
}

Future<void> initNativeDb() async {
  await _getDb();
}

Future<void> nativeSave(CommandResultRecord record) async {
  final db = await _getDb();
  await db.insert(
    'command_results',
    record.toMap(),
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}

Future<CommandResultRecord?> nativeLoad(String commandId) async {
  final db = await _getDb();
  final rows = await db.query(
    'command_results',
    where: 'commandId = ?',
    whereArgs: [commandId],
    limit: 1,
  );
  if (rows.isEmpty) return null;
  try {
    return CommandResultRecord.fromMap(rows.first);
  } catch (_) {
    return null;
  }
}

Future<List<CommandResultRecord>> nativeLoadAll() async {
  final db = await _getDb();
  final rows = await db.query('command_results', orderBy: 'savedAt DESC');
  return rows
      .map((r) {
        try {
          return CommandResultRecord.fromMap(r);
        } catch (_) {
          return null;
        }
      })
      .whereType<CommandResultRecord>()
      .toList();
}

Future<List<CommandResultRecord>> nativeLoadByDevice(String deviceId) async {
  final db = await _getDb();
  final rows = await db.query(
    'command_results',
    where: 'deviceId = ?',
    whereArgs: [deviceId],
    orderBy: 'savedAt DESC',
  );
  return rows
      .map((r) {
        try {
          return CommandResultRecord.fromMap(r);
        } catch (_) {
          return null;
        }
      })
      .whereType<CommandResultRecord>()
      .toList();
}

Future<void> nativeDelete(String commandId) async {
  final db = await _getDb();
  await db.delete(
    'command_results',
    where: 'commandId = ?',
    whereArgs: [commandId],
  );
}

Future<void> nativePruneOlderThan(DateTime cutoff) async {
  final db = await _getDb();
  await db.delete(
    'command_results',
    where: 'savedAt < ?',
    whereArgs: [cutoff.toIso8601String()],
  );
}
