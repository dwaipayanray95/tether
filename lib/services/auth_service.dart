import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../config/env_config.dart';
import '../config/google_scopes.dart';
import 'background_sync_auth_service.dart';
import 'google_drive_service.dart';
import 'log_service.dart';

// Only these two emails are allowed in
const List<String> allowedEmails = EnvConfig.allowedEmails;

const String coupleId = EnvConfig.coupleId; // shared ID for Firestore collections

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  GoogleSignIn get googleSignIn => GoogleSignIn.instance;

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // attemptLightweightAuthentication() briefly flashes Android's Credential
  // Manager UI (AssistedSignInActivity/CredentialChooserActivity) even when
  // it resolves silently. Multiple independent call sites (Drive backup,
  // restore, scope validation) each calling it separately at launch caused
  // that UI to flash repeatedly in a row, which looked like the Google
  // sign-in card "kept popping up". Cache the result for the app session so
  // it's only requested once.
  //
  // Must be static: every call site does `AuthService()` fresh (e.g.
  // GoogleDriveService() constructs its own AuthService() internally), so
  // an instance field would reset on every call and never actually cache.
  static GoogleSignInAccount? _cachedGoogleUser;
  static Future<GoogleSignInAccount?>? _lightweightAuthFuture;

  Future<GoogleSignInAccount?> getGoogleUser() {
    if (_cachedGoogleUser != null) return Future.value(_cachedGoogleUser);
    return _lightweightAuthFuture ??=
        (GoogleSignIn.instance.attemptLightweightAuthentication() ??
                Future.value(null))
            .then((user) {
      _cachedGoogleUser = user;
      _lightweightAuthFuture = null;
      return user;
    });
  }

  bool get isRay =>
      currentUser?.email?.toLowerCase() == allowedEmails[0].toLowerCase();

  String get myName => isRay ? 'Ray' : 'Aproo';
  String get partnerName => isRay ? 'Aproo' : 'Ray';
  String get myDisplayName => myName == 'Ray' ? 'Raayyy' : myName;
  String get partnerDisplayName => partnerName == 'Ray' ? 'Raayyy' : partnerName;

  Future<String?> getPartnerUid() async {
    final partnerEmail = isRay ? allowedEmails[1] : allowedEmails[0];
    final snap = await _db
        .collection('users')
        .where('email', isEqualTo: partnerEmail)
        .limit(1)
        .get();
    if (snap.docs.isNotEmpty) {
      return snap.docs.first.id;
    }
    return null;
  }

  // ── Google Sign-In ────────────────────────────────────────────────────────

  Future<UserCredential?> signInWithGoogle() async {
    LogService.log('Google Sign-In initiated');
    final GoogleSignInAccount googleUser;
    try {
      googleUser = await GoogleSignIn.instance.authenticate();
    } catch (e) {
      LogService.log('Google Sign-In cancelled or failed: $e');
      return null;
    }
    _cachedGoogleUser = googleUser;

    final email = googleUser.email.toLowerCase();
    if (!allowedEmails.map((e) => e.toLowerCase()).contains(email)) {
      LogService.log('Sign-In REJECTED: $email not allowed');
      await GoogleSignIn.instance.signOut();
      throw Exception('This app is private. Your Google account is not allowed.');
    }

    final googleAuth = googleUser.authentication;
    // Request every scope the app needs in one go, from this user-initiated
    // tap — Android requires authorizeScopes() to be triggered by a real
    // user interaction, so background code must never call it directly.
    final authorization = await googleUser.authorizationClient.authorizeScopes(GoogleScopes.all);
    final credential = GoogleAuthProvider.credential(
      accessToken: authorization.accessToken,
      idToken: googleAuth.idToken,
    );

    final result = await _auth.signInWithCredential(credential);
    LogService.log('Sign-In SUCCESS: ${result.user?.email}');
    await _ensureUserDoc(result.user!);

    // Best-effort, never blocks sign-in — see BackgroundSyncAuthService's
    // doc comment. Must run after signInWithCredential() above: the
    // exchangeGoogleAuthCode Cloud Function requires a Firebase Auth
    // context to authorize the caller.
    unawaited(BackgroundSyncAuthService().setupAfterSignIn());

    return result;
  }

  // ── Email / Password ──────────────────────────────────────────────────────

  Future<UserCredential> signIn(String email, String password) async {
    LogService.log('Email Sign-In initiated: $email');
    if (!allowedEmails.map((e) => e.toLowerCase()).contains(email.toLowerCase())) {
      LogService.log('Sign-In REJECTED: $email not allowed');
      throw Exception('This app is private. That email is not allowed.');
    }
    try {
      final result = await _auth.signInWithEmailAndPassword(
          email: email, password: password);
      LogService.log('Sign-In SUCCESS: $email');
      await _ensureUserDoc(result.user!);
      return result;
    } catch (e) {
      LogService.log('Sign-In ERROR: $e');
      rethrow;
    }
  }

  Future<UserCredential> signUp(
      String email, String password, String name) async {
    LogService.log('Sign-Up initiated: $email');
    if (!allowedEmails.map((e) => e.toLowerCase()).contains(email.toLowerCase())) {
      LogService.log('Sign-Up REJECTED: $email not allowed');
      throw Exception('This app is private. That email is not allowed.');
    }
    try {
      final result = await _auth.createUserWithEmailAndPassword(
          email: email, password: password);
      LogService.log('Sign-Up SUCCESS: $email');
      await _ensureUserDoc(result.user!, name: name);
      return result;
    } catch (e) {
      LogService.log('Sign-Up ERROR: $e');
      rethrow;
    }
  }

  Future<void> signOut() async {
    LogService.log('Sign-Out initiated');
    _cachedGoogleUser = null;
    _lightweightAuthFuture = null;
    GoogleDriveService.invalidateCachedAccessToken();
    await BackgroundSyncAuthService().clearStoredRefreshToken();
    await GoogleSignIn.instance.signOut();
    await _auth.signOut();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Future<void> _ensureUserDoc(User user, {String? name}) async {
    final ref = _db.collection('users').doc(user.uid);
    final doc = await ref.get();
    if (!doc.exists) {
      final resolvedName = name ??
          (user.email?.toLowerCase() == allowedEmails[0].toLowerCase()
              ? 'Ray'
              : 'Aproo');
      await ref.set({
        'uid': user.uid,
        'name': resolvedName,
        'email': user.email,
        'photoUrl': user.photoURL,
        'coupleId': coupleId,
      });
    }
  }
}
