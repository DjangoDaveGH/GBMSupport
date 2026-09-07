import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hyport/core/models/enums.dart';
import 'package:hyport/features/auth/domain/app_user.dart';

class UserRepository {
  final FirebaseFirestore _db;

  UserRepository(this._db);

  CollectionReference<Map<String, dynamic>> get _users =>
      _db.collection('users');

  /// Users eligible to have a ticket assigned/escalated to them (support-side
  /// roles only). Used to populate assignment dropdowns for Coordinators.
  Stream<List<AppUser>> watchAssignableUsers() {
    final assignableRoles = [
      UserRole.supportCoordinator,
      UserRole.functionalLead,
      UserRole.technicalLead,
      UserRole.vendorSupport,
    ].map((r) => r.wireValue).toList();

    return _users
        .where('role', whereIn: assignableRoles)
        .where('isActive', isEqualTo: true)
        .snapshots()
        .map(
          (snap) =>
              snap.docs.map((d) => AppUser.fromMap(d.id, d.data())).toList(),
        );
  }

  Stream<List<AppUser>> watchAllUsers() {
    return _users
        .orderBy('name')
        .snapshots()
        .map(
          (snap) =>
              snap.docs.map((d) => AppUser.fromMap(d.id, d.data())).toList(),
        );
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
