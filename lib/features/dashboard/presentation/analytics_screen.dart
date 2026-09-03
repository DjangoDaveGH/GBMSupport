import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hyport/core/auth/auth_providers.dart';
import 'package:hyport/core/models/enums.dart';
import 'package:hyport/core/theme/app_theme.dart';
import 'package:hyport/core/widgets/branded_loader.dart';
import 'package:hyport/core/widgets/empty_state.dart';
import 'package:hyport/core/widgets/percent_ring.dart';
import 'package:hyport/core/widgets/sparkline.dart';
import 'package:hyport/features/auth/data/institution_providers.dart';
import 'package:hyport/features/config/data/sla_providers.dart';
import 'package:hyport/features/config/domain/sla_policy.dart';
import 'package:hyport/features/tickets/data/ticket_providers.dart';
import 'package:hyport/features/tickets/domain/sla_calculator.dart';
import 'package:hyport/features/tickets/domain/ticket.dart';
import 'package:hyport/features/tickets/presentation/ticket_list_screen.dart' show categoryIcon;

const _categoryPalette = [
  AppTheme.navy,
  AppTheme.accentBlue,
  AppTheme.gold,
  StatusColors.resolved,
  AppTheme.plum,
  StatusColors.critical,
  StatusColors.medium,
];

/// Phase 4 mockup screen 23. Support-side only (see supportSideOnlyPaths).
/// Every figure is computed live from the same tickets the rest of the app
/// already sees — no synthetic trend data, and no page-size cap: this
/// watches [ticketAnalyticsProvider] (unbounded) rather than
/// [ticketListProvider] (capped at [ticketPageSize]) so every KPI reflects
/// the true dataset. Status/priority/category filters and a title/reference
/// search narrow that dataset down before the figures below are computed
/// from it, reusing the same TicketFilter/TicketFiltersScreen the Ticket
/// Queue uses.
class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen> {
  final _searchController = TextEditingController();
  String _search = '';
  TicketFilter _filter = const TicketFilter();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _matchesSearch(Ticket t) {
    if (_search.isEmpty) return true;
    final q = _search.toLowerCase();
    return t.title.toLowerCase().contains(q) || t.ticketReference.toLowerCase().contains(q);
  }

  Future<void> _openFilters() async {
    final result = await context.push<TicketFilter>('/tickets/filters', extra: _filter);
    if (result != null && mounted) setState(() => _filter = result);
  }

