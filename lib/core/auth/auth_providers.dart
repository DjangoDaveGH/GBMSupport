import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hyport/core/auth/auth_service.dart';
import 'package:hyport/core/services/firebase_providers.dart';
import 'package:hyport/features/auth/domain/app_user.dart';

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(ref.watch(firebaseAuthProvider));
});

/// Raw Firebase auth state (signed in / signed out).
final authStateChangesProvider = StreamProvider.autoDispose<User?>((ref) {
  return ref.watch(authServiceProvider).authStateChanges();
});

/// The signed-in user's app profile, live-synced from Firestore so role or
/// institution changes made by an admin take effect without a re-login.
/// Firestore security rules restrict `users/{uid}` reads to the owner
/// (or support-side roles), so this doubles as an access check: a
/// disabled/deleted account simply stops emitting a profile.
final currentAppUserProvider = StreamProvider.autoDispose<AppUser?>((ref) {
  final authState = ref.watch(authStateChangesProvider);
  final firestore = ref.watch(firestoreProvider);

  return authState.when(
    data: (user) {
      if (user == null) return Stream.value(null);
      return firestore.collection('users').doc(user.uid).snapshots().map((doc) {
        if (!doc.exists) return null;
        return AppUser.fromMap(doc.id, doc.data()!);
      });
    },
    // While auth itself is still resolving, "is there an app user" is
    // unknown — not "no". Emitting Stream.value(null) here would briefly
    // report a signed-in user as null (data, not loading), which the
    // router's redirect reads as logged-out and flashes /login before the
    // real Firestore profile arrives a moment later. An empty stream keeps
    // this provider in AsyncValue.loading() (its natural initial state)
    // until authState settles and this rebuilds with the real answer.
    loading: () => const Stream.empty(),
    error: (_, _) => Stream.value(null),
  );
});
