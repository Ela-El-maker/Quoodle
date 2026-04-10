import './command_results_database.dart';

// Stub implementation — used on web where sqflite is unavailable.
// All methods are no-ops; the web path in CommandResultsDatabase handles storage.

Future<void> initNativeDb() async {}

Future<void> nativeSave(CommandResultRecord record) async {}

Future<CommandResultRecord?> nativeLoad(String commandId) async => null;

Future<List<CommandResultRecord>> nativeLoadAll() async => [];

Future<List<CommandResultRecord>> nativeLoadByDevice(String deviceId) async =>
    [];

Future<void> nativeDelete(String commandId) async {}

Future<void> nativePruneOlderThan(DateTime cutoff) async {}
