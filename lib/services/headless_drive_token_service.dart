import 'package:cloud_functions/cloud_functions.dart';
import 'background_sync_auth_service.dart';
import 'log_service.dart';

/// Mints Drive-scoped access tokens for use in a headless (background,
/// no-foreground-Activity) context — the WorkManager-safe alternative to
/// GoogleDriveService's own token caching, which depends on the
/// google_sign_in plugin's session and only works with a foreground
/// Activity (see BackgroundSyncAuthService's doc comment for the full
/// story).
///
/// This does NOT replace GoogleDriveService for foreground use — it exists
/// specifically for a future background backup task (WorkManager) to call
/// BackupService/GoogleDriveService with a token minted this way instead.
/// Every call here goes through the refreshDriveAccessToken Cloud
/// Function, not directly to Google — a Web-application-type OAuth client
/// needs its client_secret on every refresh grant, not just once, so
/// there's no secret-free path directly from the device (see
/// functions/src/index.ts).
class HeadlessDriveTokenService {
  final _authService = BackgroundSyncAuthService();

  /// Returns null if headless sync isn't set up yet (no stored refresh
  /// token — e.g. the Cloud Function isn't deployed/configured, or the
  /// user hasn't signed in since it was enabled) or if the refresh token
  /// has been revoked/expired. Callers should treat null the same as "fall
  /// back to the foreground-only path" rather than as an error to retry.
  Future<String?> getAccessToken() async {
    final refreshToken = await _authService.getStoredRefreshToken();
    if (refreshToken == null) return null;

    try {
      final callable =
          FirebaseFunctions.instance.httpsCallable('refreshDriveAccessToken');
      final result =
          await callable.call<Map<String, dynamic>>({'refreshToken': refreshToken});
      return result.data['accessToken'] as String?;
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'failed-precondition') {
        // The refresh token itself was revoked/expired — clear it so the
        // next successful foreground sign-in re-establishes headless sync
        // from scratch, rather than retrying a token that will never work.
        LogService.log('HeadlessDriveToken: refresh token revoked, clearing');
        await _authService.clearStoredRefreshToken();
      } else {
        LogService.log('HeadlessDriveToken: mint failed: ${e.code} ${e.message}');
      }
      return null;
    } catch (e) {
      LogService.log('HeadlessDriveToken: mint failed: $e');
      return null;
    }
  }
}
