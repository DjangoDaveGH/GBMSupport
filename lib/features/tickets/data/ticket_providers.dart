import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hyport/core/models/enums.dart';
import 'package:hyport/core/services/firebase_providers.dart';
import 'package:hyport/features/auth/domain/app_user.dart';
import 'package:hyport/features/tickets/data/draft_ticket_repository.dart';
import 'package:hyport/features/tickets/data/ticket_repository.dart';
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

  const TicketFilter({
    this.statuses = const {},
    this.category,
    this.priorities = const {},
  });

  bool get isEmpty => statuses.isEmpty && category == null && priorities.isEmpty;

  static bool _setEquals<T>(Set<T> a, Set<T> b) =>
      a.length == b.length && a.every(b.contains);

  @override
  bool operator ==(Object other) =>
      other is TicketFilter &&
      _setEquals(other.statuses, statuses) &&
      other.category == category &&
      _setEquals(other.priorities, priorities);

  @override
  int get hashCode => Object.hash(
        Object.hashAllUnordered(statuses),
        category,
        Object.hashAllUnordered(priorities),
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

final ticketDetailProvider = StreamProvider.autoDispose.family<Ticket?, String>((ref, ticketId) {
  return ref.watch(ticketRepositoryProvider).watchTicket(ticketId);
});

final ticketActivityProvider =
    StreamProvider.autoDispose.family<List<TicketActivity>, String>((ref, ticketId) {
  return ref.watch(ticketRepositoryProvider).watchActivity(ticketId);
});
