import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hyport/core/models/enums.dart';
import 'package:hyport/features/auth/domain/app_user.dart';
import 'package:hyport/features/tickets/domain/ticket.dart';
import 'package:hyport/features/tickets/domain/ticket_activity.dart';

const int ticketPageSize = 20;

/// Firestore access for tickets + their activity subcollection. Client-side
/// scoping here is a UX convenience (fewer wasted reads, sensible defaults);
/// firestore.rules is the actual access boundary — see Section 3 of the
/// project brief and DECISIONS.md.
class TicketRepository {
  final FirebaseFirestore _db;

  TicketRepository(this._db);

  CollectionReference<Map<String, dynamic>> get _tickets => _db.collection('tickets');

  CollectionReference<Map<String, dynamic>> _activityFor(String ticketId) =>
      _tickets.doc(ticketId).collection('activity');

  /// Builds the base query scoped to what [viewer] is allowed to see. Per
  /// Section 3's role table, a plain MDA/MMDA User only sees tickets they
  /// personally logged; a Focal Person sees every ticket from their
  /// institution. Support Coordinator and Management see across
  /// institutions unrestricted (Coordinator specifically must see
  /// unassigned tickets to assign them). Functional Lead only sees tickets
  /// assigned to them; Technical Lead only the ones assigned to them that
  /// have actually been escalated (escalationLevel >= 1); vendor/specialist
  /// support only sees tickets explicitly escalated to them (escalationLevel
  /// 2 and assignedTo == their uid). This mirrors firestore.rules exactly —
  /// that's the real access boundary, this is just the matching UX query so
  /// these roles' ticket lists/dashboards aren't full of tickets they can't
  /// even open.
  Query<Map<String, dynamic>> scopedQuery(AppUser viewer) {
    if (viewer.role == UserRole.vendorSupport) {
      return _tickets.where('assignedTo', isEqualTo: viewer.id).where('escalationLevel', isEqualTo: 2);
    }
    if (viewer.role == UserRole.functionalLead || viewer.role == UserRole.technicalLead) {
      // One Applications Systems Unit — both roles see any ticket assigned
      // to them, at any escalation level (category auto-assignment places
      // level-0 tickets directly with an APPS member).
      return _tickets.where('assignedTo', isEqualTo: viewer.id);
    }
    if (viewer.role.isSupportSide) {
      return _tickets;
    }
    if (viewer.role == UserRole.focalPerson) {
      return _tickets.where('institutionId', isEqualTo: viewer.institutionId);
    }
    return _tickets.where('createdBy', isEqualTo: viewer.id);
  }

  /// Firestore allows only one `whereIn` clause per query, so when both
  /// [statuses] and [priorities] are multi-valued, [statuses] is applied
  /// server-side (the more commonly used filter — the tab chips) and
  /// [priorities] is applied client-side on the resulting page. That means a
  /// heavy priority filter can return fewer than [limit] tickets even when
  /// more would match further back — acceptable for this app's ticket
  /// volume, not correct for arbitrarily large result sets.
  /// [limit] defaults to [ticketPageSize] for list-screen pagination; pass
  /// `null` for an unbounded fetch (used by analytics/dashboard/report
  /// screens, which need every matching ticket to compute a true count, not
  /// just the page size).
  Stream<List<Ticket>> watchTickets(
    AppUser viewer, {
    Set<TicketStatus> statuses = const {},
    TicketCategory? category,
    Set<TicketPriority> priorities = const {},
    int? limit = ticketPageSize,
  }) {
    Query<Map<String, dynamic>> query = scopedQuery(viewer);
    if (statuses.isNotEmpty) {
      query = query.where('status', whereIn: statuses.map((s) => s.wireValue).toList());
    }
    if (category != null) query = query.where('category', isEqualTo: category.wireValue);
    query = query.orderBy('createdAt', descending: true);
    if (limit != null) query = query.limit(limit);

    return query.snapshots().map((snap) {
      final tickets = snap.docs.map((d) => Ticket.fromMap(d.id, d.data())).toList();
      if (priorities.isEmpty) return tickets;
      return tickets.where((t) => priorities.contains(t.priority)).toList();
    });
  }

