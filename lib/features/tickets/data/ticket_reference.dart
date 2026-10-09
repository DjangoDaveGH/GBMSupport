/// Reference namespace and Firestore counter used for ticket creation.
///
/// GBMS retains its established PFMSD format and sequence. GHANEPS and
/// GIFMIS share one PPA sequence so their references are unique across the
/// combined PPA support queue.
String ticketCounterDocumentId(String system, int year) =>
    system == 'ghaneps' || system == 'gifmis'
    ? 'tickets_ppa_$year'
    : 'tickets_$year';

String formatTicketReference({
  required String system,
  required int year,
  required int sequence,
}) {
  if (sequence < 1) {
    throw ArgumentError.value(sequence, 'sequence', 'Must be positive.');
  }
  final isPpa = system == 'ghaneps' || system == 'gifmis';
  final prefix = isPpa ? 'PPA' : 'PFMSD';
  final digits = isPpa ? 5 : 6;
  return '$prefix-$year-${sequence.toString().padLeft(digits, '0')}';
}
