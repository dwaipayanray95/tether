import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'log_service.dart';

// Only these two emails are allowed in
const List<String> allowedEmails = [
  'ray@redacted.invalid', // Raayyy
  'aproo@redacted.invalid',      // Aproo
];

const String coupleId = 'ray-aproo'; // shared ID for Firestore collections

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      'https://www.googleapis.com/auth/drive.file',
      'https://www.googleapis.com/auth/drive.appdata',
    ],
  );

  GoogleSignIn get googleSignIn => _googleSignIn;

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

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
    final googleUser = await _googleSignIn.signIn();
    if (googleUser == null) {
      LogService.log('Google Sign-In cancelled by user');
      return null;
    }

    final email = googleUser.email.toLowerCase();
    if (!allowedEmails.map((e) => e.toLowerCase()).contains(email)) {
      LogService.log('Sign-In REJECTED: $email not allowed');
      await _googleSignIn.signOut();
      throw Exception('This app is private. Your Google account is not allowed.');
    }

    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    final result = await _auth.signInWithCredential(credential);
    LogService.log('Sign-In SUCCESS: ${result.user?.email}');
    await _ensureUserDoc(result.user!);
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
    await _googleSignIn.signOut();
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
