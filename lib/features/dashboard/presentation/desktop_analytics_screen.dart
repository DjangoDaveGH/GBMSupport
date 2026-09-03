import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hyport/core/auth/auth_providers.dart';
import 'package:hyport/core/models/enums.dart';
import 'package:hyport/core/theme/app_theme.dart';
import 'package:hyport/core/widgets/branded_loader.dart';
import 'package:hyport/core/widgets/empty_state.dart';
import 'package:hyport/features/auth/data/institution_providers.dart';
import 'package:hyport/features/config/data/sla_providers.dart';
import 'package:hyport/features/config/domain/sla_policy.dart';
import 'package:hyport/features/tickets/data/ticket_providers.dart';
import 'package:hyport/features/tickets/domain/ticket.dart';
import 'package:intl/intl.dart';

const _statusOptions = [
  TicketStatus.open,
  TicketStatus.assigned,
  TicketStatus.inProgress,
  TicketStatus.escalated,
  TicketStatus.resolved,
  TicketStatus.reopened,
  TicketStatus.closed,
];

const _categoryPalette = [
  AppTheme.navy,
  AppTheme.accentBlue,
  AppTheme.gold,
  StatusColors.resolved,
  AppTheme.plum,
  StatusColors.critical,
  StatusColors.medium,
];

/// Phase 5 mockup screen 35 — same ticket data as the mobile Analytics
/// screen (via [ticketAnalyticsProvider], unbounded so every KPI reflects
/// the true dataset rather than [ticketListProvider]'s page-size cap), laid
/// out with a category donut + a Received-vs-Resolved-by-weekday bar chart
/// side by side plus a resolution-time trend line, matching the enterprise
/// mockup's density. A search + status/priority/category filter bar above
/// narrows the dataset every chart below is computed from.
class DesktopAnalyticsScreen extends ConsumerStatefulWidget {
  const DesktopAnalyticsScreen({super.key});

  @override
  ConsumerState<DesktopAnalyticsScreen> createState() => _DesktopAnalyticsScreenState();
}

class _DesktopAnalyticsScreenState extends ConsumerState<DesktopAnalyticsScreen> {
  final _searchController = TextEditingController();
  String _search = '';
  TicketStatus? _statusFilter;
  TicketPriority? _priorityFilter;
  TicketCategory? _categoryFilter;
  String? _institutionId;
  InstitutionType? _institutionType;
  DateTimeRange? _dateRange;
  bool _overdueOnly = false;

  /// Filters applied in memory over the already-loaded dataset (institution,
  /// created-date range, overdue) — see [TicketFilter.matchesClientSide].
  /// Matches the mobile Analytics screen's filter set.
  TicketFilter get _advancedFilter => TicketFilter(
        institutionId: _institutionId,
        institutionType: _institutionType,
        createdAfter: _dateRange?.start,
        createdBefore: _dateRange?.end,
        overdueOnly: _overdueOnly,
      );

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

