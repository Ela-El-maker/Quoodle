import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ScheduledJobStatus { active, paused, completed, cancelled, failed }

enum RecurrenceType { once, minutely, hourly, daily, weekly, monthly, custom }

class RecurrenceRule {
  final RecurrenceType type;
  final int interval; // e.g. every 2 hours
  final List<int>? daysOfWeek; // 1=Mon..7=Sun
  final int? dayOfMonth;
  final String? cronExpression; // custom cron string (display only)

  const RecurrenceRule({
    required this.type,
    this.interval = 1,
    this.daysOfWeek,
    this.dayOfMonth,
    this.cronExpression,
  });

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'interval': interval,
        'daysOfWeek': daysOfWeek,
        'dayOfMonth': dayOfMonth,
        'cronExpression': cronExpression,
      };

  factory RecurrenceRule.fromJson(Map<String, dynamic> j) => RecurrenceRule(
        type: RecurrenceType.values.firstWhere(
          (t) => t.name == j['type'],
          orElse: () => RecurrenceType.once,
        ),
        interval: (j['interval'] as int?) ?? 1,
        daysOfWeek: (j['daysOfWeek'] as List?)?.map((e) => e as int).toList(),
        dayOfMonth: j['dayOfMonth'] as int?,
        cronExpression: j['cronExpression'] as String?,
      );

  String get displayLabel {
    switch (type) {
      case RecurrenceType.once:
        return 'One-time';
      case RecurrenceType.minutely:
        return interval == 1 ? 'Every minute' : 'Every $interval minutes';
      case RecurrenceType.hourly:
        return interval == 1 ? 'Hourly' : 'Every $interval hours';
      case RecurrenceType.daily:
        return interval == 1 ? 'Daily' : 'Every $interval days';
      case RecurrenceType.weekly:
        if (daysOfWeek != null && daysOfWeek!.isNotEmpty) {
          const names = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
          final days = daysOfWeek!.map((d) => names[d]).join(', ');
          return 'Weekly on $days';
        }
        return 'Weekly';
      case RecurrenceType.monthly:
        return dayOfMonth != null ? 'Monthly on day $dayOfMonth' : 'Monthly';
      case RecurrenceType.custom:
        return cronExpression ?? 'Custom cron';
    }
  }
}

class ScheduledJobRun {
  final String id;
  final DateTime startedAt;
  final DateTime? completedAt;
  final bool success;
  final String? output;
  final String? error;

  ScheduledJobRun({
    required this.id,
    required this.startedAt,
    this.completedAt,
    this.success = false,
    this.output,
    this.error,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'startedAt': startedAt.toIso8601String(),
        'completedAt': completedAt?.toIso8601String(),
        'success': success,
        'output': output,
        'error': error,
      };

  factory ScheduledJobRun.fromJson(Map<String, dynamic> j) => ScheduledJobRun(
        id: j['id'] as String,
        startedAt: DateTime.parse(j['startedAt'] as String),
        completedAt: j['completedAt'] != null
            ? DateTime.parse(j['completedAt'] as String)
            : null,
        success: (j['success'] as bool?) ?? false,
        output: j['output'] as String?,
        error: j['error'] as String?,
      );
}

class ScheduledJob {
  final String id;
  final String name;
  final String description;
  final String commandMethod;
  final Map<String, dynamic> commandParams;
  final String targetDeviceId;
  final String targetDeviceName;
  final DateTime scheduledAt;
  final RecurrenceRule recurrence;
  ScheduledJobStatus status;
  DateTime? lastRunAt;
  DateTime? nextRunAt;
  int runCount;
  int successCount;
  int failureCount;
  final List<ScheduledJobRun> history;
  final DateTime createdAt;
  final String createdBy;

  ScheduledJob({
    required this.id,
    required this.name,
    required this.description,
    required this.commandMethod,
    required this.commandParams,
    required this.targetDeviceId,
    required this.targetDeviceName,
    required this.scheduledAt,
    required this.recurrence,
    this.status = ScheduledJobStatus.active,
    this.lastRunAt,
    this.nextRunAt,
    this.runCount = 0,
    this.successCount = 0,
    this.failureCount = 0,
    List<ScheduledJobRun>? history,
    required this.createdAt,
    required this.createdBy,
  }) : history = history ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'commandMethod': commandMethod,
        'commandParams': commandParams,
        'targetDeviceId': targetDeviceId,
        'targetDeviceName': targetDeviceName,
        'scheduledAt': scheduledAt.toIso8601String(),
        'recurrence': recurrence.toJson(),
        'status': status.name,
        'lastRunAt': lastRunAt?.toIso8601String(),
        'nextRunAt': nextRunAt?.toIso8601String(),
        'runCount': runCount,
        'successCount': successCount,
        'failureCount': failureCount,
        'history': history.map((r) => r.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
        'createdBy': createdBy,
      };

