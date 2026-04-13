import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:secure_device_control/features/commands/presentation/providers/commands_api_providers.dart';
import 'package:secure_device_control/features/commands/presentation/providers/send_command_state.dart';

class SendCommandDispatchResult {
  const SendCommandDispatchResult({
    required this.success,
    this.errorMessage,
    this.timelineArguments,
  });

  final bool success;
  final String? errorMessage;
  final Map<String, dynamic>? timelineArguments;
}

class SendCommandController extends AutoDisposeNotifier<SendCommandState> {
  @override
  SendCommandState build() {
    return SendCommandState.initial();
  }

  void selectMethod(String methodId) {
    state = state.copyWith(
      selectedMethodId: methodId,
      sensitiveOverride: false,
    );
  }

  void toggleSensitiveOverride() {
    state = state.copyWith(sensitiveOverride: !state.sensitiveOverride);
  }

  void togglePolicyPanel() {
    state = state.copyWith(showPolicyPanel: !state.showPolicyPanel);
  }

  Future<SendCommandDispatchResult> dispatchCommand({
    required String deviceId,
    required String deviceName,
    required String methodId,
    required Map<String, dynamic> params,
    required bool sensitive,
  }) async {
    final dispatchPayload = _normalizeForControlPlane(
      methodId: methodId,
      params: params,
    );

    state = state.copyWith(submitting: true);
    try {
      final response =
          await ref.read(commandsRemoteDataSourceProvider).dispatchCommand(
                deviceId: deviceId,
                method: dispatchPayload.methodId,
                params: dispatchPayload.params,
                sensitive: sensitive,
              );

      final status = _asString(response['status']);
      if (status != 'accepted') {
        return SendCommandDispatchResult(
          success: false,
          errorMessage: _messageForDispatchFailureReason(
            _asString(response['reason']),
          ),
        );
      }

      final commandId = _asString(response['command_id']);
      if (commandId.isEmpty) {
        return const SendCommandDispatchResult(
          success: false,
          errorMessage:
              'Command was accepted but no command ID was returned. Please retry.',
        );
      }

      final queuedAt = _asString(response['queued_at']);
      final policyDecision = 'allow';
      return SendCommandDispatchResult(
        success: true,
        timelineArguments: <String, dynamic>{
          'id': commandId,
          'method': dispatchPayload.methodId,
          'params': dispatchPayload.params,
          'sensitive': sensitive,
          'deviceId': deviceId,
          'deviceName': deviceName,
          'initiator': 'Operator',
          'role': 'operator',
          'policyDecision': policyDecision,
          if (queuedAt.isNotEmpty) 'queuedAt': queuedAt,
          'state': 'queued',
        },
      );
    } on DioException catch (error) {
      final body = error.response?.data;
      String reason = '';
      String? detail;
      if (body is Map) {
        reason = _asString(body['reason']);
        final message = _asString(body['message']);
        if (reason.isEmpty) {
          reason = message;
        }
        detail = _extractValidationDetail(body['errors']);
      }

      return SendCommandDispatchResult(
        success: false,
        errorMessage: detail ?? _messageForDispatchFailureReason(reason),
      );
    } catch (_) {
      return const SendCommandDispatchResult(
        success: false,
        errorMessage:
            'Unable to send command right now. Check network and retry.',
      );
    } finally {
      state = state.copyWith(submitting: false);
    }
  }

  String _messageForDispatchFailureReason(String reason) {
    switch (reason) {
      case '2fa_required':
        return 'Control plane requires 2FA for this command.';
      case 'invalid_2fa':
        return '2FA validation failed on control plane.';
      case 'device_not_found':
        return 'Target device was not found.';
      case 'unknown_command':
        return 'Command type is not supported.';
      case 'not_supported_runtime':
        return 'Control plane accepted method, but runtime does not support it yet.';
      case 'invalid_params':
        return 'Command parameters are invalid.';
      case 'compliance_failed':
        return 'Device compliance checks failed. Command denied.';
      case 'rate_limited':
        return 'Too many requests. Please try again shortly.';
      case 'validation_error':
        return 'Invalid request. Please check command input.';
      default:
        return 'Command rejected by policy or backend validation.';
    }
  }

  String? _extractValidationDetail(Object? errors) {
    if (errors is! Map) {
      return null;
    }
    for (final entry in errors.entries) {
      final value = entry.value;
      if (value is List && value.isNotEmpty) {
        final first = value.first;
        if (first is String && first.trim().isNotEmpty) {
          return first.trim();
        }
      }
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return null;
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

  _ControlPlaneDispatchPayload _normalizeForControlPlane({
    required String methodId,
    required Map<String, dynamic> params,
  }) {
    switch (methodId) {
      case 'screenshot_capture':
        return _ControlPlaneDispatchPayload(
          methodId: 'screenshot',
          params: <String, dynamic>{
            'resolution': _resolutionForQuality(_asString(params['quality'])),
          },
        );
      case 'process_list':
      case 'running_apps':
        return _ControlPlaneDispatchPayload(
          methodId: 'list_processes',
          params: <String, dynamic>{
            'limit': _toInt(params['limit']) ?? 50,
          },
        );
      case 'filesystem':
        return _ControlPlaneDispatchPayload(
          methodId: 'list_files',
          params: <String, dynamic>{
            'path': _normalizePath(_asString(params['path'])),
            'recursive': (_toInt(params['depth']) ?? 1) > 1,
            'limit': 200,
          },
        );
      case 'system_info':
      case 'collect_telemetry':
        return const _ControlPlaneDispatchPayload(
          methodId: 'collect_system_info',
          params: <String, dynamic>{},
        );
      case 'policy_sync':
        return const _ControlPlaneDispatchPayload(
          methodId: 'policy_probe',
          params: <String, dynamic>{'command': 'policy_sync'},
        );
      case 'reboot':
        return _ControlPlaneDispatchPayload(
          methodId: 'reboot_device',
          params: <String, dynamic>{
            'delay_seconds': _toInt(params['delay_seconds']) ?? 30,
          },
        );
      case 'upload_file':
      case 'create_file':
        final destinationSource = _asString(params['path']);
        final destination = _normalizePath(destinationSource);
        return _ControlPlaneDispatchPayload(
          methodId: 'upload_file',
          params: <String, dynamic>{
            'artifact_id': _artifactIdForPath(destinationSource),
            'destination': destination,
            'overwrite': params['overwrite'] == true,
          },
        );
      default:
        return _ControlPlaneDispatchPayload(methodId: methodId, params: params);
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
}

final sendCommandControllerProvider =
    AutoDisposeNotifierProvider<SendCommandController, SendCommandState>(
  SendCommandController.new,
);

class _ControlPlaneDispatchPayload {
  const _ControlPlaneDispatchPayload({
    required this.methodId,
    required this.params,
  });

  final String methodId;
  final Map<String, dynamic> params;
}