  Stream<Ticket?> watchTicket(String ticketId) {
    return _tickets.doc(ticketId).snapshots().map(
          (doc) => doc.exists ? Ticket.fromMap(doc.id, doc.data()!) : null,
        );
  }

  Stream<List<TicketActivity>> watchActivity(String ticketId) {
    return _activityFor(ticketId).orderBy('timestamp', descending: true).snapshots().map(
          (snap) => snap.docs.map((d) => TicketActivity.fromMap(d.id, d.data())).toList(),
        );
  }

  /// Creates a ticket with an auto-generated human-readable reference
  /// (PFMSD-{year}-{6-digit sequence}), using a transaction against a
  /// per-year counter doc so concurrent creates never collide. Also writes
  /// the initial "created" TicketActivity entry as part of the same
  /// transaction so the audit trail can never be skipped.
  Future<Ticket> createTicket({
    required String createdBy,
    required String institutionId,
    required TicketCategory category,
    required String subCategory,
    required String title,
    required String description,
    required List<String> attachmentUrls,
    required TicketPriority priority,
    required TicketImpact impact,
    required bool affectsMultipleUsers,
  }) async {
    final now = DateTime.now();
    final year = now.year;
    final counterRef = _db.collection('counters').doc('tickets_$year');
    final ticketRef = _tickets.doc();

    late final Ticket ticket;
    await _db.runTransaction<void>((tx) async {
      final counterSnap = await tx.get(counterRef);
      final nextSeq = ((counterSnap.data()?['count'] as num?)?.toInt() ?? 0) + 1;
      tx.set(counterRef, {'count': nextSeq}, SetOptions(merge: true));

      final ref = 'PFMSD-$year-${nextSeq.toString().padLeft(6, '0')}';

      // `now` here is only for the transient Ticket returned to the caller;
      // the authoritative createdAt/updatedAt are server-stamped below and
      // reach the UI via the ticket stream a moment later. Ticket ordering
      // (orderBy('createdAt')) and the Analytics response/resolution metrics
      // must never depend on each device's wall clock.
      ticket = Ticket(
        id: ticketRef.id,
        ticketReference: ref,
        createdBy: createdBy,
        institutionId: institutionId,
        category: category,
        subCategory: subCategory,
        title: title,
        description: description,
        attachmentUrls: attachmentUrls,
        priority: priority,
        impact: impact,
        affectsMultipleUsers: affectsMultipleUsers,
        status: TicketStatus.open,
        escalationLevel: 0,
        createdAt: now,
        updatedAt: now,
      );
      tx.set(ticketRef, {
        ...ticket.toMap(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      final activityRef = _activityFor(ticketRef.id).doc();
      tx.set(activityRef, {
        ...TicketActivity(
          id: activityRef.id,
          ticketId: ticketRef.id,
          actorId: createdBy,
          action: TicketActivityAction.created,
          toValue: TicketStatus.open.wireValue,
          timestamp: now,
        ).toMap(),
        'timestamp': FieldValue.serverTimestamp(),
      });
    });

    return ticket;
  }

  Future<void> _writeActivity({
    required String ticketId,
    required String actorId,
    required TicketActivityAction action,
    String? fromValue,
    String? toValue,
    String? note,
    String? attachmentUrl,
  }) {
    final ref = _activityFor(ticketId).doc();
    // Server-stamped, not the client clock — see createTicket's note. The
    // `timestamp` passed to the constructor is a throwaway, overridden below.
    return ref.set({
      ...TicketActivity(
        id: ref.id,
        ticketId: ticketId,
        actorId: actorId,
        action: action,
        fromValue: fromValue,
        toValue: toValue,
        note: note,
        attachmentUrl: attachmentUrl,
        timestamp: DateTime.now(),
      ).toMap(),
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Future<void> assignTicket({
    required String ticketId,
    required String assigneeId,
    required String actorId,
  }) async {
    // firstRespondedAt is deliberately NOT set here: assignment (manual or
    // the onTicketCreated auto-assign) isn't a "response". It's stamped by
    // the Cloud Functions on the assignee's first real action (status move
    // or comment), so the Analytics metric means the same thing regardless
    // of how a ticket got assigned.
    final batch = _db.batch();
    batch.update(_tickets.doc(ticketId), {
      'assignedTo': assigneeId,
      'status': TicketStatus.assigned.wireValue,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final activityRef = _activityFor(ticketId).doc();
    batch.set(activityRef, {
      ...TicketActivity(
        id: activityRef.id,
        ticketId: ticketId,
        actorId: actorId,
        action: TicketActivityAction.assigned,
        toValue: assigneeId,
        timestamp: DateTime.now(),
      ).toMap(),
      'timestamp': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  Future<void> changeStatus({
    required String ticketId,
    required TicketStatus from,
    required TicketStatus to,
    required String actorId,
    String? note,
  }) async {
    final batch = _db.batch();
    final updates = <String, dynamic>{
      'status': to.wireValue,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (to == TicketStatus.resolved) updates['resolvedAt'] = FieldValue.serverTimestamp();
    if (note != null && note.isNotEmpty) updates['resolutionNotes'] = note;
    batch.update(_tickets.doc(ticketId), updates);

    final activityRef = _activityFor(ticketId).doc();
    batch.set(activityRef, {
      ...TicketActivity(
        id: activityRef.id,
        ticketId: ticketId,
        actorId: actorId,
        action: TicketActivityAction.statusChanged,
        fromValue: from.wireValue,
        toValue: to.wireValue,
        note: note,
        timestamp: DateTime.now(),
      ).toMap(),
      'timestamp': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  Future<void> escalate({
    required String ticketId,
    required int toLevel,
    required String assigneeId,
    required String actorId,
    String? note,
  }) async {
    final batch = _db.batch();
    batch.update(_tickets.doc(ticketId), {
      'escalationLevel': toLevel,
      'assignedTo': assigneeId,
      'status': TicketStatus.escalated.wireValue,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    final activityRef = _activityFor(ticketId).doc();
    batch.set(activityRef, {
      ...TicketActivity(
        id: activityRef.id,
        ticketId: ticketId,
        actorId: actorId,
        action: TicketActivityAction.escalated,
        toValue: assigneeId,
        note: note,
        timestamp: DateTime.now(),
      ).toMap(),
      'timestamp': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  Future<void> addComment({
    required String ticketId,
    required String actorId,
    required String note,
    String? attachmentUrl,
  }) {
    return _writeActivity(
      ticketId: ticketId,
      actorId: actorId,
      action: TicketActivityAction.commented,
      note: note,
      attachmentUrl: attachmentUrl,
    );
  }

  Future<void> reopen({
    required String ticketId,
    required String actorId,
    String? note,
  }) async {
    final batch = _db.batch();
    batch.update(_tickets.doc(ticketId), {
      'status': TicketStatus.reopened.wireValue,
      'updatedAt': FieldValue.serverTimestamp(),
      'closedAt': null,
      'closedBy': null,
      // Clear the resolution stamp too — a reopened ticket is no longer
      // resolved, so it must stop counting toward "Tickets Resolved",
      // resolution-time averages, and SLA compliance. changeStatus() re-sets
      // it if the ticket is resolved again.
      'resolvedAt': null,
    });
    final activityRef = _activityFor(ticketId).doc();
    batch.set(activityRef, {
      ...TicketActivity(
        id: activityRef.id,
        ticketId: ticketId,
        actorId: actorId,
        action: TicketActivityAction.reopened,
        note: note,
        timestamp: DateTime.now(),
      ).toMap(),
      'timestamp': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  Future<void> close({
    required String ticketId,
    required String actorId,
  }) async {
    final batch = _db.batch();
    batch.update(_tickets.doc(ticketId), {
      'status': TicketStatus.closed.wireValue,
      'closedAt': FieldValue.serverTimestamp(),
      'closedBy': actorId,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    final activityRef = _activityFor(ticketId).doc();
    batch.set(activityRef, {
      ...TicketActivity(
        id: activityRef.id,
        ticketId: ticketId,
        actorId: actorId,
        action: TicketActivityAction.closed,
        timestamp: DateTime.now(),
      ).toMap(),
      'timestamp': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }
}
