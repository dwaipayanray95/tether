import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:dio/dio.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import '../config/notification_config.dart';
import 'log_service.dart';

class FcmService {
  static final Dio _dio = Dio();
  
  // Cache the OAuth2 access token in memory to avoid generating JWT on every message.
  static String? _cachedToken;
  static DateTime? _tokenExpiry;

  /// Exchanges private service account key credentials for a Google OAuth2 access token.
  static Future<String?> _getAccessToken() async {
    final now = DateTime.now();
    if (_cachedToken != null && _tokenExpiry != null && now.isBefore(_tokenExpiry!)) {
      return _cachedToken;
    }

    try {
      LogService.log('Generating new OAuth2 Access Token for FCM');
      
      final jwt = JWT(
        {
          'iss': NotificationConfig.clientEmail,
          'scope': 'https://www.googleapis.com/auth/firebase.messaging',
          'aud': 'https://oauth2.googleapis.com/token',
          'exp': now.add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000,
          'iat': now.millisecondsSinceEpoch ~/ 1000,
        },
      );

      final privateKeyString = NotificationConfig.privateKey;
      final key = RSAPrivateKey(privateKeyString);
      final signedJwt = jwt.sign(key, algorithm: JWTAlgorithm.RS256);

      final response = await _dio.post(
        'https://oauth2.googleapis.com/token',
        data: {
          'grant_type': 'urn:ietf:params:oauth:grant-type:jwt-bearer',
          'assertion': signedJwt,
        },
        options: Options(
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
          },
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        _cachedToken = data['access_token'] as String?;
        final expiresIn = data['expires_in'] as int? ?? 3600;
        // Expire token 5 minutes early to be safe
        _tokenExpiry = now.add(Duration(seconds: expiresIn - 300));
        LogService.log('OAuth2 Access Token successfully generated');
        return _cachedToken;
      } else {
        LogService.log('OAuth2 Token Generation failed: ${response.statusCode} - ${response.data}');
      }
    } catch (e) {
      LogService.log('ERROR generating FCM Access Token: $e');
    }
    return null;
  }

  static Future<String?> _getPartnerToken(String partnerName) async {
    final nameKey = partnerName.toLowerCase(); // 'ray', 'aproo', or 'self'
    
    try {
      if (nameKey == 'self') {
        const rayEmail = 'ray@redacted.invalid';
        final email = FirebaseAuth.instance.currentUser?.email ?? '';
        final myNameKey = email == rayEmail ? 'ray' : 'aproo';
        
        final myDoc = await FirebaseFirestore.instance
            .collection('couples')
            .doc('ray-aproo')
            .collection('fcmTokens')
            .doc(myNameKey)
            .get();
        if (myDoc.exists) {
          return myDoc.data()?['token'] as String?;
        }
        return null;
      }

      final doc = await FirebaseFirestore.instance
          .collection('couples')
          .doc('ray-aproo')
          .collection('fcmTokens')
          .doc(nameKey)
          .get();
      if (doc.exists) {
        return doc.data()?['token'] as String?;
      }
    } catch (e) {
      LogService.log('Error getting partner FCM token: $e');
    }
    return null;
  }

  static Future<({bool success, String message})> send({
    required String partnerName,
    required String title,
    required String body,
    String type = 'general',
    Map<String, String>? extra,
  }) async {
    try {
      LogService.log('FCM SEND initiated to partner: $partnerName (type: $type)');
      
      final partnerToken = await _getPartnerToken(partnerName);
      if (partnerToken == null) {
        final errMsg = 'FCM SEND cancelled: Partner token is empty in Firestore';
        LogService.log(errMsg);
        return (success: false, message: errMsg);
      }

      final accessToken = await _getAccessToken();
      if (accessToken == null) {
        final errMsg = 'FCM SEND cancelled: Could not retrieve OAuth2 access token (check private key / service account)';
        LogService.log(errMsg);
        return (success: false, message: errMsg);
      }

      final isDataOnly = type == 'call_ping' || type == 'call_ended' || type == 'ping';

      // Construct request body for HTTP v1 FCM API
      final Map<String, dynamic> requestBody = {
        'message': {
          'token': partnerToken,
          'data': {
            'type': type,
            'title': title,
            'body': body,
            if (extra != null) ...extra,
          },
          // For background actions, do not include the notification node so it is treated as a silent data-only payload.
          if (!isDataOnly)
            'notification': {
              'title': title,
              'body': body,
            },
          'android': {
            'priority': 'high',
            if (!isDataOnly)
              'notification': {
                'channel_id': type == 'call_ping' ? 'tether_calls_v1' : 'tether_updates_v1',
              },
          },
        }
      };

      final fcmUrl = 'https://fcm.googleapis.com/v1/projects/${NotificationConfig.projectId}/messages:send';
      
      final response = await _dio.post(
        fcmUrl,
        data: requestBody,
        options: Options(
          headers: {
            'Authorization': 'Bearer $accessToken',
            'Content-Type': 'application/json',
          },
        ),
      );

      if (response.statusCode == 200) {
        final successMsg = 'FCM SEND success: Message ID ${response.data['name']}';
        LogService.log(successMsg);
        return (success: true, message: successMsg);
      } else {
        final failMsg = 'FCM SEND failed with status: ${response.statusCode} - ${response.data}';
        LogService.log(failMsg);
        return (success: false, message: failMsg);
      }
    } catch (e) {
      String errMsg = 'ERROR in FCM Send: $e';
      if (e is DioException) {
        errMsg = 'FCM HTTP Error: ${e.response?.statusCode} - ${e.response?.data ?? e.message}';
      }
      LogService.log(errMsg);
      return (success: false, message: errMsg);
    }
  }
}
