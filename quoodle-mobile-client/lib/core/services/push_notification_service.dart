import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum NotificationSeverity { info, warning, high, critical }

enum NotificationCategory { command, device, alert, system }

class AppNotification {
  final String id;
  final String title;
  final String body;
  final NotificationSeverity severity;
  final NotificationCategory category;
  final DateTime timestamp;
  bool isRead;
  final String? deepLinkRoute;
  final Map<String, dynamic>? deepLinkArgs;

  AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.severity,
    required this.category,
    required this.timestamp,
    this.isRead = false,
    this.deepLinkRoute,
    this.deepLinkArgs,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        'severity': severity.name,
        'category': category.name,
        'timestamp': timestamp.toIso8601String(),
        'isRead': isRead,
        'deepLinkRoute': deepLinkRoute,
        'deepLinkArgs': deepLinkArgs,
      };

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
        id: j['id'] as String,
        title: j['title'] as String,
        body: j['body'] as String,
        severity: NotificationSeverity.values.firstWhere(
          (s) => s.name == j['severity'],
          orElse: () => NotificationSeverity.info,
        ),
        category: NotificationCategory.values.firstWhere(
          (c) => c.name == j['category'],
          orElse: () => NotificationCategory.system,
        ),
        timestamp: DateTime.parse(j['timestamp'] as String),
        isRead: (j['isRead'] as bool?) ?? false,
        deepLinkRoute: j['deepLinkRoute'] as String?,
        deepLinkArgs: j['deepLinkArgs'] != null
            ? Map<String, dynamic>.from(j['deepLinkArgs'] as Map)
            : null,
      );
}

class PushNotificationService extends ChangeNotifier {
  static final PushNotificationService _instance =
      PushNotificationService._internal();
  factory PushNotificationService() => _instance;
  PushNotificationService._internal();

  static const String _storageKey = 'app_notifications';
  static const int _maxNotifications = 100;

  final List<AppNotification> _notifications = [];
  BuildContext? _navigatorContext;
  bool _initialized = false;
  Timer? _simulationTimer;

  List<AppNotification> get notifications => List.unmodifiable(_notifications);
  int get unreadCount => _notifications.where((n) => !n.isRead).length;
  List<AppNotification> get unreadNotifications =>
      _notifications.where((n) => !n.isRead).toList();

  Future<void> initialize(BuildContext context) async {
    _navigatorContext = context;
    if (_initialized) return;
    _initialized = true;
    await _loadFromStorage();
    if (_notifications.isEmpty) _seedDemoNotifications();
    _startSimulation();
  }

