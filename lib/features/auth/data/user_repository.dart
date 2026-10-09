import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hyport/core/models/enums.dart';
import 'package:hyport/core/models/support_system.dart';
import 'package:hyport/features/auth/domain/app_user.dart';

class UserRepository {
  final FirebaseFirestore _db;

  UserRepository(this._db);

  CollectionReference<Map<String, dynamic>> get _users =>
      _db.collection('users');

  /// Users eligible to have a ticket assigned/escalated to them. System
  /// scoping is applied in the Firestore query, not only in the UI, so a
  /// GHANEPS/GIFMIS operator cannot receive GBMS users in assignment data.
  Stream<List<AppUser>> watchAssignableUsers(AppUser viewer) {
    final assignableRoles = [
      UserRole.supportCoordinator,
      UserRole.functionalLead,
      UserRole.technicalLead,
      UserRole.vendorSupport,
    ].map((r) => r.wireValue).toList();

    return _watchVisibleUsers(viewer).map(
      (users) => users
          .where((u) => assignableRoles.contains(u.role.wireValue))
          .where((u) => u.isActive)
          .toList(),
    );
  }

  /// Returns only users visible in [viewer]'s system workspace. PFM
  /// Management is the only tenant-wide role. Other support roles use one
  /// exact array-contains query per assigned system; separate streams keep
  /// Firestore rules able to prove each query is tenant-scoped.
  Stream<List<AppUser>> watchAllUsers(AppUser viewer) {
    return _watchVisibleUsers(viewer);
  }

  Stream<List<AppUser>> _watchVisibleUsers(AppUser viewer) {
    if (viewer.role == UserRole.pfmManagement) {
      return _users.snapshots().map(_decodeAndSort);
    }

    final systems = allowedSystemsForRole(viewer.role, viewer.systems);
    if (systems.isEmpty) return Stream.value(const <AppUser>[]);

    return Stream.multi((controller) {
      final latest = <String, List<AppUser>>{};
      final subscriptions = <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];

      void emit() {
        final byId = <String, AppUser>{};
        for (final users in latest.values) {
          for (final user in users) {
            byId[user.id] = user;
          }
        }
        final users = byId.values.toList()
          ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        controller.add(users);
      }

      for (final system in systems) {
        final subscription = _users
            .where('systems', arrayContains: system)
            .snapshots()
            .listen((snap) {
              latest[system] = snap.docs
                  .map((d) => AppUser.fromMap(d.id, d.data()))
                  .toList();
              emit();
            }, onError: controller.addError);
        subscriptions.add(subscription);
      }

      controller.onCancel = () async {
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
      };
    });
  }

  List<AppUser> _decodeAndSort(QuerySnapshot<Map<String, dynamic>> snap) {
    final users = snap.docs
        .map((d) => AppUser.fromMap(d.id, d.data()))
        .toList();
    users.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return users;
  }

  /// Single-user lookup by id — used for e.g. showing the assignee's name on
  /// a ticket's "Assigned to" card.
  Stream<AppUser?> watchUserById(String userId) {
    return _users
        .doc(userId)
        .snapshots()
        .map((doc) => doc.exists ? AppUser.fromMap(doc.id, doc.data()!) : null);
  }

  /// Users may update only their own profile photo URL. Storage ownership is
  /// enforced separately by storage.rules.
  Future<void> setProfilePhotoUrl(String uid, String photoUrl) {
    return _users.doc(uid).update({'profilePhotoUrl': photoUrl});
  }

  /// Called on sign-in and then every ~2 minutes for the rest of a
  /// foregrounded session by PresenceHeartbeatListener (main.dart) — a
  /// genuine "last seen" rather than a one-off stamp. Powers the
  /// online/offline dot on the admin Users screen and the ticket chat
  /// header.
  Future<void> touchLastActive(String uid) {
    return _users.doc(uid).set({
      'lastActiveAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Registers this device's FCM token against the signed-in user's doc so
  /// Cloud Functions can push to it. Additive (arrayUnion) since one person
  /// may be signed in on more than one device.
  Future<void> addFcmToken(String uid, String token) {
    return _users.doc(uid).set({
      'fcmTokens': FieldValue.arrayUnion([token]),
    }, SetOptions(merge: true));
  }

  /// Removes a stale/invalidated token (e.g. on sign-out) so pushes don't
  /// keep targeting a device that's no longer listening.
  Future<void> removeFcmToken(String uid, String token) {
    return _users.doc(uid).set({
      'fcmTokens': FieldValue.arrayRemove([token]),
    }, SetOptions(merge: true));
  }
}
