import 'package:hyport/core/models/enums.dart';
import 'package:hyport/features/auth/domain/app_user.dart';
import 'package:hyport/features/config/domain/sla_policy.dart';
import 'package:hyport/features/tickets/domain/sla_calculator.dart';
import 'package:hyport/features/tickets/domain/ticket.dart';
import 'package:intl/intl.dart';

/// One labelled table (title + label/value rows) within a report — the
/// single source of truth for a report's content, shared between
/// ReportDetailScreen's on-screen widgets and the PDF export builder so
/// the two never drift apart.
class ReportSectionData {
  final String title;
  final List<(String label, String value)> rows;

  const ReportSectionData(this.title, this.rows);
}

List<ReportSectionData> summaryReportData(List<Ticket> tickets) {
  final byStatus = <TicketStatus, int>{};
  final byPriority = <TicketPriority, int>{};
  for (final t in tickets) {
    byStatus[t.status] = (byStatus[t.status] ?? 0) + 1;
    byPriority[t.priority] = (byPriority[t.priority] ?? 0) + 1;
  }

  return [
    ReportSectionData('Overview', [('Total Tickets', '${tickets.length}')]),
    ReportSectionData('By Status', TicketStatus.values.map((s) => (s.label, '${byStatus[s] ?? 0}')).toList()),
    ReportSectionData('By Priority', TicketPriority.values.map((p) => (p.label, '${byPriority[p] ?? 0}')).toList()),
  ];
}

List<ReportSectionData> slaReportData(List<Ticket> tickets, SlaPolicy slaPolicy) {
  final overall = SlaCalculator.complianceRate(tickets, slaPolicy);
  final overdue = SlaCalculator.countOverdue(tickets, slaPolicy);

  return [
    ReportSectionData('Overall', [
      ('SLA Compliance', overall == null ? '—' : '${overall.round()}%'),
      ('Currently Overdue', '$overdue'),
    ]),
    ReportSectionData(
      'Target Resolution Windows',
      TicketPriority.values.map((p) => (p.label, '${slaPolicy.targetHoursFor(p)}h')).toList(),
    ),
    ReportSectionData(
      'Compliance by Priority',
      TicketPriority.values.map((p) {
        final subset = tickets.where((t) => t.priority == p).toList();
        final rate = SlaCalculator.complianceRate(subset, slaPolicy);
        return (p.label, rate == null ? '—' : '${rate.round()}%');
      }).toList(),
    ),
  ];
}

List<ReportSectionData> officerPerformanceReportData(List<Ticket> tickets, List<AppUser> users) {
  final officers = users.where((u) => u.role.hasBackOfficeAccess || u.role == UserRole.vendorSupport).toList();

  return [
    ReportSectionData(
      'Resolved by Officer',
      officers.map((o) {
        final resolved = tickets.where((t) => t.assignedTo == o.id && t.resolvedAt != null).toList();
        final avgHours = resolved.isEmpty
            ? null
            : resolved.map((t) => t.resolvedAt!.difference(t.createdAt).inMinutes / 60).reduce((a, b) => a + b) /
                resolved.length;
        return (
          o.name,
          avgHours == null ? '${resolved.length} resolved' : '${resolved.length} resolved · ${avgHours.toStringAsFixed(1)}h avg',
        );
      }).toList(),
    ),
  ];
}

List<ReportSectionData> categoryBreakdownReportData(List<Ticket> tickets) {
  final byCategory = <TicketCategory, int>{};
  for (final t in tickets) {
    byCategory[t.category] = (byCategory[t.category] ?? 0) + 1;
  }
  final entries = byCategory.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

  return [
    ReportSectionData(
      'Tickets by Category',
      entries.map((e) => (e.key.label, '${e.value} (${(e.value / tickets.length * 100).round()}%)')).toList(),
    ),
  ];
}

List<ReportSectionData> monthlyTrendReportData(List<Ticket> tickets) {
  final now = DateTime.now();
  final months = List.generate(6, (i) => DateTime(now.year, now.month - (5 - i)));
  final counts = {
    for (final m in months) m: tickets.where((t) => t.createdAt.year == m.year && t.createdAt.month == m.month).length,
  };

  return [
    ReportSectionData(
      'Tickets Created, Last 6 Months',
      counts.entries.map((e) => (DateFormat.yMMM().format(e.key), '${e.value}')).toList(),
    ),
  ];
}

List<ReportSectionData> reportSectionDataFor(
  String reportType,
  List<Ticket> tickets,
  List<AppUser> users,
  SlaPolicy slaPolicy,
) =>
    switch (reportType) {
      'sla' => slaReportData(tickets, slaPolicy),
      'officer_performance' => officerPerformanceReportData(tickets, users),
      'category_breakdown' => categoryBreakdownReportData(tickets),
      'monthly_trend' => monthlyTrendReportData(tickets),
      _ => summaryReportData(tickets),
    };
