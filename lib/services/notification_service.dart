import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Background messages are shown automatically by FCM — nothing to do here
}

class NotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  static Future<void> initialize(BuildContext context) async {
    // Request permission (required on Android 13+)
    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // Register background handler
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // Save token to Firestore so Cloud Functions can target this device
    final token = await _messaging.getToken();
    if (token != null) await _saveToken(token);

    // Refresh token when it changes
    _messaging.onTokenRefresh.listen(_saveToken);

    // Show a banner for messages received while app is open
    FirebaseMessaging.onMessage.listen((message) {
      final notification = message.notification;
      if (notification == null) return;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(notification.title ?? '',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, color: Colors.white)),
                if (notification.body != null)
                  Text(notification.body!,
                      style: const TextStyle(color: Colors.white70)),
              ],
            ),
            backgroundColor: const Color(0xFFE8715A),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(12),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    });
  }

  static Future<void> _saveToken(String token) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    // Save under users collection (legacy)
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .set({'fcmToken': token}, SetOptions(merge: true));

    // Also save under couple doc keyed by name so partner can look it up
    final email = FirebaseAuth.instance.currentUser?.email ?? '';
    const rayEmail = 'dwaipayanray95@gmail.com';
    final myName = email == rayEmail ? 'ray' : 'aproo';
    await FirebaseFirestore.instance
        .collection('couples')
        .doc('ray-aproo')
        .collection('fcmTokens')
        .doc(myName)
        .set({'token': token});
  }
}
