import 'package:flutter_test/flutter_test.dart';
import 'package:secure_device_control/core/errors/failures.dart';
import 'package:secure_device_control/core/errors/result.dart';

void main() {
  group('Result', () {
    test('success branch resolves data', () {
      const result = Success<int>(42);

      final value = result.when(
        success: (data) => data,
        failure: (_) => -1,
      );

      expect(result.isSuccess, isTrue);
      expect(result.isFailure, isFalse);
      expect(value, 42);
    });

    test('failure branch resolves failure object', () {
      const result = FailureResult<int>(ValidationFailure('invalid'));

      final value = result.when(
        success: (_) => 'ok',
        failure: (failure) => failure.userMessage,
      );

      expect(result.isSuccess, isFalse);
      expect(result.isFailure, isTrue);
      expect(value, 'invalid');
    });
  });
}
