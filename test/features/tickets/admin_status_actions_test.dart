import 'package:flutter_test/flutter_test.dart';
import 'package:hyport/core/models/enums.dart';
import 'package:hyport/features/auth/domain/app_user.dart';
import 'package:hyport/features/tickets/domain/ticket.dart';
import 'package:hyport/features/tickets/presentation/admin_status_actions.dart';

AppUser _user(String role) =>
    AppUser.fromMap('u1', {'name': 'A', 'email': 'a@x', 'role': role});

Ticket _ticket(TicketStatus s) => Ticket.fromMap('t1', {
  'ticketReference': 'PFMSD-2026-000001',
  'status': s.wireValue,
});

void main() {
  final admin = _user('pfm_management');
  const A = AdminStatusAction.values;

  test('admin gets Resolve + Close on active tickets', () {
    for (final s in [
      TicketStatus.open,
      TicketStatus.assigned,
      TicketStatus.inProgress,
      TicketStatus.escalated,
      TicketStatus.reopened,
    ]) {
      expect(adminStatusActionsFor(admin, _ticket(s)), [
        AdminStatusAction.resolve,
        AdminStatusAction.close,
      ], reason: '$s');
    }
  });

  test('admin gets Close + Reopen on resolved, only Reopen on closed', () {
    expect(adminStatusActionsFor(admin, _ticket(TicketStatus.resolved)), [
      AdminStatusAction.close,
      AdminStatusAction.reopen,
    ]);
    expect(adminStatusActionsFor(admin, _ticket(TicketStatus.closed)), [
      AdminStatusAction.reopen,
    ]);
    expect(A.length, 3);
  });

  test('no admin buttons for other roles', () {
    for (final role in ['support_coordinator', 'functional_lead', 'mda_user']) {
      expect(
        adminStatusActionsFor(_user(role), _ticket(TicketStatus.open)),
        isEmpty,
        reason: role,
      );
    }
  });
}
