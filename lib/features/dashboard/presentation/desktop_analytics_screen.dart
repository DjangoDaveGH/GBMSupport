import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hyport/core/auth/auth_providers.dart';
import 'package:hyport/core/models/enums.dart';
import 'package:hyport/core/theme/app_theme.dart';
import 'package:hyport/core/widgets/branded_loader.dart';
import 'package:hyport/core/widgets/empty_state.dart';
import 'package:hyport/features/tickets/data/ticket_providers.dart';
import 'package:hyport/features/tickets/domain/ticket.dart';
import 'package:intl/intl.dart';

const _categoryPalette = [
  AppTheme.navy,
  AppTheme.accentBlue,
  AppTheme.gold,
  StatusColors.resolved,
  AppTheme.plum,
  StatusColors.critical,
  StatusColors.medium,
];

/// Phase 5 mockup screen 35 — same ticketListProvider data as the mobile
/// Analytics screen, laid out with a category donut + a Received-vs-
/// Resolved-by-weekday bar chart side by side plus a resolution-time trend
/// line, matching the enterprise mockup's density.
class DesktopAnalyticsScreen extends ConsumerWidget {
  const DesktopAnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appUser = ref.watch(currentAppUserProvider).valueOrNull;
    if (appUser == null) return const BrandedLoaderCenter();

    final ticketsAsync = ref.watch(ticketListProvider((appUser, const TicketFilter())));

    return ticketsAsync.when(
      loading: () => const BrandedLoaderCenter(),
      error: (e, _) => Center(child: Text('Could not load analytics: $e')),
      data: (tickets) => _Body(tickets: tickets),
    );
  }
}

class _Body extends StatelessWidget {
  final List<Ticket> tickets;

  const _Body({required this.tickets});

  List<DateTime> get _last7Days {
    final today = DateTime.now();
    return List.generate(7, (i) => DateTime(today.year, today.month, today.day).subtract(Duration(days: 6 - i)));
  }

  bool _isSameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final resolved = tickets.where((t) => t.resolvedAt != null).toList();
    final responded = tickets.where((t) => t.firstRespondedAt != null).toList();

    final avgResolutionHours = resolved.isEmpty
        ? 0.0
        : resolved.map((t) => t.resolvedAt!.difference(t.createdAt).inMinutes / 60).reduce((a, b) => a + b) / resolved.length;
    final avgFirstResponseMinutes = responded.isEmpty
        ? 0.0
        : responded.map((t) => t.firstRespondedAt!.difference(t.createdAt).inMinutes.toDouble()).reduce((a, b) => a + b) / responded.length;

    final byCategory = <TicketCategory, int>{};
    for (final t in tickets) {
      byCategory[t.category] = (byCategory[t.category] ?? 0) + 1;
    }

