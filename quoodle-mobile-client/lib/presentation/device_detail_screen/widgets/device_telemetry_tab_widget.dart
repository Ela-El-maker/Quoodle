import 'dart:async';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:secure_device_control/features/devices/presentation/providers/devices_providers.dart';
import '../../../theme/app_theme.dart';

class DeviceTelemetryTabWidget extends ConsumerStatefulWidget {
  final String deviceId;
  const DeviceTelemetryTabWidget({super.key, required this.deviceId});

  @override
  ConsumerState<DeviceTelemetryTabWidget> createState() =>
      _DeviceTelemetryTabWidgetState();
}

enum _SyncState { syncing, fresh, stale, veryStale }

class _DeviceTelemetryTabWidgetState
    extends ConsumerState<DeviceTelemetryTabWidget>
    with SingleTickerProviderStateMixin {
  static const _pollInterval = Duration(seconds: 3);
  static const _historyWindow = Duration(minutes: 15);

  Timer? _pollTimer;
  Timer? _secondTimer;
  int _secondsSinceUpdate = 0;
  bool _isSyncing = false;
  bool _backgroundRefreshActive = true;
  DateTime _lastUpdatedAt = DateTime.now().subtract(const Duration(minutes: 1));

  double _cpu = 0;
  double _ram = 0;
  double _disk = 0;
  double _temp = 0;
  double _netTx = 0;
  double _netRx = 0;
  int _openPorts = 0;
  int _activeProcesses = 0;

  final List<FlSpot> _cpuHistory = [
    const FlSpot(0, 48),
    const FlSpot(1, 52),
    const FlSpot(2, 55),
    const FlSpot(3, 58),
    const FlSpot(4, 63),
    const FlSpot(5, 61),
    const FlSpot(6, 59),
    const FlSpot(7, 64),
    const FlSpot(8, 68),
    const FlSpot(9, 62),
    const FlSpot(10, 61),
    const FlSpot(11, 61),
  ];
  final List<FlSpot> _ramHistory = [
    const FlSpot(0, 68),
    const FlSpot(1, 70),
    const FlSpot(2, 71),
    const FlSpot(3, 72),
    const FlSpot(4, 74),
    const FlSpot(5, 73),
    const FlSpot(6, 75),
    const FlSpot(7, 74),
    const FlSpot(8, 76),
    const FlSpot(9, 74),
    const FlSpot(10, 73),
    const FlSpot(11, 74),
  ];

  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _startPolling();
    unawaited(_refreshTelemetry());
  }

  @override
  void didUpdateWidget(covariant DeviceTelemetryTabWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.deviceId != widget.deviceId) {
      unawaited(_refreshTelemetry());
    }
  }

  void _startPolling() {
    _secondTimer?.cancel();
    _pollTimer?.cancel();

    _secondTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _secondsSinceUpdate++);
    });

    _pollTimer = Timer.periodic(_pollInterval, (_) {
      if (!mounted || !_backgroundRefreshActive || _isSyncing) {
        return;
      }
      unawaited(_refreshTelemetry());
    });
  }

  Future<void> _refreshTelemetry() async {
    if (!mounted || _isSyncing) {
      return;
    }
    setState(() {
      _isSyncing = true;
    });

    try {
      final nowUtc = DateTime.now().toUtc();
      final fromUtc = nowUtc.subtract(_historyWindow);
      final telemetryDataSource =
          ref.read(deviceTelemetryRemoteDataSourceProvider);

      final responses = await Future.wait<Map<String, dynamic>>([
        telemetryDataSource.fetchLatestTelemetry(widget.deviceId),
        telemetryDataSource.fetchTelemetryHistory(
          widget.deviceId,
          from: fromUtc,
          to: nowUtc,
          limit: 500,
        ),
      ]);

      final latestPayload = responses[0];
      final historyPayload = responses[1];
      final latestMetrics = _asStringDynamicMap(latestPayload['metrics']);

      final cpu = _toDouble(latestMetrics['cpu']);
      final ram = _toDouble(latestMetrics['ram']);
      final disk = _toDouble(latestMetrics['disk_usage']);
      final netTx = _toDouble(latestMetrics['network_tx']);
      final netRx = _toDouble(latestMetrics['network_rx']);
      final temp = _toDouble(
        latestMetrics['temperature_c'] ??
            latestMetrics['temp_c'] ??
            latestMetrics['temp'],
      );
      final activeProcesses = _toInt(
        latestMetrics['active_processes'] ??
            latestMetrics['process_count'] ??
            latestMetrics['processes'],
      );
      final openPorts = _toInt(latestMetrics['open_ports']);
      final timestamp =
          _parseTimestamp(latestPayload['timestamp']) ?? DateTime.now();

      final historyCpu = <FlSpot>[];
      final historyRam = <FlSpot>[];
      final pointsRaw = historyPayload['points'];
      if (pointsRaw is List) {
        final points = pointsRaw
            .whereType<Map>()
            .map((entry) => _asStringDynamicMap(entry))
            .toList(growable: false);
        final windowed =
            points.length > 20 ? points.sublist(points.length - 20) : points;

        var x = 0.0;
        for (final point in windowed) {
          final metrics = _asStringDynamicMap(point['metrics']);
          final pointCpu = _toDouble(metrics['cpu']);
          final pointRam = _toDouble(metrics['ram']);

          if (pointCpu != null) {
            historyCpu.add(FlSpot(x, pointCpu.clamp(0, 100).toDouble()));
          }
          if (pointRam != null) {
            historyRam.add(FlSpot(x, pointRam.clamp(0, 100).toDouble()));
          }
          x += 1;
        }
      }

      if (!mounted) {
        return;
      }
      setState(() {
        if (cpu != null) {
          _cpu = cpu.clamp(0, 100).toDouble();
        }
        if (ram != null) {
          _ram = ram.clamp(0, 100).toDouble();
        }
        if (disk != null) {
          _disk = disk.clamp(0, 100).toDouble();
        }
        if (netTx != null) {
          _netTx = _normalizeNetworkRate(netTx);
        }
        if (netRx != null) {
          _netRx = _normalizeNetworkRate(netRx);
        }
        if (activeProcesses != null) {
          _activeProcesses = activeProcesses.clamp(0, 99999);
        }
        if (openPorts != null) {
          _openPorts = openPorts.clamp(0, 99999);
        }

        _temp = (temp ?? _deriveTempFromCpu(_cpu)).clamp(0, 120).toDouble();
        _secondsSinceUpdate = 0;
        _lastUpdatedAt = timestamp;
        _isSyncing = false;

        if (historyCpu.isNotEmpty) {
          _cpuHistory
            ..clear()
            ..addAll(historyCpu);
        } else {
          _appendCurrentPoint(_cpuHistory, _cpu);
        }

        if (historyRam.isNotEmpty) {
          _ramHistory
            ..clear()
            ..addAll(historyRam);
        } else {
          _appendCurrentPoint(_ramHistory, _ram);
        }
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSyncing = false;
      });
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _secondTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  _SyncState get _syncState {
    if (_isSyncing) return _SyncState.syncing;
    if (_secondsSinceUpdate < 5) return _SyncState.fresh;
    if (_secondsSinceUpdate < 15) return _SyncState.stale;
    return _SyncState.veryStale;
  }

  Color _metricColor(double value, double warn, double crit) {
    if (value >= crit) return AppTheme.error;
    if (value >= warn) return AppTheme.warning;
    return AppTheme.secondary;
  }

  String _formatTimestamp(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inSeconds < 5) return 'just now';
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }

  Map<String, dynamic> _asStringDynamicMap(Object? value) {
    if (value is Map) {
      return value.map((key, mapValue) => MapEntry(key.toString(), mapValue));
    }
    return const <String, dynamic>{};
  }

  double? _toDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) {
        return null;
      }
      final parsed = double.tryParse(trimmed);
      if (parsed != null) {
        return parsed;
      }
      final match = RegExp(r'-?\d+(\.\d+)?').firstMatch(trimmed);
      if (match == null) {
        return null;
      }
      return double.tryParse(match.group(0)!);
    }
    return null;
  }

  int? _toInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is List) {
      return value.length;
    }
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) {
        return null;
      }
      final parsed = int.tryParse(trimmed);
      if (parsed != null) {
        return parsed;
      }
      final asDouble = double.tryParse(trimmed);
      if (asDouble != null) {
        return asDouble.toInt();
      }
    }
    return null;
  }

  DateTime? _parseTimestamp(Object? value) {
    if (value is! String || value.trim().isEmpty) {
      return null;
    }
    return DateTime.tryParse(value);
  }

  double _normalizeNetworkRate(double raw) {
    if (raw.abs() >= 10000) {
      return raw / (1024 * 1024);
    }
    return raw;
  }

  double _deriveTempFromCpu(double cpuPercent) {
    return 38 + (cpuPercent * 0.35);
  }

  void _appendCurrentPoint(List<FlSpot> history, double value) {
    if (history.length >= 20) {
      history.removeAt(0);
    }
    history.add(
      FlSpot(
        history.length.toDouble(),
        double.parse(value.toStringAsFixed(1)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
      children: [
        _buildSyncStatusBar(),
        const SizedBox(height: 14),
        // Primary metric cards
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                label: 'CPU',
                value: _cpu,
                unit: '%',
                icon: Icons.memory_rounded,
                color: _metricColor(_cpu, 70, 90),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _MetricCard(
                label: 'RAM',
                value: _ram,
                unit: '%',
                icon: Icons.storage_rounded,
                color: _metricColor(_ram, 80, 95),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _MetricCard(
                label: 'Disk',
                value: _disk,
                unit: '%',
                icon: Icons.disc_full_rounded,
                color: _metricColor(_disk, 85, 95),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // Secondary metric cards
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                label: 'Temp',
                value: _temp,
                unit: '°C',
                icon: Icons.thermostat_rounded,
                color: _metricColor(_temp, 70, 85),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _MetricCardInt(
                label: 'Processes',
                value: _activeProcesses,
                icon: Icons.account_tree_rounded,
                color: AppTheme.primary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _MetricCardInt(
                label: 'Open Ports',
                value: _openPorts,
                icon: Icons.lan_rounded,
                color: _openPorts > 20 ? AppTheme.warning : AppTheme.secondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        // Network metrics
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.surfaceVariant,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.border, width: 1),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.network_check_rounded,
                size: 18,
                color: AppTheme.primary,
              ),
              const SizedBox(width: 10),
              Text(
                'Network',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(color: AppTheme.textSecondary),
              ),
              const Spacer(),
              _NetworkStat(
                label: '↑ TX',
                value: '${_netTx.toStringAsFixed(1)} MB/s',
              ),
              const SizedBox(width: 16),
              _NetworkStat(
                label: '↓ RX',
                value: '${_netRx.toStringAsFixed(1)} MB/s',
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        // Background refresh status panel
        _buildRefreshStatusPanel(),
        const SizedBox(height: 16),
        // Historical chart
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.surfaceVariant,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.border, width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Resource History (15m)',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const Spacer(),
                  if (_isSyncing)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryDim,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 8,
                            height: 8,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: AppTheme.primary,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'LIVE',
                            style: GoogleFonts.ibmPlexMono(
                              fontSize: 9,
                              color: AppTheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 140,
                child: LineChart(
                  LineChartData(
                    minY: 0,
                    maxY: 100,
                    gridData: FlGridData(
                      drawVerticalLine: false,
                      horizontalInterval: 25,
                      getDrawingHorizontalLine: (_) => FlLine(
                        color: AppTheme.border.withAlpha(102),
                        strokeWidth: 1,
                        dashArray: [4, 6],
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    titlesData: FlTitlesData(
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          interval: 25,
                          reservedSize: 30,
                          getTitlesWidget: (v, _) => Text(
                            '${v.toInt()}%',
                            style: GoogleFonts.ibmPlexMono(
                              fontSize: 9,
                              color: AppTheme.textMuted,
                            ),
                          ),
                        ),
                      ),
                      bottomTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                    ),
                    lineBarsData: [
                      _lineBar(_cpuHistory, AppTheme.warning),
                      _lineBar(_ramHistory, AppTheme.primary),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _ChartLegend(color: AppTheme.warning, label: 'CPU'),
                  const SizedBox(width: 16),
                  _ChartLegend(color: AppTheme.primary, label: 'RAM'),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSyncStatusBar() {
    final state = _syncState;
    Color barColor;
    Color bgColor;
    IconData icon;
    String message;

    switch (state) {
      case _SyncState.syncing:
        barColor = AppTheme.primary;
        bgColor = AppTheme.primaryDim;
        icon = Icons.sync_rounded;
        message = 'Syncing telemetry data…';
        break;
      case _SyncState.fresh:
        barColor = AppTheme.secondary;
        bgColor = AppTheme.secondaryMuted;
        icon = Icons.check_circle_outline_rounded;
        message =
            'Live  ·  Updated ${_formatTimestamp(_lastUpdatedAt)}  ·  Polling every 3s';
        break;
      case _SyncState.stale:
        barColor = AppTheme.warning;
        bgColor = AppTheme.warningMuted;
        icon = Icons.access_time_rounded;
        message = 'Data from ${_secondsSinceUpdate}s ago  ·  May be stale';
        break;
      case _SyncState.veryStale:
        barColor = AppTheme.error;
        bgColor = AppTheme.errorMuted;
        icon = Icons.warning_amber_rounded;
        message =
            'Stale data  ·  Last seen ${_formatTimestamp(_lastUpdatedAt)}  ·  Check connectivity';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: barColor.withAlpha(77), width: 1),
      ),
      child: Row(
        children: [
          if (state == _SyncState.syncing)
            AnimatedBuilder(
              animation: _pulseAnim,
              builder: (_, __) => Opacity(
                opacity: _pulseAnim.value,
                child: SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: barColor,
                  ),
                ),
              ),
            )
          else
            Icon(icon, size: 14, color: barColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.ibmPlexSans(fontSize: 11, color: barColor),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Stale badge
          if (state == _SyncState.stale || state == _SyncState.veryStale)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: barColor.withAlpha(38),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: barColor.withAlpha(102), width: 1),
              ),
              child: Text(
                state == _SyncState.veryStale ? 'STALE' : 'AGING',
                style: GoogleFonts.ibmPlexMono(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: barColor,
                ),
              ),
            ),
          // Real-time badge
          if (state == _SyncState.fresh || state == _SyncState.syncing) ...[
            const SizedBox(width: 6),
            AnimatedBuilder(
              animation: _pulseAnim,
              builder: (_, __) => Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: barColor.withAlpha((_pulseAnim.value * 255).toInt()),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRefreshStatusPanel() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.refresh_rounded,
                size: 15,
                color: AppTheme.textSecondary,
              ),
              const SizedBox(width: 8),
              Text(
                'Background Refresh',
                style: GoogleFonts.ibmPlexSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () {
                  setState(() {
                    _backgroundRefreshActive = !_backgroundRefreshActive;
                  });
                  if (_backgroundRefreshActive) {
                    unawaited(_refreshTelemetry());
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 38,
                  height: 20,
                  decoration: BoxDecoration(
                    color: _backgroundRefreshActive
                        ? AppTheme.secondary
                        : AppTheme.border,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: AnimatedAlign(
                    duration: const Duration(milliseconds: 200),
                    alignment: _backgroundRefreshActive
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.all(2),
                      width: 16,
                      height: 16,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _RefreshStatusItem(
                label: 'Interval',
                value: '${_pollInterval.inSeconds}s',
                icon: Icons.timer_rounded,
                color: AppTheme.primary,
              ),
              const SizedBox(width: 12),
              _RefreshStatusItem(
                label: 'Last sync',
                value: _formatTimestamp(_lastUpdatedAt),
                icon: Icons.history_rounded,
                color: _syncState == _SyncState.veryStale
                    ? AppTheme.error
                    : AppTheme.textSecondary,
              ),
              const SizedBox(width: 12),
              _RefreshStatusItem(
                label: 'Status',
                value: _backgroundRefreshActive ? 'Active' : 'Paused',
                icon: _backgroundRefreshActive
                    ? Icons.play_circle_rounded
                    : Icons.pause_circle_rounded,
                color: _backgroundRefreshActive
                    ? AppTheme.secondary
                    : AppTheme.warning,
              ),
            ],
          ),
        ],
      ),
    );
  }

  LineChartBarData _lineBar(List<FlSpot> spots, Color color) {
    return LineChartBarData(
      spots: spots,
      isCurved: true,
      curveSmoothness: 0.3,
      color: color,
      barWidth: 2,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(
        show: true,
        gradient: LinearGradient(
          colors: [color.withAlpha(31), color.withAlpha(0)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label, unit;
  final double value;
  final IconData icon;
  final Color color;
  const _MetricCard({
    required this.label,
    required this.value,
    required this.unit,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withAlpha(64), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(height: 8),
          Text(
            '${value.toStringAsFixed(1)}$unit',
            style: GoogleFonts.ibmPlexMono(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          Text(
            label,
            style: GoogleFonts.ibmPlexSans(
              fontSize: 10,
              color: AppTheme.textMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricCardInt extends StatelessWidget {
  final String label;
  final int value;
  final IconData icon;
  final Color color;
  const _MetricCardInt({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withAlpha(64), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(height: 8),
          Text(
            '$value',
            style: GoogleFonts.ibmPlexMono(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          Text(
            label,
            style: GoogleFonts.ibmPlexSans(
              fontSize: 10,
              color: AppTheme.textMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _NetworkStat extends StatelessWidget {
  final String label, value;
  const _NetworkStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          label,
          style: GoogleFonts.ibmPlexSans(
            fontSize: 9,
            color: AppTheme.textMuted,
          ),
        ),
        Text(
          value,
          style: GoogleFonts.ibmPlexMono(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _ChartLegend extends StatelessWidget {
  final Color color;
  final String label;
  const _ChartLegend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 10, height: 2, color: color),
        const SizedBox(width: 6),
        Text(
          label,
          style: GoogleFonts.ibmPlexSans(
            fontSize: 10,
            color: AppTheme.textMuted,
          ),
        ),
      ],
    );
  }
}

class _RefreshStatusItem extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _RefreshStatusItem({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.borderLight, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 11, color: color),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: GoogleFonts.ibmPlexSans(
                    fontSize: 9,
                    color: AppTheme.textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              value,
              style: GoogleFonts.ibmPlexMono(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
