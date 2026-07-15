import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../config/env_config.dart';
import '../config/google_scopes.dart';
import 'log_service.dart';

/// Manages the one-time exchange that unblocks headless (background,
/// no-foreground-Activity) Google Drive backup sync — see
/// functions/src/index.ts's doc comment for the full architecture.
///
/// Flow: request offline access at sign-in (serverAuthCode) -> hand it to
/// the exchangeGoogleAuthCode Cloud Function (the only step that needs a
/// client secret, so it can't happen on-device) -> store the returned
/// refresh_token in secure storage. From then on, HeadlessDriveTokenService
/// mints fresh Drive access tokens directly from that refresh token via a
/// plain, secret-free HTTP call — no Google Sign-In plugin/session/Activity
/// needed, safe to call from a background isolate.
///
/// A no-op today: [EnvConfig.googleWebServerClientId] is empty until the
/// Cloud Function is deployed and the Web OAuth client is configured (see
/// functions/src/index.ts). Every method here checks for that and returns
/// early rather than erroring, so this is safe to wire into the sign-in
/// flow well before that setup is complete.
class BackgroundSyncAuthService {
  static const _refreshTokenKey = 'tether_drive_refresh_token';
  final _secureStorage = const FlutterSecureStorage();

  bool get isConfigured => EnvConfig.googleWebServerClientId.isNotEmpty;

  /// Call once, right after a successful interactive sign-in (same
  /// user-interaction-required constraint as authorizeScopes() elsewhere in
  /// this app — authorizeServer() cannot be called from a background
  /// context). Best-effort: any failure is logged, never thrown, since
  /// background sync is an enhancement, not something sign-in should ever
  /// be blocked on.
  Future<void> setupAfterSignIn() async {
    if (!isConfigured) return;
    try {
      final existing = await _secureStorage.read(key: _refreshTokenKey);
      if (existing != null) return; // Already set up on this device.

      final authorization = await GoogleSignIn.instance.authorizationClient
          .authorizeServer(GoogleScopes.drive);
      final serverAuthCode = authorization?.serverAuthCode;
      if (serverAuthCode == null) {
        LogService.log('BackgroundSyncAuth: no serverAuthCode returned, skipping');
        return;
      }

      final callable =
          FirebaseFunctions.instance.httpsCallable('exchangeGoogleAuthCode');
      final result =
          await callable.call<Map<String, dynamic>>({'serverAuthCode': serverAuthCode});
      final refreshToken = result.data['refreshToken'] as String?;
      if (refreshToken == null) {
        LogService.log('BackgroundSyncAuth: exchange returned no refresh token');
        return;
      }

      await _secureStorage.write(key: _refreshTokenKey, value: refreshToken);
      LogService.log('BackgroundSyncAuth: refresh token stored, headless sync enabled');
    } catch (e) {
      LogService.log('BackgroundSyncAuth: setup failed (non-fatal): $e');
    }
  }

  Future<String?> getStoredRefreshToken() async {
    if (!isConfigured) return null;
    try {
      return await _secureStorage.read(key: _refreshTokenKey);
    } catch (e) {
      LogService.log('BackgroundSyncAuth: failed to read refresh token: $e');
      return null;
    }
  }

  /// Call on sign-out — a stale refresh token for a signed-out account must
  /// never be usable by a subsequent background sync run.
  Future<void> clearStoredRefreshToken() async {
    try {
      await _secureStorage.delete(key: _refreshTokenKey);
    } catch (e) {
      LogService.log('BackgroundSyncAuth: failed to clear refresh token: $e');
    }
  }
}
