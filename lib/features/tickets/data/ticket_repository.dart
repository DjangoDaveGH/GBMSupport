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
  /// institution. Support-side roles see across institutions, and
  /// vendor/specialist support only sees tickets explicitly escalated to
  /// them (escalationLevel 2 and assignedTo == their uid).
  Query<Map<String, dynamic>> scopedQuery(AppUser viewer) {
    if (viewer.role == UserRole.vendorSupport) {
      return _tickets.where('assignedTo', isEqualTo: viewer.id).where('escalationLevel', isEqualTo: 2);
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
  Stream<List<Ticket>> watchTickets(
    AppUser viewer, {
    Set<TicketStatus> statuses = const {},
    TicketCategory? category,
    Set<TicketPriority> priorities = const {},
    int limit = ticketPageSize,
  }) {
    Query<Map<String, dynamic>> query = scopedQuery(viewer);
    if (statuses.isNotEmpty) {
      query = query.where('status', whereIn: statuses.map((s) => s.wireValue).toList());
    }
    if (category != null) query = query.where('category', isEqualTo: category.wireValue);
    query = query.orderBy('createdAt', descending: true).limit(limit);

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
      tx.set(ticketRef, ticket.toMap());

      final activityRef = _activityFor(ticketRef.id).doc();
      tx.set(
        activityRef,
        TicketActivity(
          id: activityRef.id,
          ticketId: ticketRef.id,
          actorId: createdBy,
          action: TicketActivityAction.created,
          toValue: TicketStatus.open.wireValue,
          timestamp: now,
        ).toMap(),
      );
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
    return ref.set(
      TicketActivity(
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
    );
  }

  Future<void> assignTicket({
    required String ticketId,
    required String assigneeId,
    required String actorId,
  }) async {
    final ticketRef = _tickets.doc(ticketId);
    final now = DateTime.now();

    await _db.runTransaction<void>((tx) async {
      final snap = await tx.get(ticketRef);
      final alreadyResponded = snap.data()?['firstRespondedAt'] != null;

      tx.update(ticketRef, {
        'assignedTo': assigneeId,
        'status': TicketStatus.assigned.wireValue,
        'updatedAt': Timestamp.fromDate(now),
        // Stamped once — powers the Analytics "First Response Time" metric
        // with a real timestamp instead of an inferred/approximated one.
        if (!alreadyResponded) 'firstRespondedAt': Timestamp.fromDate(now),
      });

      final activityRef = _activityFor(ticketId).doc();
      tx.set(
        activityRef,
        TicketActivity(
          id: activityRef.id,
          ticketId: ticketId,
          actorId: actorId,
          action: TicketActivityAction.assigned,
          toValue: assigneeId,
          timestamp: now,
        ).toMap(),
      );
    });
  }

  Future<void> changeStatus({
    required String ticketId,
    required TicketStatus from,
    required TicketStatus to,
    required String actorId,
    String? note,
  }) async {
    final batch = _db.batch();
    final now = DateTime.now();
    final updates = <String, dynamic>{
      'status': to.wireValue,
      'updatedAt': Timestamp.fromDate(now),
    };
    if (to == TicketStatus.resolved) updates['resolvedAt'] = Timestamp.fromDate(now);
    if (note != null && note.isNotEmpty) updates['resolutionNotes'] = note;
    batch.update(_tickets.doc(ticketId), updates);

    final activityRef = _activityFor(ticketId).doc();
    batch.set(
      activityRef,
      TicketActivity(
        id: activityRef.id,
        ticketId: ticketId,
        actorId: actorId,
        action: TicketActivityAction.statusChanged,
        fromValue: from.wireValue,
        toValue: to.wireValue,
        note: note,
        timestamp: now,
      ).toMap(),
    );
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
    final now = DateTime.now();
    batch.update(_tickets.doc(ticketId), {
      'escalationLevel': toLevel,
      'assignedTo': assigneeId,
      'status': TicketStatus.escalated.wireValue,
      'updatedAt': Timestamp.fromDate(now),
    });
    final activityRef = _activityFor(ticketId).doc();
    batch.set(
      activityRef,
      TicketActivity(
        id: activityRef.id,
        ticketId: ticketId,
        actorId: actorId,
        action: TicketActivityAction.escalated,
        toValue: assigneeId,
        note: note,
        timestamp: now,
      ).toMap(),
    );
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
    final now = DateTime.now();
    batch.update(_tickets.doc(ticketId), {
      'status': TicketStatus.reopened.wireValue,
      'updatedAt': Timestamp.fromDate(now),
      'closedAt': null,
      'closedBy': null,
    });
    final activityRef = _activityFor(ticketId).doc();
    batch.set(
      activityRef,
      TicketActivity(
        id: activityRef.id,
        ticketId: ticketId,
        actorId: actorId,
        action: TicketActivityAction.reopened,
        note: note,
        timestamp: now,
      ).toMap(),
    );
    await batch.commit();
  }

  Future<void> close({
    required String ticketId,
    required String actorId,
  }) async {
    final batch = _db.batch();
    final now = DateTime.now();
    batch.update(_tickets.doc(ticketId), {
      'status': TicketStatus.closed.wireValue,
      'closedAt': Timestamp.fromDate(now),
      'closedBy': actorId,
      'updatedAt': Timestamp.fromDate(now),
    });
    final activityRef = _activityFor(ticketId).doc();
    batch.set(
      activityRef,
      TicketActivity(
        id: activityRef.id,
        ticketId: ticketId,
        actorId: actorId,
        action: TicketActivityAction.closed,
        timestamp: now,
      ).toMap(),
    );
    await batch.commit();
  }
}