  void updateContext(BuildContext context) {
    _navigatorContext = context;
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Called when a command transitions state (dispatched, acked, completed, failed)
  void onCommandStateTransition({
    required String commandId,
    required String commandMethod,
    required String deviceName,
    required String newState,
    String? deepLinkRoute,
    Map<String, dynamic>? deepLinkArgs,
  }) {
    final isFailure = newState == 'failed' || newState == 'timeout';
    final isComplete = newState == 'completed';
    final severity = isFailure
        ? NotificationSeverity.high
        : isComplete
            ? NotificationSeverity.info
            : NotificationSeverity.info;

    final title = isFailure
        ? 'Command Failed'
        : isComplete
            ? 'Command Completed'
            : 'Command $newState';

    final body = isFailure
        ? '$commandMethod on $deviceName failed'
        : '$commandMethod on $deviceName — $newState';

    _addNotification(
      AppNotification(
        id: 'cmd_${commandId}_$newState',
        title: title,
        body: body,
        severity: severity,
        category: NotificationCategory.command,
        timestamp: DateTime.now(),
        deepLinkRoute: deepLinkRoute,
        deepLinkArgs: deepLinkArgs,
      ),
      showToast: true,
    );
  }

  /// Called when a device changes presence (online/offline/degraded)
  void onDevicePresenceChange({
    required String deviceId,
    required String deviceName,
    required String newStatus,
    String? deepLinkRoute,
    Map<String, dynamic>? deepLinkArgs,
  }) {
    final isOffline = newStatus == 'offline';
    final isQuarantined = newStatus == 'quarantined';
    final severity = isQuarantined
        ? NotificationSeverity.critical
        : isOffline
            ? NotificationSeverity.high
            : NotificationSeverity.info;

    _addNotification(
      AppNotification(
        id: 'device_${deviceId}_$newStatus',
        title: isOffline
            ? 'Device Offline'
            : isQuarantined
                ? 'Device Quarantined'
                : 'Device Status Changed',
        body: '$deviceName is now $newStatus',
        severity: severity,
        category: NotificationCategory.device,
        timestamp: DateTime.now(),
        deepLinkRoute: deepLinkRoute,
        deepLinkArgs: deepLinkArgs,
      ),
      showToast: isOffline || isQuarantined,
    );
  }

  /// Called when an alert is triggered
  void onAlertTriggered({
    required String alertId,
    required String alertMessage,
    required String deviceName,
    required String severity,
    String? deepLinkRoute,
    Map<String, dynamic>? deepLinkArgs,
  }) {
    final sev = _parseSeverity(severity);
    _addNotification(
      AppNotification(
        id: 'alert_$alertId',
        title: 'Alert: ${severity[0].toUpperCase()}${severity.substring(1)}',
        body: '$deviceName — $alertMessage',
        severity: sev,
        category: NotificationCategory.alert,
        timestamp: DateTime.now(),
        deepLinkRoute: deepLinkRoute,
        deepLinkArgs: deepLinkArgs,
      ),
      showToast: sev == NotificationSeverity.critical ||
          sev == NotificationSeverity.high,
    );
  }

  void markAsRead(String notificationId) {
    final idx = _notifications.indexWhere((n) => n.id == notificationId);
    if (idx == -1) return;
    _notifications[idx].isRead = true;
    _saveToStorage();
    notifyListeners();
  }

  void markAllAsRead() {
    for (final n in _notifications) {
      n.isRead = true;
    }
    _saveToStorage();
    notifyListeners();
  }

  void deleteNotification(String notificationId) {
    _notifications.removeWhere((n) => n.id == notificationId);
    _saveToStorage();
    notifyListeners();
  }

  void clearAll() {
    _notifications.clear();
    _saveToStorage();
    notifyListeners();
  }

  /// Navigate to the deep link destination
  void navigateToDeepLink(AppNotification notification) {
    final ctx = _navigatorContext;
    if (ctx == null) return;
    if (notification.deepLinkRoute != null) {
      Navigator.of(ctx).pushNamed(
        notification.deepLinkRoute!,
        arguments: notification.deepLinkArgs,
      );
    }
    markAsRead(notification.id);
  }

  // ── Internal ───────────────────────────────────────────────────────────────

  void _addNotification(
    AppNotification notification, {
    bool showToast = false,
  }) {
    // Deduplicate by id
    _notifications.removeWhere((n) => n.id == notification.id);
    _notifications.insert(0, notification);
    if (_notifications.length > _maxNotifications) {
      _notifications.removeLast();
    }
    _saveToStorage();
    notifyListeners();

    if (showToast) {
      _showForegroundToast(notification);
    }
  }

  void _showForegroundToast(AppNotification notification) {
    final color = _severityColor(notification.severity);
    Fluttertoast.showToast(
      msg: '${notification.title}: ${notification.body}',
      toastLength: Toast.LENGTH_LONG,
      gravity: ToastGravity.TOP,
      backgroundColor: color.withAlpha(230),
      textColor: Colors.white,
      fontSize: 13.0,
    );
  }

  Color _severityColor(NotificationSeverity severity) {
    switch (severity) {
      case NotificationSeverity.critical:
        return const Color(0xFFFF3B3B);
      case NotificationSeverity.high:
        return const Color(0xFFEF4444);
      case NotificationSeverity.warning:
        return const Color(0xFFF59E0B);
      case NotificationSeverity.info:
        return const Color(0xFF00D4FF);
    }
  }

  NotificationSeverity _parseSeverity(String s) {
    switch (s.toLowerCase()) {
      case 'critical':
        return NotificationSeverity.critical;
      case 'high':
        return NotificationSeverity.high;
      case 'warning':
        return NotificationSeverity.warning;
      default:
        return NotificationSeverity.info;
    }
  }

  void _startSimulation() {
    // Simulate incoming notifications every 45 seconds for demo
    _simulationTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      _simulateIncomingNotification();
    });
  }

  void _simulateIncomingNotification() {
    final now = DateTime.now();
    final idx = now.second % 4;
    switch (idx) {
      case 0:
        onCommandStateTransition(
          commandId: 'cmd_sim_${now.millisecondsSinceEpoch}',
          commandMethod: 'collect_telemetry',
          deviceName: 'PROD-SRV-001',
          newState: 'completed',
          deepLinkRoute: '/command-timeline-screen',
          deepLinkArgs: {'id': 'cmd_sim_${now.millisecondsSinceEpoch}'},
        );
        break;
      case 1:
        onDevicePresenceChange(
          deviceId: 'dev-014',
          deviceName: 'PROD-SRV-014',
          newStatus: 'offline',
          deepLinkRoute: '/device-detail-screen',
          deepLinkArgs: {'deviceId': 'dev-014'},
        );
        break;
      case 2:
        onAlertTriggered(
          alertId: 'sim_${now.millisecondsSinceEpoch}',
          alertMessage: 'CPU usage exceeded 90% threshold',
          deviceName: 'EDGE-NODE-021',
          severity: 'warning',
          deepLinkRoute: '/alerts-screen',
        );
        break;
      case 3:
        onCommandStateTransition(
          commandId: 'cmd_sim2_${now.millisecondsSinceEpoch}',
          commandMethod: 'process_list',
          deviceName: 'WKS-FINANCE-07',
          newState: 'failed',
          deepLinkRoute: '/command-timeline-screen',
        );
        break;
    }
  }

  Future<void> _loadFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw != null) {
        final list = jsonDecode(raw) as List;
        _notifications.clear();
        _notifications.addAll(
          list.map((e) => AppNotification.fromJson(e as Map<String, dynamic>)),
        );
      }
    } catch (_) {}
  }

  Future<void> _saveToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _storageKey,
        jsonEncode(_notifications.map((n) => n.toJson()).toList()),
      );
    } catch (_) {}
  }

  void _seedDemoNotifications() {
    final now = DateTime.now();
    _notifications.addAll([
      AppNotification(
        id: 'notif-001',
        title: 'Device Quarantined',
        body: 'EDGE-NODE-021 — Attestation failure. Quarantine enforced.',
        severity: NotificationSeverity.critical,
        category: NotificationCategory.device,
        timestamp: now.subtract(const Duration(minutes: 8)),
        isRead: false,
        deepLinkRoute: '/device-detail-screen',
        deepLinkArgs: {'deviceId': 'dev-021'},
      ),
      AppNotification(
        id: 'notif-002',
        title: 'Command Failed',
        body: 'collect_telemetry on PROD-SRV-014 failed — timeout',
        severity: NotificationSeverity.high,
        category: NotificationCategory.command,
        timestamp: now.subtract(const Duration(minutes: 22)),
        isRead: false,
        deepLinkRoute: '/command-timeline-screen',
        deepLinkArgs: {'id': 'cmd-0091'},
      ),
      AppNotification(
        id: 'notif-003',
        title: 'Alert: High',
        body: 'PROD-SRV-014 — Device offline, no heartbeat for 18 minutes',
        severity: NotificationSeverity.high,
        category: NotificationCategory.alert,
        timestamp: now.subtract(const Duration(minutes: 35)),
        isRead: false,
        deepLinkRoute: '/alerts-screen',
      ),
      AppNotification(
        id: 'notif-004',
        title: 'Command Completed',
        body: 'policy_sync on WKS-FINANCE-07 — completed',
        severity: NotificationSeverity.info,
        category: NotificationCategory.command,
        timestamp: now.subtract(const Duration(hours: 1)),
        isRead: true,
        deepLinkRoute: '/command-timeline-screen',
        deepLinkArgs: {'id': 'cmd-0091'},
      ),
      AppNotification(
        id: 'notif-005',
        title: 'Alert: Warning',
        body: 'WKS-FINANCE-07 — Agent version below minimum (2.0.9 < 2.1.x)',
        severity: NotificationSeverity.warning,
        category: NotificationCategory.alert,
        timestamp: now.subtract(const Duration(hours: 2)),
        isRead: true,
        deepLinkRoute: '/alerts-screen',
      ),
      AppNotification(
        id: 'notif-006',
        title: 'Device Online',
        body: 'PROD-SRV-001 is now online',
        severity: NotificationSeverity.info,
        category: NotificationCategory.device,
        timestamp: now.subtract(const Duration(hours: 3)),
        isRead: true,
        deepLinkRoute: '/device-detail-screen',
        deepLinkArgs: {'deviceId': 'dev-001'},
      ),
      AppNotification(
        id: 'notif-007',
        title: 'Scheduled Job Completed',
        body: 'Daily Telemetry Sweep ran successfully — 847 metrics collected',
        severity: NotificationSeverity.info,
        category: NotificationCategory.system,
        timestamp: now.subtract(const Duration(hours: 6)),
        isRead: true,
        deepLinkRoute: '/scheduler-screen',
      ),
    ]);
    _saveToStorage();
  }

  @override
  void dispose() {
    _simulationTimer?.cancel();
    super.dispose();
  }
}
