import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hyport/core/auth/auth_providers.dart';
import 'package:hyport/core/models/enums.dart';
import 'package:hyport/core/theme/app_theme.dart';
import 'package:hyport/core/widgets/branded_loader.dart';
import 'package:hyport/features/auth/data/user_providers.dart';
import 'package:hyport/features/auth/domain/app_user.dart';
import 'package:hyport/features/config/data/sla_providers.dart';
import 'package:hyport/features/config/domain/sla_policy.dart';
import 'package:hyport/features/dashboard/data/report_providers.dart';
import 'package:hyport/features/tickets/data/ticket_providers.dart';
import 'package:hyport/features/tickets/domain/sla_calculator.dart';
import 'package:hyport/features/tickets/domain/ticket.dart';
import 'package:intl/intl.dart';

/// Renders one of the five report types from real live data — see
/// ReportsScreen for why there's no PDF export here yet.
class ReportDetailScreen extends ConsumerStatefulWidget {
  final String reportType;
  final String reportLabel;

  const ReportDetailScreen({super.key, required this.reportType, required this.reportLabel});

  @override
  ConsumerState<ReportDetailScreen> createState() => _ReportDetailScreenState();
}

class _ReportDetailScreenState extends ConsumerState<ReportDetailScreen> {
  @override
  void initState() {
    super.initState();
    final uid = ref.read(currentAppUserProvider).valueOrNull?.id;
    if (uid != null) {
      ref.read(reportViewRepositoryProvider).logView(
            viewedBy: uid,
            reportType: widget.reportType,
            reportLabel: widget.reportLabel,
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    final appUser = ref.watch(currentAppUserProvider).valueOrNull;
    if (appUser == null) return const Scaffold(body: BrandedLoaderCenter());

    final ticketsAsync = ref.watch(ticketListProvider((appUser, const TicketFilter())));
    final usersAsync = ref.watch(allUsersProvider);
    final slaPolicy = ref.watch(slaPolicyProvider).valueOrNull ?? const SlaPolicy();

    return Scaffold(
      appBar: AppBar(title: Text(widget.reportLabel)),
      body: ticketsAsync.when(
        loading: () => const BrandedLoaderCenter(),
        error: (e, _) => Center(child: Text('Could not load report: $e')),
        data: (tickets) => switch (widget.reportType) {
          'sla' => _SlaReport(tickets: tickets, slaPolicy: slaPolicy),
          'officer_performance' => _OfficerPerformanceReport(tickets: tickets, users: usersAsync.valueOrNull ?? const []),
          'category_breakdown' => _CategoryBreakdownReport(tickets: tickets),
          'monthly_trend' => _MonthlyTrendReport(tickets: tickets),
          _ => _SummaryReport(tickets: tickets),
        },
      ),
    );
  }
}

class _ReportSection extends StatelessWidget {
  final String title;
  final List<Widget> rows;

  const _ReportSection({required this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.md),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(children: rows),
          ),
        ],
      ),
    );
  }
}

class _ReportRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _ReportRow({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Theme.of(context).colorScheme.outlineVariant))),
      child: Row(
        children: [
          Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyMedium)),
          Text(
            value,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(color: valueColor),
          ),
        ],
      ),
    );
  }
}

class _SummaryReport extends StatelessWidget {
  final List<Ticket> tickets;

  const _SummaryReport({required this.tickets});

  @override
  Widget build(BuildContext context) {
    final byStatus = <TicketStatus, int>{};
    final byPriority = <TicketPriority, int>{};
    for (final t in tickets) {
      byStatus[t.status] = (byStatus[t.status] ?? 0) + 1;
      byPriority[t.priority] = (byPriority[t.priority] ?? 0) + 1;
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _ReportSection(title: 'Overview', rows: [
          _ReportRow(label: 'Total Tickets', value: '${tickets.length}'),
        ]),
        _ReportSection(
          title: 'By Status',
          rows: TicketStatus.values.map((s) => _ReportRow(label: s.label, value: '${byStatus[s] ?? 0}')).toList(),
        ),
        _ReportSection(
          title: 'By Priority',
          rows: TicketPriority.values.map((p) => _ReportRow(label: p.label, value: '${byPriority[p] ?? 0}')).toList(),
        ),
      ],
    );
  }
}