  @override
  Widget build(BuildContext context) {
    final appUser = ref.watch(currentAppUserProvider).valueOrNull;
    if (appUser == null) return const BrandedLoaderCenter();

    final institutions = [...?ref.watch(institutionListProvider).valueOrNull]..sort((a, b) => a.name.compareTo(b.name));
    final institutionNameById = {for (final i in institutions) i.id: i.name};
    final institutionTypes = {for (final i in institutions) i.id: i.type};
    final slaPolicy = ref.watch(slaPolicyProvider).valueOrNull ?? const SlaPolicy();

    // Only the query-backed fields go to the provider; institution / date /
    // overdue are applied in memory below.
    final filter = TicketFilter(
      statuses: _statusFilter == null ? const {} : {_statusFilter!},
      category: _categoryFilter,
      priorities: _priorityFilter == null ? const {} : {_priorityFilter!},
    );
    final ticketsAsync = ref.watch(ticketAnalyticsProvider((appUser, filter)));

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FilterBar(
            searchController: _searchController,
            onSearchChanged: (v) => setState(() => _search = v),
            statusFilter: _statusFilter,
            onStatusChanged: (v) => setState(() => _statusFilter = v),
            priorityFilter: _priorityFilter,
            onPriorityChanged: (v) => setState(() => _priorityFilter = v),
            categoryFilter: _categoryFilter,
            onCategoryChanged: (v) => setState(() => _categoryFilter = v),
            institutionNameById: institutionNameById,
            institutionId: institutionNameById.containsKey(_institutionId) ? _institutionId : null,
            onInstitutionChanged: (v) => setState(() => _institutionId = v),
            institutionType: _institutionType,
            onInstitutionTypeChanged: (v) => setState(() => _institutionType = v),
            dateRange: _dateRange,
            onDateRangeChanged: (v) => setState(() => _dateRange = v),
            overdueOnly: _overdueOnly,
            onOverdueChanged: (v) => setState(() => _overdueOnly = v),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: ticketsAsync.when(
              loading: () => const BrandedLoaderCenter(),
              error: (e, _) => Center(child: Text('Could not load analytics: $e')),
              data: (tickets) => _Body(
                tickets: tickets
                    .where(_matchesSearch)
                    .where((t) => _advancedFilter.matchesClientSide(t, policy: slaPolicy, institutionTypes: institutionTypes))
                    .toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final TicketStatus? statusFilter;
  final ValueChanged<TicketStatus?> onStatusChanged;
  final TicketPriority? priorityFilter;
  final ValueChanged<TicketPriority?> onPriorityChanged;
  final TicketCategory? categoryFilter;
  final ValueChanged<TicketCategory?> onCategoryChanged;
  final Map<String, String> institutionNameById;
  final String? institutionId;
  final ValueChanged<String?> onInstitutionChanged;
  final InstitutionType? institutionType;
  final ValueChanged<InstitutionType?> onInstitutionTypeChanged;
  final DateTimeRange? dateRange;
  final ValueChanged<DateTimeRange?> onDateRangeChanged;
  final bool overdueOnly;
  final ValueChanged<bool> onOverdueChanged;

  const _FilterBar({
    required this.searchController,
    required this.onSearchChanged,
    required this.statusFilter,
    required this.onStatusChanged,
    required this.priorityFilter,
    required this.onPriorityChanged,
    required this.categoryFilter,
    required this.onCategoryChanged,
    required this.institutionNameById,
    required this.institutionId,
    required this.onInstitutionChanged,
    required this.institutionType,
    required this.onInstitutionTypeChanged,
    required this.dateRange,
    required this.onDateRangeChanged,
    required this.overdueOnly,
    required this.onOverdueChanged,
  });

  @override
  Widget build(BuildContext context) {
    final institutionIds = institutionNameById.keys.toList()
      ..sort((a, b) => (institutionNameById[a] ?? '').compareTo(institutionNameById[b] ?? ''));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: searchController,
          onChanged: onSearchChanged,
          decoration: const InputDecoration(
            hintText: 'Search by title or reference',
            prefixIcon: Icon(Icons.search_rounded, size: 20),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _FilterDropdown<TicketStatus>(
              hint: 'Status',
              allLabel: 'All Statuses',
              value: statusFilter,
              items: _statusOptions,
              labelOf: (s) => s.label,
              onChanged: onStatusChanged,
            ),
            _FilterDropdown<TicketPriority>(
              hint: 'Priority',
              allLabel: 'All Priorities',
              value: priorityFilter,
              items: TicketPriority.values,
              labelOf: (p) => p.label,
              onChanged: onPriorityChanged,
            ),
            _FilterDropdown<TicketCategory>(
              hint: 'Category',
              allLabel: 'All Categories',
              value: categoryFilter,
              items: TicketCategory.values,
              labelOf: (c) => c.label,
              onChanged: onCategoryChanged,
            ),
            _FilterDropdown<String>(
              hint: 'Institution',
              allLabel: 'All Institutions',
              value: institutionId,
              items: institutionIds,
              labelOf: (id) => institutionNameById[id] ?? id,
              onChanged: onInstitutionChanged,
            ),
            _FilterDropdown<InstitutionType>(
              hint: 'Type',
              allLabel: 'All Types',
              value: institutionType,
              items: InstitutionType.values,
              labelOf: (t) => t.wireValue,
              onChanged: onInstitutionTypeChanged,
            ),
            OutlinedButton.icon(
              onPressed: () async {
                final now = DateTime.now();
                final picked = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2023),
                  lastDate: DateTime(now.year + 1, 12, 31),
                  initialDateRange: dateRange,
                );
                if (picked != null) onDateRangeChanged(picked);
              },
              icon: const Icon(Icons.date_range_outlined, size: 18),
              label: Text(
                dateRange == null
                    ? 'Date range'
                    : '${DateFormat.MMMd().format(dateRange!.start)} – ${DateFormat.MMMd().format(dateRange!.end)}',
              ),
            ),
            if (dateRange != null)
              IconButton(
                tooltip: 'Clear dates',
                icon: const Icon(Icons.close_rounded, size: 16),
                onPressed: () => onDateRangeChanged(null),
              ),
            FilterChip(
              label: const Text('Overdue'),
              selected: overdueOnly,
              onSelected: onOverdueChanged,
            ),
          ],
        ),
      ],
    );
  }
}

class _FilterDropdown<T> extends StatelessWidget {
  final String hint;
  final String allLabel;
  final T? value;
  final List<T> items;
  final String Function(T) labelOf;
  final ValueChanged<T?> onChanged;

  const _FilterDropdown({
    required this.hint,
    required this.allLabel,
    required this.value,
    required this.items,
    required this.labelOf,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 160),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T?>(
          hint: Text(hint),
          isDense: true,
          value: value,
          items: [
            DropdownMenuItem<T?>(value: null, child: Text(allLabel)),
            ...items.map((i) => DropdownMenuItem(value: i, child: Text(labelOf(i)))),
          ],
          onChanged: onChanged,
        ),
      ),
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
      padding: const EdgeInsets.only(bottom: 24),
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
