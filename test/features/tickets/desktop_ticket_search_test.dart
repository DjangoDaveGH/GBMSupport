import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyport/core/auth/auth_providers.dart';
import 'package:hyport/features/auth/data/institution_providers.dart';
import 'package:hyport/features/auth/data/user_providers.dart';
import 'package:hyport/features/auth/domain/app_user.dart';
import 'package:hyport/features/config/data/sla_providers.dart';
import 'package:hyport/features/config/domain/sla_policy.dart';
import 'package:hyport/features/tickets/data/ticket_providers.dart';
import 'package:hyport/features/tickets/domain/ticket.dart';
import 'package:hyport/features/tickets/presentation/desktop_ticket_list_screen.dart';

AppUser _coordinator() => AppUser.fromMap('c1', {
  'name': 'Coord',
  'email': 'c@x',
  'role': 'support_coordinator',
  'systems': ['ghaneps', 'gifmis'],
});

Ticket _t(String id, String ref, String title, String system) =>
    Ticket.fromMap(id, {
      'ticketReference': ref,
      'title': title,
      'system': system,
      'status': 'open',
    });

void main() {
  group('ticketMatchesSearch', () {
    final t = Ticket.fromMap('x', {
      'ticketReference': 'PPA-2026-00007',
      'title': 'Login failure',
      'description': 'Supplier portal shows error 503 at checkout',
      'system': 'ghaneps',
      'status': 'assigned',
      'priority': 'high',
      'requesterEmail': 'kofi@supplier.com',
      'requesterPhone': '0244123456',
      'assignedToName': 'Lisa Frema Boadu',
    });
    final requester = AppUser.fromMap('r', {
      'name': 'Kofi Mensah',
      'email': 'kofi@supplier.com',
      'role': 'mda_user',
    });

    for (final q in [
      '',
      'ppa-2026-00007',
      'login',
      'error 503',
      'GHANEPS',
      'assigned',
      'high',
      'lisa',
      'kofi mensah',
      'mensah kofi',
      '0244123456',
      'supplier.com',
      'ministry of finance',
    ]) {
      test('matches "$q"', () {
        expect(
          ticketMatchesSearch(
            t,
            q,
            requester: requester,
            institutionName: 'Ministry of Finance',
          ),
          isTrue,
        );
      });
    }

    test('every word must match', () {
      expect(ticketMatchesSearch(t, 'login gifmis'), isFalse);
      expect(ticketMatchesSearch(t, 'nothing-like-this'), isFalse);
    });
  });

  testWidgets('coordinator desktop search filters and keeps focus', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final users = StreamController<AppUser?>();
    final tickets = [
      _t('a', 'PPA-2026-00001', 'Cannot log in to GHANEPS', 'ghaneps'),
      _t('b', 'PPA-2026-00002', 'Payment voucher stuck', 'gifmis'),
    ];
    final container = ProviderContainer(
      overrides: [
        currentAppUserProvider.overrideWith((ref) => users.stream),
        ticketAnalyticsProvider.overrideWith(
          (ref, args) => Stream.value(tickets),
        ),
        allUsersProvider.overrideWith((ref) => Stream.value(const [])),
        institutionListProvider.overrideWith((ref) => Stream.value(const [])),
        slaPolicyProvider.overrideWith(
          (ref) => Stream.value(const SlaPolicy()),
        ),
      ],
    );
    addTearDown(container.dispose);
    users.add(_coordinator());

    final filter = TicketFilter(systems: {'ghaneps', 'gifmis'});
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(body: DesktopTicketListScreen(initialFilter: filter)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Payment voucher stuck'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'VOUCHER gifmis');
    await tester.pump();
    // Presence heartbeat re-emits the user's profile every 2 minutes.
    users.add(_coordinator());
    await tester.pumpAndSettle();

    expect(find.text('Payment voucher stuck'), findsOneWidget);
    expect(find.text('Cannot log in to GHANEPS'), findsNothing);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'VOUCHER gifmis');
  });
}
