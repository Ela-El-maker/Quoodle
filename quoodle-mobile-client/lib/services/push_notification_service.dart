import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/push_notification.dart';

/// Background message handler (must be top-level function).
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  // Firebase must be initialized for background handlers
  await Firebase.initializeApp();
  // Background messages are handled when app is opened
}

/// Configuration for push notification behavior.
class PushConfig {
  const PushConfig({
    this.androidChannelId = 'security_alerts',
    this.androidChannelName = 'Security Alerts',
    this.androidChannelDescription = 'Critical security notifications',
    this.androidIcon = '@mipmap/ic_launcher',
    this.requestPermissionOnInit = true,
  });

  final String androidChannelId;
  final String androidChannelName;
  final String androidChannelDescription;
  final String androidIcon;
  final bool requestPermissionOnInit;
}

/// Service for handling Firebase Cloud Messaging and local notifications.
class PushNotificationService {
  PushNotificationService({
    FirebaseMessaging? messaging,
    FlutterLocalNotificationsPlugin? localNotifications,
    PushConfig? config,
  })  : _messaging = messaging ?? FirebaseMessaging.instance,
        _localNotifications =
            localNotifications ?? FlutterLocalNotificationsPlugin(),
        _config = config ?? const PushConfig();

  final FirebaseMessaging _messaging;
  final FlutterLocalNotificationsPlugin _localNotifications;
  final PushConfig _config;

  final _tokenController = StreamController<String?>.broadcast();
  final _notificationController =
      StreamController<PushNotificationPayload>.broadcast();
  final _openedController =
      StreamController<PushNotificationPayload>.broadcast();

  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<RemoteMessage>? _openedSubscription;

  String? _currentToken;
  bool _initialized = false;

  /// Stream of FCM token changes.
  Stream<String?> get tokenStream => _tokenController.stream;

  /// Stream of notifications received while app is in foreground.
  Stream<PushNotificationPayload> get notificationStream =>
      _notificationController.stream;

  /// Stream of notifications that were tapped to open the app.
  Stream<PushNotificationPayload> get openedStream => _openedController.stream;

  /// Current FCM token for this device.
  String? get currentToken => _currentToken;

  /// Whether the service has been initialized.
  bool get isInitialized => _initialized;

  /// Initialize the push notification service.
  ///
  /// Call this early in app startup, after Firebase.initializeApp().
  Future<void> initialize() async {
    if (_initialized) return;

    // Set up background handler
    FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);

    // Initialize local notifications for foreground display
    await _initializeLocalNotifications();

    // Request permission if configured
    if (_config.requestPermissionOnInit) {
      await requestPermission();
    }

    // Get initial token
    _currentToken = await _messaging.getToken();
    if (!_tokenController.isClosed) {
      _tokenController.add(_currentToken);
    }

    // Listen for token refreshes
    _messaging.onTokenRefresh.listen((token) {
      _currentToken = token;
      if (!_tokenController.isClosed) {
        _tokenController.add(token);
      }
    });

    // Handle foreground messages
    _foregroundSubscription =
        FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Handle notification tap when app was in background
    _openedSubscription =
        FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationOpened);

    // Check if app was opened from a terminated state via notification
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _handleNotificationOpened(initialMessage);
    }

    _initialized = true;
  }

  Future<void> _initializeLocalNotifications() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      settings,
      onDidReceiveNotificationResponse: _onLocalNotificationTapped,
    );

    // Create Android notification channel
    if (Platform.isAndroid) {
      final channel = AndroidNotificationChannel(
        _config.androidChannelId,
        _config.androidChannelName,
        description: _config.androidChannelDescription,
        importance: Importance.high,
      );

      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
    }
  }

  /// Request notification permissions from the user.
  Future<bool> requestPermission() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
      announcement: false,
      carPlay: false,
      criticalAlert: true,
    );

    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  /// Check if notification permissions are granted.
  Future<bool> hasPermission() async {
    final settings = await _messaging.getNotificationSettings();
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  void _handleForegroundMessage(RemoteMessage message) {
    final payload = PushNotificationPayload.fromMap(message.toMap());

    // Emit to stream
    if (!_notificationController.isClosed) {
      _notificationController.add(payload);
    }

    // Show local notification since app is in foreground
    _showLocalNotification(payload, message.messageId ?? '');
  }

  void _handleNotificationOpened(RemoteMessage message) {
    final payload = PushNotificationPayload.fromMap(message.toMap());

    if (!_openedController.isClosed) {
      _openedController.add(payload);
    }
  }

  void _onLocalNotificationTapped(NotificationResponse response) {
    // Local notification was tapped while app was in foreground
    // The payload data could be passed via the response.payload field
    // For now, we rely on the notification stream for handling
  }

  Future<void> _showLocalNotification(
    PushNotificationPayload payload,
    String messageId,
  ) async {
    final androidDetails = AndroidNotificationDetails(
      _config.androidChannelId,
      _config.androidChannelName,
      channelDescription: _config.androidChannelDescription,
      importance: payload.isUrgent ? Importance.max : Importance.high,
      priority: payload.isUrgent ? Priority.max : Priority.high,
      icon: _config.androidIcon,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      messageId.hashCode,
      payload.title,
      payload.body,
      details,
    );
  }

  /// Subscribe to a topic for targeted notifications.
  Future<void> subscribeToTopic(String topic) async {
    await _messaging.subscribeToTopic(topic);
  }

  /// Unsubscribe from a topic.
  Future<void> unsubscribeFromTopic(String topic) async {
    await _messaging.unsubscribeFromTopic(topic);
  }

  /// Subscribe to device-specific alerts.
  Future<void> subscribeToDevice(String deviceId) async {
    await subscribeToTopic('device_$deviceId');
  }

  /// Unsubscribe from device-specific alerts.
  Future<void> unsubscribeFromDevice(String deviceId) async {
    await unsubscribeFromTopic('device_$deviceId');
  }

  /// Subscribe to user-specific notifications.
  Future<void> subscribeToUser(String userId) async {
    await subscribeToTopic('user_$userId');
  }

  /// Dispose the service and release resources.
  Future<void> dispose() async {
    await _foregroundSubscription?.cancel();
    await _openedSubscription?.cancel();
    await _tokenController.close();
    await _notificationController.close();
    await _openedController.close();
  }
}
