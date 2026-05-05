import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:dio/dio.dart';
import '../config/notification_config.dart';

class FcmService {
  static const _tokenUrl = 'https://oauth2.googleapis.com/token';
  static const _fcmUrl =
      'https://fcm.googleapis.com/v1/projects/${NotificationConfig.projectId}/messages:send';

  static String? _cachedToken;
  static DateTime? _tokenExpiry;

  // ── OAuth2 access token via service account JWT ───────────────────────────

  static Future<String> _getAccessToken() async {
    if (_cachedToken != null &&
        _tokenExpiry != null &&
        DateTime.now().isBefore(_tokenExpiry!)) {
      return _cachedToken!;
    }

    final now = DateTime.now();
    final jwt = JWT({
      'iss': NotificationConfig.clientEmail,
      'scope': 'https://www.googleapis.com/auth/firebase.messaging',
      'aud': _tokenUrl,
      'iat': now.millisecondsSinceEpoch ~/ 1000,
      'exp': now.add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000,
    });

    final signed = jwt.sign(
      RSAPrivateKey(NotificationConfig.privateKey),
      algorithm: JWTAlgorithm.RS256,
    );

    final dio = Dio();
    final response = await dio.post(
      _tokenUrl,
      data: 'grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=$signed',
      options: Options(
        contentType: 'application/x-www-form-urlencoded',
        validateStatus: (_) => true,
      ),
    );

    final accessToken = response.data['access_token'] as String;
    _cachedToken = accessToken;
    _tokenExpiry = now.add(const Duration(minutes: 55));
    return accessToken;
  }

  // ── Get partner's FCM token from Firestore ────────────────────────────────

  static Future<String?> _getPartnerToken(String partnerName) async {
    final snap = await FirebaseFirestore.instance
        .collection('couples')
        .doc('ray-aproo')
        .collection('fcmTokens')
        .doc(partnerName.toLowerCase())
        .get();
    return snap.data()?['token'] as String?;
  }

  // ── Send a push notification ──────────────────────────────────────────────

  static Future<void> send({
    required String partnerName,
    required String title,
    required String body,
    String type = 'general',
  }) async {
    try {
      final token = await _getPartnerToken(partnerName);
      if (token == null) return;

      final accessToken = await _getAccessToken();
      final dio = Dio();
      await dio.post(
        _fcmUrl,
        data: {
          'message': {
            'token': token,
            'notification': {'title': title, 'body': body},
            'data': {'type': type},
            'android': {
              'priority': 'high',
              'notification': {
                'channel_id': 'tether_default',
                'default_sound': true,
                'default_vibrate_timings': true,
              },
            },
          },
        },
        options: Options(
          headers: {'Authorization': 'Bearer $accessToken'},
          validateStatus: (_) => true,
        ),
      );
    } catch (_) {
      // Silently fail — notifications are best-effort
    }
  }
}
