import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hyport/core/models/audit_log.dart';
import 'package:hyport/features/auth/domain/app_user.dart';
import 'package:hyport/features/tickets/domain/ticket_activity.dart';

/// Audit log sources, built from the ticket activity subcollections (a
/// Firestore `collectionGroup` query across every ticket's `activity` docs)
/// and, for admins, the `audit_logs` collection:
///   - [watchRecent]: every ticket event across all systems. Admins only.
///   - [watchOwn]: ticket events the signed-in user performed. Everyone else.
///     Firestore rules allow this query by `actorId`, so a user can read
///     their own entries and nothing else.
///   - [watchAdminActions]: the `audit_logs` collection, written by Cloud
///     Functions (Admin SDK) for user-management and settings changes.
/// Login events are not recorded yet (needs an auth-level hook).

class AuditLogRepository {
  final FirebaseFirestore _db;

  AuditLogRepository(this._db);

  Stream<List<TicketActivity>> watchRecent({int limit = 100}) {
    return _db
        .collectionGroup('activity')
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map((d) => TicketActivity.fromMap(d.id, d.data())).toList());
  }

  Stream<List<TicketActivity>> watchOwn(AppUser viewer, {int limit = 100}) {
    return _db
        .collectionGroup('activity')
        .where('actorId', isEqualTo: viewer.id)
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map((d) => TicketActivity.fromMap(d.id, d.data())).toList());
  }

  Stream<List<AuditLog>> watchAdminActions({int limit = 100}) {
    return _db
        .collection('audit_logs')
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map((d) => AuditLog.fromMap(d.id, d.data())).toList());
  }
}
