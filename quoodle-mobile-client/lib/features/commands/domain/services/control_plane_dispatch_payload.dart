class ControlPlaneDispatchPayload {
  const ControlPlaneDispatchPayload({
    required this.methodId,
    required this.params,
  });

  final String methodId;
  final Map<String, dynamic> params;
}

ControlPlaneDispatchPayload normalizeCommandForControlPlane({
  required String methodId,
  required Map<String, dynamic> params,
}) {
  switch (methodId) {
    case 'screenshot_capture':
      return ControlPlaneDispatchPayload(
        methodId: 'screenshot',
        params: <String, dynamic>{
          'resolution': _resolutionForQuality(_asString(params['quality'])),
        },
      );
    case 'process_list':
    case 'running_apps':
      return ControlPlaneDispatchPayload(
        methodId: 'list_processes',
        params: <String, dynamic>{
          'limit': _toInt(params['limit']) ?? 50,
        },
      );
    case 'filesystem':
      return ControlPlaneDispatchPayload(
        methodId: 'list_files',
        params: <String, dynamic>{
          'path': _normalizePath(_asString(params['path'])),
          'recursive': (_toInt(params['depth']) ?? 1) > 1,
          'limit': 200,
        },
      );
    case 'system_info':
    case 'collect_telemetry':
      return const ControlPlaneDispatchPayload(
        methodId: 'collect_system_info',
        params: <String, dynamic>{},
      );
    case 'policy_sync':
      return const ControlPlaneDispatchPayload(
        methodId: 'policy_probe',
        params: <String, dynamic>{'command': 'policy_sync'},
      );
    case 'reboot':
      return ControlPlaneDispatchPayload(
        methodId: 'reboot_device',
        params: <String, dynamic>{
          'delay_seconds': _toInt(params['delay_seconds']) ?? 30,
        },
      );
    case 'upload_file':
      final destinationSource = _asString(params['path']);
      final destination = _normalizePath(destinationSource);
      return ControlPlaneDispatchPayload(
        methodId: 'upload_file',
        params: <String, dynamic>{
          'artifact_id': _artifactIdForPath(destinationSource),
          'destination': destination,
          'overwrite': params['overwrite'] == true,
        },
      );
    case 'create_file':
      return ControlPlaneDispatchPayload(
        methodId: 'create_file',
        params: <String, dynamic>{
          'path': _normalizePath(_asString(params['path'])),
          'overwrite': params['overwrite'] == true,
          if (_asString(params['content']).isNotEmpty)
            'content': _asString(params['content']),
        },
      );
    default:
      return ControlPlaneDispatchPayload(methodId: methodId, params: params);
  }
}

String _resolutionForQuality(String quality) {
  switch (quality) {
    case 'low':
      return '720p';
    case 'medium':
      return '1080p';
    default:
      return 'original';
  }
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

String _normalizePath(String raw) {
  var value = raw.trim().replaceAll('\\', '/');
  value = value.replaceFirst(RegExp(r'^[A-Za-z]:/?'), '');
  value = value.replaceFirst(RegExp(r'^/+'), '');
  if (value.isEmpty) {
    return 'tmp';
  }
  return value;
}

String _artifactIdForPath(String rawPath) {
  final normalized = _normalizePath(rawPath);
  final leaf = normalized.split('/').where((segment) => segment.isNotEmpty);
  final suffix = leaf.isEmpty ? 'artifact' : leaf.last;
  return 'mobile-$suffix';
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
