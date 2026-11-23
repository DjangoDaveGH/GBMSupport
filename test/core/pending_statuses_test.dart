import 'package:flutter_test/flutter_test.dart';
import 'package:hyport/core/models/enums.dart';
import 'package:hyport/features/tickets/presentation/ticket_list_screen.dart';

void main() {
  test('Pending is Assigned, Escalated and Reopened only', () {
    expect(pendingTicketStatuses, {
      TicketStatus.assigned,
      TicketStatus.escalated,
      TicketStatus.reopened,
    });
  });

  test('mobile chips use the same Pending and do not overlap', () {
    expect(statusesForTab(StatusTab.pending), pendingTicketStatuses);
    final seen = <TicketStatus>{};
    for (final tab in StatusTab.values.where((t) => t != StatusTab.all)) {
      for (final s in statusesForTab(tab)) {
        expect(seen.add(s), isTrue, reason: '$s is in two chips');
      }
    }
  });
}
