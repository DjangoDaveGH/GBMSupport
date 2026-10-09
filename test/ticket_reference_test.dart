import 'package:flutter_test/flutter_test.dart';
import 'package:hyport/features/tickets/data/ticket_reference.dart';

void main() {
  group('ticket reference namespaces', () {
    test('keeps the existing GBMS format and counter', () {
      expect(ticketCounterDocumentId('gbms', 2026), 'tickets_2026');
      expect(
        formatTicketReference(system: 'gbms', year: 2026, sequence: 1),
        'PFMSD-2026-000001',
      );
    });

    test('GHANEPS and GIFMIS share the PPA sequence', () {
      expect(ticketCounterDocumentId('ghaneps', 2026), 'tickets_ppa_2026');
      expect(ticketCounterDocumentId('gifmis', 2026), 'tickets_ppa_2026');
      expect(
        formatTicketReference(system: 'ghaneps', year: 2026, sequence: 1),
        'PPA-2026-00001',
      );
      expect(
        formatTicketReference(system: 'gifmis', year: 2026, sequence: 27),
        'PPA-2026-00027',
      );
    });

    test('continues beyond the minimum five-digit PPA width', () {
      expect(
        formatTicketReference(system: 'gifmis', year: 2026, sequence: 100000),
        'PPA-2026-100000',
      );
    });
  });
}
