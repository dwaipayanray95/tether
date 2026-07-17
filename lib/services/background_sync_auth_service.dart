import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
  final _secureStorage = const FlutterSecureStorage();

  bool get isConfigured => EnvConfig.googleWebServerClientId.isNotEmpty;

  // Namespaced per Firebase Auth UID rather than one shared key. This app
  // only has two allowed accounts, but the same device is regularly signed
  // in as either one (partners sharing a phone) — a single shared key meant
  // that whichever account's setupAfterSignIn() finished last "won", and if
  // that happened to be a stale in-flight call from an account that had
  // already signed out (e.g. it raced a sign-out that happened before the
  // Cloud Function round-trip completed), the other partner's backups would
  // silently mint Drive tokens against the first partner's refresh token.
  // Keying by UID makes that impossible: each account only ever reads/writes
  // its own token, so a race can at worst leave a stale write to a key
  // nobody is currently reading from.
  String? _keyFor(String? uid) =>
      uid == null ? null : 'tether_drive_refresh_token_$uid';

  /// Call once, right after a successful interactive sign-in (same
  /// user-interaction-required constraint as authorizeScopes() elsewhere in
  /// this app — authorizeServer() cannot be called from a background
  /// context). Best-effort: any failure is logged, never thrown, since
  /// background sync is an enhancement, not something sign-in should ever
  /// be blocked on.
  Future<void> setupAfterSignIn() async {
    if (!isConfigured) return;
    // Captured up front so this call is pinned to the account that was
    // signed in when it was kicked off — if that account signs out again
    // before this finishes, the result below still only ever touches that
    // account's own key, never whatever account is signed in by the time
    // the async work completes.
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final key = _keyFor(uid);
    if (key == null) return;
    try {
      final existing = await _secureStorage.read(key: key);
      if (existing != null) return; // Already set up on this device.

      await _authorizeExchangeAndStore(key, allowDisconnectRetry: true);
    } catch (e) {
      LogService.log('BackgroundSyncAuth: setup failed (non-fatal): $e');
    }
  }

  /// One authorize+exchange+store attempt. If [allowDisconnectRetry] and the
  /// exchange fails specifically because Google didn't return a
  /// refresh_token (see functions/src/index.ts — happens when this Google
  /// account already granted this Web client offline access before, e.g.
  /// after a reinstall wiped local storage but not Google's server-side
  /// grant), disconnects the current Google Sign-In session and retries
  /// exactly once. Disconnecting forces Google to treat the next
  /// authorization as a fresh consent, which reliably re-issues a
  /// refresh_token. Safe to do here specifically because this whole method
  /// only ever runs synchronously within the interactive sign-in flow
  /// (setupAfterSignIn is called right after the user's sign-in tap) — the
  /// brief re-consent UI this can trigger happens in that same
  /// user-initiated gesture, not from a background context.
  Future<void> _authorizeExchangeAndStore(String key,
      {required bool allowDisconnectRetry}) async {
    final authorization =
        await GoogleSignIn.instance.authorizationClient.authorizeServer(GoogleScopes.drive);
    final serverAuthCode = authorization?.serverAuthCode;
    if (serverAuthCode == null) {
      LogService.log('BackgroundSyncAuth: no serverAuthCode returned, skipping');
      return;
    }

    try {
      final callable = FirebaseFunctions.instance.httpsCallable('exchangeGoogleAuthCode');
      final result =
          await callable.call<Map<String, dynamic>>({'serverAuthCode': serverAuthCode});
      final refreshToken = result.data['refreshToken'] as String?;
      if (refreshToken == null) {
        LogService.log('BackgroundSyncAuth: exchange returned no refresh token');
        return;
      }
      await _secureStorage.write(key: key, value: refreshToken);
      LogService.log('BackgroundSyncAuth: refresh token stored, headless sync enabled');
    } on FirebaseFunctionsException catch (e) {
      final isMissingRefreshToken =
          e.code == 'failed-precondition' && (e.message ?? '').contains('no_refresh_token');
      if (isMissingRefreshToken && allowDisconnectRetry) {
        LogService.log('BackgroundSyncAuth: no refresh token on file, '
            're-authorizing with a fresh consent...');
        await GoogleSignIn.instance.disconnect();
        await _authorizeExchangeAndStore(key, allowDisconnectRetry: false);
      } else {
        LogService.log('BackgroundSyncAuth: exchange failed: ${e.code} ${e.message}');
      }
    }
  }

  /// Only ever returns a token for the CURRENTLY signed-in account — never
  /// whatever account happened to write the most recent token.
  Future<String?> getStoredRefreshToken() async {
    if (!isConfigured) return null;
    final key = _keyFor(FirebaseAuth.instance.currentUser?.uid);
    if (key == null) return null;
    try {
      return await _secureStorage.read(key: key);
    } catch (e) {
      LogService.log('BackgroundSyncAuth: failed to read refresh token: $e');
      return null;
    }
  }

  /// Call on sign-out — clears the signed-out account's own token so a
  /// stale in-flight setup can't leave it usable, and so a subsequent
  /// sign-in (same or different account) always re-establishes headless
  /// sync from scratch rather than reusing a token tied to whoever was
  /// signed in at write time.
  Future<void> clearStoredRefreshToken() async {
    final key = _keyFor(FirebaseAuth.instance.currentUser?.uid);
    if (key == null) return;
    try {
      await _secureStorage.delete(key: key);
    } catch (e) {
      LogService.log('BackgroundSyncAuth: failed to clear refresh token: $e');
    }
  }
}
