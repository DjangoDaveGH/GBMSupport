import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hyport/core/auth/auth_providers.dart';
import 'package:hyport/core/models/enums.dart';
import 'package:hyport/core/theme/app_theme.dart';
import 'package:hyport/core/widgets/branded_loader.dart';
import 'package:hyport/core/widgets/status_chip.dart';
import 'package:hyport/features/auth/data/user_providers.dart';
import 'package:hyport/features/auth/domain/app_user.dart';
import 'package:hyport/features/tickets/data/ticket_providers.dart';
import 'package:hyport/features/tickets/domain/ticket.dart';
import 'package:hyport/features/tickets/presentation/ticket_list_screen.dart' show categoryIcon;
import 'package:intl/intl.dart';

/// Of tickets currently matching [bucket], what fraction were created in
/// the last 7 days vs. the 7 days before that. A real, consistently-applied
/// trend measure across every stat card here — not a fabricated number —
/// even though it's a simplification of "true" period-over-period change
/// (which would need daily status-history snapshots this app doesn't
/// store).
({int count, double delta}) _weeklyTrend(List<Ticket> bucket) {
  final now = DateTime.now();
  final weekAgo = now.subtract(const Duration(days: 7));
  final twoWeeksAgo = now.subtract(const Duration(days: 14));
  final thisWeek = bucket.where((t) => t.createdAt.isAfter(weekAgo)).length;
  final lastWeek = bucket.where((t) => t.createdAt.isAfter(twoWeeksAgo) && t.createdAt.isBefore(weekAgo)).length;
  final delta = lastWeek == 0 ? (thisWeek == 0 ? 0.0 : 100.0) : ((thisWeek - lastWeek) / lastWeek * 100);
  return (count: bucket.length, delta: delta);
}

const _priorityPalette = {
  TicketPriority.critical: StatusColors.critical,
  TicketPriority.high: StatusColors.high,
  TicketPriority.medium: StatusColors.medium,
  TicketPriority.low: StatusColors.low,
};

/// Phase 5 mockup screen 30. Desktop-width, support-side counterpart to
/// HomeScreen's `_SupportHome` — same `ticketListProvider` data, entirely
/// different presentation (trend chart + table instead of cards + list).
class DesktopDashboardScreen extends ConsumerWidget {
  const DesktopDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appUser = ref.watch(currentAppUserProvider).valueOrNull;
    if (appUser == null) return const BrandedLoaderCenter();

    final ticketsAsync = ref.watch(ticketListProvider((appUser, const TicketFilter())));
    final usersAsync = ref.watch(allUsersProvider);

    return ticketsAsync.when(
      loading: () => const BrandedLoaderCenter(),
      error: (e, _) => Center(child: Text('Could not load dashboard data: $e')),
      data: (tickets) {
        final usersById = <String, AppUser>{for (final u in usersAsync.valueOrNull ?? const <AppUser>[]) u.id: u};
        return _DashboardBody(tickets: tickets, usersById: usersById);
      },
    );
  }
}

class _DashboardBody extends StatelessWidget {
  final List<Ticket> tickets;
  final Map<String, AppUser> usersById;

  const _DashboardBody({required this.tickets, required this.usersById});

  List<DateTime> get _last7Days {
    final today = DateTime.now();
    return List.generate(7, (i) => DateTime(today.year, today.month, today.day).subtract(Duration(days: 6 - i)));
  }

  bool _isSameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final open = tickets.where((t) => t.status == TicketStatus.open).toList();
    final inProgress = tickets.where((t) => t.status == TicketStatus.inProgress).toList();
    final resolved = tickets.where((t) => {TicketStatus.resolved, TicketStatus.closed}.contains(t.status)).toList();

    final totalTrend = _weeklyTrend(tickets);
    final openTrend = _weeklyTrend(open);
    final inProgressTrend = _weeklyTrend(inProgress);
    final resolvedTrend = _weeklyTrend(resolved);

    final byPriority = <TicketPriority, int>{};
    for (final t in tickets) {
      byPriority[t.priority] = (byPriority[t.priority] ?? 0) + 1;
    }

