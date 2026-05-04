import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'nav_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // FCM shows background notifications automatically when payload has
  // a 'notification' field — nothing extra needed here.
}

class NotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  static const _channel = AndroidNotificationChannel(
    'tether_default',
    'Tether',
    description: 'Messages, pokes and to-dos',
    importance: Importance.high,
    playSound: true,
  );

  // Set to true by ChatScreen while it is mounted and visible
  static bool chatIsOpen = false;

  static Future<void> initialize() async {
    await _messaging.requestPermission(alert: true, badge: true, sound: true);

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // Create Android notification channel
    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);

    // Initialise local notifications
    await _local.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (response) {
        _navigateFromPayload(response.payload);
      },
    );

    // Save / refresh FCM token
    final token = await _messaging.getToken();
    if (token != null) await _saveToken(token);
    _messaging.onTokenRefresh.listen(_saveToken);

    // Foreground FCM → show local notification
    FirebaseMessaging.onMessage.listen((message) {
      final type = message.data['type'] as String? ?? '';
      // Suppress chat banner if user is already in chat
      if (type == 'chat' && chatIsOpen) return;

      final n = message.notification;
      if (n == null) return;
      _showLocal(
        title: n.title ?? '',
        body: n.body ?? '',
        payload: type,
      );
    });

    // Notification tap while app was in background
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _navigateFromPayload(message.data['type'] as String?);
    });

    // Notification tap that cold-started the app
    final initial = await _messaging.getInitialMessage();
    if (initial != null) {
      // Delay so the navigator is ready
      Future.delayed(const Duration(milliseconds: 500), () {
        _navigateFromPayload(initial.data['type'] as String?);
      });
    }
  }

  static void _navigateFromPayload(String? type) {
    // For now all notification types go to the relevant tab
    // chat → tab 1, everything else → tab 0 (home)
    final context = navigatorKey.currentContext;
    if (context == null) return;
    if (type == 'chat') {
      // Tell MainShell to switch to chat tab
      NotificationService.pendingTab = 1;
    }
  }

  // MainShell reads and clears this after build
  static int? pendingTab;

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
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
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
