import 'package:hyport/features/dashboard/domain/report_section_data.dart';
import 'package:hyport/features/tickets/domain/ticket.dart';
import 'package:intl/intl.dart';

/// CSV builders for admin report downloads. Pure functions so they can be
/// unit-tested without Firebase or Flutter.
final _stamp = DateFormat('yyyy-MM-dd HH:mm');

/// RFC 4180 quoting: wrap in quotes when the value contains a comma, quote
/// or line break, and double any embedded quotes.
String csvEscape(String value) {
  final needsQuotes =
      value.contains(',') ||
      value.contains('"') ||
      value.contains('\n') ||
      value.contains('\r');
  if (!needsQuotes) return value;
  return '"${value.replaceAll('"', '""')}"';
}

String csvFromRows(List<List<String>> rows) =>
    rows.map((r) => r.map(csvEscape).join(',')).join('\r\n');

/// One CSV that mirrors a report's on-screen sections: each section title,
/// then its label/value rows, then a blank line before the next section.
List<List<String>> reportSectionsToRows(
  String reportLabel,
  String rangeLabel,
  List<ReportSectionData> sections,
) {
  final rows = <List<String>>[
    [reportLabel],
    ['Date range', rangeLabel],
    ['Generated', _stamp.format(DateTime.now())],
    [],
  ];
  for (final section in sections) {
    rows.add([section.title]);
    for (final (label, value) in section.rows) {
      rows.add([label, value]);
    }
    rows.add([]);
  }
  return rows;
}

/// Raw ticket-level export for the filtered set — one row per ticket.
List<List<String>> ticketsToRows(
  List<Ticket> tickets,
  Map<String, String> userNames,
) {
  final rows = <List<String>>[
    [
      'Reference',
      'System',
      'Category',
      'Title',
      'Status',
      'Priority',
      'Created',
      'Resolved',
      'Assignee',
    ],
  ];
  for (final t in tickets) {
    rows.add([
      t.ticketReference,
      t.system,
      t.category.label,
      t.title,
      t.status.label,
      t.priority.label,
      _stamp.format(t.createdAt),
      t.resolvedAt == null ? '' : _stamp.format(t.resolvedAt!),
      t.assignedTo == null
          ? 'Unassigned'
          : (userNames[t.assignedTo] ?? t.assignedToName ?? t.assignedTo!),
    ]);
  }
  return rows;
}
