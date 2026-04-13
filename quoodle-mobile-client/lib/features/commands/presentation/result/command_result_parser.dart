import 'dart:convert';

enum ParsedResultKind {
  screenshot,
  processList,
  fileSystem,
  systemInfo,
  generic,
}

class ParsedCommandResult {
  const ParsedCommandResult({
    required this.method,
    required this.canonicalMethod,
    required this.kind,
    required this.result,
    required this.resultData,
    required this.resultStatus,
    required this.resultNotes,
    required this.artifactUrl,
    required this.artifactChecksum,
    required this.executionState,
    required this.errorCode,
    required this.errorMessage,
    required this.params,
  });

  final String method;
  final String canonicalMethod;
  final ParsedResultKind kind;
  final Map<String, dynamic> result;
  final Object? resultData;
  final String resultStatus;
  final String resultNotes;
  final String artifactUrl;
  final String artifactChecksum;
  final String executionState;
  final String errorCode;
  final String errorMessage;
  final Object? params;
}

class FileSystemEntry {
  const FileSystemEntry({
    required this.path,
    required this.isDirectory,
    this.sizeBytes,
    this.modifiedAtEpoch,
  });

  final String path;
  final bool isDirectory;
  final int? sizeBytes;
  final int? modifiedAtEpoch;

  String get name {
    final normalized = path.replaceAll('\\', '/');
    final chunks = normalized.split('/').where((e) => e.isNotEmpty).toList();
    return chunks.isEmpty ? path : chunks.last;
  }

  String get parentPath {
    final normalized = path.replaceAll('\\', '/');
    final chunks = normalized.split('/').where((e) => e.isNotEmpty).toList();
    if (chunks.length <= 1) {
      return '';
    }
    if (chunks.length == 2 && RegExp(r'^[A-Za-z]:$').hasMatch(chunks.first)) {
      return '';
    }
    return chunks.sublist(0, chunks.length - 1).join('/');
  }
}

String canonicalCommandMethod(String method) {
  switch (method.trim().toLowerCase()) {
    case 'screenshot_capture':
      return 'screenshot';
    case 'process_list':
    case 'running_apps':
      return 'list_processes';
    case 'filesystem':
      return 'list_files';
    case 'system_info':
    case 'collect_telemetry':
      return 'collect_system_info';
    default:
      return method.trim().toLowerCase();
  }
}

ParsedCommandResult parseCommandResult(Map<String, dynamic> command) {
  final method = _asString(command['method']);
  final canonicalMethod = canonicalCommandMethod(method);
  final result = _asStringDynamicMap(command['result']);
  final params = _decodeMaybeJson(command['params']);
  final resultStatus =
      _asString(command['resultStatus']).ifEmpty(_asString(result['status']));
  final resultNotes = _asString(command['resultNotes'])
      .ifEmpty(_asString(result['notes']))
      .ifEmpty(_asString(command['reason']))
      .ifEmpty(_asString(command['errorMessage']));
  final artifactUrl = normalizeArtifactUrl(
    _asString(command['artifactUrl'])
        .ifEmpty(_asString(result['artifact_url'])),
  );
  final artifactChecksum = _asString(command['artifactChecksum'])
      .ifEmpty(_asString(result['artifact_checksum']));
  final executionState = _asString(command['executionState'])
      .ifEmpty(_asString(command['state']))
      .ifEmpty('unknown');
  final errorCode = _asString(command['errorCode']);
  final errorMessage =
      _asString(command['errorMessage']).ifEmpty(_asString(command['reason']));
  final resultData = _extractResultData(result);

  return ParsedCommandResult(
    method: method.ifEmpty('unknown_method'),
    canonicalMethod: canonicalMethod,
    kind: _kindForMethod(canonicalMethod),
    result: result,
    resultData: resultData,
    resultStatus: resultStatus,
    resultNotes: resultNotes,
    artifactUrl: artifactUrl,
    artifactChecksum: artifactChecksum,
    executionState: executionState,
    errorCode: errorCode,
    errorMessage: errorMessage,
    params: params,
  );
}

List<Map<String, dynamic>> extractProcessRows(Object? resultData) {
  if (resultData is List) {
    return resultData
        .whereType<Map>()
        .map(_asStringDynamicMap)
        .toList(growable: false);
  }
  if (resultData is Map) {
    final map = _asStringDynamicMap(resultData);
    final nested = map['processes'];
    if (nested is List) {
      return nested
          .whereType<Map>()
          .map(_asStringDynamicMap)
          .toList(growable: false);
    }
  }
  return const <Map<String, dynamic>>[];
}

