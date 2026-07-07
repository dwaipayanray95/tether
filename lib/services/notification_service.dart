import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import '../models/todo_model.dart';
import 'nav_service.dart';
import 'auth_service.dart';
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

  if (type == 'chat' || type == 'poke' || type == 'snap' || type == 'todo') {
    // These types are sent data-only (see fcm_service.dart) specifically so
    // this handler renders them itself via NotificationService._showLocal,
    // instead of letting the OS auto-display a plain notification that
    // bypasses MessagingStyle/shortcutId/category. Must initialize the
    // plugin fresh — this runs in its own isolate, separate from the app's.
    await NotificationService._local.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    await NotificationService._showLocal(
      title: message.data['title'] as String? ?? '',
      body: message.data['body'] as String? ?? '',
      payload: jsonEncode(message.data),
      type: type,
    );
  }
}

// ── NotificationService ───────────────────────────────────────────────────────

class NotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  static const _shortcutsChannel =
      MethodChannel('com.theawesomeray.tether/shortcuts');

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

    await _pushConversationShortcut();

    await _local.initialize(
      settings: const InitializationSettings(
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

      // chat/poke/snap/todo arrive data-only (see fcm_service.dart), so
      // title/body live in `data`, not `message.notification` (which will be
      // null for those types). Other/legacy types may still carry a
      // notification block, so fall back to that if data doesn't have it.
      final title = message.data['title'] as String? ?? message.notification?.title;
      final body = message.data['body'] as String? ?? message.notification?.body;
      if (title == null || body == null) return;
      _showLocal(
        title: title,
        body: body,
        payload: jsonEncode(message.data),
        type: type,
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

  // Registers the partner as a long-lived Android shortcut so chat/poke
  // notifications (built with a matching shortcutId in _showLocal) are
  // recognized as a "Conversation" and get grouped/pinned above regular
  // notifications, the same way WhatsApp/Instagram DMs behave. Safe to call
  // repeatedly — Android just updates the existing shortcut.
  static Future<void> _pushConversationShortcut() async {
    try {
      final auth = AuthService();
      await _shortcutsChannel.invokeMethod('pushConversationShortcut', {
        'shortcutId': 'tether_conversation_${auth.partnerName.toLowerCase()}',
        'label': auth.partnerDisplayName,
      });
    } catch (e) {
      LogService.log('Error pushing conversation shortcut: $e');
    }
  }

  static Future<void> _showLocal({
    required String title,
    required String body,
    String? payload,
    String? type,
  }) async {
    StyleInformation? styleInformation;
    String? shortcutId;
    AndroidNotificationCategory? category;

    // Every notification type here originates from the partner's actions
    // (message, poke, snap, todo update) — in a 2-person app there's only
    // ever one "conversation", so all of them ride the same shortcut/Person
    // to get Android's Conversations-section treatment, not just chat/poke.
    if (type == 'chat' || type == 'poke' || type == 'snap' || type == 'todo') {
      final auth = AuthService();
      final partnerName = auth.partnerDisplayName;
      final partner = Person(
        name: partnerName,
        key: auth.partnerName.toLowerCase(),
      );
      styleInformation = MessagingStyleInformation(
        partner,
        conversationTitle: 'Tether with $partnerName',
        messages: [
          Message(
            body,
            DateTime.now(),
            partner,
          ),
        ],
      );
      shortcutId = 'tether_conversation_${auth.partnerName.toLowerCase()}';
      category = AndroidNotificationCategory.message;
    }

    await _local.show(
      id: title.hashCode ^ body.hashCode,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _defaultChannel.id,
          _defaultChannel.name,
          channelDescription: _defaultChannel.description,
          importance: Importance.max,
          priority: Priority.max,
          playSound: true,
          enableVibration: true,
          icon: '@mipmap/ic_launcher',
          styleInformation: styleInformation,
          shortcutId: shortcutId,
          category: category,
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

    final email = FirebaseAuth.instance.currentUser?.email ?? '';
    final myName = email == allowedEmails[0] ? 'ray' : 'aproo';
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
      id: todo.id.hashCode,
      title: '⏰ Task Reminder',
      body: todo.title,
      scheduledDate: scheduledDate,
      notificationDetails: NotificationDetails(
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
    );
  }

  static Future<void> cancelTodoReminder(String todoId) async {
    LogService.log('Canceling local notification for to-do $todoId');
    await _local.cancel(id: todoId.hashCode);
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
          await _local.cancel(id: p.id);
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