    final recent = [...tickets]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _StatCard(label: 'Total Tickets', value: totalTrend.count, delta: totalTrend.delta)),
              const SizedBox(width: 16),
              Expanded(child: _StatCard(label: 'Open Tickets', value: openTrend.count, delta: openTrend.delta)),
              const SizedBox(width: 16),
              Expanded(child: _StatCard(label: 'In Progress', value: inProgressTrend.count, delta: inProgressTrend.delta)),
              const SizedBox(width: 16),
              Expanded(child: _StatCard(label: 'Resolved', value: resolvedTrend.count, delta: resolvedTrend.delta)),
            ],
          ),
          const SizedBox(height: 24),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 3,
                  child: _Panel(
                    title: 'Tickets Trend',
                    child: SizedBox(height: 260, child: _TrendChart(tickets: tickets, days: _last7Days, isSameDay: _isSameDay)),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: _Panel(
                    title: 'Tickets by Priority',
                    child: SizedBox(height: 260, child: _PriorityDonut(byPriority: byPriority, total: tickets.length)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _Panel(
            title: 'Recent Tickets',
            trailing: TextButton(onPressed: () => context.push('/tickets'), child: const Text('View All')),
            child: _RecentTicketsTable(tickets: recent.take(8).toList(), usersById: usersById),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final int value;
  final double delta;

  const _StatCard({required this.label, required this.value, required this.delta});

  @override
  Widget build(BuildContext context) {
    final rising = delta >= 0;
    final color = rising ? StatusColors.resolved : StatusColors.critical;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(NumberFormat.decimalPattern().format(value), style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 6),
          Text(label, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.black54)),
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(rising ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 14, color: color),
              Text('${delta.abs().toStringAsFixed(1)}%', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;

  const _Panel({required this.title, required this.child, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              ?trailing,
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _TrendChart extends StatelessWidget {
  final List<Ticket> tickets;
  final List<DateTime> days;
  final bool Function(DateTime, DateTime) isSameDay;

  const _TrendChart({required this.tickets, required this.days, required this.isSameDay});

  List<FlSpot> _seriesFor(TicketStatus status) => [
        for (var i = 0; i < days.length; i++)
          FlSpot(i.toDouble(), tickets.where((t) => isSameDay(t.createdAt, days[i]) && t.status == status).length.toDouble()),
      ];

  @override
  Widget build(BuildContext context) {
    final series = <(String, Color, List<FlSpot>)>[
      ('Open', StatusColors.open, _seriesFor(TicketStatus.open)),
      ('In Progress', StatusColors.inProgress, _seriesFor(TicketStatus.inProgress)),
      ('Resolved', StatusColors.resolved, _seriesFor(TicketStatus.resolved)),
      ('Closed', StatusColors.closed, _seriesFor(TicketStatus.closed)),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: LineChart(
            LineChartData(
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (v) => FlLine(color: const Color(0xFFEDF2EF), strokeWidth: 1),
              ),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    getTitlesWidget: (v, m) => Text(v.toInt().toString(), style: Theme.of(context).textTheme.bodySmall),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    // Without an explicit interval, fl_chart auto-computes a
                    // fractional one that scales with the chart's pixel
                    // width — on a wide desktop monitor this produces several
                    // tick values per integer day index, and since this
                    // widget maps ticks to days via v.toInt(), those
                    // fractional ticks collapse onto the same day, rendering
                    // each date's label 2-4x in a row. One tick per real data
                    // point (one per day) is always correct here.
                    interval: 1,
                    getTitlesWidget: (v, m) {
                      final idx = v.toInt();
                      if (idx < 0 || idx >= days.length) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(DateFormat.MMMd().format(days[idx]), style: Theme.of(context).textTheme.bodySmall),
                      );
                    },
                  ),
                ),
              ),
              borderData: FlBorderData(show: false),
              lineBarsData: [
                for (final s in series)
                  LineChartBarData(
                    spots: s.$3,
                    isCurved: true,
                    color: s.$2,
                    barWidth: 2.5,
                    dotData: const FlDotData(show: false),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 16,
          children: [
            for (final s in series)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 9, height: 9, decoration: BoxDecoration(color: s.$2, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Text(s.$1, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

class _PriorityDonut extends StatelessWidget {
  final Map<TicketPriority, int> byPriority;
  final int total;

  const _PriorityDonut({required this.byPriority, required this.total});

  @override
  Widget build(BuildContext context) {
    if (total == 0) return Center(child: Text('No ticket data yet.', style: Theme.of(context).textTheme.bodyMedium));
    return Column(
      children: [
        Expanded(
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 48,
                  sections: [
                    for (final p in TicketPriority.values)
                      if (byPriority[p] != null)
                        PieChartSectionData(
                          value: byPriority[p]!.toDouble(),
                          color: _priorityPalette[p],
                          showTitle: false,
                          radius: 30,
                        ),
                  ],
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$total', style: Theme.of(context).textTheme.headlineSmall),
                  Text('Total', style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 6,
          children: [
            for (final p in TicketPriority.values)
              if (byPriority[p] != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 9, height: 9, decoration: BoxDecoration(color: _priorityPalette[p], shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text(
                      '${p.label} ${(byPriority[p]! / total * 100).round()}%',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
          ],
        ),
      ],
    );
  }
}

class _RecentTicketsTable extends StatelessWidget {
  final List<Ticket> tickets;
  final Map<String, AppUser> usersById;

  const _RecentTicketsTable({required this.tickets, required this.usersById});

  @override
  Widget build(BuildContext context) {
    if (tickets.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(child: Text('No tickets yet.', style: Theme.of(context).textTheme.bodyMedium)),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 40,
        dataRowMinHeight: 52,
        dataRowMaxHeight: 52,
        columns: const [
          DataColumn(label: Text('ID')),
          DataColumn(label: Text('Title')),
          DataColumn(label: Text('Category')),
          DataColumn(label: Text('Priority')),
          DataColumn(label: Text('Assigned To')),
          DataColumn(label: Text('Status')),
          DataColumn(label: Text('Updated')),
        ],
        rows: tickets.map((t) {
          final assignee = t.assignedTo == null ? null : usersById[t.assignedTo];
          return DataRow(
            onSelectChanged: (_) => context.push('/tickets/${t.id}'),
            cells: [
              DataCell(Text(t.ticketReference, style: const TextStyle(fontWeight: FontWeight.w600))),
              DataCell(SizedBox(width: 220, child: Text(t.title, overflow: TextOverflow.ellipsis))),
              DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(categoryIcon(t.category), size: 16, color: AppTheme.accentBlue),
                const SizedBox(width: 6),
                Text(t.category.label),
              ])),
              DataCell(TicketPriorityChip(priority: t.priority)),
              DataCell(Text(assignee?.name ?? 'Unassigned')),
              DataCell(TicketStatusChip(status: t.status)),
              DataCell(Text(DateFormat.MMMd().add_jm().format(t.updatedAt))),
            ],
          );
        }).toList(),
      ),
    );
  }
}