  factory ScheduledJob.fromJson(Map<String, dynamic> j) {
    final historyList = (j['history'] as List?)
            ?.map((e) => ScheduledJobRun.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    return ScheduledJob(
      id: j['id'] as String,
      name: j['name'] as String,
      description: j['description'] as String? ?? '',
      commandMethod: j['commandMethod'] as String,
      commandParams: Map<String, dynamic>.from(
        (j['commandParams'] as Map?) ?? {},
      ),
      targetDeviceId: j['targetDeviceId'] as String,
      targetDeviceName: j['targetDeviceName'] as String,
      scheduledAt: DateTime.parse(j['scheduledAt'] as String),
      recurrence: RecurrenceRule.fromJson(
        j['recurrence'] as Map<String, dynamic>,
      ),
      status: ScheduledJobStatus.values.firstWhere(
        (s) => s.name == j['status'],
        orElse: () => ScheduledJobStatus.active,
      ),
      lastRunAt: j['lastRunAt'] != null
          ? DateTime.parse(j['lastRunAt'] as String)
          : null,
      nextRunAt: j['nextRunAt'] != null
          ? DateTime.parse(j['nextRunAt'] as String)
          : null,
      runCount: (j['runCount'] as int?) ?? 0,
      successCount: (j['successCount'] as int?) ?? 0,
      failureCount: (j['failureCount'] as int?) ?? 0,
      history: historyList,
      createdAt: DateTime.parse(j['createdAt'] as String),
      createdBy: j['createdBy'] as String? ?? 'operator',
    );
  }

  ScheduledJob copyWith({
    ScheduledJobStatus? status,
    DateTime? lastRunAt,
    DateTime? nextRunAt,
    int? runCount,
    int? successCount,
    int? failureCount,
  }) =>
      ScheduledJob(
        id: id,
        name: name,
        description: description,
        commandMethod: commandMethod,
        commandParams: commandParams,
        targetDeviceId: targetDeviceId,
        targetDeviceName: targetDeviceName,
        scheduledAt: scheduledAt,
        recurrence: recurrence,
        status: status ?? this.status,
        lastRunAt: lastRunAt ?? this.lastRunAt,
        nextRunAt: nextRunAt ?? this.nextRunAt,
        runCount: runCount ?? this.runCount,
        successCount: successCount ?? this.successCount,
        failureCount: failureCount ?? this.failureCount,
        history: history,
        createdAt: createdAt,
        createdBy: createdBy,
      );
}

class SchedulerService extends ChangeNotifier {
  static final SchedulerService _instance = SchedulerService._internal();
  factory SchedulerService() => _instance;
  SchedulerService._internal();

  static const String _storageKey = 'scheduler_jobs';

  final List<ScheduledJob> _jobs = [];
  Timer? _tickTimer;
  bool _initialized = false;

  List<ScheduledJob> get jobs => List.unmodifiable(_jobs);
  List<ScheduledJob> get activeJobs =>
      _jobs.where((j) => j.status == ScheduledJobStatus.active).toList();
  List<ScheduledJob> get pausedJobs =>
      _jobs.where((j) => j.status == ScheduledJobStatus.paused).toList();
  int get activeCount => activeJobs.length;
  int get totalRuns => _jobs.fold(0, (sum, j) => sum + j.runCount);

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    await _loadFromStorage();
    if (_jobs.isEmpty) _seedDemoJobs();
    _startTicker();
  }

