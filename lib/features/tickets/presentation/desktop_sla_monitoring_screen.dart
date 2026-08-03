import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hyport/core/auth/auth_providers.dart';
import 'package:hyport/core/models/enums.dart';
import 'package:hyport/core/theme/app_theme.dart';
import 'package:hyport/core/widgets/branded_loader.dart';
import 'package:hyport/core/widgets/empty_state.dart';
import 'package:hyport/features/auth/data/user_providers.dart';
import 'package:hyport/features/auth/domain/app_user.dart';
import 'package:hyport/features/config/data/sla_providers.dart';
import 'package:hyport/features/config/domain/sla_policy.dart';
import 'package:hyport/features/tickets/data/ticket_providers.dart';
import 'package:hyport/features/tickets/domain/sla_calculator.dart';
import 'package:hyport/features/tickets/domain/ticket.dart';
import 'package:intl/intl.dart';

/// Phase 5 mockup screen 39 — new to the Enterprise Web Dashboard. Every
/// figure is derived from SlaCalculator + the live ticket list, same
/// source of truth as Analytics/Assignments/the Admin Dashboard.
class DesktopSlaMonitoringScreen extends ConsumerStatefulWidget {
  const DesktopSlaMonitoringScreen({super.key});

  @override
  ConsumerState<DesktopSlaMonitoringScreen> createState() => _DesktopSlaMonitoringScreenState();
}

class _DesktopSlaMonitoringScreenState extends ConsumerState<DesktopSlaMonitoringScreen> {
  TicketCategory? _category;

  bool _isAtRisk(Ticket t, SlaPolicy policy) {
    if (!t.status.isOpenState) return false;
    final targetHours = policy.targetHoursFor(t.priority);
    final elapsedHours = DateTime.now().difference(t.createdAt).inHours;
    return elapsedHours <= targetHours && elapsedHours >= targetHours * 0.75;
  }

  bool _breachedToday(Ticket t, SlaPolicy policy) {
    if (!SlaCalculator.isOverdue(t, policy)) return false;
    final due = t.createdAt.add(Duration(hours: policy.targetHoursFor(t.priority)));
    final now = DateTime.now();
    return due.year == now.year && due.month == now.month && due.day == now.day;
  }

  @override
  Widget build(BuildContext context) {
    final appUser = ref.watch(currentAppUserProvider).valueOrNull;
    if (appUser == null) return const BrandedLoaderCenter();

    final ticketsAsync = ref.watch(ticketListProvider((appUser, const TicketFilter())));
    final usersAsync = ref.watch(allUsersProvider);
    final slaPolicy = ref.watch(slaPolicyProvider).valueOrNull ?? const SlaPolicy();

    return ticketsAsync.when(
      loading: () => const BrandedLoaderCenter(),
      error: (e, _) => Center(child: Text('Could not load SLA data: $e')),
      data: (tickets) {
        final usersById = <String, AppUser>{for (final u in usersAsync.valueOrNull ?? const <AppUser>[]) u.id: u};
        final compliance = SlaCalculator.complianceRate(tickets, slaPolicy);
        final atRisk = tickets.where((t) => _isAtRisk(t, slaPolicy)).length;
        final breachedToday = tickets.where((t) => _breachedToday(t, slaPolicy)).length;

        final breachedTickets = tickets
            .where((t) => (t.resolvedAt != null || t.closedAt != null) && !SlaCalculator.metSla(t, slaPolicy))
            .where((t) => _category == null || t.category == _category)
            .toList()
          ..sort((a, b) => (b.resolvedAt ?? b.closedAt!).compareTo(a.resolvedAt ?? a.closedAt!));

        return Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 200,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                  ),
                  child: Column(
                    children: [
                      _CategoryTile(label: 'All Categories', selected: _category == null, onTap: () => setState(() => _category = null)),
                      for (final c in TicketCategory.values)
                        _CategoryTile(label: c.label, selected: _category == c, onTap: () => setState(() => _category = c)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: _StatCard(label: 'Within SLA', value: compliance == null ? '—' : '${compliance.round()}%', color: StatusColors.resolved)),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _StatCard(
                            label: 'Breached',
                            value: compliance == null ? '—' : '${(100 - compliance).round()}%',
                            color: StatusColors.critical,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(child: _StatCard(label: 'At Risk', value: '$atRisk', color: AppTheme.gold)),
                        const SizedBox(width: 16),
                        Expanded(child: _StatCard(label: 'SLA Breached Today', value: '$breachedToday', color: StatusColors.critical)),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text('Breached Tickets', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 12),
                    Expanded(
                      child: Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(AppRadius.lg),
                          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                        ),
                        child: breachedTickets.isEmpty
                            ? const EmptyState(icon: Icons.gpp_good_outlined, message: 'No SLA breaches on record.')
                            : SingleChildScrollView(
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: DataTable(
                                    headingRowHeight: 44,
                                    columns: const [
                                      DataColumn(label: Text('Ticket ID')),
                                      DataColumn(label: Text('Title')),
                                      DataColumn(label: Text('Assigned To')),
                                      DataColumn(label: Text('SLA Due')),
                                      DataColumn(label: Text('Breached By')),
                                    ],
                                    rows: breachedTickets.map((t) {
                                      final assignee = t.assignedTo == null ? null : usersById[t.assignedTo];
                                      final due = t.createdAt.add(Duration(hours: slaPolicy.targetHoursFor(t.priority)));
                                      final resolvedAt = t.resolvedAt ?? t.closedAt!;
                                      final overBy = resolvedAt.difference(due);
                                      return DataRow(
                                        onSelectChanged: (_) => context.push('/tickets/${t.id}'),
                                        cells: [
                                          DataCell(Text(t.ticketReference, style: const TextStyle(fontWeight: FontWeight.w600))),
                                          DataCell(SizedBox(width: 220, child: Text(t.title, overflow: TextOverflow.ellipsis))),
                                          DataCell(Text(assignee?.name ?? 'Unassigned')),
                                          DataCell(Text(DateFormat.MMMd().add_jm().format(due))),
                                          DataCell(Text(
                                            '${overBy.inHours}h',
                                            style: const TextStyle(color: StatusColors.critical, fontWeight: FontWeight.w700),
                                          )),
                                        ],
                                      );
                                    }).toList(),
                                  ),
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatCard({required this.label, required this.value, required this.color});

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
          Text(value, style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: color)),
          const SizedBox(height: 6),
          Text(label, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.black54)),
        ],
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryTile({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppTheme.navy.withValues(alpha: 0.08) : Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Text(
            label,
            style: TextStyle(fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: selected ? AppTheme.navy : AppTheme.ink, fontSize: 13),
          ),
        ),
      ),
    );
  }
}
