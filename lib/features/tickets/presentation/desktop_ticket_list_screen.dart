import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hyport/core/auth/auth_providers.dart';
import 'package:hyport/core/models/enums.dart';
import 'package:hyport/core/theme/app_theme.dart';
import 'package:hyport/core/widgets/branded_loader.dart';
import 'package:hyport/core/widgets/empty_state.dart';
import 'package:hyport/core/widgets/status_chip.dart';
import 'package:hyport/features/auth/data/user_providers.dart';
import 'package:hyport/features/auth/domain/app_user.dart';
import 'package:hyport/features/tickets/data/ticket_providers.dart';
import 'package:hyport/features/tickets/domain/ticket.dart';
import 'package:hyport/features/tickets/presentation/ticket_list_screen.dart' show categoryIcon;
import 'package:intl/intl.dart';

enum _StatusTab { all, open, inProgress, pending, resolved, closed }

const _pendingStatuses = {TicketStatus.assigned, TicketStatus.escalated, TicketStatus.reopened};

/// Phase 5 mockup screen 31 — same `ticketListProvider` data as the mobile
/// Ticket Queue, rendered as a filterable/sortable table instead of cards.
class DesktopTicketListScreen extends ConsumerStatefulWidget {
  const DesktopTicketListScreen({super.key});

  @override
  ConsumerState<DesktopTicketListScreen> createState() => _DesktopTicketListScreenState();
}

class _DesktopTicketListScreenState extends ConsumerState<DesktopTicketListScreen> {
  final _searchController = TextEditingController();
  String _search = '';
  _StatusTab _tab = _StatusTab.all;
  TicketPriority? _priority;
  TicketCategory? _category;
  int _page = 0;
  static const _pageSize = 10;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _matchesTab(Ticket t) => switch (_tab) {
        _StatusTab.all => true,
        _StatusTab.open => t.status == TicketStatus.open,
        _StatusTab.inProgress => t.status == TicketStatus.inProgress,
        _StatusTab.pending => _pendingStatuses.contains(t.status),
        _StatusTab.resolved => t.status == TicketStatus.resolved,
        _StatusTab.closed => t.status == TicketStatus.closed,
      };

