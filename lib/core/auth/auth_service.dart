import 'package:firebase_auth/firebase_auth.dart';

/// Thin wrapper over FirebaseAuth. Accounts are admin-provisioned (see
/// Section 10, "out of scope: self-service registration") so this only
/// needs sign-in/out, not sign-up.
class AuthService {
  final FirebaseAuth _auth;

  AuthService(this._auth);

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  Future<UserCredential> signIn({required String email, required String password}) {
    return _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  Future<void> signOut() => _auth.signOut();

  Future<void> sendPasswordResetEmail(String email) {
    return _auth.sendPasswordResetEmail(email: email);
  }

  /// Completes a password reset started by [sendPasswordResetEmail]. The
  /// `oobCode` comes from the query parameter on the link Firebase emails —
  /// see ResetPasswordScreen / the `/reset-password` route.
  Future<void> confirmPasswordReset({required String oobCode, required String newPassword}) {
    return _auth.confirmPasswordReset(code: oobCode, newPassword: newPassword);
  }
}
