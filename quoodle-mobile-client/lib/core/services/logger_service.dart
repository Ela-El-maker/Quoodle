abstract class LoggerService {
  void debug(String message);
  void info(String message);
  void error(String message, {Object? error, StackTrace? stackTrace});
}

class ConsoleLoggerService implements LoggerService {
  @override
  void debug(String message) {
    // ignore: avoid_print
    print('[DEBUG] $message');
  }

  @override
  void info(String message) {
    // ignore: avoid_print
    print('[INFO] $message');
  }

  @override
  void error(String message, {Object? error, StackTrace? stackTrace}) {
    // ignore: avoid_print
    print('[ERROR] $message ${error ?? ''} ${stackTrace ?? ''}');
  }
}
