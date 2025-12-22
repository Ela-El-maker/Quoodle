import '../services/api_service.dart';

class ApiErrorView {
  const ApiErrorView(
      {required this.title, required this.message, required this.retryable});

  final String title;
  final String message;
  final bool retryable;
}

ApiErrorView classifyApiError(Object error) {
  if (error is! ApiException) {
    return ApiErrorView(
        title: 'Error', message: error.toString(), retryable: true);
  }

  final j = error.jsonBody;
  final status = j?['status'] as String?;
  final reason = error.reason;

  // 2FA / auth flows
  if (status == 'invalid_session') {
    return const ApiErrorView(
      title: 'Session expired',
      message: 'Please sign in again.',
      retryable: false,
    );
  }
  if (status == 'require_enrollment') {
    return const ApiErrorView(
      title: '2FA not enrolled',
      message: 'Set up 2FA first (QR code), then try again.',
      retryable: false,
    );
  }
  if (status == 'require_setup') {
    return const ApiErrorView(
      title: '2FA setup required',
      message:
          'Tap “Set up 2FA (QR code)” to enroll, then confirm with your first code.',
      retryable: false,
    );
  }

  // Command submission taxonomy
  if (reason == 'invalid_2fa') {
    return const ApiErrorView(
      title: 'Invalid 2FA code',
      message: 'Check your phone time (30s window) and try again.',
      retryable: true,
    );
  }
  if (reason == '2fa_required') {
    return const ApiErrorView(
      title: '2FA required',
      message: 'This command requires a 6-digit code.',
      retryable: true,
    );
  }
  if (reason == 'policy_out_of_sync') {
    return const ApiErrorView(
      title: 'Policy out of sync',
      message:
          'The device policy changed. Refresh policy bundle and try again.',
      retryable: false,
    );
  }

  // Default fallback
  return ApiErrorView(
    title: 'Request failed',
    message: error.toString(),
    retryable: error.statusCode >= 500,
  );
}
