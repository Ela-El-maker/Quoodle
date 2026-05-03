import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:secure_device_control/features/commands/domain/services/control_plane_dispatch_payload.dart';
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
    final dispatchPayload = normalizeCommandForControlPlane(
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
      String message = '';
      String? detail;
      if (body is Map) {
        reason = _asString(body['reason']);
        message = _asString(body['message']);
        if (reason.isEmpty) {
          reason = message;
        }
        detail = _extractValidationDetail(body['errors']);
      }

      if (reason.isEmpty) {
        reason = _reasonFromStatusCode(error.response?.statusCode);
      }

      return SendCommandDispatchResult(
        success: false,
        errorMessage:
            detail ??
            _messageForDispatchFailureReason(
              reason,
              fallbackMessage: message,
            ),
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

  String _messageForDispatchFailureReason(
    String reason, {
    String? fallbackMessage,
  }) {
    switch (reason) {
      case 'unauthenticated':
      case 'unauthorized':
      case '401':
        return 'Session expired. Please sign in again.';
      case 'forbidden':
      case '403':
        return 'You do not have permission to execute this command.';
      case 'not_found':
      case '404':
        return 'Command endpoint not found on control plane.';
      case '2fa_required':
      case 'require_2fa':
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
        if (fallbackMessage != null && fallbackMessage.trim().isNotEmpty) {
          return fallbackMessage.trim();
        }
        return 'Command rejected by policy or backend validation.';
    }
  }

  String _reasonFromStatusCode(int? statusCode) {
    switch (statusCode) {
      case 401:
        return '401';
      case 403:
        return '403';
      case 404:
        return '404';
      default:
        return '';
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
}

final sendCommandControllerProvider =
    AutoDisposeNotifierProvider<SendCommandController, SendCommandState>(
  SendCommandController.new,
);
