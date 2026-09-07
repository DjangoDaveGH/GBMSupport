import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hyport/core/models/enums.dart';
import 'package:hyport/core/services/firebase_providers.dart';
import 'package:hyport/features/auth/domain/app_user.dart';
import 'package:hyport/features/config/domain/sla_policy.dart';
import 'package:hyport/features/tickets/data/draft_ticket_repository.dart';
import 'package:hyport/features/tickets/data/ticket_repository.dart';
import 'package:hyport/features/tickets/domain/sla_calculator.dart';
import 'package:hyport/features/tickets/domain/ticket.dart';
import 'package:hyport/features/tickets/domain/ticket_activity.dart';

final ticketRepositoryProvider = Provider<TicketRepository>((ref) {
  return TicketRepository(ref.watch(firestoreProvider));
});

final draftTicketRepositoryProvider = Provider<DraftTicketRepository>((ref) {
  return DraftTicketRepository();
});

class TicketFilter {
  final Set<TicketStatus> statuses;
  final TicketCategory? category;
  final Set<TicketPriority> priorities;

  /// Client-side-only filters (see [matchesClientSide]):
  /// [TicketRepository.watchTickets] doesn't apply these — the queue and
  /// analytics screens fetch the full scoped set (unbounded) and narrow it in
  /// memory, so these never touch the Firestore query or its indexes.
  final String? institutionId;
  final InstitutionType? institutionType;
  final DateTime? createdAfter;
  final DateTime? createdBefore;
  final bool overdueOnly;

  const TicketFilter({
    this.statuses = const {},
    this.category,
    this.priorities = const {},
    this.institutionId,
    this.institutionType,
    this.createdAfter,
    this.createdBefore,
    this.overdueOnly = false,
  });

  bool get isEmpty =>
      statuses.isEmpty &&
      category == null &&
      priorities.isEmpty &&
      institutionId == null &&
      institutionType == null &&
      createdAfter == null &&
      createdBefore == null &&
      !overdueOnly;

  /// True when [t] passes the filters that aren't part of the Firestore query:
  /// institution, created-date range (whole-day inclusive at both ends), and
  /// SLA-overdue. [policy] is only consulted when [overdueOnly] is set, and
  /// [institutionTypes] (institutionId -> MDA/MMDA, from the institution list)
  /// only when [institutionType] is set — pass each whenever that filter is a
  /// possibility.
  bool matchesClientSide(Ticket t, {SlaPolicy? policy, Map<String, InstitutionType>? institutionTypes}) {
    if (institutionId != null && t.institutionId != institutionId) return false;
    if (institutionType != null && institutionTypes?[t.institutionId] != institutionType) return false;
    if (createdAfter != null) {
      final start = DateTime(createdAfter!.year, createdAfter!.month, createdAfter!.day);
      if (t.createdAt.isBefore(start)) return false;
    }
    if (createdBefore != null) {
      final end = DateTime(createdBefore!.year, createdBefore!.month, createdBefore!.day, 23, 59, 59, 999);
      if (t.createdAt.isAfter(end)) return false;
    }
    if (overdueOnly && !(policy != null && SlaCalculator.isOverdue(t, policy))) return false;
    return true;
  }

  static bool _setEquals<T>(Set<T> a, Set<T> b) =>
      a.length == b.length && a.every(b.contains);

  @override
  bool operator ==(Object other) =>
      other is TicketFilter &&
      _setEquals(other.statuses, statuses) &&
      other.category == category &&
      _setEquals(other.priorities, priorities) &&
      other.institutionId == institutionId &&
      other.institutionType == institutionType &&
      other.createdAfter == createdAfter &&
      other.createdBefore == createdBefore &&
      other.overdueOnly == overdueOnly;

  @override
  int get hashCode => Object.hash(
        Object.hashAllUnordered(statuses),
        category,
        Object.hashAllUnordered(priorities),
        institutionId,
        institutionType,
        createdAfter,
        createdBefore,
        overdueOnly,
      );
}

// autoDispose is load-bearing here, not just tidiness: without it, a
// StreamProvider.family instance keyed only by ticketId (not by viewer)
// stays cached for the app's entire lifetime once created. If User A opens
// a ticket, then signs out, the still-alive Firestore listener gets a
// permission-denied the moment auth clears — and Firestore listeners don't
// recover from that on their own. If User B then signs in and opens the
// *same* ticketId, Riverpod hands them that already-dead, already-errored
// stream instead of creating a fresh one under B's auth. Found exactly this
// bug testing role handoffs (Coordinator -> Functional Lead) in the same
// browser session; see DECISIONS.md. autoDispose tears down the provider
// (and its listener) once nothing's watching it, so the next screen that
// watches a given ticketId always gets a brand-new, correctly-authenticated
// listener.
final ticketListProvider =
    StreamProvider.autoDispose.family<List<Ticket>, (AppUser, TicketFilter)>((ref, args) {
  final (viewer, filter) = args;
  return ref.watch(ticketRepositoryProvider).watchTickets(
        viewer,
        statuses: filter.statuses,
        category: filter.category,
        priorities: filter.priorities,
      );
});

/// Unbounded counterpart to [ticketListProvider] — same scoping/filtering,
/// but fetches every matching ticket instead of stopping at [ticketPageSize].
/// Dashboards, Analytics, Reports, and the Audit Log all need a true count
/// over the full dataset, not just the most recent page, so they watch this
/// instead of ticketListProvider.
final ticketAnalyticsProvider =
    StreamProvider.autoDispose.family<List<Ticket>, (AppUser, TicketFilter)>((ref, args) {
  final (viewer, filter) = args;
  return ref.watch(ticketRepositoryProvider).watchTickets(
        viewer,
        statuses: filter.statuses,
        category: filter.category,
        priorities: filter.priorities,
        limit: null,
      );
});

final ticketDetailProvider = StreamProvider.autoDispose.family<Ticket?, String>((ref, ticketId) {
  return ref.watch(ticketRepositoryProvider).watchTicket(ticketId);
});

final ticketActivityProvider =
    StreamProvider.autoDispose.family<List<TicketActivity>, String>((ref, ticketId) {
  return ref.watch(ticketRepositoryProvider).watchActivity(ticketId);
});

/// uid -> last time that participant viewed this ticket's chat. Drives the
/// Delivered/Read ticks in TicketChatScreen.
final chatReceiptsProvider =
    StreamProvider.autoDispose.family<Map<String, DateTime>, String>((ref, ticketId) {
  return ref.watch(ticketRepositoryProvider).watchChatReceipts(ticketId);
});
