import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hyport/core/auth/auth_service.dart';
import 'package:hyport/core/services/firebase_providers.dart';
import 'package:hyport/features/auth/data/otp_repository.dart';
import 'package:hyport/features/auth/domain/app_user.dart';

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(ref.watch(firebaseAuthProvider));
});

final otpRepositoryProvider = Provider<OtpRepository>((ref) {
  return OtpRepository(ref.watch(firestoreProvider));
});

/// Whether the given uid's session has completed its 2FA step yet. Plain
/// in-memory state (not persisted) — a fresh app launch always starts
/// unverified, which is the point of a per-session second factor.
///
/// Deliberately **not** `.autoDispose`: the only readers are `ref.read`
/// calls (the router's redirect, and the verify screen setting it), never
/// a `ref.watch`, so an autoDispose instance would have zero listeners the
/// instant it's set and get torn back down to `false` before the next
/// redirect check ever saw `true` — an infinite bounce back to the OTP
/// screen right after successfully verifying.
///
/// Keying by uid means a different user signing in never inherits this
/// flag (different key, fresh default). The same user signing back in
/// *would* inherit a stale `true` from their previous session though,
/// since a plain family never tears its entries down on its own — so
/// `_goRouterRefreshProvider` explicitly invalidates the whole family on
/// sign-out (see app_router.dart) to force re-verification on the next
/// login, same account or not.
final otpVerifiedProvider = StateProvider.family<bool, String>((ref, uid) => false);

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
    loading: () => Stream.value(null),
    error: (_, _) => Stream.value(null),
  );
});
