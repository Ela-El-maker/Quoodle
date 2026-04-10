sealed class Failure {
  const Failure(this.userMessage);

  final String userMessage;
}

class NetworkFailure extends Failure {
  const NetworkFailure([super.userMessage = 'Network connection failed.']);
}

class UnauthorizedFailure extends Failure {
  const UnauthorizedFailure(
      [super.userMessage = 'Session expired. Please sign in again.']);
}

class ForbiddenFailure extends Failure {
  const ForbiddenFailure(
      [super.userMessage =
          'You do not have permission to perform this action.']);
}

class ValidationFailure extends Failure {
  const ValidationFailure(super.userMessage);
}

class NotFoundFailure extends Failure {
  const NotFoundFailure(
      [super.userMessage = 'Requested resource was not found.']);
}

class TimeoutFailure extends Failure {
  const TimeoutFailure(
      [super.userMessage = 'Request timed out. Please retry.']);
}

class ServerFailure extends Failure {
  const ServerFailure([super.userMessage = 'Server error occurred.']);
}

class CacheFailure extends Failure {
  const CacheFailure([super.userMessage = 'Unable to read local cached data.']);
}

class TwoFactorRequiredFailure extends Failure {
  const TwoFactorRequiredFailure(
      [super.userMessage = 'Two-factor verification required.']);
}

class UnknownFailure extends Failure {
  const UnknownFailure([super.userMessage = 'Something went wrong.']);
}
