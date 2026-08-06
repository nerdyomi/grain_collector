import 'package:firebase_auth/firebase_auth.dart';

/// Wraps Firebase Auth's email/password sign-in behind a plain
/// worker-ID + password concept - workers never see or type an email.
/// The synthetic email domain is never delivered to; it exists only
/// because Firebase Auth's email/password provider requires one.
class AuthService {
  static const _emailDomain = 'ifarmer.local';

  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? get currentWorkerId => _auth.currentUser?.uid;

  bool get isSignedIn => _auth.currentUser != null;

  Future<void> signIn({required String workerId, required String password}) async {
    final id = workerId.trim();
    try {
      await _auth
          .signInWithEmailAndPassword(
            email: '$id@$_emailDomain',
            password: password,
          )
          .timeout(const Duration(seconds: 20));
    } on FirebaseAuthException {
      throw Exception('Invalid ID or password.');
    }
  }

  Future<void> signOut() => _auth.signOut();
}