  void _exportCsv(List<Ticket> tickets, Map<String, AppUser> usersById) {
    final buffer = StringBuffer('Reference,Title,Category,Priority,Assigned To,Status,Created\n');
    for (final t in tickets) {
      final assignee = t.assignedTo == null ? '' : (usersById[t.assignedTo]?.name ?? '');
      buffer.writeln(
        '"${t.ticketReference}","${t.title.replaceAll('"', '""')}","${t.category.label}","${t.priority.label}","$assignee","${t.status.label}","${DateFormat.yMd().format(t.createdAt)}"',
      );
    }
    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copied ${tickets.length} rows as CSV to clipboard — paste into Excel/Sheets.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appUser = ref.watch(currentAppUserProvider).valueOrNull;
    if (appUser == null) return const BrandedLoaderCenter();

    final ticketsAsync = ref.watch(
      ticketListProvider((appUser, TicketFilter(priorities: _priority == null ? const {} : {_priority!}, category: _category))),
    );
    final usersAsync = ref.watch(allUsersProvider);

    return ticketsAsync.when(
      loading: () => const BrandedLoaderCenter(),
      error: (e, _) => Center(child: Text('Could not load tickets: $e')),
      data: (allTickets) {
        final usersById = <String, AppUser>{for (final u in usersAsync.valueOrNull ?? const <AppUser>[]) u.id: u};
        final search = _search.toLowerCase();
        final filtered = allTickets.where(_matchesTab).where((t) {
          if (search.isEmpty) return true;
          return t.title.toLowerCase().contains(search) || t.ticketReference.toLowerCase().contains(search);
        }).toList();

        final totalPages = (filtered.length / _pageSize).ceil().clamp(1, 999999);
        final pageClamped = _page.clamp(0, totalPages - 1);
        final pageItems = filtered.skip(pageClamped * _pageSize).take(_pageSize).toList();

        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      onChanged: (v) => setState(() {
                        _search = v;
                        _page = 0;
                      }),
                      decoration: const InputDecoration(hintText: 'Search tickets…', prefixIcon: Icon(Icons.search_rounded, size: 20)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  _FilterDropdown<TicketPriority>(
                    hint: 'Priority',
                    value: _priority,
                    items: TicketPriority.values,
                    labelOf: (p) => p.label,
                    onChanged: (v) => setState(() {
                      _priority = v;
                      _page = 0;
                    }),
                  ),
                  const SizedBox(width: 12),
                  _FilterDropdown<TicketCategory>(
                    hint: 'Category',
                    value: _category,
                    items: TicketCategory.values,
                    labelOf: (c) => c.label,
                    onChanged: (v) => setState(() {
                      _category = v;
                      _page = 0;
                    }),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: filtered.isEmpty ? null : () => _exportCsv(filtered, usersById),
                    icon: const Icon(Icons.download_outlined, size: 18),
                    label: const Text('Export'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                children: [
                  _tabChip('All (${allTickets.length})', _StatusTab.all, allTickets),
                  _tabChip('Open (${allTickets.where((t) => t.status == TicketStatus.open).length})', _StatusTab.open, allTickets),
                  _tabChip(
                    'In Progress (${allTickets.where((t) => t.status == TicketStatus.inProgress).length})',
                    _StatusTab.inProgress,
                    allTickets,
                  ),
                  _tabChip('Pending (${allTickets.where((t) => _pendingStatuses.contains(t.status)).length})', _StatusTab.pending, allTickets),
                  _tabChip(
                    'Resolved (${allTickets.where((t) => t.status == TicketStatus.resolved).length})',
                    _StatusTab.resolved,
                    allTickets,
                  ),
                  _tabChip('Closed (${allTickets.where((t) => t.status == TicketStatus.closed).length})', _StatusTab.closed, allTickets),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                  ),
                  child: filtered.isEmpty
                      ? const EmptyState(icon: Icons.confirmation_number_outlined, message: 'No tickets match these filters.')
                      : Column(
                          children: [
                            Expanded(
                              child: SingleChildScrollView(
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: DataTable(
                                    headingRowHeight: 44,
                                    dataRowMinHeight: 56,
                                    dataRowMaxHeight: 56,
                                    columns: const [
                                      DataColumn(label: Text('ID')),
                                      DataColumn(label: Text('Title')),
                                      DataColumn(label: Text('Category')),
                                      DataColumn(label: Text('Priority')),
                                      DataColumn(label: Text('Assigned To')),
                                      DataColumn(label: Text('Status')),
                                      DataColumn(label: Text('Created')),
                                    ],
                                    rows: pageItems.map((t) {
                                      final assignee = t.assignedTo == null ? null : usersById[t.assignedTo];
                                      return DataRow(
                                        onSelectChanged: (_) => context.push('/tickets/${t.id}'),
                                        cells: [
                                          DataCell(Text(t.ticketReference, style: const TextStyle(fontWeight: FontWeight.w600))),
                                          DataCell(SizedBox(width: 260, child: Text(t.title, overflow: TextOverflow.ellipsis))),
                                          DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                                            Icon(categoryIcon(t.category), size: 16, color: AppTheme.accentBlue),
                                            const SizedBox(width: 6),
                                            Text(t.category.label),
                                          ])),
                                          DataCell(TicketPriorityChip(priority: t.priority)),
                                          DataCell(Text(assignee?.name ?? 'Unassigned')),
                                          DataCell(TicketStatusChip(status: t.status)),
                                          DataCell(Text(DateFormat.MMMd().add_jm().format(t.createdAt))),
                                        ],
                                      );
                                    }).toList(),
                                  ),
                                ),
                              ),
                            ),
                            _Pagination(
                              page: pageClamped,
                              totalPages: totalPages,
                              onChanged: (p) => setState(() => _page = p),
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _tabChip(String label, _StatusTab tab, List<Ticket> allTickets) {
    final selected = tab == _tab;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      selectedColor: AppTheme.navy,
      labelStyle: TextStyle(color: selected ? Colors.white : AppTheme.ink, fontWeight: FontWeight.w600),
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      onSelected: (_) => setState(() {
        _tab = tab;
        _page = 0;
      }),
    );
  }
}

class _FilterDropdown<T> extends StatelessWidget {
  final String hint;
  final T? value;
  final List<T> items;
  final String Function(T) labelOf;
  final ValueChanged<T?> onChanged;

  const _FilterDropdown({required this.hint, required this.value, required this.items, required this.labelOf, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 150),
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
            DropdownMenuItem<T?>(value: null, child: Text('All $hint')),
            ...items.map((i) => DropdownMenuItem(value: i, child: Text(labelOf(i)))),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _Pagination extends StatelessWidget {
  final int page;
  final int totalPages;
  final ValueChanged<int> onChanged;

  const _Pagination({required this.page, required this.totalPages, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          IconButton(
            onPressed: page > 0 ? () => onChanged(page - 1) : null,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Text('Page ${page + 1} of $totalPages', style: Theme.of(context).textTheme.bodySmall),
          IconButton(
            onPressed: page < totalPages - 1 ? () => onChanged(page + 1) : null,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }
}