  @override
  Widget build(BuildContext context) {
    final appUser = ref.watch(currentAppUserProvider).valueOrNull;
    if (appUser == null) return const Scaffold(body: BrandedLoaderCenter());

    // Only the query-backed fields go to the provider; institution / date /
    // overdue are applied in memory (TicketFilter.matchesClientSide) so they
    // don't spawn an identical refetch under a new family key.
    final queryFilter = TicketFilter(statuses: _filter.statuses, category: _filter.category, priorities: _filter.priorities);
    final ticketsAsync = ref.watch(ticketAnalyticsProvider((appUser, queryFilter)));
    final slaPolicy = ref.watch(slaPolicyProvider).valueOrNull ?? const SlaPolicy();
    final institutionTypes = {
      for (final i in [...?ref.watch(institutionListProvider).valueOrNull]) i.id: i.type,
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Analytics'),
        actions: [
          IconButton(
            onPressed: _openFilters,
            icon: Icon(_filter.isEmpty ? Icons.filter_alt_outlined : Icons.filter_alt_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _search = v),
              decoration: InputDecoration(
                hintText: 'Search by title or reference',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: _search.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () => setState(() {
                          _searchController.clear();
                          _search = '';
                        }),
                      ),
              ),
            ),
          ),
          Expanded(
            child: ticketsAsync.when(
              loading: () => const BrandedLoaderCenter(),
              error: (e, _) => Center(child: Text('Could not load analytics data: $e')),
              data: (tickets) => _AnalyticsBody(
                tickets: tickets
                    .where(_matchesSearch)
                    .where((t) => _filter.matchesClientSide(t, policy: slaPolicy, institutionTypes: institutionTypes))
                    .toList(),
                slaPolicy: slaPolicy,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnalyticsBody extends StatelessWidget {
  final List<Ticket> tickets;
  final SlaPolicy slaPolicy;

  const _AnalyticsBody({required this.tickets, required this.slaPolicy});

  List<DateTime> get _last7Days {
    final today = DateTime.now();
    return List.generate(7, (i) => DateTime(today.year, today.month, today.day).subtract(Duration(days: 6 - i)));
  }

  bool _isSameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  /// [countMode] = true for a count metric (e.g. "Tickets Resolved"): the
  /// series is tickets-per-day and the percent change compares the two
  /// 7-day counts. Without it, [valueOf] is averaged (used for time-based
  /// metrics like resolution hours) — averaging a constant, as the resolved
  /// count previously did, made the change always 0 / ±100.
  ({List<double> series, double total, double percentChange}) _dailyTrend(
    List<Ticket> tickets,
    DateTime? Function(Ticket) dateOf,
    double Function(Ticket) valueOf, {
    bool countMode = false,
  }) {
    final days = _last7Days;
    final series = <double>[];
    for (final day in days) {
      final onDay = tickets.where((t) {
        final d = dateOf(t);
        return d != null && _isSameDay(d, day);
      }).toList();
      if (countMode) {
        series.add(onDay.length.toDouble());
      } else {
        series.add(onDay.isEmpty ? 0 : onDay.map(valueOf).reduce((a, b) => a + b) / onDay.length);
      }
    }

    final priorStart = days.first.subtract(const Duration(days: 7));
    final priorTickets = tickets.where((t) {
      final d = dateOf(t);
      return d != null && !d.isBefore(priorStart) && d.isBefore(days.first);
    }).toList();
    final currentTickets = tickets.where((t) {
      final d = dateOf(t);
      return d != null && !d.isBefore(days.first);
    }).toList();

    final double currentValue;
    final double priorValue;
    if (countMode) {
      currentValue = currentTickets.length.toDouble();
      priorValue = priorTickets.length.toDouble();
    } else {
      currentValue = currentTickets.isEmpty ? 0.0 : currentTickets.map(valueOf).reduce((a, b) => a + b) / currentTickets.length;
      priorValue = priorTickets.isEmpty ? 0.0 : priorTickets.map(valueOf).reduce((a, b) => a + b) / priorTickets.length;
    }
    final change = priorValue == 0 ? (currentValue == 0 ? 0.0 : 100.0) : ((currentValue - priorValue) / priorValue) * 100;

    return (series: series, total: currentTickets.length.toDouble(), percentChange: change);
  }

  Map<TicketCategory, int> get _byCategory {
    final map = <TicketCategory, int>{};
    for (final t in tickets) {
      map[t.category] = (map[t.category] ?? 0) + 1;
    }
    return map;
  }

  List<MapEntry<TicketCategory, int>> get _recurring {
    final entries = _byCategory.entries.where((e) => e.value > 1).toList()..sort((a, b) => b.value.compareTo(a.value));
    return entries;
  }

  @override
  Widget build(BuildContext context) {
    final resolved = tickets.where((t) => t.resolvedAt != null).toList();

    final resolvedTrend = _dailyTrend(resolved, (t) => t.resolvedAt, (_) => 1, countMode: true);
    final resolutionTimeTrend = _dailyTrend(
      resolved,
      (t) => t.resolvedAt,
      (t) => t.resolvedAt!.difference(t.createdAt).inMinutes / 60,
    );
    final responded = tickets.where((t) => t.firstRespondedAt != null).toList();
    final firstResponseTrend = _dailyTrend(
      responded,
      (t) => t.firstRespondedAt,
      (t) => t.firstRespondedAt!.difference(t.createdAt).inMinutes.toDouble(),
    );
    final slaCompliance = SlaCalculator.complianceRate(tickets, slaPolicy);

    final avgResolutionHours =
        resolved.isEmpty ? 0.0 : resolved.map((t) => t.resolvedAt!.difference(t.createdAt).inMinutes / 60).reduce((a, b) => a + b) / resolved.length;
    final avgFirstResponseMinutes =
        responded.isEmpty ? 0.0 : responded.map((t) => t.firstRespondedAt!.difference(t.createdAt).inMinutes.toDouble()).reduce((a, b) => a + b) / responded.length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Row(
            children: [
              const Icon(Icons.calendar_today_rounded, size: 15, color: AppTheme.accentBlue),
              const SizedBox(width: 8),
              Text('Last 7 days', style: Theme.of(context).textTheme.labelMedium),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.25,
          children: [
            _MetricCard(
              label: 'Tickets Resolved',
              value: resolvedTrend.total.toInt().toString(),
              percentChange: resolvedTrend.percentChange,
              sparkline: resolvedTrend.series,
              color: AppTheme.accentBlue,
            ),
            _MetricCard(
              label: 'Avg. Resolution Time',
              value: '${avgResolutionHours.toStringAsFixed(1)} hrs',
              percentChange: resolutionTimeTrend.percentChange,
              percentChangeIsGood: false,
              sparkline: resolutionTimeTrend.series,
              color: AppTheme.gold,
            ),
            _SlaComplianceCard(percent: slaCompliance),
            _MetricCard(
              label: 'First Response Time',
              value: avgFirstResponseMinutes >= 60
                  ? '${(avgFirstResponseMinutes / 60).toStringAsFixed(1)} hrs'
                  : '${avgFirstResponseMinutes.round()}m',
              percentChange: firstResponseTrend.percentChange,
              percentChangeIsGood: false,
              sparkline: firstResponseTrend.series,
              color: AppTheme.plum,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        Text('Tickets by Category', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.md),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: _byCategory.isEmpty
              ? const EmptyState(icon: Icons.pie_chart_outline_rounded, message: 'No ticket data yet.')
              : _CategoryDonut(byCategory: _byCategory, total: tickets.length),
        ),
        const SizedBox(height: AppSpacing.xl),
        Text('Recurring Issues', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.md),
        if (_recurring.isEmpty)
          const EmptyState(icon: Icons.insights_rounded, message: 'No recurring patterns detected yet.')
        else
          ..._recurring.map((e) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppTheme.gold.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Icon(categoryIcon(e.key), size: 17, color: AppTheme.gold),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(e.key.label, style: Theme.of(context).textTheme.titleSmall)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Text('${e.value} tickets', style: Theme.of(context).textTheme.labelMedium),
                    ),
                  ],
                ),
              )),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final double percentChange;
  final bool percentChangeIsGood;
  final List<double> sparkline;
  final Color color;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.percentChange,
    required this.sparkline,
    required this.color,
    this.percentChangeIsGood = true,
  });

  @override
  Widget build(BuildContext context) {
    final rising = percentChange >= 0;
    final good = rising == percentChangeIsGood;
    final changeColor = good ? StatusColors.resolved : StatusColors.critical;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        boxShadow: softShadow(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: AppTheme.ink)),
          const SizedBox(height: 2),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(rising ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 12, color: changeColor),
              Text(
                '${percentChange.abs().toStringAsFixed(0)}%',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(color: changeColor),
              ),
            ],
          ),
          const Spacer(),
          Sparkline(values: sparkline, color: color),
        ],
      ),
    );
  }
}

class _SlaComplianceCard extends StatelessWidget {
  final double? percent;

  const _SlaComplianceCard({required this.percent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        boxShadow: softShadow(),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('SLA Compliance', style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 4),
                Text(
                  'Resolved within target',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.outline),
                ),
              ],
            ),
          ),
          PercentRing(percent: percent, color: StatusColors.resolved, size: 56, strokeWidth: 6),
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
    final entries = byCategory.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      children: [
        SizedBox(
          height: 180,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 52,
                  sections: [
                    for (var i = 0; i < entries.length; i++)
                      PieChartSectionData(
                        value: entries[i].value.toDouble(),
                        color: _categoryPalette[i % _categoryPalette.length],
                        showTitle: false,
                        radius: 34,
                      ),
                  ],
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$total', style: Theme.of(context).textTheme.headlineMedium),
                  Text('Total', style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Wrap(
          spacing: 16,
          runSpacing: 10,
          children: [
            for (var i = 0; i < entries.length; i++)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(color: _categoryPalette[i % _categoryPalette.length], shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${entries[i].key.label} ${(entries[i].value / total * 100).round()}%',
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