List<FileSystemEntry> extractFileSystemEntries(Object? resultData) {
  final entriesRaw = _extractFileSystemEntriesRaw(resultData);
  final parsed = <FileSystemEntry>[];
  for (final item in entriesRaw) {
    final entry = _asStringDynamicMap(item);
    final path = _asString(entry['path']);
    if (path.isEmpty) {
      continue;
    }
    final isDir = _toBool(entry['is_dir']) || _toBool(entry['is_directory']);
    parsed.add(
      FileSystemEntry(
        path: path,
        isDirectory: isDir,
        sizeBytes: _toInt(entry['size']),
        modifiedAtEpoch: _toInt(entry['mtime']),
      ),
    );
  }
  parsed.sort((a, b) {
    if (a.isDirectory != b.isDirectory) {
      return a.isDirectory ? -1 : 1;
    }
    return a.path.toLowerCase().compareTo(b.path.toLowerCase());
  });
  return parsed;
}

Map<String, dynamic> extractSystemInfoData(Object? resultData) {
  return _asStringDynamicMap(resultData);
}

bool inferWindowsStylePaths(
  List<FileSystemEntry> entries, {
  Map<String, dynamic>? systemInfoData,
}) {
  if (entries.any((entry) => entry.path.contains('\\'))) {
    return true;
  }
  if (entries.any((entry) => RegExp(r'^[A-Za-z]:').hasMatch(entry.path))) {
    return true;
  }
  final osData = _asStringDynamicMap(systemInfoData?['os']);
  final identity = _asStringDynamicMap(systemInfoData?['identity']);
  final hints = [
    _asString(osData['platform']),
    _asString(osData['name']),
    _asString(osData['product_name']),
    _asString(identity['platform']),
  ].join(' ').toLowerCase();
  return hints.contains('windows');
}

String normalizeArtifactUrl(String raw) {
  final value = raw.trim();
  if (value.isEmpty) {
    return '';
  }
  if (value.startsWith('/api/artifact/')) {
    return value;
  }
  if (value.startsWith('api/artifact/')) {
    return '/$value';
  }

  final parsed = Uri.tryParse(value);
  if (parsed != null &&
      (parsed.scheme == 'http' || parsed.scheme == 'https') &&
      parsed.path.contains('/api/artifact/')) {
    return parsed.toString();
  }
  return value;
}

Object? _extractResultData(Map<String, dynamic> result) {
  final data = result['data'];
  if (data != null) {
    return data;
  }
  if (result.containsKey('processes') ||
      result.containsKey('entries') ||
      result.containsKey('identity') ||
      result.containsKey('os') ||
      result.containsKey('hardware') ||
      result.containsKey('runtime')) {
    return result;
  }
  return result.isEmpty ? null : result;
}

List<Map<dynamic, dynamic>> _extractFileSystemEntriesRaw(Object? resultData) {
  if (resultData is Map) {
    final map = _asStringDynamicMap(resultData);
    final entries = map['entries'];
    if (entries is List) {
      return entries.whereType<Map>().toList(growable: false);
    }
  }
  if (resultData is List) {
    return resultData.whereType<Map>().toList(growable: false);
  }
  return const <Map<dynamic, dynamic>>[];
}

ParsedResultKind _kindForMethod(String method) {
  switch (method) {
    case 'screenshot':
      return ParsedResultKind.screenshot;
    case 'list_processes':
      return ParsedResultKind.processList;
    case 'list_files':
      return ParsedResultKind.fileSystem;
    case 'collect_system_info':
      return ParsedResultKind.systemInfo;
    default:
      return ParsedResultKind.generic;
  }
}

Map<String, dynamic> _asStringDynamicMap(Object? value) {
  if (value is Map) {
    return value.map(
      (key, mapValue) => MapEntry(key.toString(), mapValue),
    );
  }
  return const <String, dynamic>{};
}

Object? _decodeMaybeJson(Object? value) {
  if (value is Map || value is List) {
    return value;
  }
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    try {
      return jsonDecode(trimmed);
    } catch (_) {
      return trimmed;
    }
  }
  return value;
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

bool _toBool(Object? value) {
  if (value is bool) {
    return value;
  }
  if (value is num) {
    return value != 0;
  }
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    return normalized == 'true' || normalized == '1' || normalized == 'yes';
  }
  return false;
}

int? _toInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value.trim());
  }
  return null;
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
