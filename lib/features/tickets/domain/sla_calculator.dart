import 'package:hyport/features/config/domain/sla_policy.dart';
import 'package:hyport/features/tickets/domain/ticket.dart';

/// Shared, real-data SLA math used by both the Admin Dashboard and
/// Analytics screens, so "Overdue" and "SLA Compliance" always mean the
/// same thing in both places.
class SlaCalculator {
  SlaCalculator._();

  static bool isOverdue(Ticket ticket, SlaPolicy policy) {
    if (!ticket.status.isOpenState) return false;
    final targetHours = policy.targetHoursFor(ticket.priority);
    return DateTime.now().difference(ticket.createdAt).inHours > targetHours;
  }

  static int countOverdue(List<Ticket> tickets, SlaPolicy policy) =>
      tickets.where((t) => isOverdue(t, policy)).length;

  static bool metSla(Ticket ticket, SlaPolicy policy) {
    final resolvedAt = ticket.resolvedAt ?? ticket.closedAt;
    if (resolvedAt == null) return false;
    final targetHours = policy.targetHoursFor(ticket.priority);
    return resolvedAt.difference(ticket.createdAt).inHours <= targetHours;
  }

  /// Percentage (0-100) of resolved/closed tickets that met their SLA
  /// target. Returns null when there's no resolved data yet to judge.
  static double? complianceRate(List<Ticket> tickets, SlaPolicy policy) {
    final resolved = tickets.where((t) => t.resolvedAt != null || t.closedAt != null).toList();
    if (resolved.isEmpty) return null;
    final met = resolved.where((t) => metSla(t, policy)).length;
    return met / resolved.length * 100;
  }
}
