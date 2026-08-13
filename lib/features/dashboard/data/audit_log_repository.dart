import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hyport/core/models/audit_log.dart';
import 'package:hyport/features/tickets/domain/ticket_activity.dart';

/// A real, honestly-scoped "audit log" (Phase 5 mockup screen 40) built
/// from two sources:
///   - [watchRecent]: the same ticket activity subcollections the Timeline
///     tab already reads — a Firestore `collectionGroup` query across every
///     ticket's `activity` docs. Covers ticket lifecycle events
///     (created/assigned/escalated/status changes/comments).
///   - [watchAdminActions]: the `audit_logs` collection, written by the
///     `adminCreateUser`/`adminUpdateUser` Cloud Functions (Admin SDK) for
///     user-management actions (account creation, role changes,
///     activate/deactivate).
/// Neither covers login events or settings changes — that would need
/// broader Cloud Functions instrumentation that hasn't been built yet
/// (not a billing blocker anymore; see DECISIONS.md). Scoped truthfully
/// rather than presented as a complete system audit trail.
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

  Stream<List<AuditLog>> watchAdminActions({int limit = 100}) {
    return _db
        .collection('audit_logs')
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map((d) => AuditLog.fromMap(d.id, d.data())).toList());
  }
}
