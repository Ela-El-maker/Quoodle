class AppException implements Exception {
  const AppException(this.message);

  final String message;

  @override
  String toString() => 'AppException: $message';
}

class UnauthorizedException extends AppException {
  const UnauthorizedException([super.message = 'Unauthorized']);
}

class NetworkException extends AppException {
  const NetworkException([super.message = 'Network error']);
}

class TimeoutException extends AppException {
  const TimeoutException([super.message = 'Timeout']);
}

class ValidationException extends AppException {
  const ValidationException(super.message);
}
