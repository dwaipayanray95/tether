import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import '../models/todo_model.dart';
import 'nav_service.dart';
import 'log_service.dart';

// ── Background handler (runs in a separate isolate) ───────────────────────────

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  LogService.log('Background FCM received: ${message.data}');

  final type = message.data['type'] as String? ?? '';

  if (type == 'ping') {
    // Location pings removed
    return;
  }

  if (type == 'call_ping' || type == 'call_ended') {
    // Calling is removed
    return;
  }
}

// ── NotificationService ───────────────────────────────────────────────────────

class NotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  // Default channel — messages, pokes, to-dos
  static const _defaultChannel = AndroidNotificationChannel(
    'tether_updates_v1',
    'Tether Notifications',
    description: 'Messages, pokes and to-dos',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  // Set to true by ChatScreen while it is mounted and visible
  static bool chatIsOpen = false;

  // ── Pending navigation set before MainShell reads them ───────────────────
  static int? pendingTab;

  // ── init ─────────────────────────────────────────────────────────────────

  static Future<void> initialize() async {
    LogService.log('Initializing NotificationService');
    tz.initializeTimeZones();
    await _messaging.requestPermission(alert: true, badge: true, sound: true);

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // Create Android notification channels
    final androidPlugin = _local.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(_defaultChannel);

    // Initialise local notifications
    await _local.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        LogService.log(
            'Local notification tapped: payload=${response.payload}');
        _navigateFromPayload(response.payload);
      },
    );

    // Handle app launched BY a local notification (e.g. full-screen call tap)
    final launchDetails = await _local.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp == true) {
      final payload = launchDetails?.notificationResponse?.payload;
      LogService.log('App launched by local notification: payload=$payload');
      if (payload != null) {
        Future.delayed(const Duration(milliseconds: 500),
            () => _navigateFromPayload(payload));
      }
    }

    // Save / refresh FCM token
    final token = await _messaging.getToken();
    if (token != null) await _saveToken(token);
    _messaging.onTokenRefresh.listen(_saveToken);

    // Foreground FCM → show local notification (calls are handled by Firestore stream)
    FirebaseMessaging.onMessage.listen((message) async {
      LogService.log('Foreground FCM received: ${message.data}');
      final type = message.data['type'] as String? ?? '';

      if (type == 'ping') {
        // Location pings removed
        return;
      }

      if (type == 'call_ping' || type == 'call_ended') {
        // Calling is removed
        return;
      }

      // Suppress chat banner if user is already in chat
      if (type == 'chat' && chatIsOpen) return;

      final n = message.notification;
      if (n == null) return;
      _showLocal(
        title: n.title ?? '',
        body: n.body ?? '',
        payload: jsonEncode(message.data),
      );
    });

    // Notification tap while app was in background (FCM notification)
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      LogService.log('FCM notification tapped (background): ${message.data}');
      _navigateFromPayload(jsonEncode(message.data));
    });

    // Notification tap that cold-started the app (FCM notification)
    final initial = await _messaging.getInitialMessage();
    if (initial != null) {
      LogService.log(
          'FCM notification tapped (cold start): ${initial.data}');
      Future.delayed(const Duration(milliseconds: 500), () {
        _navigateFromPayload(jsonEncode(initial.data));
      });
    }
  }

  // ── Navigation ────────────────────────────────────────────────────────────

  static void _navigateFromPayload(String? payload) {
    if (payload == null) return;
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      final type = data['type'] as String?;

      final context = navigatorKey.currentContext;
      if (context == null) return;

      if (type == 'chat') {
        pendingTab = 1;
      } else if (type == 'snap') {
        pendingTab = 0;
      }
    } catch (e) {
      LogService.log('Error parsing notification payload: $e');
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static Future<void> showTest() async {
    await _showLocal(
      title: '🔔 Test Notification',
      body: 'If you hear this, sound and vibration are working!',
      payload: jsonEncode({'type': 'test'}),
    );
  }

  static Future<void> _showLocal({
    required String title,
    required String body,
    String? payload,
  }) async {
    await _local.show(
      title.hashCode ^ body.hashCode,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _defaultChannel.id,
          _defaultChannel.name,
          channelDescription: _defaultChannel.description,
          importance: Importance.max,
          priority: Priority.max,
          playSound: true,
          enableVibration: true,
          icon: '@mipmap/ic_launcher',
        ),
      ),
      payload: payload,
    );
  }

  static Future<void> _saveToken(String token) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .set({'fcmToken': token}, SetOptions(merge: true));

    const rayEmail = 'ray@redacted.invalid';
    final email = FirebaseAuth.instance.currentUser?.email ?? '';
    final myName = email == rayEmail ? 'ray' : 'aproo';
    await FirebaseFirestore.instance
        .collection('couples')
        .doc('ray-aproo')
        .collection('fcmTokens')
        .doc(myName)
        .set({'token': token});
  }

  // ── Todo Reminders ────────────────────────────────────────────────────────

  static Future<void> scheduleTodoReminder(TodoItem todo) async {
    if (todo.dueDate == null || todo.isDone) return;
    if (todo.dueDate!.isBefore(DateTime.now())) return;

    LogService.log('Scheduling local notification for to-do ${todo.id} at ${todo.dueDate}');
    final scheduledDate = tz.TZDateTime.from(todo.dueDate!, tz.local);

    await _local.zonedSchedule(
      todo.id.hashCode,
      '⏰ Task Reminder',
      todo.title,
      scheduledDate,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _defaultChannel.id,
          _defaultChannel.name,
          channelDescription: _defaultChannel.description,
          importance: Importance.max,
          priority: Priority.max,
          playSound: true,
          enableVibration: true,
          icon: '@mipmap/ic_launcher',
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  static Future<void> cancelTodoReminder(String todoId) async {
    LogService.log('Canceling local notification for to-do $todoId');
    await _local.cancel(todoId.hashCode);
  }

  static Future<void> syncTodoNotifications(List<TodoItem> todos) async {
    try {
      final pending = await _local.pendingNotificationRequests();
      final activeTodoHashCodes = todos
          .where((t) => !t.isDone && t.dueDate != null && t.dueDate!.isAfter(DateTime.now()))
          .map((t) => t.id.hashCode)
          .toSet();

      for (final p in pending) {
        // Only manage todo notification hashes (skip other notifications if any)
        if (!activeTodoHashCodes.contains(p.id)) {
          await _local.cancel(p.id);
        }
      }

      for (final todo in todos) {
        if (!todo.isDone && todo.dueDate != null && todo.dueDate!.isAfter(DateTime.now())) {
          await scheduleTodoReminder(todo);
        }
      }
    } catch (e) {
      LogService.log('Error syncing todo notifications: $e');
    }
  }
}
