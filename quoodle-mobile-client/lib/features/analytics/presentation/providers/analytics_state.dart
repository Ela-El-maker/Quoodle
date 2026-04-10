class AnalyticsState {
  const AnalyticsState({
    required this.timeRange,
  });

  factory AnalyticsState.initial() {
    return const AnalyticsState(timeRange: '7d');
  }

  static const List<String> timeRanges = ['24h', '7d', '30d', '90d'];

  final String timeRange;

  AnalyticsState copyWith({String? timeRange}) {
    return AnalyticsState(timeRange: timeRange ?? this.timeRange);
  }
}
