import 'package:dio/dio.dart';
import 'package:secure_device_control/core/errors/exceptions.dart';
import 'package:secure_device_control/core/errors/failures.dart';

class FailureMapper {
  const FailureMapper._();

  static Failure fromObject(Object error) {
    if (error is Failure) {
      return error;
    }

    if (error is AppException) {
      return switch (error) {
        UnauthorizedException() => const UnauthorizedFailure(),
        NetworkException() => const NetworkFailure(),
        TimeoutException() => const TimeoutFailure(),
        ValidationException() => ValidationFailure(error.message),
        _ => UnknownFailure(error.message),
      };
    }

    if (error is DioException) {
      final statusCode = error.response?.statusCode;
      if (statusCode == 401) {
        return const UnauthorizedFailure();
      }
      if (statusCode == 403) {
        return const ForbiddenFailure();
      }
      if (statusCode == 404) {
        return const NotFoundFailure();
      }
      if (statusCode != null && statusCode >= 500) {
        return const ServerFailure();
      }

      return switch (error.type) {
        DioExceptionType.connectionTimeout => const TimeoutFailure(),
        DioExceptionType.sendTimeout => const TimeoutFailure(),
        DioExceptionType.receiveTimeout => const TimeoutFailure(),
        DioExceptionType.connectionError => const NetworkFailure(),
        _ => const UnknownFailure(),
      };
    }

    return const UnknownFailure();
  }
}