class _SlaReport extends StatelessWidget {
  final List<Ticket> tickets;
  final SlaPolicy slaPolicy;

  const _SlaReport({required this.tickets, required this.slaPolicy});

  @override
  Widget build(BuildContext context) {
    final overall = SlaCalculator.complianceRate(tickets, slaPolicy);
    final overdue = SlaCalculator.countOverdue(tickets, slaPolicy);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _ReportSection(title: 'Overall', rows: [
          _ReportRow(
            label: 'SLA Compliance',
            value: overall == null ? '—' : '${overall.round()}%',
            valueColor: AppTheme.accentBlue,
          ),
          _ReportRow(label: 'Currently Overdue', value: '$overdue', valueColor: StatusColors.critical),
        ]),
        _ReportSection(
          title: 'Target Resolution Windows',
          rows: TicketPriority.values
              .map((p) => _ReportRow(label: p.label, value: '${slaPolicy.targetHoursFor(p)}h'))
              .toList(),
        ),
        _ReportSection(
          title: 'Compliance by Priority',
          rows: TicketPriority.values.map((p) {
            final subset = tickets.where((t) => t.priority == p).toList();
            final rate = SlaCalculator.complianceRate(subset, slaPolicy);
            return _ReportRow(label: p.label, value: rate == null ? '—' : '${rate.round()}%');
          }).toList(),
        ),
      ],
    );
  }
}

class _OfficerPerformanceReport extends StatelessWidget {
  final List<Ticket> tickets;
  final List<AppUser> users;

  const _OfficerPerformanceReport({required this.tickets, required this.users});

  @override
  Widget build(BuildContext context) {
    final officers = users.where((u) => u.role.hasBackOfficeAccess || u.role == UserRole.vendorSupport).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _ReportSection(
          title: 'Resolved by Officer',
          rows: officers.map((o) {
            final resolved = tickets.where((t) => t.assignedTo == o.id && t.resolvedAt != null).toList();
            final avgHours = resolved.isEmpty
                ? null
                : resolved.map((t) => t.resolvedAt!.difference(t.createdAt).inMinutes / 60).reduce((a, b) => a + b) /
                    resolved.length;
            return _ReportRow(
              label: o.name,
              value: avgHours == null ? '${resolved.length} resolved' : '${resolved.length} resolved · ${avgHours.toStringAsFixed(1)}h avg',
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _CategoryBreakdownReport extends StatelessWidget {
  final List<Ticket> tickets;

  const _CategoryBreakdownReport({required this.tickets});

  @override
  Widget build(BuildContext context) {
    final byCategory = <TicketCategory, int>{};
    for (final t in tickets) {
      byCategory[t.category] = (byCategory[t.category] ?? 0) + 1;
    }
    final entries = byCategory.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _ReportSection(
          title: 'Tickets by Category',
          rows: entries
              .map((e) => _ReportRow(
                    label: e.key.label,
                    value: '${e.value} (${(e.value / tickets.length * 100).round()}%)',
                  ))
              .toList(),
        ),
      ],
    );
  }
}

class _MonthlyTrendReport extends StatelessWidget {
  final List<Ticket> tickets;

  const _MonthlyTrendReport({required this.tickets});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final months = List.generate(6, (i) => DateTime(now.year, now.month - (5 - i)));
    final counts = {
      for (final m in months) m: tickets.where((t) => t.createdAt.year == m.year && t.createdAt.month == m.month).length,
    };

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _ReportSection(
          title: 'Tickets Created, Last 6 Months',
          rows: counts.entries.map((e) => _ReportRow(label: DateFormat.yMMM().format(e.key), value: '${e.value}')).toList(),
        ),
      ],
    );
  }
}
