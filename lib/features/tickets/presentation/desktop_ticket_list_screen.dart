import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hyport/core/auth/auth_providers.dart';
import 'package:hyport/core/models/enums.dart';
import 'package:hyport/core/theme/app_theme.dart';
import 'package:hyport/core/widgets/branded_loader.dart';
import 'package:hyport/core/widgets/empty_state.dart';
import 'package:hyport/core/widgets/scrollable_table.dart';
import 'package:hyport/core/widgets/status_chip.dart';
import 'package:hyport/features/auth/data/institution_providers.dart';
import 'package:hyport/features/auth/data/user_providers.dart';
import 'package:hyport/features/auth/domain/app_user.dart';
import 'package:hyport/features/config/data/sla_providers.dart';
import 'package:hyport/features/config/domain/sla_policy.dart';
import 'package:hyport/features/tickets/data/ticket_providers.dart';
import 'package:hyport/features/tickets/domain/ticket.dart';
import 'package:hyport/features/tickets/presentation/ticket_list_screen.dart' show categoryIcon;
import 'package:intl/intl.dart';

const _pendingStatuses = {TicketStatus.assigned, TicketStatus.escalated, TicketStatus.reopened};

/// Multi-select status groups — the same idea as the mobile Filters screen,
/// so a laptop user can now narrow to several statuses at once (e.g. Open +
/// Pending) instead of one tab. An empty selection = all statuses.
const _statusGroups = <(String, Set<TicketStatus>)>[
  ('Open', {TicketStatus.open}),
  ('In Progress', {TicketStatus.inProgress}),
  ('Pending', _pendingStatuses),
  ('Resolved', {TicketStatus.resolved}),
  ('Closed', {TicketStatus.closed}),
];

/// Phase 5 mockup screen 31 — same `ticketListProvider` data as the mobile
/// Ticket Queue, rendered as a filterable/sortable table instead of cards.
class DesktopTicketListScreen extends ConsumerStatefulWidget {
  /// Seeds the filter state from e.g. a dashboard stat card ("Open Tickets"
  /// -> statuses: {open}) so arriving here already shows the relevant data
  /// instead of the unfiltered list.
  final TicketFilter? initialFilter;

  const DesktopTicketListScreen({super.key, this.initialFilter});

  @override
  ConsumerState<DesktopTicketListScreen> createState() => _DesktopTicketListScreenState();
}

class _DesktopTicketListScreenState extends ConsumerState<DesktopTicketListScreen> {
  final _searchController = TextEditingController();
  String _search = '';
  Set<TicketStatus> _statuses = {};
  TicketPriority? _priority;
  TicketCategory? _category;
  String? _institutionId;
  InstitutionType? _institutionType;
  DateTimeRange? _dateRange;
  bool _overdueOnly = false;
  int _page = 0;
  static const _pageSize = 10;

  @override
  void initState() {
    super.initState();
    final f = widget.initialFilter;
    if (f != null) {
      _statuses = f.statuses;
      _priority = f.priorities.firstOrNull;
      _category = f.category;
      _institutionId = f.institutionId;
      _institutionType = f.institutionType;
      if (f.createdAfter != null && f.createdBefore != null) {
        _dateRange = DateTimeRange(start: f.createdAfter!, end: f.createdBefore!);
      }
      _overdueOnly = f.overdueOnly;
    }
  }

  /// Filters applied in memory over the already-loaded list (institution,
  /// created-date range, overdue) — see [TicketFilter.matchesClientSide].
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

  bool _matchesTab(Ticket t) => _statuses.isEmpty || _statuses.contains(t.status);

  void _toggleGroup(Set<TicketStatus> group, bool on) {
    setState(() {
      if (on) {
        _statuses.addAll(group);
      } else {
        _statuses.removeAll(group);
      }
      _page = 0;
    });
  }