    final days = _last7Days;
    final receivedByDay = [for (final d in days) tickets.where((t) => _isSameDay(t.createdAt, d)).length];
    final resolvedByDay = [for (final d in days) resolved.where((t) => _isSameDay(t.resolvedAt!, d)).length];
    final resolutionTrend = [
      for (final d in days)
        () {
          final onDay = resolved.where((t) => _isSameDay(t.resolvedAt!, d)).toList();
          if (onDay.isEmpty) return 0.0;
          return onDay.map((t) => t.resolvedAt!.difference(t.createdAt).inMinutes / 60).reduce((a, b) => a + b) / onDay.length;
        }(),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _MetricCard(label: 'Tickets Received', value: '${tickets.length}')),
              const SizedBox(width: 16),
              Expanded(child: _MetricCard(label: 'Tickets Resolved', value: '${resolved.length}')),
              const SizedBox(width: 16),
              Expanded(child: _MetricCard(label: 'Avg. Resolution Time', value: '${avgResolutionHours.toStringAsFixed(1)} hrs')),
              const SizedBox(width: 16),
              Expanded(
                child: _MetricCard(
                  label: 'First Response Time',
                  value: avgFirstResponseMinutes >= 60 ? '${(avgFirstResponseMinutes / 60).toStringAsFixed(1)} hrs' : '${avgFirstResponseMinutes.round()}m',
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _Panel(
                    title: 'Tickets by Category',
                    child: SizedBox(height: 240, child: _CategoryDonut(byCategory: byCategory, total: tickets.length)),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _Panel(
                    title: 'Tickets by Day',
                    child: SizedBox(height: 240, child: _ByDayBarChart(days: days, received: receivedByDay, resolved: resolvedByDay)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _Panel(
            title: 'Resolution Time Trend (hrs)',
            child: SizedBox(height: 220, child: _ResolutionTrendChart(days: days, values: resolutionTrend)),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;

  const _MetricCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
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
          Text(value, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 6),
          Text(label, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.black54)),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  final String title;
  final Widget child;

  const _Panel({required this.title, required this.child});

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
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _CategoryDonut extends StatelessWidget {
  final Map<TicketCategory, int> byCategory;
  final int total;

  const _CategoryDonut({required this.byCategory, required this.total});

  @override
  Widget build(BuildContext context) {
    if (total == 0) return const EmptyState(icon: Icons.pie_chart_outline_rounded, message: 'No ticket data yet.');
    final entries = byCategory.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return Row(
      children: [
        Expanded(
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 44,
                  sections: [
                    for (var i = 0; i < entries.length; i++)
                      PieChartSectionData(value: entries[i].value.toDouble(), color: _categoryPalette[i % _categoryPalette.length], showTitle: false, radius: 28),
                  ],
                ),
              ),
              Column(mainAxisSize: MainAxisSize.min, children: [
                Text('$total', style: Theme.of(context).textTheme.titleLarge),
                Text('Total', style: Theme.of(context).textTheme.bodySmall),
              ]),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < entries.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Container(width: 8, height: 8, decoration: BoxDecoration(color: _categoryPalette[i % _categoryPalette.length], shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${entries[i].key.label} ${(entries[i].value / total * 100).round()}%',
                          style: Theme.of(context).textTheme.bodySmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ByDayBarChart extends StatelessWidget {
  final List<DateTime> days;
  final List<int> received;
  final List<int> resolved;

  const _ByDayBarChart({required this.days, required this.received, required this.resolved});

  @override
  Widget build(BuildContext context) {
    final maxY = [...received, ...resolved].fold<int>(0, (m, v) => v > m ? v : m).toDouble() + 1;
    return Column(
      children: [
        Expanded(
          child: BarChart(
            BarChartData(
              maxY: maxY,
              barGroups: [
                for (var i = 0; i < days.length; i++)
                  BarChartGroupData(x: i, barRods: [
                    BarChartRodData(toY: received[i].toDouble(), color: AppTheme.accentBlue, width: 8, borderRadius: BorderRadius.circular(3)),
                    BarChartRodData(toY: resolved[i].toDouble(), color: StatusColors.resolved, width: 8, borderRadius: BorderRadius.circular(3)),
                  ]),
              ],
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 24, getTitlesWidget: (v, m) => Text('${v.toInt()}', style: Theme.of(context).textTheme.bodySmall))),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    // See _TrendChart's identical fix in desktop_dashboard_screen.dart:
                    // without this, fl_chart's auto-computed interval scales with
                    // pixel width and produces duplicate day labels on wide screens.
                    interval: 1,
                    getTitlesWidget: (v, m) {
                      final idx = v.toInt();
                      if (idx < 0 || idx >= days.length) return const SizedBox.shrink();
                      return Padding(padding: const EdgeInsets.only(top: 4), child: Text(DateFormat.E().format(days[idx]).substring(0, 3), style: Theme.of(context).textTheme.bodySmall));
                    },
                  ),
                ),
              ),
              gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (v) => FlLine(color: const Color(0xFFEDF2EF), strokeWidth: 1)),
              borderData: FlBorderData(show: false),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(width: 9, height: 9, color: AppTheme.accentBlue),
            const SizedBox(width: 6),
            Text('Received', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(width: 16),
            Container(width: 9, height: 9, color: StatusColors.resolved),
            const SizedBox(width: 6),
            Text('Resolved', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ],
    );
  }
}

class _ResolutionTrendChart extends StatelessWidget {
  final List<DateTime> days;
  final List<double> values;

  const _ResolutionTrendChart({required this.days, required this.values});

  @override
  Widget build(BuildContext context) {
    return LineChart(
      LineChartData(
        minY: 0,
        gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (v) => FlLine(color: const Color(0xFFEDF2EF), strokeWidth: 1)),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 28, getTitlesWidget: (v, m) => Text('${v.toInt()}', style: Theme.of(context).textTheme.bodySmall))),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              // See _TrendChart's identical fix in desktop_dashboard_screen.dart.
              interval: 1,
              getTitlesWidget: (v, m) {
                final idx = v.toInt();
                if (idx < 0 || idx >= days.length) return const SizedBox.shrink();
                return Padding(padding: const EdgeInsets.only(top: 6), child: Text(DateFormat.MMMd().format(days[idx]), style: Theme.of(context).textTheme.bodySmall));
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: [for (var i = 0; i < values.length; i++) FlSpot(i.toDouble(), values[i])],
            isCurved: true,
            color: AppTheme.accentBlue,
            barWidth: 2.5,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(show: true, color: AppTheme.accentBlue.withValues(alpha: 0.08)),
          ),
        ],
      ),
    );
  }
}
