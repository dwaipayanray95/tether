import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Only these two emails are allowed in
const List<String> allowedEmails = [
  'dwaipayanray95@gmail.com', // Ray
  'apoo.0404@gmail.com',      // Aproo
];

const String coupleId = 'ray-aproo'; // shared ID for Firestore collections

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  bool get isRay =>
      currentUser?.email?.toLowerCase() == allowedEmails[0].toLowerCase();

  String get myName => isRay ? 'Ray' : 'Aproo';
  String get partnerName => isRay ? 'Aproo' : 'Ray';

  // ── Google Sign-In ────────────────────────────────────────────────────────

  Future<UserCredential?> signInWithGoogle() async {
    final googleUser = await _googleSignIn.signIn();
    if (googleUser == null) return null; // user cancelled

    final email = googleUser.email.toLowerCase();
    if (!allowedEmails.map((e) => e.toLowerCase()).contains(email)) {
      await _googleSignIn.signOut();
      throw Exception('This app is private. Your Google account is not allowed.');
    }

    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    final result = await _auth.signInWithCredential(credential);
    await _ensureUserDoc(result.user!);
    return result;
  }

  // ── Email / Password ──────────────────────────────────────────────────────

  Future<UserCredential> signIn(String email, String password) async {
    if (!allowedEmails.map((e) => e.toLowerCase()).contains(email.toLowerCase())) {
      throw Exception('This app is private. That email is not allowed.');
    }
    final result = await _auth.signInWithEmailAndPassword(
        email: email, password: password);
    await _ensureUserDoc(result.user!);
    return result;
  }

  Future<UserCredential> signUp(
      String email, String password, String name) async {
    if (!allowedEmails.map((e) => e.toLowerCase()).contains(email.toLowerCase())) {
      throw Exception('This app is private. That email is not allowed.');
    }
    final result = await _auth.createUserWithEmailAndPassword(
        email: email, password: password);
    await _ensureUserDoc(result.user!, name: name);
    return result;
  }

  Future<void> signOut() async {
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
