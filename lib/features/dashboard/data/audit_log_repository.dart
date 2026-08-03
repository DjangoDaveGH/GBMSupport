import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hyport/features/tickets/domain/ticket_activity.dart';

/// A real, honestly-scoped "audit log" (Phase 5 mockup screen 40) built
/// from the same ticket activity subcollections the Timeline tab already
/// reads — a Firestore `collectionGroup` query across every ticket's
/// `activity` docs, ordered newest-first. This covers ticket lifecycle
/// events (created/assigned/escalated/status changes/comments) but *not*
/// login events, settings changes, or user management actions — those
/// would need a true audit-events collection written by Cloud Functions,
/// which are blocked on the Blaze plan (see DECISIONS.md). Scoped
/// truthfully rather than presented as a complete system audit trail.
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
}
