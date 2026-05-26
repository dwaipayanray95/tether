import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'nav_service.dart';
import 'location_service.dart';
import 'auth_service.dart';
import 'log_service.dart';

// ── Background handler (runs in a separate isolate) ───────────────────────────

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  LogService.log('Background FCM received: ${message.data}');

  final type = message.data['type'] as String? ?? '';

  if (type == 'ping') {
    final auth = AuthService();
    final myKey = auth.isRay ? 'ray' : 'aproo';
    final pos = await LocationService.getCurrentPosition();
    if (pos != null) {
      await LocationService.forceUpload(pos, myKey, auth.myName);
    }
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
        final auth = AuthService();
        final myKey = auth.isRay ? 'ray' : 'aproo';
        final pos = await LocationService.getCurrentPosition();
        if (pos != null) {
          await LocationService.forceUpload(pos, myKey, auth.myName);
        }
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

    const rayEmail = 'dwaipayanray95@gmail.com';
    final email = FirebaseAuth.instance.currentUser?.email ?? '';
    final myName = email == rayEmail ? 'ray' : 'aproo';
    await FirebaseFirestore.instance
        .collection('couples')
        .doc('ray-aproo')
        .collection('fcmTokens')
        .doc(myName)
        .set({'token': token});
  }
}