  void _exportCsv(List<Ticket> tickets, Map<String, AppUser> usersById) {
    final buffer = StringBuffer('Reference,Title,Category,Priority,Assigned To,Status,Created\n');
    for (final t in tickets) {
      final assignee = t.assignedTo == null ? '' : (usersById[t.assignedTo]?.name ?? t.assignedToName ?? '');
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
      ticketAnalyticsProvider((appUser, TicketFilter(priorities: _priority == null ? const {} : {_priority!}, category: _category))),
    );
    // Requesters can't read other users' docs (firestore.rules) — only fetch
    // the roster for support-side viewers; requesters fall back to the
    // denormalized ticket.assignedToName in the table.
    final usersAsync = appUser.role.isSupportSide ? ref.watch(allUsersProvider) : null;
    final institutions = [...?ref.watch(institutionListProvider).valueOrNull]..sort((a, b) => a.name.compareTo(b.name));
    final institutionNameById = {for (final i in institutions) i.id: i.name};
    final institutionTypes = {for (final i in institutions) i.id: i.type};
    final slaPolicy = ref.watch(slaPolicyProvider).valueOrNull ?? const SlaPolicy();

    return ticketsAsync.when(
      loading: () => const BrandedLoaderCenter(),
      error: (e, _) => Center(child: Text('Could not load tickets: $e')),
      data: (rawTickets) {
        final usersById = <String, AppUser>{for (final u in usersAsync?.valueOrNull ?? const <AppUser>[]) u.id: u};
        final search = _search.toLowerCase();
        // Advanced (in-memory) filters first, so the tab counts reflect them.
        final allTickets = rawTickets
            .where((t) => _advancedFilter.matchesClientSide(t, policy: slaPolicy, institutionTypes: institutionTypes))
            .toList();
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
                  OutlinedButton.icon(
                    onPressed: filtered.isEmpty ? null : () => _exportCsv(filtered, usersById),
                    icon: const Icon(Icons.download_outlined, size: 18),
                    label: const Text('Export'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
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
                  _FilterDropdown<String>(
                    hint: 'Institution',
                    value: institutionNameById.containsKey(_institutionId) ? _institutionId : null,
                    items: institutions.map((i) => i.id).toList(),
                    labelOf: (id) => institutionNameById[id] ?? id,
                    onChanged: (v) => setState(() {
                      _institutionId = v;
                      _page = 0;
                    }),
                  ),
                  _FilterDropdown<InstitutionType>(
                    hint: 'Type',
                    value: _institutionType,
                    items: InstitutionType.values,
                    labelOf: (t) => t.wireValue,
                    onChanged: (v) => setState(() {
                      _institutionType = v;
                      _page = 0;
                    }),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final now = DateTime.now();
                      final picked = await showDateRangePicker(
                        context: context,
                        firstDate: DateTime(2023),
                        lastDate: DateTime(now.year + 1, 12, 31),
                        initialDateRange: _dateRange,
                      );
                      if (picked != null) {
                        setState(() {
                          _dateRange = picked;
                          _page = 0;
                        });
                      }
                    },
                    icon: const Icon(Icons.date_range_outlined, size: 18),
                    label: Text(
                      _dateRange == null
                          ? 'Date range'
                          : '${DateFormat.MMMd().format(_dateRange!.start)} – ${DateFormat.MMMd().format(_dateRange!.end)}',
                    ),
                  ),
                  if (_dateRange != null)
                    IconButton(
                      tooltip: 'Clear dates',
                      icon: const Icon(Icons.close_rounded, size: 16),
                      onPressed: () => setState(() {
                        _dateRange = null;
                        _page = 0;
                      }),
                    ),
                  FilterChip(
                    label: const Text('Overdue'),
                    selected: _overdueOnly,
                    onSelected: (v) => setState(() {
                      _overdueOnly = v;
                      _page = 0;
                    }),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: Text('All (${allTickets.length})'),
                    selected: _statuses.isEmpty,
                    showCheckmark: false,
                    selectedColor: AppTheme.navy,
                    labelStyle: TextStyle(
                      color: _statuses.isEmpty ? Colors.white : AppTheme.ink,
                      fontWeight: FontWeight.w600,
                    ),
                    backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
                    onSelected: (_) => setState(() {
                      _statuses = {};
                      _page = 0;
                    }),
                  ),
                  for (final group in _statusGroups)
                    _statusChip(
                      '${group.$1} (${allTickets.where((t) => group.$2.contains(t.status)).length})',
                      group.$2,
                    ),
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
                                child: ScrollableTable(
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
                                          DataCell(Text(assignee?.name ?? t.assignedToName ?? 'Unassigned')),
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

  Widget _statusChip(String label, Set<TicketStatus> group) {
    final selected = group.every(_statuses.contains);
    return FilterChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      selectedColor: AppTheme.navy,
      labelStyle: TextStyle(color: selected ? Colors.white : AppTheme.ink, fontWeight: FontWeight.w600),
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      onSelected: (on) => _toggleGroup(group, on),
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