  void _startTicker() {
    _tickTimer?.cancel();
    _tickTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _checkDueJobs();
    });
  }

  void _checkDueJobs() {
    final now = DateTime.now();
    bool changed = false;
    for (int i = 0; i < _jobs.length; i++) {
      final job = _jobs[i];
      if (job.status != ScheduledJobStatus.active) continue;
      final next = job.nextRunAt;
      if (next != null && now.isAfter(next)) {
        _executeJob(i);
        changed = true;
      }
    }
    if (changed) {
      _saveToStorage();
      notifyListeners();
    }
  }

  void _executeJob(int index) {
    final job = _jobs[index];
    final runId = '${job.id}_run_${job.runCount + 1}';
    final now = DateTime.now();
    final success = (now.millisecond % 10) < 8;

    final run = ScheduledJobRun(
      id: runId,
      startedAt: now,
      completedAt: now.add(const Duration(seconds: 2)),
      success: success,
      output: success ? 'Command dispatched successfully' : null,
      error: success ? null : 'Device unreachable',
    );

    job.history.insert(0, run);
    if (job.history.length > 50) job.history.removeLast();

    _jobs[index] = job.copyWith(
      lastRunAt: now,
      nextRunAt: job.recurrence.type == RecurrenceType.once
          ? null
          : _computeNextRun(job.recurrence, now),
      runCount: job.runCount + 1,
      successCount: success ? job.successCount + 1 : job.successCount,
      failureCount: success ? job.failureCount : job.failureCount + 1,
      status: job.recurrence.type == RecurrenceType.once
          ? ScheduledJobStatus.completed
          : ScheduledJobStatus.active,
    );
  }

  DateTime _computeNextRun(RecurrenceRule rule, DateTime from) {
    switch (rule.type) {
      case RecurrenceType.minutely:
        return from.add(Duration(minutes: rule.interval));
      case RecurrenceType.hourly:
        return from.add(Duration(hours: rule.interval));
      case RecurrenceType.daily:
        return from.add(Duration(days: rule.interval));
      case RecurrenceType.weekly:
        return from.add(Duration(days: 7 * rule.interval));
      case RecurrenceType.monthly:
        return DateTime(
          from.year,
          from.month + rule.interval,
          from.day,
          from.hour,
          from.minute,
        );
      default:
        return from.add(const Duration(hours: 1));
    }
  }

  Future<void> addJob(ScheduledJob job) async {
    final withNext = ScheduledJob(
      id: job.id,
      name: job.name,
      description: job.description,
      commandMethod: job.commandMethod,
      commandParams: job.commandParams,
      targetDeviceId: job.targetDeviceId,
      targetDeviceName: job.targetDeviceName,
      scheduledAt: job.scheduledAt,
      recurrence: job.recurrence,
      status: job.status,
      lastRunAt: job.lastRunAt,
      nextRunAt: job.recurrence.type == RecurrenceType.once
          ? job.scheduledAt
          : _computeNextRun(job.recurrence, DateTime.now()),
      runCount: job.runCount,
      successCount: job.successCount,
      failureCount: job.failureCount,
      history: job.history,
      createdAt: job.createdAt,
      createdBy: job.createdBy,
    );
    _jobs.insert(0, withNext);
    await _saveToStorage();
    notifyListeners();
  }

  Future<void> pauseJob(String jobId) async {
    final idx = _jobs.indexWhere((j) => j.id == jobId);
    if (idx == -1) return;
    _jobs[idx] = _jobs[idx].copyWith(status: ScheduledJobStatus.paused);
    await _saveToStorage();
    notifyListeners();
  }

  Future<void> resumeJob(String jobId) async {
    final idx = _jobs.indexWhere((j) => j.id == jobId);
    if (idx == -1) return;
    _jobs[idx] = _jobs[idx].copyWith(status: ScheduledJobStatus.active);
    await _saveToStorage();
    notifyListeners();
  }

  Future<void> cancelJob(String jobId) async {
    final idx = _jobs.indexWhere((j) => j.id == jobId);
    if (idx == -1) return;
    _jobs[idx] = _jobs[idx].copyWith(status: ScheduledJobStatus.cancelled);
    await _saveToStorage();
    notifyListeners();
  }

  Future<void> deleteJob(String jobId) async {
    _jobs.removeWhere((j) => j.id == jobId);
    await _saveToStorage();
    notifyListeners();
  }

  Future<void> runNow(String jobId) async {
    final idx = _jobs.indexWhere((j) => j.id == jobId);
    if (idx == -1) return;
    _executeJob(idx);
    await _saveToStorage();
    notifyListeners();
  }

  Future<void> _loadFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw != null) {
        final list = jsonDecode(raw) as List;
        _jobs.clear();
        _jobs.addAll(
          list.map((e) => ScheduledJob.fromJson(e as Map<String, dynamic>)),
        );
      }
    } catch (_) {}
  }

  Future<void> _saveToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _storageKey,
        jsonEncode(_jobs.map((j) => j.toJson()).toList()),
      );
    } catch (_) {}
  }

  void _seedDemoJobs() {
    final now = DateTime.now();
    _jobs.addAll([
      ScheduledJob(
        id: 'job-001',
        name: 'Daily Telemetry Sweep',
        description: 'Collect system telemetry from all production servers',
        commandMethod: 'collect_telemetry',
        commandParams: {'scope': 'full', 'compress': true},
        targetDeviceId: 'dev-001',
        targetDeviceName: 'PROD-SRV-001',
        scheduledAt: now.subtract(const Duration(days: 3)),
        recurrence: const RecurrenceRule(
          type: RecurrenceType.daily,
          interval: 1,
        ),
        status: ScheduledJobStatus.active,
        lastRunAt: now.subtract(const Duration(hours: 6)),
        nextRunAt: now.add(const Duration(hours: 18)),
        runCount: 12,
        successCount: 11,
        failureCount: 1,
        history: [
          ScheduledJobRun(
            id: 'job-001_run_12',
            startedAt: now.subtract(const Duration(hours: 6)),
            completedAt: now.subtract(const Duration(hours: 6, seconds: -3)),
            success: true,
            output: 'Telemetry collected: 847 metrics',
          ),
          ScheduledJobRun(
            id: 'job-001_run_11',
            startedAt: now.subtract(const Duration(hours: 30)),
            completedAt: now.subtract(const Duration(hours: 30, seconds: -2)),
            success: false,
            error: 'Device unreachable — timeout after 30s',
          ),
          ScheduledJobRun(
            id: 'job-001_run_10',
            startedAt: now.subtract(const Duration(hours: 54)),
            completedAt: now.subtract(const Duration(hours: 54, seconds: -4)),
            success: true,
            output: 'Telemetry collected: 823 metrics',
          ),
        ],
        createdAt: now.subtract(const Duration(days: 3)),
        createdBy: 'L. Nakamura',
      ),
      ScheduledJob(
        id: 'job-002',
        name: 'Hourly Process Snapshot',
        description: 'Capture running process list on finance workstations',
        commandMethod: 'process_list',
        commandParams: {'include_system': false},
        targetDeviceId: 'dev-007',
        targetDeviceName: 'WKS-FINANCE-07',
        scheduledAt: now.subtract(const Duration(days: 1)),
        recurrence: const RecurrenceRule(
          type: RecurrenceType.hourly,
          interval: 1,
        ),
        status: ScheduledJobStatus.paused,
        lastRunAt: now.subtract(const Duration(hours: 3)),
        nextRunAt: null,
        runCount: 24,
        successCount: 23,
        failureCount: 1,
        history: [
          ScheduledJobRun(
            id: 'job-002_run_24',
            startedAt: now.subtract(const Duration(hours: 3)),
            completedAt: now.subtract(const Duration(hours: 3, seconds: -2)),
            success: true,
            output: '47 processes captured',
          ),
        ],
        createdAt: now.subtract(const Duration(days: 1)),
        createdBy: 'A. Patel',
      ),
      ScheduledJob(
        id: 'job-003',
        name: 'Weekly Compliance Scan',
        description: 'Full policy compliance audit across edge nodes',
        commandMethod: 'policy_sync',
        commandParams: {'force': true, 'version': '1.0.4'},
        targetDeviceId: 'dev-021',
        targetDeviceName: 'EDGE-NODE-021',
        scheduledAt: now.subtract(const Duration(days: 7)),
        recurrence: RecurrenceRule(
          type: RecurrenceType.weekly,
          interval: 1,
          daysOfWeek: [1, 3, 5],
        ),
        status: ScheduledJobStatus.active,
        lastRunAt: now.subtract(const Duration(days: 2)),
        nextRunAt: now.add(const Duration(days: 1)),
        runCount: 6,
        successCount: 6,
        failureCount: 0,
        history: [
          ScheduledJobRun(
            id: 'job-003_run_6',
            startedAt: now.subtract(const Duration(days: 2)),
            completedAt: now.subtract(const Duration(days: 2, seconds: -5)),
            success: true,
            output: 'All 14 compliance rules passed',
          ),
        ],
        createdAt: now.subtract(const Duration(days: 7)),
        createdBy: 'L. Nakamura',
      ),
      ScheduledJob(
        id: 'job-004',
        name: 'Network Topology Snapshot',
        description: 'Capture network interfaces and active connections',
        commandMethod: 'network_info',
        commandParams: {'include_connections': true},
        targetDeviceId: 'dev-014',
        targetDeviceName: 'PROD-SRV-014',
        scheduledAt: now.subtract(const Duration(hours: 2)),
        recurrence: const RecurrenceRule(type: RecurrenceType.once),
        status: ScheduledJobStatus.completed,
        lastRunAt: now.subtract(const Duration(hours: 1)),
        nextRunAt: null,
        runCount: 1,
        successCount: 1,
        failureCount: 0,
        history: [
          ScheduledJobRun(
            id: 'job-004_run_1',
            startedAt: now.subtract(const Duration(hours: 1)),
            completedAt: now.subtract(const Duration(hours: 1, seconds: -3)),
            success: true,
            output: '4 interfaces, 12 active connections captured',
          ),
        ],
        createdAt: now.subtract(const Duration(hours: 2)),
        createdBy: 'A. Patel',
      ),
    ]);
    _saveToStorage();
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    super.dispose();
  }
}
