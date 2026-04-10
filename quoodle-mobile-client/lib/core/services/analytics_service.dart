abstract class AnalyticsService {
  Future<void> trackEvent(String name, {Map<String, Object?>? params});
}

class NoOpAnalyticsService implements AnalyticsService {
  @override
  Future<void> trackEvent(String name, {Map<String, Object?>? params}) async {}
}
