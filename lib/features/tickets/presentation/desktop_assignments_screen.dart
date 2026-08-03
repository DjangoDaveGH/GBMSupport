import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hyport/core/auth/auth_providers.dart';
import 'package:hyport/core/theme/app_theme.dart';
import 'package:hyport/core/widgets/branded_loader.dart';
import 'package:hyport/core/widgets/empty_state.dart';
import 'package:hyport/core/widgets/status_chip.dart';
import 'package:hyport/features/auth/data/user_providers.dart';
import 'package:hyport/features/auth/domain/app_user.dart';
import 'package:hyport/features/config/data/sla_providers.dart';
import 'package:hyport/features/config/domain/sla_policy.dart';
import 'package:hyport/features/tickets/data/ticket_providers.dart';
import 'package:hyport/features/tickets/domain/sla_calculator.dart';
import 'package:intl/intl.dart';

/// Phase 5 mockup screen 33 — new to the Enterprise Web Dashboard (not in
/// the mobile Admin app). Every figure here is derived from the same
/// tickets/SLA-policy data the rest of the app already computes from.
class DesktopAssignmentsScreen extends ConsumerStatefulWidget {
  const DesktopAssignmentsScreen({super.key});

  @override
  ConsumerState<DesktopAssignmentsScreen> createState() => _DesktopAssignmentsScreenState();
}

class _DesktopAssignmentsScreenState extends ConsumerState<DesktopAssignmentsScreen> {
  final _searchController = TextEditingController();
  String _search = '';
  String? _officerFilter;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
      error: (e, _) => Center(child: Text('Could not load assignments: $e')),
      data: (tickets) {
        final usersById = <String, AppUser>{for (final u in usersAsync.valueOrNull ?? const <AppUser>[]) u.id: u};
        final officers = usersAsync.valueOrNull?.where((u) => u.role.hasBackOfficeAccess || u.role.wireValue == 'vendor_support').toList() ??
            const <AppUser>[];

        final unassigned = tickets.where((t) => t.assignedTo == null && t.status.isOpenState).length;
        final myOpen = tickets.where((t) => t.assignedTo == appUser.id && t.status.isOpenState).length;
        final overdue = SlaCalculator.countOverdue(tickets, slaPolicy);
        final slaBreached = tickets
            .where((t) => (t.resolvedAt != null || t.closedAt != null) && !SlaCalculator.metSla(t, slaPolicy))
            .length;

        var filtered = tickets.where((t) => t.status.isOpenState).toList();
        if (_officerFilter != null) filtered = filtered.where((t) => t.assignedTo == _officerFilter).toList();
        if (_search.isNotEmpty) {
          final q = _search.toLowerCase();
          filtered = filtered.where((t) => t.title.toLowerCase().contains(q) || t.ticketReference.toLowerCase().contains(q)).toList();
        }
        filtered.sort((a, b) => a.createdAt.compareTo(b.createdAt));

        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _StatCardRow(children: [
                _StatCard(label: 'Unassigned', value: unassigned, color: AppTheme.gold),
                _StatCard(label: 'My Open', value: myOpen, color: AppTheme.accentBlue),
                _StatCard(label: 'Overdue', value: overdue, color: StatusColors.critical),
                _StatCard(label: 'SLA Breached', value: slaBreached, color: StatusColors.critical),
              ]),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      onChanged: (v) => setState(() => _search = v),
                      decoration: const InputDecoration(hintText: 'Search assignments…', prefixIcon: Icon(Icons.search_rounded, size: 20)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    constraints: const BoxConstraints(minWidth: 180),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String?>(
                        hint: const Text('Officer'),
                        isDense: true,
                        value: _officerFilter,
                        items: [
                          const DropdownMenuItem<String?>(value: null, child: Text('All Officers')),
                          ...officers.map((o) => DropdownMenuItem(value: o.id, child: Text(o.name))),
                        ],
                        onChanged: (v) => setState(() => _officerFilter = v),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                  ),
                  child: filtered.isEmpty
                      ? const EmptyState(icon: Icons.assignment_ind_outlined, message: 'No open assignments match.')
                      : SingleChildScrollView(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              headingRowHeight: 44,
                              columns: const [
                                DataColumn(label: Text('Ticket ID')),
                                DataColumn(label: Text('Title')),
                                DataColumn(label: Text('Priority')),
                                DataColumn(label: Text('Assigned To')),
                                DataColumn(label: Text('Status')),
                                DataColumn(label: Text('SLA Due')),
                              ],
                              rows: filtered.map((t) {
                                final assignee = t.assignedTo == null ? null : usersById[t.assignedTo];
                                final due = t.createdAt.add(Duration(hours: slaPolicy.targetHoursFor(t.priority)));
                                final overdueRow = SlaCalculator.isOverdue(t, slaPolicy);
                                return DataRow(
                                  onSelectChanged: (_) => context.push('/tickets/${t.id}'),
                                  cells: [
                                    DataCell(Text(t.ticketReference, style: const TextStyle(fontWeight: FontWeight.w600))),
                                    DataCell(SizedBox(width: 240, child: Text(t.title, overflow: TextOverflow.ellipsis))),
                                    DataCell(TicketPriorityChip(priority: t.priority)),
                                    DataCell(Text(assignee?.name ?? 'Unassigned')),
                                    DataCell(TicketStatusChip(status: t.status)),
                                    DataCell(Text(
                                      DateFormat.MMMd().add_jm().format(due),
                                      style: TextStyle(color: overdueRow ? StatusColors.critical : null, fontWeight: overdueRow ? FontWeight.w700 : null),
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
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final int value;
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
          Text('$value', style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: color)),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.black54),
          ),
        ],
      ),
    );
  }
}

/// This screen has no separate mobile layout (see the class doc comment —
/// it's Enterprise Web Dashboard-only), but `/assignments`' mobile route
/// still falls back to rendering it directly (app_router.dart), so the
/// 4-across stat row needs to survive a 390px viewport too: a straight
/// `Row` of `Expanded` cards squeezed labels like "Unassigned" and "SLA
/// Breached" into ~70px, forcing mid-word line breaks ("Una/ssig/ned").
/// 2x2 below the desktop breakpoint fixes it without touching the desktop
/// layout at all.
class _StatCardRow extends StatelessWidget {
  final List<Widget> children;

  const _StatCardRow({required this.children});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 560) {
          return Row(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(width: 16),
                Expanded(child: children[i]),
              ],
            ],
          );
        }
        return Column(
          children: [
            Row(children: [
              Expanded(child: children[0]),
              const SizedBox(width: 12),
              Expanded(child: children[1]),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: children[2]),
              const SizedBox(width: 12),
              Expanded(child: children[3]),
            ]),
          ],
        );
      },
    );
  }
}
